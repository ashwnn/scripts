// ==UserScript==
// @name         M365 Copilot Chat Exporter 
// @namespace    https://github.com/ashwnn/scripts
// @version      5.4
// @description  Export current/all Microsoft 365 Copilot conversations as ChatGPT-compatible conversations.json
// @license      MIT
// @author       ingo
// @match        https://m365.cloud.microsoft/
// @match        https://m365.cloud.microsoft/chat*
// @match        https://microsoft365.com/chat*
// @match        https://www.microsoft365.com/chat*
// @icon         data:image/svg+xml;base64,PHN2ZyBoZWlnaHQ9IjFlbSIgc3R5bGU9ImZsZXg6bm9uZTtsaW5lLWhlaWdodDoxIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHdpZHRoPSIxZW0iIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHRpdGxlPkNvcGlsb3Q8L3RpdGxlPjxwYXRoIGQ9Ik0xNy41MzMgMS44MjlBMi41MjggMi41MjggMCAwMDE1LjExIDBoLS43MzdhMi41MzEgMi41MzEgMCAwMC0yLjQ4NCAyLjA4N2wtMS4yNjMgNi45MzcuMzE0LTEuMDhhMi41MjggMi41MjggMCAwMTIuNDI0LTEuODMzaDQuMjg0bDEuNzk3LjcwNiAxLjczMS0uNzA2aC0uNTA1YTIuNTI4IDIuNTI4IDAgMDEtMi40MjMtMS44MjlsLS43MTUtMi40NTN6IiBmaWxsPSJ1cmwoI2xvYmUtaWNvbnMtY29waWxvdC0wLV9SXzBfKSIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMCAxKSI+PC9wYXRoPjxwYXRoIGQ9Ik02LjcyNiAyMC4xNkEyLjUyOCAyLjUyOCAwIDAwOS4xNTIgMjJoMS41NjZjMS4zNyAwIDIuNDktMS4xIDIuNTI1LTIuNDhsLjE3LTYuNjktLjM1NyAxLjIyOGEyLjUyOCAyLjUyOCAwIDAxLTIuNDIzIDEuODNoLTQuMzJsLTEuNTQtLjg0Mi0xLjY2Ny44NDNoLjQ5N2MxLjEyNCAwIDIuMTEzLjc1IDIuNDI2IDEuODRsLjY5NyAyLjQzMnoiIGZpbGw9InVybCgjbG9iZS1pY29ucy1jb3BpbG90LTEtX1JfMF8pIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgwIDEpIj48L3BhdGg+PHBhdGggZD0iTTE1IDBINi4yNTJjLTIuNSAwLTQgMy4zMzEtNSA2LjY2Mi0xLjE4NCAzLjk0Ny0yLjczNCA5LjIyNSAxLjc1IDkuMjI1SDYuNzhjMS4xMyAwIDIuMTItLjc1MyAyLjQzLTEuODQ3LjY1Ny0yLjMxNyAxLjgwOS02LjM1OSAyLjcxMy05LjQzNi40Ni0xLjU2My44NDItMi45MDYgMS40My0zLjc0MkExLjk3IDEuOTcgMCAwMTE1IDAiIGZpbGw9InVybCgjbG9iZS1pY29ucy1jb3BpbG90LTItX1JfMF8pIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgwIDEpIj48L3BhdGg+PHBhdGggZD0iTTE1IDBINi4yNTJjLTIuNSAwLTQgMy4zMzEtNSA2LjY2Mi0xLjE4NCAzLjk0Ny0yLjczNCA5LjIyNSAxLjc1IDkuMjI1SDYuNzhjMS4xMyAwIDIuMTItLjc1MyAyLjQzLTEuODQ3LjY1Ny0yLjMxNyAxLjgwOS02LjM1OSAyLjcxMy05LjQzNi40Ni0xLjU2My44NDItMi45MDYgMS40My0zLjc0MkExLjk3IDEuOTcgMCAwMTE1IDAiIGZpbGw9InVybCgjbG9iZS1pY29ucy1jb3BpbG90LTMtX1JfMF8pIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgwIDEpIj48L3BhdGg+PHBhdGggZD0iTTkgMjJoOC43NDljMi41IDAgNC0zLjMzMiA1LTYuNjYzIDEuMTg0LTMuOTQ4IDIuNzM0LTkuMjI3LTEuNzUtOS4yMjdIMTcuMjJjLTEuMTI5IDAtMi4xMi43NTQtMi40MyAxLjg0OGExMTQ5LjIgMTE0OS4yIDAgMDEtMi43MTMgOS40MzdjLS40NiAxLjU2NC0uODQyIDIuOTA3LTEuNDMgMy43NDNBMS45NyAxLjk3IDAgMDE5IDIyIiBmaWxsPSJ1cmwoI2xvYmUtaWNvbnMtY29waWxvdC00LV9SXzBfKSIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMCAxKSI+PC9wYXRoPjxwYXRoIGQ9Ik05IDIyaDguNzQ5YzIuNSAwIDQtMy4zMzIgNS02LjY2MyAxLjE4NC0zLjk0OCAyLjczNC05LjIyNy0xLjc1LTkuMjI3SDE3LjIyYy0xLjEyOSAwLTIuMTIuNzU0LTIuNDMgMS44NDhhMTE0OS4yIDExNDkuMiAwIDAxLTIuNzEzIDkuNDM3Yy0uNDYgMS41NjQtLjg0MiAyLjkwNy0xLjQzIDMuNzQzQTEuOTcgMS45NyAwIDAxOSAyMiIgZmlsbD0idXJsKCNsb2JlLWljb25zLWNvcGlsb3QtNS1fUl8wXykiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDAgMSkiPjwvcGF0aD48ZGVmcz48cmFkaWFsR3JhZGllbnQgY3g9Ijg1LjQ0JSIgY3k9IjEwMC42NTMlIiBmeD0iODUuNDQlIiBmeT0iMTAwLjY1MyUiIGdyYWRpZW50VHJhbnNmb3JtPSJzY2FsZSgtLjg1NTMgLTEpIHJvdGF0ZSg1MC45MjcgMi4wNDEgLTEuOTQ2KSIgaWQ9ImxvYmUtaWNvbnMtY29waWxvdC0wLV9SXzBfIiByPSIxMDUuMTE2JSI+PHN0b3Agb2Zmc2V0PSI5LjYlIiBzdG9wLWNvbG9yPSIjMDBBRUZGIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSI3Ny4zJSIgc3RvcC1jb2xvcj0iIzIyNTNDRSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iMTAwJSIgc3RvcC1jb2xvcj0iIzA3MzZDNCI+PC9zdG9wPjwvcmFkaWFsR3JhZGllbnQ+PHJhZGlhbEdyYWRpZW50IGN4PSIxOC4xNDMlIiBjeT0iMzIuOTI4JSIgZng9IjE4LjE0MyUiIGZ5PSIzMi45MjglIiBncmFkaWVudFRyYW5zZm9ybT0ic2NhbGUoLjg4OTcgMSkgcm90YXRlKDUyLjA2OSAuMTkzIC4zNTIpIiBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTEtX1JfMF8iIHI9Ijk1LjYxMiUiPjxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiNGRkI2NTciPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjYzLjQlIiBzdG9wLWNvbG9yPSIjRkY1RjNEIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSI5Mi4zJSIgc3RvcC1jb2xvcj0iI0MwMkIzQyI+PC9zdG9wPjwvcmFkaWFsR3JhZGllbnQ+PHJhZGlhbEdyYWRpZW50IGN4PSI4Mi45ODclIiBjeT0iLTkuNzkyJSIgZng9IjgyLjk4NyUiIGZ5PSItOS43OTIlIiBncmFkaWVudFRyYW5zZm9ybT0ic2NhbGUoLTEgLS45NDQxKSByb3RhdGUoLTcwLjg3MiAuMTQyIDEuMTcpIiBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTQtX1JfMF8iIHI9IjE0MC42MjIlIj48c3RvcCBvZmZzZXQ9IjYuNiUiIHN0b3AtY29sb3I9IiM4QzQ4RkYiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjUwJSIgc3RvcC1jb2xvcj0iI0YyNTk4QSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iODkuNiUiIHN0b3AtY29sb3I9IiNGRkIxNTIiPjwvc3RvcD48L3JhZGlhbEdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTItX1JfMF8iIHgxPSIzOS40NjUlIiB4Mj0iNDYuODg0JSIgeTE9IjEyLjExNyUiIHkyPSIxMDMuNzc0JSI+PHN0b3Agb2Zmc2V0PSIxNS42JSIgc3RvcC1jb2xvcj0iIzBEOTFFMSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iNDguNyUiIHN0b3AtY29sb3I9IiM1MkI0NzEiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjY1LjIlIiBzdG9wLWNvbG9yPSIjOThCRDQyIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSI5My43JSIgc3RvcC1jb2xvcj0iI0ZGQzgwMCI+PC9zdG9wPjwvbGluZWFyR3JhZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJsb2JlLWljb25zLWNvcGlsb3QtMy1fUl8wXyIgeDE9IjQ1Ljk0OSUiIHgyPSI1MCUiIHkxPSIwJSIgeTI9IjEwMCUiPjxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMzRENCRkYiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjI0LjclIiBzdG9wLWNvbG9yPSIjMDU4OEY3IiBzdG9wLW9wYWNpdHk9IjAiPjwvc3RvcD48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTUtX1JfMF8iIHgxPSI4My41MDclIiB4Mj0iODMuNDUzJSIgeTE9Ii02LjEwNiUiIHkyPSIyMS4xMzElIj48c3RvcCBvZmZzZXQ9IjUuOCUiIHN0b3AtY29sb3I9IiNGOEFERkEiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjcwLjglIiBzdG9wLWNvbG9yPSIjQTg2RUREIiBzdG9wLW9wYWNpdHk9IjAiPjwvc3RvcD48L2xpbmVhckdyYWRpZW50PjwvZGVmcz48L3N2Zz4=
// @grant        none
// @run-at       document-end
// ==/UserScript==

