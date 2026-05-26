#Requires -Version 5.1
<#
.SYNOPSIS
Runs Azure Export for Terraform and/or EntraExporter into one evidence folder.

.DESCRIPTION
Collection-only runner for Azure and Microsoft Entra evidence.
Default behavior runs both collectors. Use -ExportTarget to run only one collector.

Default layout when both collectors are selected:
  <OutputRoot>\<Client>\Azure\<Subscription>
  <OutputRoot>\<Client>\Entra
  <OutputRoot>\<Client>\Logs
  <OutputRoot>\<Client>\export-summary.json

Standalone layouts create only the selected collector folder plus Logs and export-summary.json.

It does not delete resources, change Azure settings, modify Entra settings, or run Terraform apply.

.EXAMPLE
.\Export-AzureAndEntra.ps1
Runs both Azure Export for Terraform and EntraExporter.

.EXAMPLE
.\Export-AzureAndEntra.ps1 -ExportTarget Azure -SubscriptionId "<subscription-id>" -NonInteractive
Runs only Azure Export for Terraform.

.EXAMPLE
.\Export-AzureAndEntra.ps1 -ExportTarget Aztfexport -SubscriptionId "<subscription-id>" -NonInteractive
Runs only Azure Export for Terraform using the aztfexport alias.

.EXAMPLE
.\Export-AzureAndEntra.ps1 -ExportTarget Entra -TenantId "<tenant-id>"
Runs only EntraExporter.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = ".\exports",
    [string]$ClientName,
    [string]$TenantId,
    [string]$SubscriptionId,

    [ValidateSet("Both", "Azure", "Aztfexport", "Entra", "EntraExport", "EntraExporter")]
    [string]$ExportTarget = "Both",

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

$script:RunAztfexport = $false
$script:RunEntra = $false
$script:NormalizedExportTarget = $null

