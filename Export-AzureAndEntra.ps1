#Requires -Version 5.1
<#
.SYNOPSIS
Runs Azure Export for Terraform and EntraExporter into one combined evidence folder.

.DESCRIPTION
Collection-only runner for Azure and Microsoft Entra evidence.
The script creates this layout:
  <OutputRoot>\<Client>\Azure\<Subscription>
  <OutputRoot>\<Client>\Entra
  <OutputRoot>\<Client>\Logs
  <OutputRoot>\<Client>\export-summary.json

It does not delete resources, change Azure settings, modify Entra settings, or run Terraform apply.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = ".\exports",
    [string]$ClientName,
    [string]$TenantId,
    [string]$SubscriptionId,

    [ValidateSet("Query", "ResourceGroup", "Resource", "MappingFile")]
    [string]$AztfexportMode = "Query",

    [string]$Query = "type != ''",
    [string]$ResourceGroupName,
    [string[]]$ResourceId = @(),
    [string]$ResourceIdFile,
    [string]$MappingFile,

    [ValidateSet("Default", "All", "Custom")]
    [string]$EntraExportPreset = "All",
    [string[]]$EntraType = @(),

    [switch]$SkipAztfexport,
    [switch]$SkipEntra,
    [switch]$InstallMissing,
    [switch]$NonInteractive,
    [switch]$UseDeviceCode,
    [switch]$Force,
    [switch]$StopOnAztfexportError,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:Summary = [ordered]@{
    started_at = (Get-Date).ToString("o")
    completed_at = $null
    status = "Started"
    errors = @()
    warnings = @()
    paths = [ordered]@{}
    tools = [ordered]@{}
    azure = [ordered]@{}
    entra = [ordered]@{}
    commands = @()
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "[*] $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-WarnSafe {
    param([string]$Message)
    $script:Summary.warnings += $Message
    Write-Warning $Message
}

function Add-ErrorSummary {
    param([string]$Message)
    $script:Summary.errors += $Message
}

function ConvertTo-SafeName {
    param([string]$Value, [string]$Fallback = "Client")
    $name = [string]$Value
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $Fallback }
    $name = $name.Trim() -replace '[<>:"/\\|?*]+', '-' -replace '\s+', ' '
    $name = $name.Trim(' ', '.')
    if ([string]::IsNullOrWhiteSpace($name)) { return $Fallback }
    return $name
}

function Save-Summary {
    param([string]$Path)
    try {
        $script:Summary.completed_at = (Get-Date).ToString("o")
        $script:Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    catch {
        Write-Warning "Could not write summary file: $($_.Exception.Message)"
    }
}


function Get-SummaryPathOrNull {
    if ($script:Summary.Contains("paths") -and $script:Summary.paths -and $script:Summary.paths.Contains("summary")) {
        return $script:Summary.paths["summary"]
    }
    return $null
}

function Get-CommandPathOrNull {
    param([string]$Command)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-NativeVersion {
    param([string]$Command, [string[]]$Arguments = @("--version"))
    try {
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { return "not found" }
        $output = & $Command @Arguments 2>&1
        $line = @($output | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        if ($line.Count -gt 0) { return $line[0] }
        return "available"
    }
    catch {
        return "available, version check failed: $($_.Exception.Message)"
    }
}

function Install-EntraExporterIfApproved {
    if (-not $InstallMissing) { return }
    if ($NonInteractive) { throw "EntraExporter is missing and -NonInteractive prevents installation prompts." }
    Write-Step "Installing EntraExporter for current user"
    Install-Module EntraExporter -Scope CurrentUser -Force -AllowClobber
}

function Assert-Dependencies {
    Write-Step "Checking dependencies"

    if (-not $SkipAztfexport) {
        if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI was not found in PATH. Install Azure CLI, then rerun." }
        if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { throw "Terraform was not found in PATH. Azure Export for Terraform requires Terraform." }
        if (-not (Get-Command aztfexport -ErrorAction SilentlyContinue)) { throw "aztfexport was not found in PATH. Install it with winget install aztfexport or from the Azure/aztfexport releases." }
        $script:Summary.tools.azure_cli = Get-NativeVersion -Command "az"
        $script:Summary.tools.terraform = Get-NativeVersion -Command "terraform"
        $script:Summary.tools.aztfexport = Get-NativeVersion -Command "aztfexport" -Arguments @("--version")
        Write-Ok "Azure CLI: $($script:Summary.tools.azure_cli)"
        Write-Ok "Terraform: $($script:Summary.tools.terraform)"
        Write-Ok "aztfexport: $($script:Summary.tools.aztfexport)"
    }

    if (-not $SkipEntra) {
        if (-not (Get-Module -ListAvailable -Name EntraExporter)) {
            Install-EntraExporterIfApproved
        }
        if (-not (Get-Module -ListAvailable -Name EntraExporter)) { throw "PowerShell module EntraExporter was not found. Install with: Install-Module EntraExporter -Scope CurrentUser" }
        $mod = Get-Module -ListAvailable -Name EntraExporter | Sort-Object Version -Descending | Select-Object -First 1
        $script:Summary.tools.entra_exporter = $mod.Version.ToString()
        Write-Ok "EntraExporter: $($script:Summary.tools.entra_exporter)"
    }
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [switch]$AllowFailure
    )

    $commandText = "$FilePath $($Arguments -join ' ')".Trim()
    $script:Summary.commands += $commandText
    Write-Info "Running: $commandText"

    if ($ValidateOnly) { return 0 }

    $oldLocation = (Get-Location).Path
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { Set-Location -LiteralPath $WorkingDirectory }
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and -not $AllowFailure) { throw "$FilePath exited with code $exitCode." }
        return $exitCode
    }
    finally {
        Set-Location -LiteralPath $oldLocation
    }
}

