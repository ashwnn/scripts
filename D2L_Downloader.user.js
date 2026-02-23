// ==UserScript==
// @name         D2L Downloader
// @namespace    https://violentmonkey.github.io/
// @version      3.0
// @description  Downloads all files from D2L content pages with a single click.
// @author       ashwnn
// @match        *://learn.bcit.ca/d2l/le/content/*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    // Configuration
    const DELAY_MS = 1500; // 1.5 seconds delay to prevent server rate-limiting
    const ALLOWED_TYPES = [
        "pdf document",
        "word document",
        "powerpoint presentation",
        "excel spreadsheet",
        "text document"
    ];

    // CSS Styling
    const style = document.createElement('style');
    style.innerHTML = `
        :root {
            --bcit-font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, "Apple Color Emoji", "Segoe UI Emoji";
            --bcit-bg: rgba(17, 17, 17, 0.92);
            --bcit-bg-hover: rgba(17, 17, 17, 0.98);
            --bcit-border: rgba(255, 255, 255, 0.14);
            --bcit-border-strong: rgba(255, 255, 255, 0.22);
            --bcit-text: rgba(255, 255, 255, 0.92);
            --bcit-muted: rgba(255, 255, 255, 0.70);
            --bcit-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
            --bcit-shadow-strong: 0 24px 70px rgba(0, 0, 0, 0.55);
            --bcit-radius: 999px;
            --bcit-radius-inner: 12px;
            --bcit-green: #00d26a;
            --bcit-ring: 0 0 0 4px rgba(255, 255, 255, 0.10);
        }

        @keyframes bcit-in {
            from { transform: translateY(10px) scale(0.99); opacity: 0; }
            to { transform: translateY(0) scale(1); opacity: 1; }
        }

        @keyframes bcit-spin {
            to { transform: rotate(360deg); }
        }

        @keyframes bcit-shimmer {
            0% { transform: translateX(-120%); opacity: 0; }
            15% { opacity: 0.22; }
            55% { opacity: 0.12; }
            100% { transform: translateX(120%); opacity: 0; }
        }

        #bcit-dl-btn {
            position: fixed;
            bottom: 24px;
            right: 24px;
            z-index: 999999;

            display: flex;
            align-items: center;
            gap: 12px;

            padding: 10px 14px 10px 10px;
            border-radius: var(--bcit-radius);
            border: 1px solid var(--bcit-border);

            background: linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0.03)) , var(--bcit-bg);
            color: var(--bcit-text);

            font-family: var(--bcit-font);
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.2px;

            box-shadow: var(--bcit-shadow);
            cursor: pointer;

            -webkit-font-smoothing: antialiased;
            text-rendering: geometricPrecision;

            transition: transform 160ms ease, box-shadow 160ms ease, border-color 160ms ease, background 160ms ease, filter 160ms ease;
            animation: bcit-in 220ms ease-out 1;
            overflow: hidden;

            backdrop-filter: blur(10px);
            -webkit-backdrop-filter: blur(10px);
        }

        #bcit-dl-btn::after {
            content: "";
            position: absolute;
            inset: 0;
            background: linear-gradient(90deg, rgba(255,255,255,0) 0%, rgba(255,255,255,0.20) 45%, rgba(255,255,255,0) 75%);
            transform: translateX(-120%);
            opacity: 0;
            pointer-events: none;
        }

        #bcit-dl-btn:hover:not(:disabled) {
            transform: translateY(-2px);
            box-shadow: var(--bcit-shadow-strong);
            border-color: var(--bcit-border-strong);
            background: linear-gradient(180deg, rgba(255,255,255,0.07), rgba(255,255,255,0.03)) , var(--bcit-bg-hover);
        }

        #bcit-dl-btn:hover:not(:disabled)::after {
            opacity: 1;
            animation: bcit-shimmer 900ms ease-out 1;
        }

        #bcit-dl-btn:active:not(:disabled) {
            transform: translateY(-1px) scale(0.995);
            box-shadow: var(--bcit-shadow);
        }

        #bcit-dl-btn:focus-visible {
            outline: none;
            box-shadow: var(--bcit-ring), var(--bcit-shadow-strong);
            border-color: rgba(255,255,255,0.30);
        }

        #bcit-dl-btn:disabled {
            cursor: not-allowed;
            opacity: 0.92;
            filter: saturate(0.9);
        }

        .bcit-pill {
            width: 34px;
            height: 34px;
            border-radius: var(--bcit-radius);
            display: grid;
            place-items: center;
            border: 1px solid rgba(255,255,255,0.12);
            background: linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0.03));
            box-shadow: inset 0 1px 0 rgba(255,255,255,0.08);
            flex: 0 0 auto;
        }

        .bcit-dl-icon {
            width: 18px;
            height: 18px;
            fill: rgba(255,255,255,0.92);
        }

        #bcit-dl-btn[aria-busy="true"] .bcit-dl-icon {
            animation: bcit-spin 900ms linear infinite;
            transform-origin: 50% 50%;
        }

        .bcit-text {
            display: flex;
            flex-direction: column;
            line-height: 1.15;
            gap: 2px;
            padding-right: 6px;
            white-space: nowrap;
        }

        .bcit-title {
            font-size: 13px;
            font-weight: 650;
        }

        .bcit-sub {
            font-size: 11.5px;
            color: var(--bcit-muted);
            font-weight: 600;
        }

        .bcit-progress {
            position: absolute;
            left: 0;
            top: 0;
            bottom: 0;
            width: 0%;
            pointer-events: none;
            background: linear-gradient(90deg, rgba(0, 210, 106, 0.00) 0%, rgba(0, 210, 106, 0.16) 45%, rgba(0, 210, 106, 0.06) 100%);
            transition: width 180ms ease;
            mix-blend-mode: screen;
        }

        #bcit-dl-btn.bcit-done {
            border-color: rgba(0, 210, 106, 0.35);
        }

        #bcit-dl-btn.bcit-done .bcit-pill {
            border-color: rgba(0, 210, 106, 0.35);
            background: linear-gradient(180deg, rgba(0,210,106,0.20), rgba(0,210,106,0.10));
        }

        #bcit-dl-btn.bcit-done .bcit-sub {
            color: rgba(0, 210, 106, 0.85);
        }

        @media (max-width: 520px) {
            #bcit-dl-btn {
                bottom: 16px;
                right: 16px;
            }
        }
    `;
    document.head.appendChild(style);

    // SVG Icon
    const downloadIcon = `
        <svg class="bcit-dl-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
            <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/>
        </svg>
    `;

    // Sleep Helper
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

    // Helper to extract IDs
    function parseLink(href) {
        const match = href.match(/\/content\/(\d+)\/viewContent\/(\d+)\/View/);
        return match ? { courseId: match[1], topicId: match[2] } : null;
    }

    // Identify downloadable items
    function getDownloadableItems() {
        const items = [];
        const links = document.querySelectorAll('a.d2l-link[href*="/viewContent/"]');

        links.forEach(link => {
            // Skip if already downloaded
            if (link.dataset.downloaded === "true") return;

            const container = link.closest('.d2l-inline.d2l-topic-view') || link.closest('.d2l-inline');
            if (!container) return;

            const typeLabel = container.querySelector('.d2l-textblock.d2l-body-small');
            if (typeLabel) {
                const typeText = typeLabel.innerText.trim().toLowerCase();
                
                // Check if it matches any allowed types
                const isAllowed = ALLOWED_TYPES.some(t => typeText.includes(t));
                
                if (isAllowed) {
                    const ids = parseLink(link.getAttribute('href'));
                    if (ids) {
                        items.push({
                            title: link.innerText.trim(),
                            courseId: ids.courseId,
                            topicId: ids.topicId,
                            element: link
                        });
                    }
                }
            }
        });
        return items;
    }

    // Trigger download
    function triggerDownload(item) {
        const url = `${window.location.origin}/d2l/le/content/${item.courseId}/topics/files/download/${item.topicId}/DirectFileTopicDownload`;
        
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        iframe.src = url;
        document.body.appendChild(iframe);
        
        // Clean up DOM
        setTimeout(() => document.body.removeChild(iframe), 30000);

        // Visual feedback on the actual link
        item.element.style.color = "#008a00";
        item.element.style.fontWeight = "bold";
        item.element.innerHTML = "✔ " + item.element.innerText;
        item.element.dataset.downloaded = "true"; // Prevent duplicate downloads
    }

    // Batch Process (Using Async/Await)
    async function startBatchDownload(btn, textSpan) {
        btn.disabled = true;

        // Auto-Expand folders so we don't miss hidden items
        const expandBtns = Array.from(document.querySelectorAll('a.d2l-link')).filter(a => a.innerText.trim() === "Expand All");
        if (expandBtns.length > 0 && expandBtns[0].offsetParent !== null) {
            textSpan.innerText = "Expanding folders...";
            btn.querySelector('.bcit-sub').innerText = "Preparing";
            expandBtns[0].click();
            await sleep(2000); // Wait for DOM to render expanded items
        }

        const items = getDownloadableItems();
        
        if (items.length === 0) {
            alert("No new downloadable files found. Check if they are already downloaded or if the page hasn't fully loaded.");
            btn.disabled = false;
            textSpan.innerText = "Download All Files";
            btn.querySelector('.bcit-sub').innerText = "Ready";
            btn.removeAttribute('aria-busy');
            btn.classList.remove('bcit-done');
            btn.querySelector('.bcit-progress').style.width = '0%';
            btn.style.background = "";
            return;
        }

        if (!confirm(`Found ${items.length} files. Start downloading?`)) {
            btn.disabled = false;
            textSpan.innerText = "Download All Files";
            btn.querySelector('.bcit-sub').innerText = "Ready";
            btn.removeAttribute('aria-busy');
            btn.querySelector('.bcit-progress').style.width = '0%';
            btn.style.background = "";
            return;
        }

        btn.setAttribute('aria-busy', 'true');
        btn.classList.remove('bcit-done');
        btn.querySelector('.bcit-sub').innerText = "Downloading";
        btn.querySelector('.bcit-progress').style.width = '0%';

        // Processing loop
        for (let i = 0; i < items.length; i++) {
            const percentage = Math.round(((i + 1) / items.length) * 100);
            
            // Update UI text and background progress bar
            textSpan.innerText = `Downloading ${i + 1}/${items.length} (${percentage}%)`;
            btn.querySelector('.bcit-progress').style.width = `${percentage}%`;
            
            triggerDownload(items[i]);
            await sleep(DELAY_MS);
        }

        // Completion
        btn.removeAttribute('aria-busy');
        btn.classList.add('bcit-done');
        btn.querySelector('.bcit-progress').style.width = '100%';
        btn.querySelector('.bcit-sub').innerText = "Completed";
        textSpan.innerText = "Downloaded All Files";

        // Reset button after 5 seconds
        setTimeout(() => {
            btn.disabled = false;
            btn.classList.remove('bcit-done');
            btn.querySelector('.bcit-progress').style.width = '0%';
            btn.querySelector('.bcit-sub').innerText = "Ready";
            textSpan.innerText = "Download All Files";
        }, 5000);
    }

    // UI Initialization
    function init() {
        // Prevent duplicate buttons
        if (document.getElementById('bcit-dl-btn')) return;

        const btn = document.createElement('button');
        btn.id = 'bcit-dl-btn';
        btn.setAttribute('type', 'button');
        btn.setAttribute('aria-label', 'Download all files');
        
        btn.innerHTML = `
            <span class="bcit-progress" aria-hidden="true"></span>
            <span class="bcit-pill" aria-hidden="true">
                ${downloadIcon}
            </span>
            <span class="bcit-text">
                <span class="bcit-title">Download All Files</span>
                <span class="bcit-sub">Ready</span>
            </span>
        `;

        const textSpan = btn.querySelector('.bcit-title');

        btn.onclick = async (e) => {
            e.preventDefault();
            await startBatchDownload(btn, textSpan);
        };

        document.body.appendChild(btn);
    }

    // Ensure button exists even if D2L uses single-page navigation without full reloads
    setInterval(() => {
        // Only inject if we are on a content page
        if (window.location.href.includes('/d2l/le/content/')) {
            init();
        } else {
            const btn = document.getElementById('bcit-dl-btn');
            if (btn) btn.remove();
        }
    }, 1500);

})();