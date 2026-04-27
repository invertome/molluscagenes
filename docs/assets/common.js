// Shared utilities for the MolluscaGenes site.

// Render a sortable, filterable HTML table from an array of row objects.
// Options: { container, columns, rows, sortable=true, rowClass, onRow }
// columns is an array of { key, label, type='string'|'number', cls, render }
function makeTable({ container, columns, rows, sortable = true, rowClass, onRow }) {
    const root = container instanceof HTMLElement ? container : document.querySelector(container);
    root.innerHTML = "";
    const table = document.createElement("table");
    table.className = "data";
    const thead = document.createElement("thead");
    const trh = document.createElement("tr");
    columns.forEach((col, i) => {
        const th = document.createElement("th");
        th.textContent = col.label;
        if (col.cls) th.classList.add(col.cls);
        if (sortable) {
            th.addEventListener("click", () => {
                const order = th.classList.contains("sort-asc") ? "desc" : "asc";
                trh.querySelectorAll("th").forEach(o => o.classList.remove("sort-asc", "sort-desc"));
                th.classList.add(order === "asc" ? "sort-asc" : "sort-desc");
                rows.sort((a, b) => {
                    const av = a[col.key], bv = b[col.key];
                    if (col.type === "number") {
                        const an = parseFloat(av) || 0, bn = parseFloat(bv) || 0;
                        return order === "asc" ? an - bn : bn - an;
                    }
                    return order === "asc"
                        ? String(av).localeCompare(String(bv))
                        : String(bv).localeCompare(String(av));
                });
                renderBody();
            });
        }
        trh.appendChild(th);
    });
    thead.appendChild(trh);
    table.appendChild(thead);
    const tbody = document.createElement("tbody");
    table.appendChild(tbody);
    root.appendChild(table);

    function renderBody() {
        tbody.innerHTML = "";
        rows.forEach(row => {
            const tr = document.createElement("tr");
            if (rowClass) tr.className = rowClass(row);
            columns.forEach(col => {
                const td = document.createElement("td");
                if (col.cls) td.classList.add(col.cls);
                const val = row[col.key];
                if (col.render) {
                    const out = col.render(val, row);
                    if (out instanceof HTMLElement) td.appendChild(out);
                    else td.innerHTML = out ?? "";
                } else {
                    td.textContent = val ?? "";
                }
                tr.appendChild(td);
            });
            if (onRow) onRow(tr, row);
            tbody.appendChild(tr);
        });
    }
    renderBody();
    return { table, renderBody };
}

// Parse a tab-separated file into row objects. First row is the header.
async function fetchTSV(path) {
    const r = await fetch(path);
    if (!r.ok) throw new Error(`fetch ${path}: HTTP ${r.status}`);
    const text = await r.text();
    const lines = text.split(/\r?\n/).filter(l => l.length > 0);
    if (!lines.length) return [];
    const header = lines[0].split("\t");
    return lines.slice(1).map(line => {
        const cells = line.split("\t");
        const row = {};
        header.forEach((h, i) => row[h] = cells[i] ?? "");
        return row;
    });
}

// Open a modal with a copyable curl snippet for downloading selected files.
function showDownloadModal(htmlBody) {
    let modal = document.getElementById("download-modal");
    if (!modal) {
        modal = document.createElement("div");
        modal.id = "download-modal";
        modal.innerHTML = `<div class="modal-body"><span class="close">×</span><div class="content"></div></div>`;
        document.body.appendChild(modal);
        modal.querySelector(".close").addEventListener("click", () => modal.classList.remove("shown"));
        modal.addEventListener("click", e => { if (e.target === modal) modal.classList.remove("shown"); });
    }
    modal.querySelector(".content").innerHTML = htmlBody;
    modal.classList.add("shown");
}