function Invoke-AzJson {
    param([string[]]$Arguments)
    if ($ValidateOnly) { return $null }
    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = [string]::Join([System.Environment]::NewLine, @($output | ForEach-Object { $_.ToString() })).Trim()
    if ($exitCode -ne 0) { throw "az $($Arguments -join ' ') failed with exit code $exitCode. $text" }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Ensure-AzLoginAndContext {
    if ($SkipAztfexport) { return }
    Write-Step "Checking Azure CLI context"

    $account = $null
    try { $account = Invoke-AzJson -Arguments @("account", "show", "-o", "json") }
    catch {
        Write-Info "Azure CLI is not logged in. Starting az login."
        $args = @("login")
        if ($UseDeviceCode) { $args += "--use-device-code" }
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $args += @("--tenant", $TenantId) }
        Invoke-NativeChecked -FilePath "az" -Arguments $args | Out-Null
        $account = Invoke-AzJson -Arguments @("account", "show", "-o", "json")
    }

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        Invoke-NativeChecked -FilePath "az" -Arguments @("account", "set", "--subscription", $SubscriptionId) | Out-Null
        $account = Invoke-AzJson -Arguments @("account", "show", "-o", "json")
        if ($account -and $account.id -ne $SubscriptionId) { throw "Azure CLI subscription context did not switch to $SubscriptionId." }
    }

    if ($account) {
        $script:Summary.azure.account_name = $account.name
        $script:Summary.azure.subscription_id = $account.id
        $script:Summary.azure.tenant_id = $account.tenantId
        Write-Ok "Azure context: $($account.name) [$($account.id)]"
    }
}

function Get-EffectiveClientName {
    if (-not [string]::IsNullOrWhiteSpace($ClientName)) { return ConvertTo-SafeName -Value $ClientName }
    if (-not $SkipAztfexport -and -not $ValidateOnly) {
        try {
            $account = Invoke-AzJson -Arguments @("account", "show", "-o", "json")
            if ($account -and -not [string]::IsNullOrWhiteSpace($account.name)) { return ConvertTo-SafeName -Value $account.name }
        }
        catch { }
    }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { return ConvertTo-SafeName -Value $TenantId }
    return "Client"
}

function New-OutputLayout {
    $safeClient = Get-EffectiveClientName
    $root = Resolve-Path -LiteralPath $OutputRoot -ErrorAction SilentlyContinue
    if ($root) { $baseRoot = $root.Path } else { $baseRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot) }
    $clientDir = Join-Path $baseRoot $safeClient
    $subFolder = if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) { ConvertTo-SafeName -Value $SubscriptionId -Fallback "Subscription" } else { "Subscription" }
    $azureDir = Join-Path (Join-Path $clientDir "Azure") $subFolder
    $entraDir = Join-Path $clientDir "Entra"
    $logsDir = Join-Path $clientDir "Logs"

    foreach ($dir in @($clientDir, $azureDir, $entraDir, $logsDir)) {
        if ((Test-Path -LiteralPath $dir) -and -not $Force -and -not $ValidateOnly) { }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $script:Summary.paths.client = $clientDir
    $script:Summary.paths.azure = $azureDir
    $script:Summary.paths.entra = $entraDir
    $script:Summary.paths.logs = $logsDir
    $script:Summary.paths.summary = Join-Path $clientDir "export-summary.json"
    return [pscustomobject]@{ Client = $clientDir; Azure = $azureDir; Entra = $entraDir; Logs = $logsDir; Summary = $script:Summary.paths.summary }
}

function Get-ResourceIdsFromInput {
    $ids = @()
    if ($ResourceId) { $ids += $ResourceId }
    if (-not [string]::IsNullOrWhiteSpace($ResourceIdFile)) {
        if (-not (Test-Path -LiteralPath $ResourceIdFile)) { throw "ResourceIdFile not found: $ResourceIdFile" }
        $ids += Get-Content -LiteralPath $ResourceIdFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
    }
    return @($ids | Select-Object -Unique)
}

