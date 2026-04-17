// ==UserScript==
// @name         ScreenConnect Helper
// @namespace    local
// @version      1.4.1
// @icon         https://www.screenconnect.com/siteassets/media/logos/screenconnect-icon-48x48.png
// @author       Ashwin C.
// @description  Automatically prunes old command history in ScreenConnect, keeping only the most recent N groups, adds a toggleable PowerShell mode to the command entry panel, and adds a full-width organization search bar below the MasterPanel Build button.
// @match        *://<your-domain>.ca/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------
  const KEEP_LAST_COMMANDS = Math.max(
    1,
    Number(localStorage.getItem('scKeepLastCommandsLimit')) || 5
  );

  const LIST_SELECTOR      = '.Commands .ListPanel';
  const GROUP_START_SEL    = '.Host.QueuedCommand';
  const ENTRY_SELECTOR     = ':scope > div';
  const ENTRY_PANEL_SEL    = '.Commands .EntryPanel';
  const OBSERVER_KEY       = 'scKeepLastCommandsObserverAttached';
  const ENTRY_PANEL_KEY    = 'scPsToggleAttached';
  const TOAST_ID           = 'sc-helper-toast';
  const PS_PREFIX          = '#!ps\n';

  const MASTER_PANEL_SEL   = '.MasterPanel';
  const MASTER_PANEL_KEY   = 'scMasterToolbarAttached';
  const MASTER_LIST_SEL    = '.MasterListContainer';

  let pruneQueued  = false;
  let toastTimeout = null;
  let psEnabled    = false;

  // ---------------------------------------------------------------------------
  // Console banner
  // ---------------------------------------------------------------------------
  console.log(
    '%c[SC Helper]%c Loaded. Keeping the last %c' + KEEP_LAST_COMMANDS + '%c command group(s).',
    'color:#cc3232;font-weight:bold', 'color:inherit',
    'color:#2d862d;font-weight:bold', 'color:inherit'
  );
  console.log(
    '%c[SC Helper]%c To change the limit run: %clocalStorage.setItem(\'scKeepLastCommandsLimit\', N)%c then reload.',
    'color:#cc3232;font-weight:bold', 'color:inherit',
    'color:#cc7a00;font-weight:bold', 'color:inherit'
  );

  // ---------------------------------------------------------------------------
  // Styles
  // ---------------------------------------------------------------------------
  function injectStyles() {
    if (document.getElementById('sc-helper-styles')) return;

    const style = document.createElement('style');
    style.id = 'sc-helper-styles';
    style.textContent = `
      /* Toast - matches SC's white/grey palette with red accent */
      #${TOAST_ID} {
        position: fixed;
        top: 16px;
        right: 16px;
        z-index: 2147483647;
        background: rgb(255, 255, 255);
        color: rgb(33, 33, 33);
        font-family: "Roboto", "Segoe UI", "Helvetica Neue", Helvetica, Tahoma, Arial;
        font-size: 13px;
        padding: 10px 16px;
        border-radius: 2px;
        border-left: 3px solid rgb(204, 50, 50);
        border-top: 1px solid rgb(230, 230, 230);
        border-right: 1px solid rgb(230, 230, 230);
        border-bottom: 1px solid rgb(230, 230, 230);
        box-shadow: 0 2px 8px rgba(0,0,0,0.15);
        opacity: 0;
        transform: translateY(-6px);
        transition: opacity 0.15s ease-in-out, transform 0.15s ease-in-out;
        pointer-events: none;
        white-space: nowrap;
      }
      #${TOAST_ID}.sc-toast-visible {
        opacity: 1;
        transform: translateY(0);
      }

      /* Toggle wrapper - hard-locked width, never grows */
      .sc-ps-toggle-wrap {
        flex: 0 0 38px !important;
        width: 38px !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        border-right: 1px solid rgb(230, 230, 230);
        box-sizing: border-box;
      }

      /* Track - vertical pill */
      .sc-ps-track {
        position: relative;
        width: 16px;
        height: 30px;
        border-radius: 8px;
        background: rgb(204, 204, 204);
        border: 1px solid rgb(180, 180, 180);
        cursor: pointer;
        transition: background 0.15s ease-in-out, border-color 0.15s ease-in-out;
        flex-shrink: 0;
        box-sizing: border-box;
      }
      .sc-ps-toggle-wrap.sc-ps-on .sc-ps-track {
        background: rgb(204, 50, 50);
        border-color: rgb(170, 35, 35);
      }

      /* Thumb - starts at bottom, slides up when active */
      .sc-ps-thumb {
        position: absolute;
        bottom: 2px;
        left: 2px;
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: rgb(255, 255, 255);
        box-shadow: 0 1px 2px rgba(0,0,0,0.2);
        transition: transform 0.15s ease-in-out;
      }
      .sc-ps-toggle-wrap.sc-ps-on .sc-ps-thumb {
        transform: translateY(-14px);
      }

      /* Textarea tint when PS mode is active */
      .sc-ps-active-textarea {
        background: rgb(255, 245, 245) !important;
      }

      /* -----------------------------------------------------------------------
         MasterPanel - compact Build button + inline search bar
         ----------------------------------------------------------------------- */

      /* Make p.Create a flex row with vertical padding to preserve spacing */
      .sc-create-enhanced {
        display: flex !important;
        align-items: center !important;
        gap: 8px !important;
        padding: 6px 8px !important;
        box-sizing: border-box !important;
      }

      /* Override SC's full-width red block button with a compact inline version */
      .sc-create-enhanced a {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        flex-shrink: 0 !important;
        width: auto !important;
        height: 26px !important;
        padding: 0 10px !important;
        background: rgb(204, 50, 50) !important;
        color: rgb(255, 255, 255) !important;
        font-size: 12px !important;
        font-family: "Roboto", "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif !important;
        font-weight: 600 !important;
        text-decoration: none !important;
        border-radius: 2px !important;
        white-space: nowrap !important;
        letter-spacing: 0.02em !important;
        box-sizing: border-box !important;
        transition: background 0.12s ease-in-out !important;
      }
      .sc-create-enhanced a:hover {
        background: rgb(185, 35, 35) !important;
        text-decoration: none !important;
      }
      .sc-create-enhanced a:active {
        background: rgb(165, 25, 25) !important;
      }

      /* Wrapper holds input + clear button, fills remaining width */
      .sc-master-search-wrap {
        flex: 1 1 0;
        min-width: 0;
        position: relative;
        display: flex;
        align-items: center;
      }

      /* Search input - same height as the button, red focus accent */
      .sc-master-search {
        width: 100%;
        height: 26px;
        border: 1px solid rgb(204, 50, 50);
        border-radius: 2px;
        outline: none;
        padding: 0 22px 0 8px;
        font-size: 12px;
        font-family: "Roboto", "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
        color: rgb(33, 33, 33);
        background: rgb(255, 255, 255);
        box-sizing: border-box;
        transition: border-color 0.12s ease-in-out, box-shadow 0.12s ease-in-out;
      }
      .sc-master-search:focus {
        border-color: rgb(204, 50, 50);
        box-shadow: 0 0 0 2px rgba(204, 50, 50, 0.15);
      }
      .sc-master-search::placeholder {
        color: rgb(185, 185, 185);
      }

      /* Clear button - absolute inside wrapper */
      .sc-master-search-clear {
        position: absolute;
        right: 5px;
        top: 50%;
        transform: translateY(-50%);
        display: none;
        align-items: center;
        justify-content: center;
        width: 14px;
        height: 14px;
        border: none;
        background: transparent;
        color: rgb(180, 180, 180);
        font-size: 13px;
        line-height: 1;
        cursor: pointer;
        padding: 0;
        outline: none;
      }
      .sc-master-search-clear:hover {
        color: rgb(204, 50, 50);
      }
      .sc-master-search-clear.sc-visible {
        display: flex;
      }

      /* No-results notice */
      .sc-master-no-results {
        display: none;
        padding: 6px 8px;
        font-size: 12px;
        font-family: "Roboto", "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
        color: rgb(160, 160, 160);
        font-style: italic;
        box-sizing: border-box;
      }
      .sc-master-no-results.sc-visible {
        display: block;
      }
    `;

    document.head.appendChild(style);
  }

  // ---------------------------------------------------------------------------
  // Toast
  // ---------------------------------------------------------------------------
  function getOrCreateToast() {
    let toast = document.getElementById(TOAST_ID);
    if (!toast) {
      injectStyles();
      toast = document.createElement('div');
      toast.id = TOAST_ID;
      document.body.appendChild(toast);
    }
    return toast;
  }

  function showToast(message) {
    const toast = getOrCreateToast();
    toast.textContent = message;

    if (toastTimeout) {
      clearTimeout(toastTimeout);
      toastTimeout = null;
    }

    toast.classList.remove('sc-toast-visible');
    void toast.offsetWidth;
    toast.classList.add('sc-toast-visible');

    toastTimeout = setTimeout(() => {
      toast.classList.remove('sc-toast-visible');
      toastTimeout = null;
    }, 3000);
  }

  // ---------------------------------------------------------------------------
  // PS toggle injection
  // ---------------------------------------------------------------------------
  function injectPsToggle(entryPanel) {
    if (!isElement(entryPanel) || entryPanel.dataset[ENTRY_PANEL_KEY] === '1') return;
    entryPanel.dataset[ENTRY_PANEL_KEY] = '1';

    injectStyles();

    const textarea  = entryPanel.querySelector('textarea');
    const runButton = entryPanel.querySelector('input[type="button"]');
    if (!textarea || !runButton) return;

    const wrap = document.createElement('div');
    wrap.className = 'sc-ps-toggle-wrap';

    const track = document.createElement('div');
    track.className = 'sc-ps-track';
    track.setAttribute('role', 'switch');
    track.setAttribute('aria-checked', 'false');
    track.setAttribute('tabindex', '0');
    track.setAttribute('title', 'Toggle PowerShell mode - prepends #!ps to commands');

    const thumb = document.createElement('div');
    thumb.className = 'sc-ps-thumb';

    track.appendChild(thumb);
    wrap.appendChild(track);

    const textareaDiv = textarea.closest('div') || textarea.parentElement;
    textareaDiv.insertAdjacentElement('beforebegin', wrap);

    function setToggle(on) {
      psEnabled = on;
      wrap.classList.toggle('sc-ps-on', on);
      track.setAttribute('aria-checked', String(on));
      textarea.classList.toggle('sc-ps-active-textarea', on);

      console.log(
        '%c[SC Helper]%c PowerShell mode %c' + (on ? 'ON' : 'OFF') + '%c - commands will ' +
        (on ? 'be prefixed with #!ps' : 'run as plain CMD'),
        'color:#cc3232;font-weight:bold', 'color:inherit',
        on ? 'color:#2d862d;font-weight:bold' : 'color:#cc3232;font-weight:bold',
        'color:inherit'
      );
    }

    track.addEventListener('click', () => setToggle(!psEnabled));
    track.addEventListener('keydown', (e) => {
      if (e.key === ' ' || e.key === 'Enter') {
        e.preventDefault();
        setToggle(!psEnabled);
      }
    });

    const proto = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    Object.defineProperty(textarea, 'value', {
      get() {
        const raw = proto.get.call(textarea);
        if (psEnabled && raw.trim() !== '' && !raw.startsWith('#!ps')) {
          return PS_PREFIX + raw;
        }
        return raw;
      },
      set(v) {
        proto.set.call(textarea, v);
      },
      configurable: true
    });

    console.log(
      '%c[SC Helper]%c PowerShell toggle injected into the entry panel.',
      'color:#cc3232;font-weight:bold', 'color:inherit'
    );
  }

  function attachEntryPanels() {
    for (const panel of document.querySelectorAll(ENTRY_PANEL_SEL)) {
      injectPsToggle(panel);
    }
  }

  // ---------------------------------------------------------------------------
  // MasterPanel toolbar (+ button + org search)
  // ---------------------------------------------------------------------------
  function filterOrgs(listContainer, noResults, query) {
    const items = listContainer.querySelectorAll(':scope > ul > li');
    let visible = 0;

    for (const li of items) {
      const titleEl = li.querySelector('.AllCommandChildrenInvisible > p[title]');
      const name    = titleEl ? titleEl.getAttribute('title').toLowerCase() : '';
      const match   = !query || name.includes(query);
      li.style.display = match ? '' : 'none';
      if (match) visible++;
    }

    noResults.classList.toggle('sc-visible', query.length > 0 && visible === 0);
  }

  function injectMasterToolbar(masterPanel) {
    if (!isElement(masterPanel) || masterPanel.dataset[MASTER_PANEL_KEY] === '1') return;

    const createP    = masterPanel.querySelector('p.Create');
    const listContainer = masterPanel.querySelector(MASTER_LIST_SEL);
    if (!createP || !listContainer) return;

    masterPanel.dataset[MASTER_PANEL_KEY] = '1';
    injectStyles();

    // Style p.Create as a flex row - the existing "Build +" link stays untouched on the left
    createP.classList.add('sc-create-enhanced');

    // Search wrapper (holds input + clear button)
    const wrap = document.createElement('div');
    wrap.className = 'sc-master-search-wrap';

    const searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.className = 'sc-master-search';
    searchInput.placeholder = 'Search organizations\u2026';
    searchInput.setAttribute('aria-label', 'Search organizations');
    searchInput.setAttribute('autocomplete', 'off');
    searchInput.setAttribute('spellcheck', 'false');

    const clearBtn = document.createElement('button');
    clearBtn.type = 'button';
    clearBtn.className = 'sc-master-search-clear';
    clearBtn.textContent = '\u00d7';
    clearBtn.title = 'Clear search';

    wrap.appendChild(searchInput);
    wrap.appendChild(clearBtn);
    createP.appendChild(wrap);

    // No-results notice sits after the list container
    const noResults = document.createElement('div');
    noResults.className = 'sc-master-no-results';
    noResults.textContent = 'No matching organizations.';
    listContainer.insertAdjacentElement('afterend', noResults);

    // Wire up search
    searchInput.addEventListener('input', () => {
      const query = searchInput.value.toLowerCase();
      clearBtn.classList.toggle('sc-visible', query.length > 0);
      filterOrgs(listContainer, noResults, query);
    });

    clearBtn.addEventListener('click', () => {
      searchInput.value = '';
      clearBtn.classList.remove('sc-visible');
      filterOrgs(listContainer, noResults, '');
      searchInput.focus();
    });

    searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        searchInput.value = '';
        clearBtn.classList.remove('sc-visible');
        filterOrgs(listContainer, noResults, '');
      }
    });

    console.log(
      '%c[SC Helper]%c MasterPanel search bar injected beside Build+ link.',
      'color:#cc3232;font-weight:bold', 'color:inherit'
    );
  }

  function attachMasterPanels() {
    for (const panel of document.querySelectorAll(MASTER_PANEL_SEL)) {
      injectMasterToolbar(panel);
    }
  }

  // ---------------------------------------------------------------------------
  // DOM helpers
  // ---------------------------------------------------------------------------
  function isElement(node) {
    return !!node && node.nodeType === Node.ELEMENT_NODE;
  }

  function getListPanels(root = document) {
    return Array.from(root.querySelectorAll(LIST_SELECTOR));
  }

  function splitIntoCommandGroups(listPanel) {
    const entries = Array.from(listPanel.querySelectorAll(ENTRY_SELECTOR));
    const groups  = [];
    let currentGroup = [];

    for (const entry of entries) {
      if (!isElement(entry)) continue;

      if (entry.matches(GROUP_START_SEL)) {
        if (currentGroup.length) groups.push(currentGroup);
        currentGroup = [entry];
        continue;
      }

      if (!currentGroup.length) {
        currentGroup = [entry];
      } else {
        currentGroup.push(entry);
      }
    }

    if (currentGroup.length) groups.push(currentGroup);
    return groups;
  }

  function scrubAndRemove(node) {
    if (!isElement(node)) return;
    for (const d of node.querySelectorAll('.Data')) d.textContent = '';
    node.replaceChildren();
    node.remove();
  }

  // ---------------------------------------------------------------------------
  // Prune
  // ---------------------------------------------------------------------------
  function pruneListPanel(listPanel) {
    if (!isElement(listPanel)) return 0;

    const groups = splitIntoCommandGroups(listPanel);
    if (groups.length <= KEEP_LAST_COMMANDS) return 0;

    const toRemove = groups.slice(0, groups.length - KEEP_LAST_COMMANDS);
    for (const group of toRemove) {
      for (const node of group) scrubAndRemove(node);
    }

    return toRemove.length;
  }

  function pruneAll() {
    pruneQueued = false;
    let totalRemoved = 0;

    for (const listPanel of getListPanels()) {
      totalRemoved += pruneListPanel(listPanel);
    }

    if (totalRemoved > 0) {
      const label = totalRemoved === 1 ? 'group' : 'groups';
      console.log(
        '%c[SC Helper]%c Pruned %c' + totalRemoved + '%c command ' + label +
        '. Keeping last %c' + KEEP_LAST_COMMANDS + '%c. ' +
        'To adjust: %clocalStorage.setItem(\'scKeepLastCommandsLimit\', N)%c then reload.',
        'color:#cc3232;font-weight:bold', 'color:inherit',
        'color:#cc3232;font-weight:bold', 'color:inherit',
        'color:#2d862d;font-weight:bold', 'color:inherit',
        'color:#cc7a00;font-weight:bold', 'color:inherit'
      );
      showToast(
        'Last ' + KEEP_LAST_COMMANDS + ' Commands Kept - ' +
        totalRemoved + ' Older ' + (totalRemoved === 1 ? 'Entry' : 'Entries') + ' Cleared'
      );
    }
  }

  function queuePrune() {
    if (pruneQueued) return;
    pruneQueued = true;
    requestAnimationFrame(pruneAll);
  }

  // ---------------------------------------------------------------------------
  // Observers
  // ---------------------------------------------------------------------------
  function attachListObserver(listPanel) {
    if (!isElement(listPanel) || listPanel.dataset[OBSERVER_KEY] === '1') return;
    new MutationObserver(() => queuePrune()).observe(listPanel, { childList: true, subtree: true });
    listPanel.dataset[OBSERVER_KEY] = '1';
  }

  function init() {
    const listPanels = getListPanels();
    const found = !!listPanels.length;
    for (const lp of listPanels) attachListObserver(lp);
    attachEntryPanels();
    attachMasterPanels();
    if (found) queuePrune();
    return found;
  }

  new MutationObserver(() => {
    attachMasterPanels();
    if (init()) queuePrune();
  }).observe(document.documentElement || document.body, { childList: true, subtree: true });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
