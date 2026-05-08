#!/usr/bin/env python3
"""Tests for build_hmm_metadata.py v2 schema (12 themes / 99 subcategories).

The v2 bundle replaces the v1 single ``category`` column with stable
ID-based fields (``theme_id`` / ``subcategory_id``) plus human-readable
display labels (``theme`` / ``subcategory``). The site filters by IDs
and shows the labels.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
META_JSON = REPO / "metadata" / "hmm_metadata.json"
DOCS_JSON = REPO / "docs" / "data" / "hmm_metadata.json"
SCHEMA_TSV = (
    REPO.parent / "tiammat_mollusca" / "taxonomy" / "theme_subcategory_schema.tsv"
)


def _load_rows() -> list[dict]:
    return json.loads(META_JSON.read_text())["rows"]


def test_metadata_has_1057_rows() -> None:
    rows = _load_rows()
    assert len(rows) == 1057, f"expected 1057 rows, got {len(rows)}"


def test_rows_have_theme_subcategory_id_and_display() -> None:
    """Each row exposes both stable IDs and human-readable display names."""
    rows = _load_rows()
    required = {"theme_id", "theme", "subcategory_id", "subcategory"}
    for r in rows[:5] + rows[-5:]:
        missing = required - set(r)
        assert not missing, f"row missing keys {missing}: keys={sorted(r)}"


def test_no_legacy_category_key() -> None:
    """The v1 ``category`` field should be fully migrated out."""
    rows = _load_rows()
    for r in rows:
        assert "category" not in r, (
            f"stale 'category' key still present in row {r.get('pfam_name')}"
        )


def test_metadata_and_docs_data_byte_identical() -> None:
    """The reproducibility copy and the site copy must match exactly."""
    a = META_JSON.read_bytes()
    b = DOCS_JSON.read_bytes()
    assert a == b, "metadata/ and docs/data/ JSON copies have diverged"


def test_theme_id_resolves_to_display_name() -> None:
    """Spot-check: '01_sensory' must map to 'Sensory perception' in every row."""
    rows = _load_rows()
    sensory_rows = [r for r in rows if r.get("theme_id") == "01_sensory"]
    assert sensory_rows, "expected at least one row with theme_id='01_sensory'"
    for r in sensory_rows:
        assert r["theme"] == "Sensory perception", (
            f"theme_id={r['theme_id']!r} but theme={r['theme']!r}"
        )


def test_schema_tsv_exists() -> None:
    """The display-name lookup source must be present (sibling repo)."""
    assert SCHEMA_TSV.is_file(), f"schema TSV missing at {SCHEMA_TSV}"
