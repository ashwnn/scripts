// ==UserScript==
// @name        RBC Transaction Exporter
// @namespace   https://violentmonkey.github.io/
// @match       https://*.royalbank.com/sgw1/olb/*
// @grant       none
// @version     3.0
// @author      ashwnn
// @run-at      document-end
// @description Exports visible transactions to CSV.
// ==/UserScript==

(function () {
  "use strict";

  const CFG = {
    ui: {
      id: "rbc-export-container",
      styleId: "rbc-export-styles",
      mountPollMs: 1200,
    },
    loading: {
      maxBatches: 200,
      clickDelayMs: 350,
      postClickWaitMs: 1600,
      stableChecks: 3,
      stableIntervalMs: 700,
      maxNoProgress: 6,
    },
    selectors: {
      // Transaction rows (keep your known-good selector; add light fallbacks)
      rows: 'tr[data-role="transaction-list-table-transaction"]',
      // Columns (best-effort, future tolerant)
      date: ".date-column-padding, [headers*='date' i]",
      desc: ".rbc-transaction-list-desc",
      withdraw: ".rbc-transaction-list-withdraw",
      deposit: ".rbc-transaction-list-deposit, .rbc-transaction-list-dep",
      balance: ".rbc-transaction-list-balance",
    },
    text: {
      showMore: "show more",
    },
    files: {
      prefix: "RBC_Export",
    },
  };

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function formatISODate(date = new Date()) {
    return date.toISOString().split("T")[0];
  }

  function isVisible(el) {
    if (!el) return false;
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return false;
    const style = window.getComputedStyle(el);
    return style.visibility !== "hidden" && style.display !== "none" && style.opacity !== "0";
  }

  function safeText(el) {
    return (el?.innerText || el?.textContent || "").replace(/\s+/g, " ").trim();
  }

  function escapeCsv(value) {
    const s = String(value ?? "");
    const escaped = s.replace(/"/g, '""');
    return `"${escaped}"`;
  }

  function findShowMoreButton() {
    const buttons = Array.from(document.querySelectorAll("button"));
    const match = buttons.find((b) => safeText(b).toLowerCase().includes(CFG.text.showMore));
    return match && isVisible(match) ? match : null;
  }

  function clickLikeUser(el) {
    if (!el) return false;
    try {
      el.focus?.();
      el.scrollIntoView?.({ behavior: "smooth", block: "center" });
      el.dispatchEvent(new MouseEvent("mouseover", { bubbles: true, cancelable: true }));
      el.dispatchEvent(new MouseEvent("mousemove", { bubbles: true, cancelable: true }));
      el.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, button: 0 }));
      el.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true, button: 0 }));
      el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }));
      return true;
    } catch {
      try {
        el.click();
        return true;
      } catch {
        return false;
      }
    }
  }

  function injectStyles() {
    if (document.getElementById(CFG.ui.styleId)) return;

    const style = document.createElement("style");
    style.id = CFG.ui.styleId;
    style.textContent = `
      :root {
        --rbcx-bg: rgba(255, 255, 255, 0.78);
        --rbcx-border: rgba(0, 0, 0, 0.08);
        --rbcx-text: #0f172a;
        --rbcx-muted: #64748b;
        --rbcx-shadow: 0 10px 30px rgba(0,0,0,0.12);
        --rbcx-radius: 14px;
        --rbcx-font: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
      }

      #${CFG.ui.id} {
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 2147483647;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px;
        border-radius: var(--rbcx-radius);
        border: 1px solid var(--rbcx-border);
        background: var(--rbcx-bg);
        box-shadow: var(--rbcx-shadow);
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
        font-family: var(--rbcx-font);
      }

      #${CFG.ui.id} .rbcx-btn {
        appearance: none;
        border: 1px solid var(--rbcx-border);
        background: #0f172a;
        color: #ffffff;
        padding: 10px 12px;
        border-radius: 12px;
        font-size: 13px;
        font-weight: 650;
        line-height: 1;
        cursor: pointer;
        transition: transform 120ms ease, box-shadow 120ms ease, opacity 120ms ease;
        box-shadow: 0 1px 2px rgba(0,0,0,0.06);
        user-select: none;
        white-space: nowrap;
      }

      #${CFG.ui.id} .rbcx-btn:hover {
        transform: translateY(-1px);
        box-shadow: 0 8px 22px rgba(0,0,0,0.12);
      }

      #${CFG.ui.id} .rbcx-btn:active {
        transform: translateY(0px);
      }

      #${CFG.ui.id} .rbcx-btn:disabled {
        opacity: 0.55;
        cursor: not-allowed;
        transform: none;
        box-shadow: 0 1px 2px rgba(0,0,0,0.06);
      }

      #${CFG.ui.id} .rbcx-secondary {
        background: #ffffff;
        color: var(--rbcx-text);
      }

      #${CFG.ui.id} .rbcx-chip {
        display: none;
        align-items: center;
        padding: 9px 10px;
        border-radius: 12px;
        border: 1px solid var(--rbcx-border);
        background: #ffffff;
        color: var(--rbcx-muted);
        font-size: 12px;
        font-weight: 650;
        white-space: nowrap;
      }
    `;
    document.head.appendChild(style);
  }

  function createUI() {
    if (document.getElementById(CFG.ui.id)) return;

    injectStyles();

    const container = document.createElement("div");
    container.id = CFG.ui.id;

    const exportBtn = document.createElement("button");
    exportBtn.className = "rbcx-btn";
    exportBtn.type = "button";
    exportBtn.textContent = "Export CSV";

    const loadBtn = document.createElement("button");
    loadBtn.className = "rbcx-btn rbcx-secondary";
    loadBtn.type = "button";
    loadBtn.textContent = "Load all";

    const chip = document.createElement("div");
    chip.className = "rbcx-chip";
    chip.textContent = "Idle";

    function setChip(text) {
      chip.style.display = "inline-flex";
      chip.textContent = text;
    }

    function hideChip() {
      chip.style.display = "none";
    }

    loadBtn.addEventListener("click", async () => {
      loadBtn.disabled = true;
      exportBtn.disabled = true;
      setChip("Loading...");
      try {
        await autoLoadTransactions((t) => setChip(t));
        setChip("Loaded");
      } finally {
        loadBtn.disabled = false;
        exportBtn.disabled = false;
        setTimeout(hideChip, 1400);
      }
    });

    exportBtn.addEventListener("click", async () => {
      loadBtn.disabled = true;
      exportBtn.disabled = true;
      setChip("Processing...");
      try {
        // Best effort: load remaining items first, then export
        await autoLoadTransactions((t) => setChip(t));
        const count = exportData();
        setChip(`Saved ${count} rows`);
      } finally {
        loadBtn.disabled = false;
        exportBtn.disabled = false;
        setTimeout(hideChip, 1600);
      }
    });

    container.appendChild(exportBtn);
    container.appendChild(loadBtn);
    container.appendChild(chip);
    document.body.appendChild(container);
  }

  async function waitForRowCountToStabilize(getCount, stableChecks, intervalMs) {
    let last = getCount();
    let stable = 0;

    while (stable < stableChecks) {
      await sleep(intervalMs);
      const next = getCount();
      if (next === last) {
        stable += 1;
      } else {
        stable = 0;
        last = next;
      }
    }

    return last;
  }

  async function autoLoadTransactions(setStatus) {
    let batches = 0;
    let noProgress = 0;

    const getRowCount = () => document.querySelectorAll(CFG.selectors.rows).length;

    // Stabilize before starting, avoids racing initial render
    await waitForRowCountToStabilize(getRowCount, 2, 400);

    while (batches < CFG.loading.maxBatches) {
      const btn = findShowMoreButton();
      const before = getRowCount();

      if (!btn) {
        setStatus(`Ready (${before} rows)`);
        return;
      }

      batches += 1;
      setStatus(`Loading batch ${batches} (${before} rows)`);

      btn.scrollIntoView({ behavior: "smooth", block: "center" });
      await sleep(CFG.loading.clickDelayMs);

      const clicked = clickLikeUser(btn);
      if (!clicked) {
        setStatus("Could not click. Try again.");
        return;
      }

      await sleep(CFG.loading.postClickWaitMs);

      const after = await waitForRowCountToStabilize(
        getRowCount,
        CFG.loading.stableChecks,
        CFG.loading.stableIntervalMs
      );

      if (after <= before) {
        noProgress += 1;
        if (noProgress >= CFG.loading.maxNoProgress) {
          setStatus(`Stopped (no progress, ${after} rows)`);
          return;
        }
      } else {
        noProgress = 0;
      }
    }

    setStatus(`Stopped (max batches, ${document.querySelectorAll(CFG.selectors.rows).length} rows)`);
  }

  function exportData() {
    const rows = Array.from(document.querySelectorAll(CFG.selectors.rows));
    const seen = new Set();

    const csv = [];
    csv.push(["Date", "Description", "Withdrawal/Debit", "Deposit/Credit", "Balance"].map(escapeCsv).join(","));

    let written = 0;

    for (const row of rows) {
      const date = safeText(row.querySelector(CFG.selectors.date));
      const desc = safeText(row.querySelector(CFG.selectors.desc));
      const withdraw = safeText(row.querySelector(CFG.selectors.withdraw));
      const deposit = safeText(row.querySelector(CFG.selectors.deposit));
      const balance = safeText(row.querySelector(CFG.selectors.balance));

      if (!date) continue;

      const fingerprint = [date, desc, withdraw, deposit, balance].join("|");
      if (seen.has(fingerprint)) continue;
      seen.add(fingerprint);

      csv.push([date, desc, withdraw, deposit, balance].map(escapeCsv).join(","));
      written += 1;
    }

    const content = csv.join("\n");
    const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);

    const a = document.createElement("a");
    a.href = url;
    a.download = `${CFG.files.prefix}_${formatISODate()}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);

    URL.revokeObjectURL(url);

    return written;
  }

  const mountInterval = setInterval(() => {
    if (!document.body) return;
    createUI();
  }, CFG.ui.mountPollMs);

  // If the page is a single-page app, keep the interval running.
  // If you prefer a one-time mount, uncomment the following line:
  // clearInterval(mountInterval);
})();