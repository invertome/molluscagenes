#!/usr/bin/env python3
"""Render an HTML report for an mg_characterize run.

Usage: _render_characterize_html.py <characterize_outdir>

Reads <outdir>/summary.tsv (must already exist) and writes a self-contained HTML
to stdout. No CSS framework, no JS — just a styled table the user can open in a
browser or send to collaborators.
"""

from __future__ import annotations

import csv
import datetime
import html
import sys
from pathlib import Path


CSS = """
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
       max-width: 1400px; margin: 2em auto; padding: 0 1em; color: #222; }
h1 { font-size: 1.5em; }
.meta { color: #666; font-size: 0.85em; margin-bottom: 1.5em; }
table { border-collapse: collapse; font-size: 0.85em; width: 100%; }
th, td { border: 1px solid #ddd; padding: 4px 8px; text-align: left;
         vertical-align: top; white-space: nowrap; }
th { background: #f5f5f5; position: sticky; top: 0; }
tr:nth-child(even) { background: #fafafa; }
.species { color: #1565c0; font-style: italic; }
.eval { font-family: ui-monospace, "SF Mono", Menlo, monospace; color: #555; }
.empty { color: #aaa; }
"""


def render_cell(col: str, val: str) -> str:
    if not val:
        return '<td class="empty">—</td>'
    if "evalue" in col:
        return f'<td class="eval">{html.escape(val)}</td>'
    if "species" in col:
        return f'<td class="species">{html.escape(val)}</td>'
    return f"<td>{html.escape(val)}</td>"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    summary = outdir / "summary.tsv"
    if not summary.is_file():
        print(f"summary.tsv not found in {outdir}", file=sys.stderr)
        return 1

    with open(summary) as f:
        rdr = csv.reader(f, delimiter="\t")
        header = next(rdr)
        rows = list(rdr)

    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    print(f"""<!doctype html>
<html><head>
<meta charset="utf-8">
<title>mg_characterize report — {html.escape(outdir.name)}</title>
<style>{CSS}</style>
</head><body>
<h1>mg_characterize report</h1>
<div class="meta">Output dir: <code>{html.escape(str(outdir))}</code><br>
Generated: {when}<br>
Queries: {len(rows)}</div>
<table>
<thead><tr>{''.join(f'<th>{html.escape(h)}</th>' for h in header)}</tr></thead>
<tbody>""")
    for row in rows:
        cells = [render_cell(header[i] if i < len(header) else "", v) for i, v in enumerate(row)]
        print(f"<tr>{''.join(cells)}</tr>")
    print("</tbody></table>")
    print("<p class='meta'>Detailed per-search outputs: <code>blast/</code>, <code>diamond/</code>, <code>hmm/</code>.</p>")
    print("</body></html>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
