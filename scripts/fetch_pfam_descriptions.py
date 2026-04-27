#!/usr/bin/env python3
"""Fetch human-readable descriptions for every Pfam HMM in hmm_metadata.json.

Uses the InterPro REST API (the modern home of Pfam):
    https://www.ebi.ac.uk/interpro/api/entry/pfam/{accession}/?format=json

Writes back into metadata/hmm_metadata.tsv and metadata/hmm_metadata.json with
two new columns:
    pfam_description       short prose description from Pfam
    pfam_short_name        the human-readable short name (often more useful than `pfam_name`)

Cached under metadata/_cache/pfam/<accession>.json so re-runs are fast.

Usage:
    python scripts/fetch_pfam_descriptions.py
    python scripts/fetch_pfam_descriptions.py --skip-network   # cache-only
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parent.parent
TSV_PATH = REPO_ROOT / "metadata" / "hmm_metadata.tsv"
JSON_PATH = REPO_ROOT / "metadata" / "hmm_metadata.json"
CACHE_DIR = REPO_ROOT / "metadata" / "_cache" / "pfam"

API_URL = "https://www.ebi.ac.uk/interpro/api/entry/pfam/{}/?format=json"
HTML_RE = re.compile(r"<[^>]+>")


def strip_html(s: str) -> str:
    """InterPro descriptions are HTML; strip tags + normalise whitespace."""
    return re.sub(r"\s+", " ", HTML_RE.sub("", s or "")).strip()


def fetch(accession: str, skip_network: bool = False) -> dict:
    cache = CACHE_DIR / f"{accession}.json"
    if cache.is_file():
        try:
            return json.loads(cache.read_text())
        except Exception:
            pass
    if skip_network:
        return {}
    try:
        r = requests.get(API_URL.format(accession), timeout=20,
                         headers={"Accept": "application/json"})
    except Exception as e:
        print(f"  {accession}: network error {e}", file=sys.stderr)
        return {}
    if r.status_code != 200:
        print(f"  {accession}: HTTP {r.status_code}", file=sys.stderr)
        return {}
    data = r.json()
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(data))
    return data


def _coerce_text(x) -> str:
    """Tolerate any of the shapes InterPro uses for textual fields:
    a string, a dict with a 'text' key, or a list of either."""
    if x is None:
        return ""
    if isinstance(x, str):
        return x
    if isinstance(x, dict):
        return _coerce_text(x.get("text") or x.get("description") or "")
    if isinstance(x, list):
        for item in x:
            t = _coerce_text(item)
            if t:
                return t
        return ""
    return str(x)


def extract_fields(api_data: dict) -> tuple[str, str]:
    """Return (description, short_name) from an InterPro entry response."""
    if not api_data:
        return "", ""
    md = api_data.get("metadata", {})
    name_field = md.get("name", {})
    if isinstance(name_field, dict):
        long_ = name_field.get("name", "") or name_field.get("short", "")
    else:
        long_ = _coerce_text(name_field)
    desc = strip_html(_coerce_text(md.get("description", "")))
    return desc, long_


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-network", action="store_true")
    args = ap.parse_args()

    if not TSV_PATH.is_file() or not JSON_PATH.is_file():
        sys.exit("hmm_metadata.tsv/.json missing — run scripts/build_hmm_metadata.py first.")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    with open(TSV_PATH) as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    print(f"loading {len(rows)} HMMs from hmm_metadata.tsv...", file=sys.stderr)

    last = time.time()
    descs = {}
    for i, row in enumerate(rows, 1):
        acc = row["pfam_accession"]
        if not acc:
            continue
        if acc in descs:
            continue
        # Polite throttling: ~3 req/s
        elapsed = time.time() - last
        if elapsed < 0.35:
            time.sleep(0.35 - elapsed)
        api = fetch(acc, skip_network=args.skip_network)
        last = time.time()
        descs[acc] = extract_fields(api)
        if i % 10 == 0 or i == len(rows):
            print(f"  {i}/{len(rows)}", file=sys.stderr)

    # Update rows
    for row in rows:
        d, sn = descs.get(row["pfam_accession"], ("", ""))
        row["pfam_description"] = d
        row["pfam_short_name"] = sn

    # Write TSV (append the two new columns)
    with open(TSV_PATH) as f:
        header = next(csv.reader(f, delimiter="\t"))
    new_cols = header + ["pfam_short_name", "pfam_description"]
    with open(TSV_PATH, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(new_cols)
        for row in rows:
            w.writerow([row.get(c, "") for c in new_cols])

    # Write JSON
    with open(JSON_PATH) as f:
        payload = json.load(f)
    payload["columns"] = new_cols
    payload["rows"] = rows
    with open(JSON_PATH, "w") as f:
        json.dump(payload, f, indent=2)

    print(f"updated {TSV_PATH}", file=sys.stderr)
    print(f"updated {JSON_PATH}", file=sys.stderr)
    print(f"descriptions populated: {sum(1 for r in rows if r['pfam_description'])}/{len(rows)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