function Invoke-AztfexportCollection {
    param([string]$AzureDir)
    if ($SkipAztfexport) {
        Write-WarnSafe "Skipped Azure Export for Terraform by request."
        return
    }

    Write-Step "Running Azure Export for Terraform"
    $common = @()
    if ($NonInteractive) { $common += "--non-interactive" }

    switch ($AztfexportMode) {
        "Query" {
            if ([string]::IsNullOrWhiteSpace($Query)) { throw "-Query is required for AztfexportMode Query." }
            Invoke-NativeChecked -FilePath "aztfexport" -Arguments (@("query") + $common + @($Query)) -WorkingDirectory $AzureDir -AllowFailure:(!$StopOnAztfexportError) | Out-Null
        }
        "ResourceGroup" {
            if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { throw "-ResourceGroupName is required for AztfexportMode ResourceGroup." }
            Invoke-NativeChecked -FilePath "aztfexport" -Arguments (@("resource-group") + $common + @($ResourceGroupName)) -WorkingDirectory $AzureDir -AllowFailure:(!$StopOnAztfexportError) | Out-Null
        }
        "Resource" {
            $ids = Get-ResourceIdsFromInput
            if ($ids.Count -eq 0) { throw "At least one -ResourceId or -ResourceIdFile entry is required for AztfexportMode Resource." }
            foreach ($id in $ids) {
                Invoke-NativeChecked -FilePath "aztfexport" -Arguments (@("resource") + $common + @($id)) -WorkingDirectory $AzureDir -AllowFailure:(!$StopOnAztfexportError) | Out-Null
            }
        }
        "MappingFile" {
            if ([string]::IsNullOrWhiteSpace($MappingFile)) { throw "-MappingFile is required for AztfexportMode MappingFile." }
            if (-not (Test-Path -LiteralPath $MappingFile)) { throw "MappingFile not found: $MappingFile" }
            Invoke-NativeChecked -FilePath "aztfexport" -Arguments (@("mapping-file") + $common + @($MappingFile)) -WorkingDirectory $AzureDir -AllowFailure:(!$StopOnAztfexportError) | Out-Null
        }
    }

    $script:Summary.azure.output = $AzureDir
    if (-not $ValidateOnly) {
        $script:Summary.azure.file_count = @(Get-ChildItem -LiteralPath $AzureDir -Recurse -File -ErrorAction SilentlyContinue).Count
    }
    Write-Ok "Azure export folder: $AzureDir"
}

function Connect-EntraExporterSafe {
    if ($ValidateOnly) { return }
    Import-Module EntraExporter -ErrorAction Stop
    $cmd = Get-Command Connect-EntraExporter -ErrorAction Stop
    $args = @{}
    if (-not [string]::IsNullOrWhiteSpace($TenantId) -and $cmd.Parameters.ContainsKey("TenantId")) { $args.TenantId = $TenantId }
    if ($cmd.Parameters.ContainsKey("UseDeviceCode") -and $UseDeviceCode) { $args.UseDeviceCode = $true }
    Connect-EntraExporter @args
}

function Invoke-EntraCollection {
    param([string]$EntraDir)
    if ($SkipEntra) {
        Write-WarnSafe "Skipped EntraExporter by request."
        return
    }

    Write-Step "Running EntraExporter"
    if (-not $ValidateOnly) { Connect-EntraExporterSafe }

    $arguments = @($EntraDir)
    if ($EntraExportPreset -eq "All") {
        $arguments += "-All"
    }
    elseif ($EntraExportPreset -eq "Custom") {
        if (-not $EntraType -or $EntraType.Count -eq 0) { throw "-EntraType is required when -EntraExportPreset Custom is used." }
        foreach ($type in $EntraType) { $arguments += @("-Type", $type) }
    }

    $script:Summary.commands += "Export-Entra $($arguments -join ' ')"
    Write-Info "Running: Export-Entra $($arguments -join ' ')"
    if (-not $ValidateOnly) { Export-Entra @arguments }

    $script:Summary.entra.output = $EntraDir
    if (-not $ValidateOnly) {
        $script:Summary.entra.file_count = @(Get-ChildItem -LiteralPath $EntraDir -Recurse -File -ErrorAction SilentlyContinue).Count
    }
    Write-Ok "Entra export folder: $EntraDir"
}

try {
    Write-Step "Preparing Microsoft AD and Entra export"
    $layout = New-OutputLayout
    $script:Summary.status = "Prepared"
    Save-Summary -Path $layout.Summary

    $transcriptPath = Join-Path $layout.Logs ("export-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    if (-not $ValidateOnly) {
        try { Start-Transcript -Path $transcriptPath -Force | Out-Null } catch { Write-WarnSafe "Could not start transcript: $($_.Exception.Message)" }
    }
    $script:Summary.paths.transcript = $transcriptPath

    Assert-Dependencies
    Ensure-AzLoginAndContext
    Invoke-AztfexportCollection -AzureDir $layout.Azure
    Invoke-EntraCollection -EntraDir $layout.Entra

    $script:Summary.status = if ($ValidateOnly) { "Validated" } else { "Completed" }
    Save-Summary -Path $layout.Summary
    Write-Step "Done"
    Write-Ok "Client folder: $($layout.Client)"
    Write-Ok "Summary file: $($layout.Summary)"
}
catch {
    $message = $_.Exception.Message
    Add-ErrorSummary $message
    $script:Summary.status = "Failed"
    $summaryPath = Get-SummaryPathOrNull
    if ($summaryPath) { Save-Summary -Path $summaryPath }
    Write-Error $message
    exit 1
}
finally {
    if (-not $ValidateOnly) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
