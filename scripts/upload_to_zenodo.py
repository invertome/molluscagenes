#!/usr/bin/env python3
"""Upload a built MolluscaGenes Zenodo deposit using the Zenodo REST API.

This creates a new deposition (or updates an existing draft), uploads every
file in the staging directory via the bucket API (chunked, robust on large
files), sets deposit metadata, and prints the deposition URL. It does NOT
publish — that final step is done manually via the Zenodo web UI after
human review of the draft.

Usage:
    python scripts/upload_to_zenodo.py <staging_dir>
    python scripts/upload_to_zenodo.py <staging_dir> --sandbox
    python scripts/upload_to_zenodo.py <staging_dir> --deposition-id 12345
        (resume into an existing draft)

Token is read from ~/.zenodo_token (or $ZENODO_TOKEN). Token must be a
Personal Access Token with `deposit:write` and `deposit:actions` scopes.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests

ZENODO_PROD = "https://zenodo.org/api"
ZENODO_SANDBOX = "https://sandbox.zenodo.org/api"


def load_token() -> str:
    """Read PAT from $ZENODO_TOKEN or ~/.zenodo_token."""
    tok = os.environ.get("ZENODO_TOKEN", "").strip()
    if tok:
        return tok
    p = Path.home() / ".zenodo_token"
    if not p.is_file():
        sys.exit("error: no Zenodo token. Set $ZENODO_TOKEN or save the PAT to ~/.zenodo_token (chmod 600).")
    tok = p.read_text().strip()
    if not tok:
        sys.exit(f"error: {p} is empty")
    return tok


def deposit_metadata() -> dict:
    """Metadata for the deposition. Mirrors CITATION.cff and the manuscript abstract."""
    return {
        "metadata": {
            "title": "MolluscaGenes v0.1 — preliminary release",
            "upload_type": "dataset",
            "description": (
                "<p><strong>MolluscaGenes v0.1 — preliminary release.</strong> A "
                "taxonomically comprehensive mollusc transcriptome and proteome "
                "resource consolidating de-novo and previously published transcriptomes "
                "for ~300 species spanning all eight molluscan classes "
                "(Gastropoda, Bivalvia, Cephalopoda, Polyplacophora, Scaphopoda, "
                "Solenogastres, Caudofoveata, Monoplacophora). The release is paired "
                "with the TIAMMAt mollusc-revised Pfam HMMs (190 domains across 50 "
                "biological categories) for sensitive detection of divergent homologs "
                "across the phylum.</p>"
                "<p><strong>Contents.</strong> BLAST and DIAMOND databases (protein), "
                "BLAST nucleotide database, raw protein and mRNA FASTA (gzipped), "
                "TIAMMAt-revised HMMs with hmmpress indices, per-species and per-HMM "
                "metadata tables, manifest with SHA256 checksums.</p>"
                "<p><strong>Code.</strong> Command-line wrappers and reproducibility "
                "scripts ship in the companion GitHub repository "
                "<a href=\"https://github.com/invertome/molluscagenes\">"
                "invertome/molluscagenes</a> (GPL-3.0). The wrapper "
                "<code>mg_fetch.sh</code> downloads every artifact in this deposit, "
                "verifies SHA256 against the manifest, extracts the tarballs, and "
                "writes a populated configuration file.</p>"
                "<p><strong>Versioning.</strong> v0.1 is the database used in the "
                "accompanying biorxiv preprint. A full HPC rebuild (v1.0) is in "
                "progress and will supersede v0.1 under the same Zenodo concept "
                "DOI.</p>"
            ),
            "creators": [
                {
                    "name": "Pérez-Moreno, Jorge L.",
                    "affiliation": "University of Massachusetts Amherst",
                },
                {
                    "name": "Katz, Paul S.",
                    "affiliation": "University of Massachusetts Amherst",
                },
            ],
            "keywords": [
                "mollusca",
                "transcriptome",
                "proteome",
                "BLAST database",
                "DIAMOND database",
                "HMM",
                "Pfam",
                "phylogenetics",
                "chemotactile receptor",
                "nicotinic acetylcholine receptor",
            ],
            "license": "cc-by-4.0",
            "access_right": "open",
            "version": "0.1.0",
            "related_identifiers": [
                {
                    "identifier": "https://github.com/invertome/molluscagenes",
                    "relation": "isSupplementTo",
                    "scheme": "url",
                },
            ],
            "language": "eng",
        }
    }


def api_get(base: str, path: str, token: str) -> dict:
    r = requests.get(f"{base}{path}", headers={"Authorization": f"Bearer {token}"}, timeout=60)
    r.raise_for_status()
    return r.json()


def api_post(base: str, path: str, token: str, json_body: dict | None = None) -> dict:
    r = requests.post(
        f"{base}{path}",
        json=json_body or {},
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=60,
    )
    r.raise_for_status()
    return r.json() if r.text else {}


def api_put_json(base: str, path: str, token: str, json_body: dict) -> dict:
    r = requests.put(
        f"{base}{path}",
        json=json_body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=120,
    )
    r.raise_for_status()
    return r.json()


def upload_file_to_bucket(bucket_url: str, path: Path, token: str, max_retries: int = 3) -> None:
    """PUT a file to the deposition bucket. Streams the body — no whole-file load."""
    name = path.name
    size = path.stat().st_size
    print(f"  upload: {name} ({size:,} bytes)", flush=True)
    last_err: Exception | None = None
    for attempt in range(1, max_retries + 1):
        try:
            with open(path, "rb") as fh:
                r = requests.put(
                    f"{bucket_url}/{name}",
                    data=fh,
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=None,  # large files
                )
            if r.status_code in (200, 201):
                return
            last_err = RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
        except Exception as e:
            last_err = e
        if attempt < max_retries:
            wait = 5 * attempt
            print(f"    upload failed ({last_err}); retry {attempt + 1}/{max_retries} in {wait}s", flush=True)
            time.sleep(wait)
    raise RuntimeError(f"giving up on {name}: {last_err}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("staging", help="path to staging dir produced by scripts/build_all.sh")
    ap.add_argument("--sandbox", action="store_true", help="use sandbox.zenodo.org")
    ap.add_argument("--deposition-id", type=int, default=None, help="resume into an existing draft")
    ap.add_argument("--metadata-only", action="store_true", help="set metadata + skip uploads")
    args = ap.parse_args()

    staging = Path(args.staging).resolve()
    if not staging.is_dir():
        sys.exit(f"not a directory: {staging}")

    base = ZENODO_SANDBOX if args.sandbox else ZENODO_PROD
    token = load_token()
    print(f"target: {base}")
    print(f"staging: {staging}")

    # Skip these dotfiles / sentinels if any leaked in
    files = sorted(p for p in staging.iterdir()
                   if p.is_file() and not p.name.startswith("."))
    if not files:
        sys.exit("no files to upload in staging dir")
    print(f"found {len(files)} files to upload")

    if args.deposition_id:
        dep = api_get(base, f"/deposit/depositions/{args.deposition_id}", token)
        print(f"resuming deposition {dep['id']} (state={dep.get('state')})")
    else:
        print("creating new deposition...")
        dep = api_post(base, "/deposit/depositions", token, json_body={})
        print(f"created deposition {dep['id']}")

    bucket_url = dep["links"]["bucket"]
    print(f"bucket: {bucket_url}")

    if not args.metadata_only:
        # List files already on the deposition (resume case)
        existing = {f["filename"] for f in dep.get("files", [])}
        for f in files:
            if f.name in existing:
                print(f"  skip: {f.name} (already uploaded)")
                continue
            upload_file_to_bucket(bucket_url, f, token)

    print("setting metadata...")
    api_put_json(base, f"/deposit/depositions/{dep['id']}", token, deposit_metadata())

    # Refresh and print the html URL for human review
    dep = api_get(base, f"/deposit/depositions/{dep['id']}", token)
    print()
    print("=" * 60)
    print(f"deposition id : {dep['id']}")
    print(f"state         : {dep.get('state')}")
    print(f"draft URL     : {dep['links'].get('html', '(unknown)')}")
    print(f"reserved DOI  : {dep.get('metadata', {}).get('prereserve_doi', {}).get('doi', '(none yet)')}")
    print(f"file count    : {len(dep.get('files', []))}")
    print()
    print("Review the draft in the browser. When ready to publish,")
    print(f"either click 'Publish' on the deposition page, or run:")
    print(f"  curl -X POST -H 'Authorization: Bearer $TOKEN' \\")
    print(f"       {base}/deposit/depositions/{dep['id']}/actions/publish")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