$script:Summary = [ordered]@{
    started_at = (Get-Date).ToString("o")
    completed_at = $null
    status = "Started"
    requested_export_target = $ExportTarget
    effective_export_target = $null
    collectors = [ordered]@{
        aztfexport = $false
        entra_exporter = $false
    }
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
    if ($ValidateOnly) { return }

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

function Get-AztfexportVersion {
    if (-not (Get-Command aztfexport -ErrorAction SilentlyContinue)) { return "not found" }

    $candidates = @(
        @("--version"),
        @("version"),
        @("--help")
    )

    foreach ($candidate in $candidates) {
        try {
            $output = & aztfexport @candidate 2>&1
            $lines = @($output | ForEach-Object { $_.ToString() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $firstUseful = @($lines | Where-Object { $_ -notmatch "No help topic|unknown command|unknown flag|error" } | Select-Object -First 1)
            if ($firstUseful.Count -gt 0) { return $firstUseful[0] }
        }
        catch { }
    }

    return "available"
}

function Resolve-ExportSelection {
    $normalized = switch ($ExportTarget) {
        "Aztfexport" { "Azure"; break }
        "EntraExport" { "Entra"; break }
        "EntraExporter" { "Entra"; break }
        default { $ExportTarget; break }
    }

    $runAzure = $normalized -in @("Both", "Azure")
    $runEntra = $normalized -in @("Both", "Entra")

    if ($SkipAztfexport -and $runAzure) {
        Write-WarnSafe "-SkipAztfexport was provided. Azure Export for Terraform will not run. Prefer -ExportTarget Entra for standalone Entra exports."
        $runAzure = $false
    }

    if ($SkipEntra -and $runEntra) {
        Write-WarnSafe "-SkipEntra was provided. EntraExporter will not run. Prefer -ExportTarget Azure for standalone Azure exports."
        $runEntra = $false
    }

    if (-not $runAzure -and -not $runEntra) {
        throw "No export collectors selected. Use -ExportTarget Both, Azure, or Entra, or remove conflicting skip switches."
    }

    if ($runAzure -and $runEntra) {
        $effective = "Both"
    }
    elseif ($runAzure) {
        $effective = "Azure"
    }
    else {
        $effective = "Entra"
    }

    $script:RunAztfexport = $runAzure
    $script:RunEntra = $runEntra
    $script:NormalizedExportTarget = $effective
    $script:Summary.effective_export_target = $effective
    $script:Summary.collectors.aztfexport = $runAzure
    $script:Summary.collectors.entra_exporter = $runEntra

    $collectorNames = @()
    if ($runAzure) { $collectorNames += "aztfexport" }
    if ($runEntra) { $collectorNames += "EntraExporter" }
    Write-Ok "Selected collector(s): $($collectorNames -join ', ')"
}

function Install-EntraExporterIfApproved {
    if (-not $InstallMissing) { return }
    if ($ValidateOnly) { throw "EntraExporter is missing. -ValidateOnly will not install missing modules." }
    if ($NonInteractive) { throw "EntraExporter is missing and -NonInteractive prevents installation prompts." }
    Write-Step "Installing EntraExporter for current user"
    Install-Module EntraExporter -Scope CurrentUser -Force -AllowClobber
}

function Assert-Dependencies {
    Write-Step "Checking dependencies"

    if ($script:RunAztfexport) {
        if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI was not found in PATH. Install Azure CLI, then rerun." }
        if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { throw "Terraform was not found in PATH. Azure Export for Terraform requires Terraform." }
        if (-not (Get-Command aztfexport -ErrorAction SilentlyContinue)) { throw "aztfexport was not found in PATH. Install it with winget install aztfexport or from the Azure/aztfexport releases." }
        $script:Summary.tools.azure_cli = Get-NativeVersion -Command "az"
        $script:Summary.tools.terraform = Get-NativeVersion -Command "terraform"
        $script:Summary.tools.aztfexport = Get-AztfexportVersion
        Write-Ok "Azure CLI: $($script:Summary.tools.azure_cli)"
        Write-Ok "Terraform: $($script:Summary.tools.terraform)"
        Write-Ok "aztfexport: $($script:Summary.tools.aztfexport)"
    }

    if ($script:RunEntra) {
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
    if (-not $script:RunAztfexport) { return }
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
    if ($script:RunAztfexport -and -not $ValidateOnly) {
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
    $logsDir = Join-Path $clientDir "Logs"

    $azureDir = $null
    if ($script:RunAztfexport) {
        $subFolder = if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) { ConvertTo-SafeName -Value $SubscriptionId -Fallback "Subscription" } else { "Subscription" }
        $azureDir = Join-Path (Join-Path $clientDir "Azure") $subFolder
    }

    $entraDir = $null
    if ($script:RunEntra) {
        $entraDir = Join-Path $clientDir "Entra"
    }

    $dirs = @($clientDir, $logsDir)
    if ($azureDir) { $dirs += $azureDir }
    if ($entraDir) { $dirs += $entraDir }

    foreach ($dir in $dirs) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        if (-not $ValidateOnly) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $script:Summary.paths.client = $clientDir
    $script:Summary.paths.logs = $logsDir
    if ($azureDir) { $script:Summary.paths.azure = $azureDir }
    if ($entraDir) { $script:Summary.paths.entra = $entraDir }
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
    if (-not $script:RunAztfexport) {
        Write-Info "Azure Export for Terraform not selected."
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
    if (-not $script:RunEntra) {
        Write-Info "EntraExporter not selected."
        return
    }

    Write-Step "Running EntraExporter"
    if (-not $ValidateOnly) { Connect-EntraExporterSafe }

    $exportParams = @{ Path = $EntraDir }
    $commandParts = @("Export-Entra", "-Path", "`"$EntraDir`"")

    if ($EntraExportPreset -eq "All") {
        $exportParams.All = $true
        $commandParts += "-All"
    }
    elseif ($EntraExportPreset -eq "Custom") {
        if (-not $EntraType -or $EntraType.Count -eq 0) { throw "-EntraType is required when -EntraExportPreset Custom is used." }
        $exportParams.Type = $EntraType
        $commandParts += @("-Type", ($EntraType -join ","))
    }

    $commandText = $commandParts -join " "
    $script:Summary.commands += $commandText
    Write-Info "Running: $commandText"
    if (-not $ValidateOnly) { Export-Entra @exportParams }

    $script:Summary.entra.output = $EntraDir
    if (-not $ValidateOnly) {
        $script:Summary.entra.file_count = @(Get-ChildItem -LiteralPath $EntraDir -Recurse -File -ErrorAction SilentlyContinue).Count
    }
    Write-Ok "Entra export folder: $EntraDir"
}

try {
    Write-Step "Preparing Microsoft AD and Entra export"
    Resolve-ExportSelection
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
    Write-Ok "Effective export target: $($script:Summary.effective_export_target)"
    Write-Ok "Client folder: $($layout.Client)"
    if (-not $ValidateOnly) { Write-Ok "Summary file: $($layout.Summary)" }
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