(function () {
  "use strict";

  // State

  const conversations = new Map();
  const rawCaptures = [];
  let isFetchingAll = false;
  let isFetchingCurrent = false;
  let currentConversationId = null;
  let suppressCurrentConversationDetection = false;
  let observedSubstrateAuth = null;
  const capturedRequestTemplates = [];
  const capturedConversationPayloads = new Map();
  let lastStaticRouterHydrationData = null;
  const backgroundFetchedConversationIds = new Set();

  const SKIP_MESSAGE_TYPES = new Set([
    "CrossPluginGroundingData",
    "Internal",
    "InternalSuggestions",
    "InternalLoaderMessage",
    "InternalSearchResult",
    "InternalSearchQuery",
    "InternalUserSummary",
    "InternalActionMarker",
    "HintInvocation",
    "InvokeAction",
    "Progress",
    "Suggestion",
    "RenderCardRequest",
    "GenerateContentQuery",
    "AdsQuery",
  ]);

  // Utilities

  function sanitizeText(text) {
    if (!text) return text;
    let result = "";
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      const code = text.charCodeAt(i);

      if (code === 0x2028 || code === 0x2029) {
        result += " ";
      } else if (code >= 32) {
        result += char;
      } else if (code === 10 || code === 13) {
        result += " ";
      } else if (code === 9) {
        result += " ";
      }
    }
    return result;
  }

  // Date filtering

  function getDateRange() {
    const sel = document.getElementById("copilot-date-range");
    if (!sel) return null;
    const preset = sel.value;
    if (preset === "all") return null;

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    if (preset === "custom") {
      const fromEl = document.getElementById("copilot-date-from");
      const toEl = document.getElementById("copilot-date-to");
      const from = fromEl?.value ? new Date(fromEl.value) : null;
      const to = toEl?.value ? new Date(toEl.value) : null;
      if (!from && !to) return null;
      const toEnd = to ? new Date(to.getTime() + 86400000) : tomorrow;
      return { from: from || new Date(0), to: toEnd };
    }

    let from;
    switch (preset) {
      case "today":
        from = today;
        break;
      case "week": {
        from = new Date(today);
        from.setDate(from.getDate() - 7);
        break;
      }
      case "month": {
        from = new Date(today);
        from.setMonth(from.getMonth() - 1);
        break;
      }
      case "year": {
        from = new Date(today);
        from.setFullYear(from.getFullYear() - 1);
        break;
      }
      default:
        return null;
    }
    return { from, to: tomorrow };
  }

  function isInDateRange(conv, range) {
    if (!range) return true;
    const ts = conv.createTimeUtc;
    if (!ts) return true; // keep conversations with unknown dates
    const d = new Date(typeof ts === "number" && ts > 1e12 ? ts : ts);
    return d >= range.from && d < range.to;
  }

  const SUBSTRATE_BASE = "https://substrate.office.com/m365Copilot";
  const DEFAULT_VARIANTS =
    "feature.EnableLastMessageForGetChats,feature.EnableMRUAgents,feature.EnableHasLoopPages,feature.EnableIsInputControlInGptItem";

  // Auth discovery

  const getCookie = (key) =>
    document.cookie.match(`(^|;)\\s*${key}\\s*=\\s*([^;]+)`)?.pop() || "";

  function base64DecToArr(base64String) {
    let s = base64String.replace(/-/g, "+").replace(/_/g, "/");
    switch (s.length % 4) {
      case 2:
        s += "==";
        break;
      case 3:
        s += "=";
        break;
    }
    const bin = atob(s);
    return Uint8Array.from(bin, (c) => c.codePointAt(0) || 0);
  }

  function toArrayBuffer(bufferLike) {
    return Uint8Array.from(bufferLike).buffer;
  }

  async function deriveKey(baseKey, nonce, context) {
    return crypto.subtle.deriveKey(
      {
        name: "HKDF",
        salt: toArrayBuffer(nonce),
        hash: "SHA-256",
        info: new TextEncoder().encode(context),
      },
      baseKey,
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"],
    );
  }

  async function decryptPayload(baseKey, nonce, context, encryptedData) {
    const encoded = base64DecToArr(encryptedData);
    const derived = await deriveKey(baseKey, base64DecToArr(nonce), context);
    const decrypted = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: new Uint8Array(12) },
      derived,
      toArrayBuffer(encoded),
    );
    return new TextDecoder().decode(decrypted);
  }

  async function getEncryptionCookie() {
    const raw = decodeURIComponent(getCookie("msal.cache.encryption"));
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error("Failed to parse msal.cache.encryption cookie");
    }
    if (!parsed?.key || !parsed?.id)
      throw new Error("No encryption cookie found");
    return {
      id: parsed.id,
      key: await crypto.subtle.importKey(
        "raw",
        toArrayBuffer(base64DecToArr(parsed.key)),
        "HKDF",
        false,
        ["deriveKey"],
      ),
    };
  }

  const COPILOT_CLIENT_ID = "c0ab8ce9-e9a0-42e7-b064-33d422df41f1";
  const SUBSTRATE_SCOPE = "https://substrate.office.com/sydney/.default";

  function decodeBase64UrlJson(value) {
    if (!value) return null;
    try {
      let s = String(value).replace(/-/g, "+").replace(/_/g, "/");
      while (s.length % 4) s += "=";
      return JSON.parse(atob(s));
    } catch {
      return null;
    }
  }

  function decodeJwtClaims(token) {
    const parts = String(token || "").split(".");
    if (parts.length < 2) return null;
    return decodeBase64UrlJson(parts[1]);
  }

  function getMsalIdsFromIdentityElement() {
    const el = document.getElementById("identity");
    if (!el?.textContent) return null;

    try {
      const { objectId, tenantId } = JSON.parse(el.textContent);
      if (!objectId || !tenantId) return null;
      return {
        localAccountId: objectId,
        tenantId,
        homeAccountId: `${objectId}.${tenantId}`,
        clientId: COPILOT_CLIENT_ID,
      };
    } catch {
      return null;
    }
  }

  function getActiveAccountFilters() {
    const directKeys = [
      `msal.${COPILOT_CLIENT_ID}.active-account-filters`,
      `msal.${COPILOT_CLIENT_ID}.activeAccountFilters`,
    ];

    for (const key of directKeys) {
      try {
        const parsed = JSON.parse(localStorage.getItem(key) || "null");
        if (parsed?.localAccountId && parsed?.tenantId) {
          return {
            localAccountId: parsed.localAccountId,
            tenantId: parsed.tenantId,
            homeAccountId:
              parsed.homeAccountId ||
              `${parsed.localAccountId}.${parsed.tenantId}`,
            clientId: COPILOT_CLIENT_ID,
          };
        }
      } catch {}
    }

    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (!key || !key.includes("active-account-filters")) continue;
        const parsed = JSON.parse(localStorage.getItem(key) || "null");
        if (parsed?.localAccountId && parsed?.tenantId) {
          return {
            localAccountId: parsed.localAccountId,
            tenantId: parsed.tenantId,
            homeAccountId:
              parsed.homeAccountId ||
              `${parsed.localAccountId}.${parsed.tenantId}`,
            clientId: COPILOT_CLIENT_ID,
          };
        }
      }
    } catch {}

    return null;
  }

  function parseMsalAccessTokenKey(key) {
    if (!key || !String(key).toLowerCase().includes("accesstoken")) return null;
    const raw = String(key);

    if (raw.startsWith("msal.") && raw.includes("|")) {
      const parts = raw.split("|");
      const homeAccountId = parts[1] || null;
      const authority = parts[2] || null;
      const credentialType = (parts[3] || "").toLowerCase();
      const clientId = parts[4] || null;
      const tenantId = parts[5] || null;
      const target = parts[6] || "";

      if (credentialType !== "accesstoken") return null;
      if (clientId !== COPILOT_CLIENT_ID) return null;

      const localAccountId =
        homeAccountId && tenantId && homeAccountId.endsWith(`.${tenantId}`)
          ? homeAccountId.slice(0, -(tenantId.length + 1))
          : homeAccountId
            ? homeAccountId.split(".")[0]
            : null;

      return {
        format: "pipe",
        key: raw,
        authority,
        credentialType: "AccessToken",
        clientId,
        tenantId,
        realm: tenantId,
        target,
        homeAccountId,
        localAccountId,
      };
    }

    const marker = `-accesstoken-${COPILOT_CLIENT_ID}-`;
    const index = raw.indexOf(marker);
    if (index < 0) return null;

    const prefix = raw.slice(0, index);
    const rest = raw.slice(index + marker.length);
    const dashScopeIndex = rest.indexOf("-https://");
    const tenantId = dashScopeIndex >= 0 ? rest.slice(0, dashScopeIndex) : null;
    const target =
      dashScopeIndex >= 0
        ? rest.slice(dashScopeIndex + 1).replace(/--$/, "")
        : "";

    const knownAuthoritySuffixes = [
      "-login.windows.net",
      "-login.microsoftonline.com",
      "-sts.windows.net",
    ];

    let homeAccountId = null;
    for (const suffix of knownAuthoritySuffixes) {
      if (prefix.endsWith(suffix)) {
        homeAccountId = prefix.slice(0, -suffix.length);
        break;
      }
    }

    homeAccountId =
      homeAccountId || prefix.split("-").slice(0, -1).join("-") || null;
    const localAccountId =
      homeAccountId && tenantId && homeAccountId.endsWith(`.${tenantId}`)
        ? homeAccountId.slice(0, -(tenantId.length + 1))
        : homeAccountId
          ? homeAccountId.split(".")[0]
          : null;

    return {
      format: "dash",
      key: raw,
      authority: null,
      credentialType: "AccessToken",
      clientId: COPILOT_CLIENT_ID,
      tenantId,
      realm: tenantId,
      target,
      homeAccountId,
      localAccountId,
    };
  }

  function getTenantIdFromAccessTokenKey(key) {
    return parseMsalAccessTokenKey(key)?.tenantId || null;
  }

  function getHomeAccountIdFromAccessTokenKey(key) {
    return parseMsalAccessTokenKey(key)?.homeAccountId || null;
  }

  function isSubstrateTokenKey(key) {
    const parsed = parseMsalAccessTokenKey(key);
    if (!parsed) return false;
    const target = String(parsed.target || "").toLowerCase();
    return (
      target.includes("https://substrate.office.com/sydney/.default") ||
      target.includes("https://substrate.office.com/.default") ||
      target.includes("https://substrate.office.com/search/.default")
    );
  }

  function substrateKeyRank(key) {
    const target = String(
      parseMsalAccessTokenKey(key)?.target || "",
    ).toLowerCase();
    if (target.includes("https://substrate.office.com/sydney/.default"))
      return 0;
    if (target.includes("https://substrate.office.com/.default")) return 1;
    if (target.includes("https://substrate.office.com/search/.default"))
      return 2;
    return 9;
  }

  function buildAuthFromToken(token, key = "", preferredIds = null) {
    const claims = decodeJwtClaims(token) || {};
    const tenantId =
      preferredIds?.tenantId ||
      claims.tid ||
      getTenantIdFromAccessTokenKey(key);
    const localAccountId =
      preferredIds?.localAccountId || claims.oid || claims.sub;
    const homeAccountId =
      preferredIds?.homeAccountId ||
      getHomeAccountIdFromAccessTokenKey(key) ||
      (localAccountId && tenantId ? `${localAccountId}.${tenantId}` : null);

    if (!token || !tenantId || !localAccountId) return null;

    if (claims.exp && Date.now() >= Number(claims.exp) * 1000) {
      return null;
    }

    return {
      token,
      localAccountId,
      tenantId,
      homeAccountId,
      clientId: COPILOT_CLIENT_ID,
    };
  }

  function readHeader(headers, name) {
    if (!headers || !name) return null;
    const wanted = name.toLowerCase();

    try {
      if (typeof headers.get === "function") {
        return headers.get(name) || headers.get(wanted);
      }
    } catch {}

    if (Array.isArray(headers)) {
      for (const entry of headers) {
        if (!Array.isArray(entry) || entry.length < 2) continue;
        if (String(entry[0]).toLowerCase() === wanted) return String(entry[1]);
      }
      return null;
    }

    if (typeof headers === "object") {
      for (const key of Object.keys(headers)) {
        if (key.toLowerCase() === wanted) return String(headers[key]);
      }
    }

    return null;
  }

  function parseAnchorMailbox(value) {
    const match = String(value || "").match(/^Oid:([^@]+)@([^@]+)$/i);
    if (!match) return null;
    return {
      localAccountId: match[1],
      tenantId: match[2],
      homeAccountId: `${match[1]}.${match[2]}`,
    };
  }

  function captureAuthFromHeaders(headers, source) {
    const authHeader = readHeader(headers, "authorization");
    const tokenMatch = String(authHeader || "").match(/^Bearer\s+(.+)$/i);
    if (!tokenMatch) return;

    const anchorMailbox = readHeader(headers, "x-anchormailbox");
    const routingSessionKey = readHeader(
      headers,
      "x-routingparameter-sessionkey",
    );
    const scenario = readHeader(headers, "x-scenario");
    const preferredIds = parseAnchorMailbox(anchorMailbox);
    const auth = buildAuthFromToken(tokenMatch[1], "", preferredIds);
    if (!auth) return;

    observedSubstrateAuth = {
      ...auth,
      anchorMailbox:
        anchorMailbox || `Oid:${auth.localAccountId}@${auth.tenantId}`,
      routingSessionKey: routingSessionKey || auth.localAccountId,
      scenario: scenario || "OfficeWebIncludedCopilot",
    };

    console.log(`[Copilot Export] Captured page Substrate auth from ${source}`);
  }

  function getObservedSubstrateAuth() {
    if (!observedSubstrateAuth?.token) return null;

    const auth = buildAuthFromToken(
      observedSubstrateAuth.token,
      "",
      observedSubstrateAuth,
    );
    if (!auth) {
      observedSubstrateAuth = null;
      return null;
    }

    return {
      ...auth,
      anchorMailbox:
        observedSubstrateAuth.anchorMailbox ||
        `Oid:${auth.localAccountId}@${auth.tenantId}`,
      routingSessionKey:
        observedSubstrateAuth.routingSessionKey || auth.localAccountId,
      scenario: observedSubstrateAuth.scenario || "OfficeWebIncludedCopilot",
    };
  }

  function cloneRequestHeaders(headers) {
    const out = {};
    if (!headers) return out;

    try {
      if (typeof Headers !== "undefined" && headers instanceof Headers) {
        headers.forEach((value, key) => {
          out[key] = value;
        });
        return out;
      }
    } catch {}

    if (Array.isArray(headers)) {
      for (const entry of headers) {
        if (!Array.isArray(entry) || entry.length < 2) continue;
        out[String(entry[0])] = String(entry[1]);
      }
      return out;
    }

    if (typeof headers === "object") {
      for (const key of Object.keys(headers)) {
        if (headers[key] == null) continue;
        out[key] = String(headers[key]);
      }
    }

    return out;
  }

  function getFetchRequestDetails(args) {
    const input = args[0];
    const init = args[1] || {};
    const url = typeof input === "string" ? input : input?.url || "";
    const method = init.method || input?.method || "GET";
    const headers = {
      ...cloneRequestHeaders(input?.headers),
      ...cloneRequestHeaders(init.headers),
    };
    return {
      url: String(url || ""),
      method: String(method || "GET").toUpperCase(),
      headers,
    };
  }

  function rememberPageRequestTemplate(url, method, headers, source) {
    if (!url || !String(url).includes("substrate.office.com/m365Copilot/"))
      return;
    if (!/GetConversation|GetChats/i.test(String(url))) return;

    const endpoint = String(url).includes("GetConversation")
      ? "GetConversation"
      : "GetChats";
    const headerCopy = { ...headers };

    for (const key of Object.keys(headerCopy)) {
      if (/^(host|content-length)$/i.test(key)) delete headerCopy[key];
    }

    capturedRequestTemplates.push({
      endpoint,
      url: String(url),
      method: method || "GET",
      headers: headerCopy,
      source,
      timestamp: Date.now(),
    });

    while (capturedRequestTemplates.length > 20)
      capturedRequestTemplates.shift();
  }

  function rememberCapturedConversation(data) {
    const convId = normalizeConversationId(data?.conversationId);
    if (!convId) return;
    capturedConversationPayloads.set(convId, data);
    while (capturedConversationPayloads.size > 25) {
      const first = capturedConversationPayloads.keys().next().value;
      capturedConversationPayloads.delete(first);
    }
  }

  async function readAccessTokenPayload(
    cookie,
    stored,
    preferredIds = null,
    key = "",
  ) {
    let payload;
    try {
      payload = JSON.parse(stored);
    } catch {
      return null;
    }

    if (payload?.secret) {
      return buildAuthFromToken(
        payload.secret,
        key,
        preferredIds || parseMsalAccessTokenKey(key),
      );
    }

    if (!payload?.nonce || !payload?.data || !cookie?.key) return null;

    try {
      const decrypted = await decryptPayload(
        cookie.key,
        payload.nonce,
        COPILOT_CLIENT_ID,
        payload.data,
      );
      const parsed = JSON.parse(decrypted);
      const token = parsed.secret || parsed.access_token || parsed.accessToken;
      return buildAuthFromToken(
        token,
        key,
        preferredIds || parseMsalAccessTokenKey(key),
      );
    } catch {
      return null;
    }
  }

  async function getAccessTokenFromExactKey(cookie, msalIds) {
    if (!msalIds) return null;

    const exactKeys = [
      `msal.2|${msalIds.homeAccountId}|login.microsoftonline.com|accesstoken|${COPILOT_CLIENT_ID}|${msalIds.tenantId}|https://substrate.office.com/sydney/.default||`,
      `msal.2|${msalIds.homeAccountId}|login.windows.net|accesstoken|${COPILOT_CLIENT_ID}|${msalIds.tenantId}|https://substrate.office.com/sydney/.default||`,
      `msal.2|${msalIds.homeAccountId}|login.microsoftonline.com|accesstoken|${COPILOT_CLIENT_ID}|${msalIds.tenantId}|https://substrate.office.com/.default||`,
      `msal.2|${msalIds.homeAccountId}|login.windows.net|accesstoken|${COPILOT_CLIENT_ID}|${msalIds.tenantId}|https://substrate.office.com/.default||`,
      `${msalIds.homeAccountId}-login.windows.net-accesstoken-${COPILOT_CLIENT_ID}-${msalIds.tenantId}-${SUBSTRATE_SCOPE}--`,
      `${msalIds.homeAccountId}-login.microsoftonline.com-accesstoken-${COPILOT_CLIENT_ID}-${msalIds.tenantId}-${SUBSTRATE_SCOPE}--`,
    ];

    for (const lsKey of exactKeys) {
      let stored = null;
      try {
        stored = localStorage.getItem(lsKey);
      } catch {
        stored = null;
      }
      if (!stored) continue;
      const auth = await readAccessTokenPayload(cookie, stored, msalIds, lsKey);
      if (auth) return auth;
    }

    return null;
  }

  async function findSubstrateAccessToken(cookie, preferredIds = null) {
    const candidates = [];

    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (!key) continue;
        if (!isSubstrateTokenKey(key)) continue;
        candidates.push(key);
      }
    } catch {}

    candidates.sort((a, b) => substrateKeyRank(a) - substrateKeyRank(b));

    for (const key of candidates) {
      let stored = null;
      try {
        stored = localStorage.getItem(key);
      } catch {
        stored = null;
      }
      if (!stored) continue;

      const keyIds = parseMsalAccessTokenKey(key);
      const auth = await readAccessTokenPayload(
        cookie,
        stored,
        preferredIds || keyIds,
        key,
      );
      if (auth) return auth;
    }

    return null;
  }

  async function getTokenAndIds() {
    const observed = getObservedSubstrateAuth();
    if (observed) return observed;

    const msalIds =
      getMsalIdsFromIdentityElement() || getActiveAccountFilters();

    let cookie = null;
    try {
      cookie = await getEncryptionCookie();
    } catch {
      cookie = null;
    }

    const exact = await getAccessTokenFromExactKey(cookie, msalIds);
    if (exact) return exact;

    const discovered = await findSubstrateAccessToken(cookie, msalIds);
    if (discovered) return discovered;

    const hasSubstrateCacheKey = (() => {
      try {
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i);
          if (key && isSubstrateTokenKey(key)) return true;
        }
      } catch {}
      return false;
    })();

    if (hasSubstrateCacheKey && !cookie) {
      throw new Error(
        "Found Substrate MSAL token cache entries, but they appear encrypted and the msal.cache.encryption cookie was unavailable. Reload Microsoft 365 Copilot and try again before opening DevTools, or use the page normally once so the exporter can capture an authenticated Substrate request.",
      );
    }

    throw new Error(
      "Missing usable Substrate auth. Reload the chat with the exporter enabled, wait for the chat to finish loading, open an existing conversation once, then try Fetch Current Conversation again.",
    );
  }

  // Current conversation detection

  const CONVERSATION_ID_RE =
    /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i;
  const CONVERSATION_ID_PARAM_NAMES = new Set([
    "conversationid",
    "conversation_id",
    "chatid",
    "chat_id",
    "threadid",
    "thread_id",
    "sessionid",
    "session_id",
  ]);

  function normalizeConversationId(value) {
    if (!value) return null;
    const match = String(value).match(CONVERSATION_ID_RE);
    return match ? match[0] : null;
  }

  function findConversationIdInObject(value, depth = 0, seen = new WeakSet()) {
    if (!value || depth > 6) return null;

    if (typeof value === "string") {
      return normalizeConversationId(value);
    }

    if (typeof value !== "object") return null;
    if (seen.has(value)) return null;
    seen.add(value);

    const preferredKeys = [
      "conversationId",
      "conversationID",
      "conversation_id",
      "chatId",
      "chatID",
      "chat_id",
      "threadId",
      "threadID",
      "thread_id",
      "sessionId",
      "sessionID",
      "session_id",
    ];

    for (const key of preferredKeys) {
      if (Object.prototype.hasOwnProperty.call(value, key)) {
        const found = findConversationIdInObject(value[key], depth + 1, seen);
        if (found) return found;
      }
    }

    for (const [key, child] of Object.entries(value)) {
      if (!/conversation|chat|thread|session/i.test(key)) continue;
      const found = findConversationIdInObject(child, depth + 1, seen);
      if (found) return found;
    }

    return null;
  }

  function extractConversationIdFromUrlString(urlString) {
    if (!urlString) return null;
    const rawUrl = String(urlString);

    try {
      const parsed = new URL(rawUrl, window.location.href);

      const requestParam = parsed.searchParams.get("request");
      if (requestParam) {
        try {
          const requestJson = JSON.parse(requestParam);
          const fromRequest = findConversationIdInObject(requestJson);
          if (fromRequest) return fromRequest;
        } catch {}
      }

      for (const [key, value] of parsed.searchParams.entries()) {
        if (!CONVERSATION_ID_PARAM_NAMES.has(key.toLowerCase())) continue;
        const fromParam = normalizeConversationId(value);
        if (fromParam) return fromParam;
      }

      if (parsed.hash) {
        const hashText = parsed.hash.slice(1);
        const queryStart = hashText.indexOf("?");
        const hashQuery =
          queryStart >= 0 ? hashText.slice(queryStart + 1) : hashText;
        const hashParams = new URLSearchParams(hashQuery);
        for (const [key, value] of hashParams.entries()) {
          if (!CONVERSATION_ID_PARAM_NAMES.has(key.toLowerCase())) continue;
          const fromHash = normalizeConversationId(value);
          if (fromHash) return fromHash;
        }
      }

      if (/GetConversation|conversation|chat|thread|session/i.test(rawUrl)) {
        const fromRoute = normalizeConversationId(rawUrl);
        if (fromRoute) return fromRoute;
      }
    } catch {
      if (/GetConversation|conversation|chat|thread|session/i.test(rawUrl)) {
        return normalizeConversationId(rawUrl);
      }
    }

    return null;
  }

  function setCurrentConversationId(conversationId, source) {
    const normalized = normalizeConversationId(conversationId);
    if (!normalized) return null;

    if (
      source === "recent browser request" &&
      backgroundFetchedConversationIds.has(normalized)
    ) {
      return null;
    }

    if (currentConversationId !== normalized) {
      currentConversationId = normalized;
      console.log(
        `[Copilot Export] Current conversation ID detected from ${source}: ${normalized}`,
      );
      updateBadge();
    }

    return normalized;
  }

  function captureCurrentConversationIdFromUrl(url, source) {
    const conversationId = extractConversationIdFromUrlString(url);
    return conversationId
      ? setCurrentConversationId(conversationId, source)
      : null;
  }

  function findConversationIdFromRecentRequests() {
    try {
      const entries = (performance.getEntriesByType?.("resource") || [])
        .slice()
        .reverse();
      for (const entry of entries) {
        const name = entry?.name || "";
        if (!name.includes("GetConversation")) continue;
        const found = captureCurrentConversationIdFromUrl(
          name,
          "recent browser request",
        );
        if (found) return found;
      }
    } catch {}
    return null;
  }

  function findConversationIdFromActiveDom() {
    const selectors = [
      '[aria-current="page"]',
      '[aria-selected="true"]',
      '[data-is-selected="true"]',
      '[data-selected="true"]',
      ".is-selected",
      ".selected",
    ];

    try {
      for (const selector of selectors) {
        const nodes = Array.from(document.querySelectorAll(selector));
        for (const node of nodes) {
          const candidates = [node, node.closest?.("a[href]")].filter(Boolean);

          for (const candidate of candidates) {
            if (candidate.href) {
              const fromHref = extractConversationIdFromUrlString(
                candidate.href,
              );
              if (fromHref)
                return setCurrentConversationId(fromHref, "active DOM href");
            }

            for (const attrName of candidate.getAttributeNames?.() || []) {
              if (!/conversation|chat|thread|session|href/i.test(attrName))
                continue;
              const fromAttr = normalizeConversationId(
                candidate.getAttribute(attrName),
              );
              if (fromAttr)
                return setCurrentConversationId(
                  fromAttr,
                  "active DOM attribute",
                );
            }
          }
        }
      }
    } catch {}

    return null;
  }

  function getCurrentConversationId(options = {}) {
    const { allowPrompt = false } = options;

    const fromLocation = captureCurrentConversationIdFromUrl(
      window.location.href,
      "current URL",
    );
    if (fromLocation) return fromLocation;

    const fromHistory = findConversationIdInObject(window.history?.state);
    if (fromHistory)
      return setCurrentConversationId(fromHistory, "history state");

    const fromRecentRequest = findConversationIdFromRecentRequests();
    if (fromRecentRequest) return fromRecentRequest;

    const fromDom = findConversationIdFromActiveDom();
    if (fromDom) return fromDom;

    if (currentConversationId) return currentConversationId;

    const loadedConversations = Array.from(conversations.values()).filter(
      (c) => c.messages && c.messages.length > 0,
    );
    if (loadedConversations.length === 1) {
      return setCurrentConversationId(
        loadedConversations[0].conversationId,
        "single loaded conversation",
      );
    }

    if (allowPrompt) {
      const manual = window.prompt(
        "Could not auto-detect the current Copilot conversation ID. Paste the GUID from the current chat URL, /debug output, or GetConversation request.",
      );
      const fromManual = normalizeConversationId(manual);
      if (fromManual)
        return setCurrentConversationId(fromManual, "manual entry");
    }

    return null;
  }

  // Conversation ingestion

  function isExportableMessage(message) {
    if (!message) return false;
    if (SKIP_MESSAGE_TYPES.has(message.messageType)) return false;
    if (message.author === "system") return false;
    if (!message.text && !message.adaptiveCards?.length) return false;

    const origin = String(message.contentOrigin || "");
    if (
      /^(UserShortTermConversation|UserKnowledgeSummaryLlm|UserBehaviorSummaryLlm|UserMemorySummarizer|ChainOfThoughtSummary|SuggestionsProviderService|annotation-provider|citation-formatter)$/i.test(
        origin,
      )
    ) {
      return false;
    }

    return true;
  }

  function toStoredConversation(data, messages) {
    return {
      conversationId: data.conversationId,
      chatName: data.chatName || "",
      createTimeUtc: data.createTimeUtc,
      updateTimeUtc: data.updateTimeUtc,
      tone: data.tone || "",
      isLegacyWebChat: data.isLegacyWebChat || false,
      messages,
    };
  }

  function handleGetConversation(data, options = {}) {
    const { markAsCurrent = true } = options;
    const convId = data.conversationId;
    if (!convId) return;
    rememberCapturedConversation(data);
    if (markAsCurrent)
      setCurrentConversationId(convId, "GetConversation response");

    const visibleMessages = (data.messages || []).filter(isExportableMessage);
    if (visibleMessages.length === 0) return;

    conversations.set(convId, toStoredConversation(data, visibleMessages));

    updateBadge();
  }

  function handleGetChats(data) {
    const chats = data.chats || [];
    for (const chat of chats) {
      const convId = chat.conversationId;
      if (!convId) continue;
      if (!conversations.has(convId)) {
        conversations.set(convId, {
          conversationId: convId,
          chatName: chat.chatName || "",
          createTimeUtc: chat.createTimeUtc,
          updateTimeUtc: chat.updateTimeUtc,
          tone: chat.tone || "",
          isLegacyWebChat: chat.isLegacyWebChat || false,
          messages: [],
        });
      }
    }
    console.log(
      `[Copilot Export] Chat list: ${chats.length} conversations (${conversations.size} total known)`,
    );
    updateBadge();
    return data;
  }

  // M365 SSR and rehydration capture

  function isM365ConversationUrl(url) {
    return /\/chat\/conversation\/[0-9a-f-]{36}/i.test(String(url || ""));
  }

  function findRawConversationResponse(
    value,
    preferredConversationId = null,
    depth = 0,
    seen = new WeakSet(),
  ) {
    if (!value || typeof value !== "object" || depth > 10) return null;
    if (seen.has(value)) return null;
    seen.add(value);

    if (
      value.rawConversationResponse &&
      typeof value.rawConversationResponse === "object" &&
      Array.isArray(value.rawConversationResponse.messages)
    ) {
      const raw = value.rawConversationResponse;
      if (
        !preferredConversationId ||
        raw.conversationId === preferredConversationId
      )
        return raw;
    }

    if (Array.isArray(value.messages) && value.conversationId) {
      if (
        !preferredConversationId ||
        value.conversationId === preferredConversationId
      )
        return value;
    }

    const preferredKeys = [
      "rawConversationResponse",
      "chat-history",
      "chatHistory",
      "loaderData",
      "store",
      "data",
    ];

    for (const key of preferredKeys) {
      if (Object.prototype.hasOwnProperty.call(value, key)) {
        const found = findRawConversationResponse(
          value[key],
          preferredConversationId,
          depth + 1,
          seen,
        );
        if (found) return found;
      }
    }

    for (const child of Object.values(value)) {
      if (!child || typeof child !== "object") continue;
      const found = findRawConversationResponse(
        child,
        preferredConversationId,
        depth + 1,
        seen,
      );
      if (found) return found;
    }

    return null;
  }

  function findConversationList(value, depth = 0, seen = new WeakSet()) {
    if (!value || typeof value !== "object" || depth > 8) return null;
    if (seen.has(value)) return null;
    seen.add(value);

    if (
      Array.isArray(value.chats) &&
      value.chats.some((c) => c?.conversationId)
    ) {
      return value;
    }

    if (value.conversationPageHistoryList?.chats) {
      return value.conversationPageHistoryList;
    }

    for (const key of [
      "conversationPageHistoryList",
      "loaderData",
      "root",
      "store",
      "data",
    ]) {
      if (Object.prototype.hasOwnProperty.call(value, key)) {
        const found = findConversationList(value[key], depth + 1, seen);
        if (found) return found;
      }
    }

    for (const child of Object.values(value)) {
      if (!child || typeof child !== "object") continue;
      const found = findConversationList(child, depth + 1, seen);
      if (found) return found;
    }

    return null;
  }

  function ingestM365HydrationPayload(
    payload,
    source = "M365 hydration",
    preferredConversationId = null,
  ) {
    if (!payload || typeof payload !== "object") return false;

    let changed = false;

    const chatList = findConversationList(payload);
    if (chatList?.chats?.length) {
      handleGetChats(chatList);
      changed = true;
    }

    const rawConversation = findRawConversationResponse(
      payload,
      preferredConversationId,
    );
    if (rawConversation?.conversationId && rawConversation?.messages?.length) {
      rememberCapturedConversation(rawConversation);
      handleGetConversation(rawConversation, { markAsCurrent: true });
      console.log(
        `[Copilot Export] Captured conversation ${rawConversation.conversationId} from ${source}`,
      );
      changed = true;
    }

    return changed;
  }

  function parseStaticRouterHydrationScript(scriptText) {
    const marker = "window.__staticRouterHydrationData";
    const start = String(scriptText || "").indexOf(marker);
    if (start < 0) return null;

    const parseCall = scriptText.indexOf("JSON.parse(", start);
    if (parseCall < 0) return null;

    const firstQuote = scriptText.indexOf('"', parseCall);
    if (firstQuote < 0) return null;

    let i = firstQuote + 1;
    let escaped = false;

    for (; i < scriptText.length; i++) {
      const ch = scriptText[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === "\\") {
        escaped = true;
        continue;
      }
      if (ch === '"') break;
    }

    if (i >= scriptText.length) return null;

    const stringLiteral = scriptText.slice(firstQuote, i + 1);
    try {
      const decodedJson = JSON.parse(stringLiteral);
      return JSON.parse(decodedJson);
    } catch {
      return null;
    }
  }

  function parseStaticRouterHydrationHtml(htmlText) {
    if (!htmlText || !String(htmlText).includes("__staticRouterHydrationData"))
      return null;

    const scripts =
      String(htmlText).match(/<script\b[^>]*>[\s\S]*?<\/script>/gi) || [];
    for (const scriptTag of scripts) {
      if (!scriptTag.includes("__staticRouterHydrationData")) continue;
      const inner = scriptTag
        .replace(/^<script\b[^>]*>/i, "")
        .replace(/<\/script>$/i, "");
      const parsed = parseStaticRouterHydrationScript(inner);
      if (parsed) return parsed;
    }

    return parseStaticRouterHydrationScript(String(htmlText));
  }

  function captureCurrentPageHydration(preferredConversationId = null) {
    try {
      if (window.__staticRouterHydrationData) {
        lastStaticRouterHydrationData = window.__staticRouterHydrationData;
        return ingestM365HydrationPayload(
          window.__staticRouterHydrationData,
          "current page window.__staticRouterHydrationData",
          preferredConversationId,
        );
      }
    } catch {}

    try {
      for (const scriptEl of Array.from(document.scripts || [])) {
        const text = scriptEl.textContent || "";
        if (!text.includes("__staticRouterHydrationData")) continue;
        const parsed = parseStaticRouterHydrationScript(text);
        if (!parsed) continue;
        lastStaticRouterHydrationData = parsed;
        return ingestM365HydrationPayload(
          parsed,
          "current page script hydration",
          preferredConversationId,
        );
      }
    } catch {}

    return false;
  }

  async function fetchM365ConversationFromCloud(conversationId) {
    const sessionId =
      lastStaticRouterHydrationData?.loaderData?.root?.store?.sessionID ||
      window.__staticRouterHydrationData?.loaderData?.root?.store?.sessionID ||
      crypto.randomUUID();

    const path = `/chat/conversation/${encodeURIComponent(conversationId)}`;
    const headers = {
      accept: "application/json",
      "x-slim-rehydration": "true",
      "x-allowed-message-types": "",
      "x-route-id": "chat-history",
      "x-host-context": JSON.stringify({
        clientPlatform: "web",
        hostName: "officeweb",
        appName: "SSR",
      }),
      "x-session-id": sessionId,
    };

    let lastError = null;

    try {
      const resp = await originalFetch(path, {
        method: "GET",
        headers,
        credentials: "include",
      });

      if (resp.ok) {
        const text = await resp.text();
        try {
          const json = JSON.parse(text);
          rawCaptures.push({
            url: path,
            status: resp.status,
            timestamp: new Date().toISOString(),
            byteLength: text.length,
            data: json,
          });

          if (
            ingestM365HydrationPayload(
              json,
              "M365 slim rehydration endpoint",
              conversationId,
            )
          ) {
            const found = conversations.get(conversationId);
            if (found?.messages?.length) return found;
          }
        } catch {
          const hydration = parseStaticRouterHydrationHtml(text);
          if (
            hydration &&
            ingestM365HydrationPayload(
              hydration,
              "M365 HTML hydration endpoint",
              conversationId,
            )
          ) {
            const found = conversations.get(conversationId);
            if (found?.messages?.length) return found;
          }
        }
      } else {
        lastError = new Error(
          `M365 cloud conversation endpoint returned ${resp.status}`,
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      const resp = await originalFetch(path, {
        method: "GET",
        headers: {
          accept:
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
        credentials: "include",
      });

      if (!resp.ok) {
        throw new Error(`M365 cloud HTML endpoint returned ${resp.status}`);
      }

      const html = await resp.text();
      const hydration = parseStaticRouterHydrationHtml(html);
      if (
        hydration &&
        ingestM365HydrationPayload(
          hydration,
          "M365 HTML fallback endpoint",
          conversationId,
        )
      ) {
        const found = conversations.get(conversationId);
        if (found?.messages?.length) return found;
      }
    } catch (e) {
      lastError = e;
    }

    if (lastError) throw lastError;
    return null;
  }

  // Passive capture hooks

  const originalFetch = window.fetch;

  window.fetch = async function (...args) {
    const { url, method, headers } = getFetchRequestDetails(args);
    if (
      url.includes("substrate.office.com") ||
      url.includes("m365.cloud.microsoft")
    ) {
      captureAuthFromHeaders(headers, "fetch request");
      rememberPageRequestTemplate(url, method, headers, "fetch request");
    }
    if (
      !suppressCurrentConversationDetection &&
      url.includes("GetConversation")
    ) {
      captureCurrentConversationIdFromUrl(url, "fetch request");
    }
    const response = await originalFetch.apply(this, args);

    if (
      !url.includes("substrate.office.com") &&
      !url.includes("m365.cloud.microsoft")
    ) {
      return response;
    }

    const clone = response.clone();
    clone
      .text()
      .then((text) => {
        if (!text || text.length < 20) return;
        try {
          const json = JSON.parse(text);
          rawCaptures.push({
            url: url.substring(0, 500),
            status: response.status,
            timestamp: new Date().toISOString(),
            byteLength: text.length,
            data: json,
          });
          if (url.includes("GetConversation")) handleGetConversation(json);
          else if (url.includes("GetChats")) handleGetChats(json);
          else if (isM365ConversationUrl(url) || url.includes("/chat")) {
            ingestM365HydrationPayload(
              json,
              "captured M365 JSON fetch",
              getCurrentConversationId({ allowPrompt: false }),
            );
          }
        } catch {
          if (
            isM365ConversationUrl(url) &&
            text.includes("__staticRouterHydrationData")
          ) {
            const hydration = parseStaticRouterHydrationHtml(text);
            if (hydration) {
              lastStaticRouterHydrationData = hydration;
              ingestM365HydrationPayload(
                hydration,
                "captured M365 HTML fetch",
                getCurrentConversationId({ allowPrompt: false }),
              );
            }
          }
        }
      })
      .catch(() => {});

    return response;
  };

  const origXHROpen = XMLHttpRequest.prototype.open;
  const origXHRSend = XMLHttpRequest.prototype.send;
  const origXHRSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;

  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this._captureUrl = url;
    this._captureHeaders = {};
    if (
      !suppressCurrentConversationDetection &&
      String(url || "").includes("GetConversation")
    ) {
      captureCurrentConversationIdFromUrl(url, "XHR request");
    }
    return origXHROpen.call(this, method, url, ...rest);
  };

  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    this._captureHeaders = this._captureHeaders || {};
    this._captureHeaders[name] = value;
    return origXHRSetRequestHeader.call(this, name, value);
  };

  XMLHttpRequest.prototype.send = function (...args) {
    const url = this._captureUrl || "";
    if (
      String(url).includes("substrate.office.com") ||
      String(url).includes("m365.cloud.microsoft")
    ) {
      captureAuthFromHeaders(this._captureHeaders, "XHR request");
      rememberPageRequestTemplate(
        url,
        "GET",
        this._captureHeaders,
        "XHR request",
      );
    }
    this.addEventListener("load", function () {
      const url = this._captureUrl || "";
      if (
        !url.includes("substrate.office.com") &&
        !url.includes("m365.cloud.microsoft")
      )
        return;
      try {
        const json = JSON.parse(this.responseText);
        rawCaptures.push({
          url: url.substring(0, 500),
          status: this.status,
          timestamp: new Date().toISOString(),
          byteLength: this.responseText.length,
          data: json,
        });
        if (url.includes("GetConversation")) handleGetConversation(json);
        else if (url.includes("GetChats")) handleGetChats(json);
        else if (isM365ConversationUrl(url) || url.includes("/chat")) {
          ingestM365HydrationPayload(
            json,
            "captured M365 JSON XHR",
            getCurrentConversationId({ allowPrompt: false }),
          );
        }
      } catch {
        if (
          isM365ConversationUrl(url) &&
          String(this.responseText || "").includes(
            "__staticRouterHydrationData",
          )
        ) {
          const hydration = parseStaticRouterHydrationHtml(this.responseText);
          if (hydration) {
            lastStaticRouterHydrationData = hydration;
            ingestM365HydrationPayload(
              hydration,
              "captured M365 HTML XHR",
              getCurrentConversationId({ allowPrompt: false }),
            );
          }
        }
      }
    });
    return origXHRSend.apply(this, args);
  };

  // Fetch workflows

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function setStatus(text) {
    const el = document.getElementById("copilot-export-status");
    if (el) el.textContent = text;
  }

  function getLoadedConversations(range = null) {
    return Array.from(conversations.values()).filter(
      (conversation) =>
        conversation.messages?.length > 0 && isInDateRange(conversation, range),
    );
  }

  function exportDateStamp() {
    return new Date().toISOString().slice(0, 10);
  }

  function setButtonBusy(button, busy, label) {
    if (!button) return;
    button.disabled = busy;
    if (label) button.textContent = label;
  }

  async function substrateGet(auth, endpoint, params, includeVariants) {
    const requestJson = JSON.stringify(params);
    const variantsSuffix = includeVariants
      ? `&variants=${encodeURIComponent(DEFAULT_VARIANTS)}`
      : "";
    const url = `${SUBSTRATE_BASE}/${endpoint}?request=${encodeURIComponent(requestJson)}${variantsSuffix}`;

    const headers = {
      authorization: `Bearer ${auth.token}`,
      "content-type": "application/json",
      "x-anchormailbox":
        auth.anchorMailbox || `Oid:${auth.localAccountId}@${auth.tenantId}`,
      "x-clientrequestid": crypto.randomUUID().replace(/-/g, ""),
      "x-routingparameter-sessionkey":
        auth.routingSessionKey || auth.localAccountId,
      "x-scenario": auth.scenario || "OfficeWebIncludedCopilot",
    };

    const resp = await originalFetch(url, {
      method: "GET",
      headers,
      credentials: "include",
    });

    if (!resp.ok) {
      throw new Error(`${endpoint} returned ${resp.status}`);
    }
    return resp.json();
  }

  function buildReplayedConversationRequest(template, conversationId) {
    const url = new URL(template.url, window.location.href);
    let request = {};
    try {
      request = JSON.parse(url.searchParams.get("request") || "{}");
    } catch {
      request = {};
    }

    request.conversationId = conversationId;
    request.source = request.source || "officeweb";
    request.traceId = crypto.randomUUID().replace(/-/g, "");
    url.searchParams.set("request", JSON.stringify(request));

    const headers = { ...template.headers };
    for (const key of Object.keys(headers)) {
      if (/^(host|content-length)$/i.test(key)) delete headers[key];
    }
    if (headers["x-clientrequestid"])
      headers["x-clientrequestid"] = crypto.randomUUID().replace(/-/g, "");
    if (headers["X-ClientRequestId"])
      headers["X-ClientRequestId"] = crypto.randomUUID().replace(/-/g, "");

    return { url: url.toString(), headers };
  }

  async function replayPageGetConversation(conversationId) {
    const templates = capturedRequestTemplates
      .filter(
        (t) =>
          t.endpoint === "GetConversation" &&
          t.headers &&
          readHeader(t.headers, "authorization"),
      )
      .slice()
      .reverse();

    if (templates.length === 0) return null;

    let lastError = null;
    for (const template of templates) {
      try {
        const req = buildReplayedConversationRequest(template, conversationId);
        const resp = await originalFetch(req.url, {
          method: template.method || "GET",
          headers: req.headers,
          credentials: "include",
        });

        if (!resp.ok) {
          lastError = new Error(
            `replayed GetConversation returned ${resp.status}`,
          );
          continue;
        }

        return await resp.json();
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError) throw lastError;
    return null;
  }

  async function fetchAllChatIds(auth) {
    const allChats = [];
    let syncState = null;
    let page = 0;

    while (true) {
      page++;
      setStatus(`Fetching chat list page ${page}...`);

      const params = {
        source: "officeweb",
        traceId: crypto.randomUUID(),
        threadType: "bizchat",
        MaxReturnedChatsCount: 50,
        mergeWorkWebChats: true,
        includeChatsWithHarmfulContentProtectionDisabled: true,
      };
      if (syncState) {
        params.syncState = syncState;
      }

      const data = await substrateGet(auth, "GetChats", params, true);
      const chats = data.chats || [];
      allChats.push(...chats);
      handleGetChats(data);

      console.log(
        `[Copilot Export] GetChats page ${page}: ${chats.length} chats (${allChats.length} total)`,
      );

      syncState = data.syncState || null;
      if (chats.length === 0 || !syncState) break;

      await sleep(500);
    }

    return allChats;
  }

  async function fetchConversation(auth, conversationId, options = {}) {
    const { markAsCurrent = true } = options;
    const previousSuppression = suppressCurrentConversationDetection;

    if (!markAsCurrent) {
      suppressCurrentConversationDetection = true;
      backgroundFetchedConversationIds.add(conversationId);
    }

    try {
      const captured = capturedConversationPayloads.get(conversationId);
      if (captured?.messages?.length) {
        handleGetConversation(captured, { markAsCurrent });
        return captured;
      }

      try {
        const replayed = await replayPageGetConversation(conversationId);
        if (replayed) {
          handleGetConversation(replayed, { markAsCurrent });
          return replayed;
        }
      } catch (e) {
        console.warn(
          `[Copilot Export] Page-template replay failed for ${conversationId}: ${e.message}`,
        );
      }

      const data = await substrateGet(
        auth,
        "GetConversation",
        {
          conversationId,
          source: "officeweb",
          traceId: crypto.randomUUID().replace(/-/g, ""),
        },
        false,
      );
      handleGetConversation(data, { markAsCurrent });
      return data;
    } finally {
      suppressCurrentConversationDetection = previousSuppression;
    }
  }

  async function loadCurrentConversation(options = {}) {
    const { force = false } = options;
    const conversationId = getCurrentConversationId({ allowPrompt: true });

    if (!conversationId) {
      throw new Error("Could not detect the current conversation ID");
    }

    captureCurrentPageHydration(conversationId);

    let existing = conversations.get(conversationId);
    if (!force && existing?.messages?.length) {
      return { conversationId, conversation: existing, loadedFromApi: false };
    }

    setStatus(
      `Reading current conversation ${conversationId.slice(0, 8)} from M365 page state...`,
    );
    try {
      await fetchM365ConversationFromCloud(conversationId);
      existing = conversations.get(conversationId);
      if (existing?.messages?.length) {
        return { conversationId, conversation: existing, loadedFromApi: true };
      }
    } catch (e) {
      console.warn(
        `[Copilot Export] M365 cloud conversation load failed: ${e.message}`,
      );
    }

    setStatus("Acquiring auth token...");
    const auth = await getTokenAndIds();

    setStatus(
      `Fetching current conversation ${conversationId.slice(0, 8)} via Substrate fallback...`,
    );
    await fetchConversation(auth, conversationId, { markAsCurrent: true });

    const conversation = conversations.get(conversationId);
    if (!conversation?.messages?.length) {
      throw new Error(
        "Current conversation fetched, but no exportable messages were returned",
      );
    }

    return { conversationId, conversation, loadedFromApi: true };
  }

  async function doFetchCurrent() {
    if (isFetchingCurrent) return;
    isFetchingCurrent = true;

    const btn = document.getElementById("copilot-btn-fetchcurrent");
    const oldText = btn?.textContent || "Refresh";
    setButtonBusy(btn, true, "Fetching...");

    try {
      setStatus("Detecting current conversation ID...");
      const { conversationId, conversation } = await loadCurrentConversation({
        force: true,
      });
      setStatus(
        `Current conversation loaded: ${conversation.messages.length} messages (${conversationId.slice(0, 8)}...)`,
      );
      updateBadge();
    } catch (e) {
      setStatus(`Error: ${e.message}`);
      console.error("[Copilot Export] Fetch current failed:", e);
    } finally {
      isFetchingCurrent = false;
      setButtonBusy(btn, false, oldText);
    }
  }

  async function doFetchAll() {
    if (isFetchingAll) return;
    isFetchingAll = true;
    const previousCurrentConversationId = currentConversationId;
    const btn = document.getElementById("copilot-btn-fetchall");
    setButtonBusy(btn, true, "Fetching...");

    try {
      setStatus("Acquiring auth token...");
      const auth = await getTokenAndIds();
      console.log(`[Copilot Export] Auth acquired for ${auth.localAccountId}`);

      const allChats = await fetchAllChatIds(auth);
      console.log(
        `[Copilot Export] Found ${allChats.length} total conversations`,
      );

      const range = getDateRange();
      const filteredChats = range
        ? allChats.filter((c) => isInDateRange(c, range))
        : allChats;

      if (range) {
        console.log(
          `[Copilot Export] Date filter: ${filteredChats.length}/${allChats.length} conversations in range`,
        );
        setStatus(
          `${filteredChats.length} of ${allChats.length} conversations match date filter`,
        );
        await sleep(800);
      }

      const toFetch = filteredChats.filter((c) => {
        const existing = conversations.get(c.conversationId);
        return !existing || existing.messages.length === 0;
      });

      console.log(
        `[Copilot Export] Need to fetch ${toFetch.length} conversations (${filteredChats.length - toFetch.length} already loaded)`,
      );

      let fetched = 0;
      let errors = 0;

      for (const chat of toFetch) {
        fetched++;
        setStatus(
          `Fetching ${fetched}/${toFetch.length}: ${(chat.chatName || "").substring(0, 40)}...`,
        );

        try {
          await fetchConversation(auth, chat.conversationId, {
            markAsCurrent: false,
          });
        } catch (e) {
          errors++;
          console.warn(
            `[Copilot Export] Failed to fetch ${chat.conversationId}: ${e.message}`,
          );
        }

        await sleep(500);
        updateBadge();
      }

      const loaded = getLoadedConversations();
      setStatus(
        `Done! ${loaded.length} conversations loaded` +
          (errors > 0 ? ` (${errors} errors)` : ""),
      );
    } catch (e) {
      setStatus(`Error: ${e.message}`);
      console.error("[Copilot Export] Fetch all failed:", e);
    } finally {
      isFetchingAll = false;
      if (previousCurrentConversationId)
        currentConversationId = previousCurrentConversationId;
      updateBadge();
      setButtonBusy(btn, false, "Fetch all");
    }
  }

  // ChatGPT export conversion

  function toUnixSeconds(ts) {
    if (!ts) return null;
    if (typeof ts === "number") return ts > 1e12 ? ts / 1000 : ts;
    try {
      return new Date(ts).getTime() / 1000;
    } catch {
      return null;
    }
  }

  function buildConversationsJson(range, onlyConversationId = null) {
    const output = [];

    for (const [convId, conv] of conversations) {
      if (onlyConversationId && convId !== onlyConversationId) continue;
      if (!conv.messages || conv.messages.length === 0) continue;
      if (!isInDateRange(conv, range)) continue;

      const firstTs =
        toUnixSeconds(conv.createTimeUtc) ||
        toUnixSeconds(conv.messages[0]?.createdAt);
      const lastTs =
        toUnixSeconds(conv.updateTimeUtc) ||
        toUnixSeconds(conv.messages[conv.messages.length - 1]?.createdAt);

      const mapping = {};

      const rootId = "client-created-root";
      mapping[rootId] = {
        id: rootId,
        message: null,
        parent: null,
        children: [],
      };

      const systemId = crypto.randomUUID();
      mapping[systemId] = {
        id: systemId,
        message: {
          id: systemId,
          author: { role: "system", name: null, metadata: {} },
          create_time: firstTs,
          update_time: null,
          content: { content_type: "text", parts: [""] },
          status: "finished_successfully",
          end_turn: true,
          weight: 1.0,
          metadata: {},
          recipient: "all",
          channel: null,
        },
        parent: rootId,
        children: [],
      };
      mapping[rootId].children.push(systemId);

      let prevId = systemId;
      let title = sanitizeText(conv.chatName) || null;

      for (const msg of conv.messages) {
        const created = toUnixSeconds(msg.createdAt);
        const text = sanitizeText(msg.text || "");

        let role;
        if (msg.author === "user") {
          role = "user";
          if (!title && text) title = text.substring(0, 100).trim();
        } else if (msg.author === "bot") {
          role = "assistant";
        } else {
          continue;
        }

        const nodeId = msg.messageId || crypto.randomUUID();

        mapping[nodeId] = {
          id: nodeId,
          message: {
            id: nodeId,
            author: { role, name: null, metadata: {} },
            create_time: created,
            update_time: null,
            content: { content_type: "text", parts: [text] },
            status: "finished_successfully",
            end_turn: role === "assistant",
            weight: 1.0,
            metadata: {
              copilot_app_class: msg.contentOrigin || "",
              copilot_session_id: convId,
              copilot_message_id: msg.messageId || "",
              copilot_request_id: msg.requestId || "",
            },
            recipient: "all",
            channel: null,
          },
          parent: prevId,
          children: [],
        };

        mapping[prevId].children.push(nodeId);
        prevId = nodeId;
      }

      output.push({
        title: title || "Copilot Chat",
        create_time: firstTs,
        update_time: lastTs,
        mapping,
        moderation_results: [],
        current_node: prevId,
        plugin_ids: null,
        conversation_id: convId,
        conversation_template_id: null,
        gizmo_id: null,
        gizmo_type: null,
        is_archived: false,
        is_starred: null,
        safe_urls: [],
        blocked_urls: [],
        default_model_slug: "copilot",
        conversation_origin: null,
        is_read_only: null,
        voice: null,
        async_status: null,
        disabled_tool_ids: [],
        is_do_not_remember: false,
        memory_scope: null,
        context_scopes: null,
        sugar_item_id: null,
        sugar_item_visible: false,
        pinned_time: null,
        is_study_mode: false,
        owner: null,
        id: convId,
      });
    }

    output.sort((a, b) => (b.create_time || 0) - (a.create_time || 0));
    return output;
  }

  // Downloads

  function downloadJson(data, filename) {
    const jsonStr = JSON.stringify(data, null, 2);
    const blob = new Blob([jsonStr], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  async function doExportCurrentConverted() {
    const btn = document.getElementById("copilot-btn-export-current");
    const oldText = btn?.textContent || "Export current";
    setButtonBusy(btn, true, "Exporting...");

    try {
      const { conversationId, conversation } = await loadCurrentConversation({
        force: false,
      });
      const result = buildConversationsJson(null, conversationId);

      if (result.length === 0) {
        throw new Error("Current conversation has no exportable messages");
      }

      downloadJson(
        { conversations: result },
        `copilot_current_conversation_${conversationId.slice(0, 8)}_${exportDateStamp()}.json`,
      );

      console.log(
        `[Copilot Export] Exported current conversation ${conversationId} with ${conversation.messages.length} messages`,
      );
      setStatus(
        `Exported current conversation: ${conversation.messages.length} messages`,
      );
    } catch (e) {
      setStatus(`Error: ${e.message}`);
      console.error("[Copilot Export] Export current failed:", e);
      alert(`Could not export current conversation.\n\n${e.message}`);
    } finally {
      setButtonBusy(btn, false, oldText);
    }
  }

  function doExportConverted() {
    const range = getDateRange();
    const withMessages = getLoadedConversations(range);

    if (withMessages.length === 0) {
      alert(
        range
          ? "No conversations with content in the selected date range.\n\nTry a wider date range or use Fetch All first."
          : "No conversation content captured yet.\n\n" +
              'Use "Fetch Current Conversation" or "Fetch All Conversations" first.',
      );
      return;
    }

    const result = buildConversationsJson(range);
    const totalMsgs = withMessages.reduce((s, c) => s + c.messages.length, 0);

    downloadJson(
      { conversations: result },
      `copilot_conversations_${exportDateStamp()}.json`,
    );

    console.log(
      `[Copilot Export] Exported ${result.length} conversations with ${totalMsgs} messages`,
    );
  }

  function doExportRaw() {
    if (rawCaptures.length === 0) {
      alert("No API responses captured yet.");
      return;
    }
    downloadJson(rawCaptures, `copilot_raw_capture_${exportDateStamp()}.json`);
  }

  // UI

  function updateBadge() {
    const withMessages = getLoadedConversations();
    const totalMsgs = withMessages.reduce((s, c) => s + c.messages.length, 0);
    const currentShort = currentConversationId
      ? currentConversationId.slice(0, 8)
      : "-";

    const chatsMetric = document.getElementById("copilot-export-metric-chats");
    const msgsMetric = document.getElementById("copilot-export-metric-msgs");
    const currentMetric = document.getElementById(
      "copilot-export-metric-current",
    );

    if (chatsMetric)
      chatsMetric.textContent = `${withMessages.length}/${conversations.size}`;
    if (msgsMetric) msgsMetric.textContent = `${totalMsgs}`;
    if (currentMetric) currentMetric.textContent = currentShort;

    const badge = document.getElementById("copilot-export-badge");
    if (badge && !chatsMetric) {
      const parts = [
        `Loaded: ${withMessages.length}/${conversations.size} chats`,
        `${totalMsgs} msgs`,
      ];
      if (currentConversationId) parts.push(`Current: ${currentShort}`);
      badge.textContent = parts.join(" | ");
    }
  }

  const COPILOT_ICON_DATA_URI =
    "data:image/svg+xml;base64,PHN2ZyBoZWlnaHQ9IjFlbSIgc3R5bGU9ImZsZXg6bm9uZTtsaW5lLWhlaWdodDoxIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHdpZHRoPSIxZW0iIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHRpdGxlPkNvcGlsb3Q8L3RpdGxlPjxwYXRoIGQ9Ik0xNy41MzMgMS44MjlBMi41MjggMi41MjggMCAwMDE1LjExIDBoLS43MzdhMi41MzEgMi41MzEgMCAwMC0yLjQ4NCAyLjA4N2wtMS4yNjMgNi45MzcuMzE0LTEuMDhhMi41MjggMi41MjggMCAwMTIuNDI0LTEuODMzaDQuMjg0bDEuNzk3LjcwNiAxLjczMS0uNzA2aC0uNTA1YTIuNTI4IDIuNTI4IDAgMDEtMi40MjMtMS44MjlsLS43MTUtMi40NTN6IiBmaWxsPSJ1cmwoI2xvYmUtaWNvbnMtY29waWxvdC0wLV9SXzBfKSIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMCAxKSI+PC9wYXRoPjxwYXRoIGQ9Ik02LjcyNiAyMC4xNkEyLjUyOCAyLjUyOCAwIDAwOS4xNTIgMjJoMS41NjZjMS4zNyAwIDIuNDktMS4xIDIuNTI1LTIuNDhsLjE3LTYuNjktLjM1NyAxLjIyOGEyLjUyOCAyLjUyOCAwIDAxLTIuNDIzIDEuODNoLTQuMzJsLTEuNTQtLjg0Mi0xLjY2Ny44NDNoLjQ5N2MxLjEyNCAwIDIuMTEzLjc1IDIuNDI2IDEuODRsLjY5NyAyLjQzMnoiIGZpbGw9InVybCgjbG9iZS1pY29ucy1jb3BpbG90LTEtX1JfMF8pIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgwIDEpIj48L3BhdGg+PHBhdGggZD0iTTE1IDBINi4yNTJjLTIuNSAwLTQgMy4zMzEtNSA2LjY2Mi0xLjE4NCAzLjk0Ny0yLjczNCA5LjIyNSAxLjc1IDkuMjI1SDYuNzhjMS4xMyAwIDIuMTItLjc1MyAyLjQzLTEuODQ3LjY1Ny0yLjMxNyAxLjgwOS02LjM1OSAyLjcxMy05LjQzNi40Ni0xLjU2My44NDItMi45MDYgMS40My0zLjc0MkExLjk3IDEuOTcgMCAwMTE1IDAiIGZpbGw9InVybCgjbG9iZS1pY29ucy1jb3BpbG90LTItX1JfMF8pIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgwIDEpIj48L3BhdGg+PHBhdGggZD0iTTE1IDBINi4yNTJjLTIuNSAwLTQgMy4zMzEtNSA2LjY2Mi0xLjE4NCAzLjk0Ny0yLjczNCA5LjIyNSAxLjc1IDkuMjI1SDYuNzhjMS4xMyAwIDIuMTItLjc1MyAyLjQzLTEuODQ3LjY1Ny0yLjMxNyAxLjgwOS02LjM1OSAyLjcxMy05LjQzNi40Ni0xLjU2My44NDItMi45MDYgMS40My0zLjc0MkExLjk3IDEuOTcgMCAwMTE1IDAiIGZpbGw9InVybCgjbG9iZS1pY29ucy1jb3BpbG90LTMtX1JfMF8pIiB0cmFuc2Zvcm09InRyYW5zbGF0ZSgwIDEpIj48L3BhdGg+PHBhdGggZD0iTTkgMjJoOC43NDljMi41IDAgNC0zLjMzMiA1LTYuNjYzIDEuMTg0LTMuOTQ4IDIuNzM0LTkuMjI3LTEuNzUtOS4yMjdIMTcuMjJjLTEuMTI5IDAtMi4xMi43NTQtMi40MyAxLjg0OGExMTQ5LjIgMTE0OS4yIDAgMDEtMi43MTMgOS40MzdjLS40NiAxLjU2NC0uODQyIDIuOTA3LTEuNDMgMy43NDNBMS45NyAxLjk3IDAgMDE5IDIyIiBmaWxsPSJ1cmwoI2xvYmUtaWNvbnMtY29waWxvdC00LV9SXzBfKSIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMCAxKSI+PC9wYXRoPjxwYXRoIGQ9Ik05IDIyaDguNzQ5YzIuNSAwIDQtMy4zMzIgNS02LjY2MyAxLjE4NC0zLjk0OCAyLjczNC05LjIyNy0xLjc1LTkuMjI3SDE3LjIyYy0xLjEyOSAwLTIuMTIuNzU0LTIuNDMgMS44NDhhMTE0OS4yIDExNDkuMiAwIDAxLTIuNzEzIDkuNDM3Yy0uNDYgMS41NjQtLjg0MiAyLjkwNy0xLjQzIDMuNzQzQTEuOTcgMS45NyAwIDAxOSAyMiIgZmlsbD0idXJsKCNsb2JlLWljb25zLWNvcGlsb3QtNS1fUl8wXykiIHRyYW5zZm9ybT0idHJhbnNsYXRlKDAgMSkiPjwvcGF0aD48ZGVmcz48cmFkaWFsR3JhZGllbnQgY3g9Ijg1LjQ0JSIgY3k9IjEwMC42NTMlIiBmeD0iODUuNDQlIiBmeT0iMTAwLjY1MyUiIGdyYWRpZW50VHJhbnNmb3JtPSJzY2FsZSgtLjg1NTMgLTEpIHJvdGF0ZSg1MC45MjcgMi4wNDEgLTEuOTQ2KSIgaWQ9ImxvYmUtaWNvbnMtY29waWxvdC0wLV9SXzBfIiByPSIxMDUuMTE2JSI+PHN0b3Agb2Zmc2V0PSI5LjYlIiBzdG9wLWNvbG9yPSIjMDBBRUZGIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSI3Ny4zJSIgc3RvcC1jb2xvcj0iIzIyNTNDRSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iMTAwJSIgc3RvcC1jb2xvcj0iIzA3MzZDNCI+PC9zdG9wPjwvcmFkaWFsR3JhZGllbnQ+PHJhZGlhbEdyYWRpZW50IGN4PSIxOC4xNDMlIiBjeT0iMzIuOTI4JSIgZng9IjE4LjE0MyUiIGZ5PSIzMi45MjglIiBncmFkaWVudFRyYW5zZm9ybT0ic2NhbGUoLjg4OTcgMSkgcm90YXRlKDUyLjA2OSAuMTkzIC4zNTIpIiBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTEtX1JfMF8iIHI9Ijk1LjYxMiUiPjxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiNGRkI2NTciPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjYzLjQlIiBzdG9wLWNvbG9yPSIjRkY1RjNEIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSI5Mi4zJSIgc3RvcC1jb2xvcj0iI0MwMkIzQyI+PC9zdG9wPjwvcmFkaWFsR3JhZGllbnQ+PHJhZGlhbEdyYWRpZW50IGN4PSI4Mi45ODclIiBjeT0iLTkuNzkyJSIgZng9IjgyLjk4NyUiIGZ5PSItOS43OTIlIiBncmFkaWVudFRyYW5zZm9ybT0ic2NhbGUoLTEgLS45NDQxKSByb3RhdGUoLTcwLjg3MiAuMTQyIDEuMTcpIiBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTQtX1JfMF8iIHI9IjE0MC42MjIlIj48c3RvcCBvZmZzZXQ9IjYuNiUiIHN0b3AtY29sb3I9IiM4QzQ4RkYiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjUwJSIgc3RvcC1jb2xvcj0iI0YyNTk4QSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iODkuNiUiIHN0b3AtY29sb3I9IiNGRkIxNTIiPjwvc3RvcD48L3JhZGlhbEdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTItX1JfMF8iIHgxPSIzOS40NjUlIiB4Mj0iNDYuODg0JSIgeTE9IjEyLjExNyUiIHkyPSIxMDMuNzc0JSI+PHN0b3Agb2Zmc2V0PSIxNS42JSIgc3RvcC1jb2xvcj0iIzBEOTFFMSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iNDguNyUiIHN0b3AtY29sb3I9IiM1MkI0NzEiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjY1LjIlIiBzdG9wLWNvbG9yPSIjOThCRDQyIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSI5My43JSIgc3RvcC1jb2xvcj0iI0ZGQzgwMCI+PC9zdG9wPjwvbGluZWFyR3JhZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJsb2JlLWljb25zLWNvcGlsb3QtMy1fUl8wXyIgeDE9IjQ1Ljk0OSUiIHgyPSI1MCUiIHkxPSIwJSIgeTI9IjEwMCUiPjxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMzRENCRkYiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjI0LjclIiBzdG9wLWNvbG9yPSIjMDU4OEY3IiBzdG9wLW9wYWNpdHk9IjAiPjwvc3RvcD48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0ibG9iZS1pY29ucy1jb3BpbG90LTUtX1JfMF8iIHgxPSI4My41MDclIiB4Mj0iODMuNDUzJSIgeTE9Ii02LjEwNiUiIHkyPSIyMS4xMzElIj48c3RvcCBvZmZzZXQ9IjUuOCUiIHN0b3AtY29sb3I9IiNGOEFERkEiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjcwLjglIiBzdG9wLWNvbG9yPSIjQTg2RUREIiBzdG9wLW9wYWNpdHk9IjAiPjwvc3RvcD48L2xpbmVhckdyYWRpZW50PjwvZGVmcz48L3N2Zz4=";

  function createUI() {
    const container = document.createElement("div");
    container.id = "copilot-export-ui";
    container.innerHTML = `
      <style>
        #copilot-export-ui {
          position: fixed;
          bottom: 18px;
          right: 18px;
          z-index: 999999;
          font-family: "Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, Roboto, Arial, sans-serif;
          font-size: 12px;
          color: #f5f5f5;
          --ce-bg: #242424;
          --ce-bg-elevated: #2b2b2b;
          --ce-bg-soft: #323232;
          --ce-border: rgba(255, 255, 255, 0.12);
          --ce-border-strong: rgba(255, 255, 255, 0.18);
          --ce-text: #f5f5f5;
          --ce-muted: rgba(255, 255, 255, 0.62);
          --ce-faint: rgba(255, 255, 255, 0.42);
          --ce-accent: #8b7cff;
          --ce-accent-soft: rgba(139, 124, 255, 0.16);
        }

        #copilot-export-panel {
          width: 292px;
          background: rgba(36, 36, 36, 0.96);
          border: 1px solid var(--ce-border);
          border-radius: 16px;
          box-shadow: 0 18px 44px rgba(0, 0, 0, 0.34);
          overflow: hidden;
          backdrop-filter: blur(18px);
        }

        #copilot-export-title-row {
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto;
          align-items: center;
          gap: 10px;
          padding: 10px 10px 9px 12px;
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }

        #copilot-export-panel .brand {
          display: flex;
          align-items: center;
          min-width: 0;
          gap: 9px;
        }

        #copilot-export-panel .brand-icon {
          width: 22px;
          height: 22px;
          flex: 0 0 auto;
          border-radius: 7px;
        }

        #copilot-export-panel .title-stack {
          min-width: 0;
          line-height: 1.2;
        }

        #copilot-export-panel .title {
          color: var(--ce-text);
          font-size: 12.5px;
          font-weight: 600;
          white-space: nowrap;
        }

        #copilot-export-panel .subtitle {
          color: var(--ce-muted);
          font-size: 10.5px;
          margin-top: 1px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          max-width: 178px;
        }

        #copilot-export-panel .title-actions {
          display: inline-flex;
          align-items: center;
          gap: 6px;
        }

        #copilot-export-minimize-btn,
        #copilot-export-quick-btn {
          width: 30px !important;
          height: 30px;
          min-height: 30px !important;
          margin: 0;
          padding: 0;
          border: 1px solid rgba(255, 255, 255, 0.10);
          border-radius: 9px;
          background: rgba(255, 255, 255, 0.045);
          color: rgba(255, 255, 255, 0.76);
          cursor: pointer;
          font-size: 11px;
          font-family: inherit;
          line-height: 1;
        }

        #copilot-export-quick-btn {
          background: var(--ce-accent-soft);
          border-color: rgba(139, 124, 255, 0.30);
          color: #dedaff;
        }

        #copilot-export-minimize-btn:hover,
        #copilot-export-quick-btn:hover {
          background: rgba(255, 255, 255, 0.09);
          border-color: var(--ce-border-strong);
          color: #ffffff;
        }

        #copilot-export-quick-btn:hover {
          background: rgba(139, 124, 255, 0.23);
          border-color: rgba(139, 124, 255, 0.48);
        }

        #copilot-export-quick-btn svg,
        #copilot-export-minimize-btn svg {
          width: 15px;
          height: 15px;
          display: block;
          pointer-events: none;
        }

        #copilot-export-body {
          padding: 10px 10px 11px;
        }

        #copilot-export-badge {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: 6px;
          margin-bottom: 8px;
        }

        #copilot-export-badge .metric {
          min-width: 0;
          padding: 6px 7px;
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 10px;
          background: rgba(255, 255, 255, 0.04);
        }

        #copilot-export-badge .metric-label {
          display: block;
          color: var(--ce-faint);
          font-size: 9.5px;
          line-height: 1;
          margin-bottom: 4px;
        }

        #copilot-export-badge .metric-value {
          display: block;
          color: var(--ce-text);
          font-size: 11.5px;
          font-weight: 600;
          line-height: 1;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-variant-numeric: tabular-nums;
        }

        #copilot-export-status {
          display: flex;
          align-items: center;
          gap: 6px;
          min-height: 18px;
          margin-bottom: 10px;
          color: var(--ce-muted);
          font-size: 11px;
          line-height: 1.3;
          word-break: break-word;
        }

        #copilot-export-status::before {
          content: "";
          width: 6px;
          height: 6px;
          flex: 0 0 auto;
          border-radius: 999px;
          background: #6ee7b7;
          box-shadow: 0 0 0 3px rgba(110, 231, 183, 0.10);
        }

        #copilot-export-panel .button-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 7px;
        }

        #copilot-export-panel button {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 7px;
          min-height: 31px;
          width: 100%;
          margin: 0;
          padding: 7px 10px;
          border: 1px solid rgba(255, 255, 255, 0.12);
          border-radius: 10px;
          background: rgba(255, 255, 255, 0.055);
          color: rgba(255, 255, 255, 0.88);
          cursor: pointer;
          font-size: 12px;
          font-family: inherit;
          font-weight: 500;
          line-height: 1;
          text-align: center;
        }

        #copilot-export-panel button:hover:not(:disabled) {
          background: rgba(255, 255, 255, 0.095);
          border-color: rgba(255, 255, 255, 0.20);
          color: #ffffff;
        }

        #copilot-export-panel button:disabled {
          opacity: 0.58;
          cursor: not-allowed;
        }

        #copilot-export-panel button.primary {
          border-color: rgba(139, 124, 255, 0.34);
          background: rgba(139, 124, 255, 0.16);
          color: #ffffff;
          font-weight: 650;
        }

        #copilot-export-panel button.primary:hover:not(:disabled) {
          background: rgba(139, 124, 255, 0.23);
          border-color: rgba(139, 124, 255, 0.52);
        }

        #copilot-export-panel .btn-icon {
          width: 14px;
          height: 14px;
          flex: 0 0 auto;
        }

        #copilot-export-panel details {
          margin-top: 9px;
          border-top: 1px solid rgba(255, 255, 255, 0.08);
          padding-top: 8px;
        }

        #copilot-export-panel summary {
          display: flex;
          align-items: center;
          justify-content: space-between;
          list-style: none;
          cursor: pointer;
          color: rgba(255, 255, 255, 0.68);
          font-size: 11.5px;
          font-weight: 600;
          padding: 2px 0 6px;
        }

        #copilot-export-panel summary:hover {
          color: #ffffff;
        }

        #copilot-export-panel summary::-webkit-details-marker {
          display: none;
        }

        #copilot-export-panel summary::after {
          content: "+";
          color: rgba(255, 255, 255, 0.44);
          font-size: 14px;
          line-height: 1;
        }

        #copilot-export-panel details[open] summary::after {
          content: "-";
        }

        #copilot-date-row {
          margin: 0 0 8px;
        }

        #copilot-date-row label {
          display: none;
        }

        #copilot-date-row select,
        #copilot-date-row input[type="date"] {
          width: 100%;
          box-sizing: border-box;
          min-height: 30px;
          background: rgba(0, 0, 0, 0.16);
          color: rgba(255, 255, 255, 0.88);
          border: 1px solid rgba(255, 255, 255, 0.11);
          border-radius: 10px;
          padding: 6px 8px;
          font-size: 12px;
          font-family: inherit;
        }

        #copilot-custom-dates {
          display: none;
          grid-template-columns: 1fr 1fr;
          gap: 7px;
          margin-top: 7px;
        }

        #copilot-custom-dates.visible {
          display: grid;
        }

        #copilot-export-panel .hint {
          color: rgba(255, 255, 255, 0.45);
          font-size: 10.5px;
          line-height: 1.35;
          margin-top: 7px;
        }

        #copilot-export-icon {
          display: none;
          min-width: 116px;
          height: 42px;
          align-items: center;
          justify-content: center;
          gap: 8px;
          padding: 0 12px 0 10px;
          border: 1px solid rgba(255, 255, 255, 0.14);
          border-radius: 999px;
          background: rgba(36, 36, 36, 0.94);
          box-shadow: 0 18px 44px rgba(0, 0, 0, 0.34);
          cursor: pointer;
          backdrop-filter: blur(18px);
          color: rgba(255, 255, 255, 0.88);
          font-size: 12px;
          font-weight: 600;
        }

        #copilot-export-icon img {
          width: 22px;
          height: 22px;
          flex: 0 0 auto;
        }

        #copilot-export-icon .mini-label {
          line-height: 1;
        }

        #copilot-export-icon .mini-export {
          width: 14px;
          height: 14px;
          color: #dedaff;
          opacity: 0.95;
        }

        #copilot-export-icon:hover {
          background: rgba(46, 46, 46, 0.98);
          border-color: rgba(255, 255, 255, 0.22);
        }

        #copilot-export-ui.minimized #copilot-export-panel {
          display: none;
        }

        #copilot-export-ui.minimized #copilot-export-icon {
          display: inline-flex;
        }
      </style>

      <div id="copilot-export-icon" title="Open Copilot Exporter">
        <img src="${COPILOT_ICON_DATA_URI}" alt="Copilot">
        <span class="mini-label">Export</span>
        <svg class="mini-export" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M10 3v8m0 0 3-3m-3 3L7 8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 12.5v2.25A2.25 2.25 0 0 0 7.25 17h5.5A2.25 2.25 0 0 0 15 14.75V12.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
      </div>

      <div id="copilot-export-panel">
        <div id="copilot-export-title-row">
          <div class="brand">
            <img class="brand-icon" src="${COPILOT_ICON_DATA_URI}" alt="Copilot">
            <div class="title-stack">
              <div class="title">Copilot Exporter</div>
              <div class="subtitle">Current conversation</div>
            </div>
          </div>
          <div class="title-actions">
            <button id="copilot-export-quick-btn" title="Export current conversation" aria-label="Export current conversation">
              <svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M10 3v8m0 0 3-3m-3 3L7 8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 12.5v2.25A2.25 2.25 0 0 0 7.25 17h5.5A2.25 2.25 0 0 0 15 14.75V12.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
            </button>
            <button id="copilot-export-minimize-btn" title="Minimize" aria-label="Minimize">
              <svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M5 10h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
            </button>
          </div>
        </div>

        <div id="copilot-export-body">
          <div id="copilot-export-badge">
            <div class="metric"><span class="metric-label">Chats</span><span class="metric-value" id="copilot-export-metric-chats">0/0</span></div>
            <div class="metric"><span class="metric-label">Messages</span><span class="metric-value" id="copilot-export-metric-msgs">0</span></div>
            <div class="metric"><span class="metric-label">Current</span><span class="metric-value" id="copilot-export-metric-current">-</span></div>
          </div>
          <div id="copilot-export-status">Ready</div>

          <div class="button-row">
            <button id="copilot-btn-export-current" class="primary"><svg class="btn-icon" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M10 3v8m0 0 3-3m-3 3L7 8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 12.5v2.25A2.25 2.25 0 0 0 7.25 17h5.5A2.25 2.25 0 0 0 15 14.75V12.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>Export current</button>
            <button id="copilot-btn-fetchcurrent">Refresh</button>
          </div>

          <details id="copilot-all-section">
            <summary>All conversations</summary>
            <div id="copilot-date-row">
              <label>Date range</label>
              <select id="copilot-date-range">
                <option value="all">All time</option>
                <option value="today">Today</option>
                <option value="week">Last 7 days</option>
                <option value="month">Last 30 days</option>
                <option value="year">Last year</option>
                <option value="custom">Custom</option>
              </select>
              <div id="copilot-custom-dates">
                <input type="date" id="copilot-date-from" title="From date">
                <input type="date" id="copilot-date-to" title="To date">
              </div>
            </div>
            <div class="button-row">
              <button id="copilot-btn-export">Export all</button>
              <button id="copilot-btn-fetchall">Fetch all</button>
            </div>
          </details>

          <details id="copilot-diagnostics-section">
            <summary>Diagnostics</summary>
            <button id="copilot-btn-raw">Export raw captures</button>
            <div class="hint">Use only for parser troubleshooting. Tokens are not intentionally exported.</div>
          </details>
        </div>
      </div>
    `;

    document.body.appendChild(container);
    document
      .getElementById("copilot-btn-fetchcurrent")
      .addEventListener("click", doFetchCurrent);
    document
      .getElementById("copilot-btn-export-current")
      .addEventListener("click", doExportCurrentConverted);
    document
      .getElementById("copilot-export-quick-btn")
      .addEventListener("click", doExportCurrentConverted);
    document
      .getElementById("copilot-btn-fetchall")
      .addEventListener("click", doFetchAll);
    document
      .getElementById("copilot-btn-export")
      .addEventListener("click", doExportConverted);
    document
      .getElementById("copilot-btn-raw")
      .addEventListener("click", doExportRaw);

    document
      .getElementById("copilot-date-range")
      .addEventListener("change", (e) => {
        const customRow = document.getElementById("copilot-custom-dates");
        customRow.classList.toggle("visible", e.target.value === "custom");
      });

    const ui = document.getElementById("copilot-export-ui");
    const minimizeBtn = document.getElementById("copilot-export-minimize-btn");
    const icon = document.getElementById("copilot-export-icon");

    minimizeBtn.addEventListener("click", () => {
      ui.classList.add("minimized");
    });

    icon.addEventListener("click", () => {
      ui.classList.remove("minimized");
    });

    updateBadge();
  }

  // Init
  console.log("[Copilot Export v5.4] Loaded.");
  createUI();

  setTimeout(() => {
    try {
      captureCurrentConversationIdFromUrl();
      captureCurrentPageHydration(
        getCurrentConversationId({ allowPrompt: false }),
      );
    } catch {}
  }, 250);
})();
