#!/usr/bin/env python3
"""For every species with a WoRMS AphiaID, fetch the full record and add an
'is_marine' flag (1 if marine/brackish/freshwater, 0 if strictly terrestrial,
empty if WoRMS returns no record). The species browser uses this flag to
suppress the WoRMS link for terrestrial-only molluscs whose WoRMS pages are
stubs.

Adds a `worms_is_marine` column to metadata/species_metadata.tsv and the
matching JSON. Caches each WoRMS record under metadata/_cache/worms_record/.

Usage:
    python scripts/augment_worms_marine.py            # network calls (cached)
    python scripts/augment_worms_marine.py --refresh  # ignore cache, re-fetch all
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parent.parent
TSV_PATH = REPO_ROOT / "metadata" / "species_metadata.tsv"
SCHEMA_PATH = REPO_ROOT / "metadata" / "species_metadata.schema.json"
CACHE_DIR = REPO_ROOT / "metadata" / "_cache" / "worms_record"

WORMS_API = "https://www.marinespecies.org/rest/AphiaRecordByAphiaID/{}"


def fetch_record(aphia_id: str, refresh: bool = False) -> dict | None:
    if not aphia_id or not aphia_id.isdigit():
        return None
    cache = CACHE_DIR / f"{aphia_id}.json"
    if cache.is_file() and not refresh:
        try:
            return json.loads(cache.read_text())
        except Exception:
            pass
    try:
        r = requests.get(WORMS_API.format(aphia_id), timeout=15,
                         headers={"Accept": "application/json"})
    except Exception as e:
        print(f"  network error for {aphia_id}: {e}", file=sys.stderr)
        return None
    if r.status_code == 204 or not r.text.strip():
        record = {"_status": "no record"}
    elif r.status_code != 200:
        print(f"  HTTP {r.status_code} for {aphia_id}", file=sys.stderr)
        return None
    else:
        try:
            record = r.json()
        except Exception:
            return None
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(record))
    return record


def is_marine_flag(rec: dict) -> str:
    """Return '1' if WoRMS classifies the species as marine/brackish/freshwater
    (i.e. the WoRMS page is meaningfully informative), '0' if strictly
    terrestrial, '' if unknown / no record."""
    if not rec or rec.get("_status") == "no record":
        return ""
    flags = (
        rec.get("isMarine"),
        rec.get("isBrackish"),
        rec.get("isFreshwater"),
    )
    is_terrestrial = rec.get("isTerrestrial")
    if any(f == 1 for f in flags):
        return "1"
    if is_terrestrial == 1:
        return "0"
    # No flags set in record — be conservative, mark as unknown so the WoRMS
    # link still shows.
    return "1"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    args = ap.parse_args()

    with open(TSV_PATH) as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    n_with_aphia = sum(1 for r in rows if r.get("worms_aphia_id"))
    print(f"loaded {len(rows)} rows; {n_with_aphia} with worms_aphia_id", file=sys.stderr)

    last = time.time()
    flagged_marine = flagged_terr = unknown = 0
    for i, r in enumerate(rows, 1):
        aphia = r.get("worms_aphia_id", "")
        if not aphia:
            r["worms_is_marine"] = ""
            continue
        # polite ~3 req/s
        elapsed = time.time() - last
        if elapsed < 0.34:
            time.sleep(0.34 - elapsed)
        rec = fetch_record(aphia, refresh=args.refresh)
        last = time.time()
        flag = is_marine_flag(rec or {})
        r["worms_is_marine"] = flag
        if flag == "1":
            flagged_marine += 1
        elif flag == "0":
            flagged_terr += 1
        else:
            unknown += 1
        if i % 25 == 0 or i == len(rows):
            print(f"  {i}/{len(rows)}  marine={flagged_marine}  terrestrial={flagged_terr}  unknown={unknown}",
                  file=sys.stderr)

    # Write back the TSV with the new column appended.
    with open(TSV_PATH) as f:
        header = next(csv.reader(f, delimiter="\t"))
    if "worms_is_marine" not in header:
        header.append("worms_is_marine")
    with open(TSV_PATH, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(header)
        for r in rows:
            w.writerow([r.get(c, "") for c in header])

    # Schema
    if SCHEMA_PATH.is_file():
        schema = json.loads(SCHEMA_PATH.read_text())
        schema.setdefault("columns", {})["worms_is_marine"] = {
            "type": "string",
            "description": "'1' if WoRMS marks the species as marine/brackish/freshwater (linkable WoRMS page); '0' if strictly terrestrial; empty if WoRMS returned no record."
        }
        SCHEMA_PATH.write_text(json.dumps(schema, indent=2))

    print(f"\ndone — marine: {flagged_marine}, terrestrial: {flagged_terr}, unknown: {unknown}", file=sys.stderr)
    print(f"wrote {TSV_PATH}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
