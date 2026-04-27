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

// Lazy-load JSZip from a CDN. Returns a promise resolving to the JSZip constructor.
function loadJSZip() {
    if (window.JSZip) return Promise.resolve(window.JSZip);
    return new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = "https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js";
        s.onload = () => resolve(window.JSZip);
        s.onerror = () => reject(new Error("Failed to load JSZip from CDN"));
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
