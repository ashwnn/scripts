// ==UserScript==
// @name         ScreenConnect Helper
// @namespace    local
// @version      1.3.2
// @icon         https://www.screenconnect.com/siteassets/media/logos/screenconnect-icon-48x48.png
// @author       Ashwin C.
// @description  Automatically prunes old command history in ScreenConnect, keeping only the most recent N groups, and adds a toggleable PowerShell mode to the command entry panel.
// @match        *://help.tecnet.ca/*
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

  const LIST_SELECTOR   = '.Commands .ListPanel';
  const GROUP_START_SEL = '.Host.QueuedCommand';
  const ENTRY_SELECTOR  = ':scope > div';
  const ENTRY_PANEL_SEL = '.Commands .EntryPanel';
  const OBSERVER_KEY    = 'scKeepLastCommandsObserverAttached';
  const ENTRY_PANEL_KEY = 'scPsToggleAttached';
  const TOAST_ID        = 'sc-helper-toast';
  const PS_PREFIX       = '#!ps\n';

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
    void toast.offsetWidth; // force reflow to restart the transition
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

    // Build toggle wrapper
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

    // Override the textarea value getter to prepend the PS prefix when active
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
    if (found) queuePrune();
    return found;
  }

  // Re-run init whenever the DOM changes (handles SPA navigation / late rendering)
  new MutationObserver(() => {
    if (init()) queuePrune();
  }).observe(document.documentElement || document.body, { childList: true, subtree: true });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
