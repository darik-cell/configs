(() => {
  "use strict";

  const endpoint = "/__livepreview/task";
  const token = document.querySelector('meta[name="live-preview-token"]')?.content || "";
  let markdownLines = [];

  const nativeMatchMedia = window.matchMedia.bind(window);
  window.matchMedia = (query) => {
    if (query.replace(/\s/g, "") !== "(prefers-color-scheme:dark)") {
      return nativeMatchMedia(query);
    }

    return {
      matches: false,
      media: query,
      onchange: null,
      addListener() {},
      removeListener() {},
      addEventListener() {},
      removeEventListener() {},
      dispatchEvent() {
        return false;
      },
    };
  };

  const nativeMarkdownIt = window.markdownit;
  window.markdownit = function (...args) {
    const parser = nativeMarkdownIt.apply(this, args);
    const nativeRender = parser.render.bind(parser);
    parser.render = (source, ...renderArgs) => {
      markdownLines = source.split(/\r\n|\n|\r/);
      return nativeRender(source, ...renderArgs);
    };
    return parser;
  };
  Object.assign(window.markdownit, nativeMarkdownIt);

  const findTaskMarker = (item) => {
    const walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const parent = node.parentElement;
      if (!parent || parent.closest("li") !== item || parent.closest("pre, code")) {
        continue;
      }

      const match = node.nodeValue.match(/^(\s*)\[([ xX])\](?=\s|$)/);
      if (match) {
        return { node, checked: match[2].toLowerCase() === "x", markerLength: match[0].length };
      }
      if (node.nodeValue.trim() !== "") {
        return null;
      }
    }
    return null;
  };

  const normalizeSourceLines = (root) => {
    const elements = [];
    if (root.matches("[data-source-line]")) {
      elements.push(root);
    }
    elements.push(...root.querySelectorAll("[data-source-line]"));

    elements.forEach((element) => {
      if (element.dataset.fileSourceLine !== undefined) {
        return;
      }
      const fileLine = Number(element.dataset.sourceLine);
      if (!Number.isInteger(fileLine) || fileLine < 0) {
        return;
      }
      element.dataset.fileSourceLine = String(fileLine);
      element.dataset.sourceLine = String(fileLine + 1);
    });
  };

  const enhanceTask = (item) => {
    if (item.querySelector(":scope input[data-live-preview-task]")) {
      return;
    }

    const marker = findTaskMarker(item);
    if (!marker) {
      return;
    }

    const fileLine = Number(item.dataset.fileSourceLine);
    const sourceLine = markdownLines[fileLine];
    if (
      !Number.isInteger(fileLine)
      || sourceLine === undefined
      || !/^\s*(?:[-+*]|\d+[.)])\s+\[[ xX]\](?:\s|$)/.test(sourceLine)
    ) {
      return;
    }

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = marker.checked;
    checkbox.className = "task-list-item-checkbox";
    checkbox.dataset.livePreviewTask = "true";
    checkbox.dataset.fileSourceLine = String(fileLine);
    checkbox.setAttribute("aria-label", "Изменить состояние задачи");

    marker.node.nodeValue = marker.node.nodeValue.slice(marker.markerLength);
    marker.node.parentNode.insertBefore(checkbox, marker.node);
    item.classList.add("task-list-item", "enabled");
    item.parentElement?.closest("ul, ol")?.classList.add("contains-task-list");

  };

  const enhanceTasks = (root) => {
    if (!(root instanceof Element)) {
      return;
    }

    normalizeSourceLines(root);

    if (root.matches("li")) {
      enhanceTask(root);
    }
    const parentItem = root.closest("li");
    if (parentItem) {
      enhanceTask(parentItem);
    }
    root.querySelectorAll("li").forEach(enhanceTask);
  };

  const sha256 = async (text) => {
    const bytes = new TextEncoder().encode(text);
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  };

  const toggleTask = async (checkbox) => {
    const previous = !checkbox.checked;
    const lineNumber = Number(checkbox.dataset.fileSourceLine);
    const sourceLine = markdownLines[lineNumber];

    if (!Number.isInteger(lineNumber) || lineNumber < 0 || sourceLine === undefined || !token) {
      checkbox.checked = previous;
      checkbox.title = "Не удалось связать checkbox с исходным Markdown";
      return;
    }

    checkbox.disabled = true;
    try {
      const query = new URLSearchParams({
        line: String(lineNumber),
        checked: checkbox.checked ? "1" : "0",
        hash: await sha256(sourceLine),
      });
      const response = await fetch(`${endpoint}?${query}`, {
        method: "POST",
        cache: "no-store",
        headers: {
          Accept: "application/json",
          "X-LivePreview-Token": token,
        },
      });
      const result = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
      if (!response.ok || !result.ok) {
        throw new Error(result.error || `HTTP ${response.status}`);
      }

      checkbox.checked = result.checked;
      markdownLines[lineNumber] = result.line;
      checkbox.title = result.saved
        ? "Состояние сохранено в Markdown"
        : "Состояние изменено в Neovim; сохрани буфер, чтобы записать его на диск";
    } catch (error) {
      checkbox.checked = previous;
      checkbox.title = `Не удалось изменить Markdown: ${error.message}`;
      console.error("live-preview task toggle failed", error);
    } finally {
      if (checkbox.isConnected) {
        checkbox.disabled = false;
      }
    }
  };

  const setup = () => {
    const root = document.querySelector(".markdown-body");
    if (!root) {
      return;
    }

    enhanceTasks(root);
    new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach(enhanceTasks);
      });
    }).observe(root, { childList: true, subtree: true });

    root.addEventListener("change", (event) => {
      const checkbox = event.target.closest?.('input[type="checkbox"][data-live-preview-task]');
      if (checkbox) {
        void toggleTask(checkbox);
      }
    });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setup, { once: true });
  } else {
    setup();
  }
})();