// Lazy-load JSZip from the local bundle (no CDN dependency at runtime).
function loadJSZip() {
    if (window.JSZip) return Promise.resolve(window.JSZip);
    return new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = "assets/jszip.min.js";
        s.onload = () => resolve(window.JSZip);
        s.onerror = () => reject(new Error("Failed to load assets/jszip.min.js"));
        document.head.appendChild(s);
    });
}

// Trigger a download of `blob` as `filename` from the user's browser.
function triggerBlobDownload(blob, filename) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

// "/" focuses the page's search input (skipped if user is already typing).
document.addEventListener("keydown", (e) => {
    if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey) return;
    const tag = (document.activeElement && document.activeElement.tagName || "").toLowerCase();
    if (tag === "input" || tag === "textarea" || tag === "select") return;
    const search = document.querySelector('input[type="search"]');
    if (search) { e.preventDefault(); search.focus(); search.select(); }
});

// Add copy-to-clipboard buttons to every <pre> on the page.
function installCopyButtons(root = document) {
    for (const pre of root.querySelectorAll("pre")) {
        if (pre.querySelector(".copy-btn")) continue;
        pre.classList.add("copyable");
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "copy-btn";
        btn.textContent = "Copy";
        btn.setAttribute("aria-label", "Copy to clipboard");
        btn.addEventListener("click", async () => {
            const text = pre.innerText.replace(/^Copy\n?/, "");
            try {
                await navigator.clipboard.writeText(text);
                btn.textContent = "Copied";
                btn.classList.add("copied");
                setTimeout(() => { btn.textContent = "Copy"; btn.classList.remove("copied"); }, 1600);
            } catch (err) {
                btn.textContent = "Copy failed";
                setTimeout(() => { btn.textContent = "Copy"; }, 1600);
            }
        });
        pre.appendChild(btn);
    }
}

// IntersectionObserver-driven count-up for stat numbers.
function installStatCountUp(root = document) {
    const targets = root.querySelectorAll(".stat .num");
    if (!targets.length || !("IntersectionObserver" in window)) return;
    const ease = (t) => 1 - Math.pow(1 - t, 3);
    const animate = (el) => {
        if (el.classList.contains("stat-counted")) return;
        el.classList.add("stat-counted");
        // Capture the original text, parse out the leading number, hold any suffix
        // (e.g. "M", "classes" inside <small>) verbatim.
        const original = el.innerHTML;
        const match = el.textContent.trim().match(/^[~]?(\d+(?:\.\d+)?)/);
        if (!match) return;
        const target = parseFloat(match[1]);
        const prefix = el.textContent.trim().startsWith("~") ? "~" : "";
        const suffixHTML = original.replace(/^\s*[~]?\d+(?:\.\d+)?/, "");
        const dur = 1200;
        const t0 = performance.now();
        const step = (now) => {
            const t = Math.min(1, (now - t0) / dur);
            const v = Math.round(ease(t) * target);
            el.innerHTML = prefix + v + suffixHTML;
            if (t < 1) requestAnimationFrame(step);
            else el.innerHTML = original;
        };
        requestAnimationFrame(step);
    };
    const obs = new IntersectionObserver((entries) => {
        for (const e of entries) if (e.isIntersecting) animate(e.target);
    }, { threshold: 0.4 });
    targets.forEach(t => obs.observe(t));
}

// Trap keyboard focus inside an element while it is open as a modal.
function installFocusTrap(modalEl) {
    const handler = (e) => {
        if (!modalEl.classList.contains("shown")) return;
        if (e.key === "Escape") { modalEl.classList.remove("shown"); return; }
        if (e.key !== "Tab") return;
        const focusables = modalEl.querySelectorAll(
            'a[href], button, textarea, input, select, [tabindex]:not([tabindex="-1"])'
        );
        if (!focusables.length) return;
        const first = focusables[0], last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    document.addEventListener("keydown", handler);
}

// Auto-install on every page that loads common.js
document.addEventListener("DOMContentLoaded", () => {
    installCopyButtons();
    installStatCountUp();
    const modal = document.getElementById("download-modal");
    if (modal) installFocusTrap(modal);
});
