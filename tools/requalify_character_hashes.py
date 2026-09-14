"""Re-qualify the character production hashes after a reviewed asset promotion.

Two records pin the accepted production characters, and both go stale the
moment an asset or editable source is promoted:

* `art/source/character_production_hashes.json` — the SHA-256 of all twenty
  production GLBs and the four editable `.blend` sources.
* `tools/verify_character_exports.py`'s `PINS` — the semantic digest of the
  four adult variants, which the exporter test compares against.

Editing either by hand is how they rot: in iteration 63 the sixteen GLB entries
were refreshed while the four `.blend` entries were left at their pre-promotion
values, so a manifest that exists to detect exactly that drift was itself wrong.
This tool refreshes both from the files on disk in one pass, then immediately
re-reads them and fails if anything still disagrees — so a promotion cannot
succeed while a pin is stale.

It does not decide whether a promotion was correct: run it only after the
replacement has been reviewed and the character contract probe passes.

    python3 tools/requalify_character_hashes.py [--check]

`--check` makes no changes and exits non-zero if either record is stale, which
is the form a test or CI step should use.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'art/source/character_production_hashes.json'
VERIFIER = ROOT / 'tools/verify_character_exports.py'
ADULT_PINS = ('character.glb', 'character_broad.glb',
              'character_lod.glb', 'character_broad_lod.glb')
EXPECTED_ENTRIES = 20


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_verifier():
    sys.path.insert(0, str(ROOT / 'tools'))
    from verify_character_exports import semantic_digest, PINS
    return semantic_digest, PINS


def stale_entries(manifest: dict) -> list[str]:
    stale = []
    for key, recorded in manifest.items():
        path = ROOT / key
        if not path.is_file():
            stale.append(key + ' (missing)')
        elif sha256(path) != recorded:
            stale.append(key)
    return stale


def stale_pins(pins: dict) -> list[str]:
    semantic_digest, _ = load_verifier()
    stale = []
    for name in ADULT_PINS:
        path = ROOT / 'assets/models' / name
        if not path.is_file():
            stale.append(name + ' (missing)')
        elif semantic_digest(path) != pins.get(name):
            stale.append(name)
    return stale


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true',
                        help='report staleness and change nothing')
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    if len(manifest) != EXPECTED_ENTRIES:
        print('Manifest has %d entries, expected %d' % (len(manifest), EXPECTED_ENTRIES))
        return 2

    _, pins = load_verifier()
    stale_m, stale_p = stale_entries(manifest), stale_pins(pins)

    if args.check:
        for key in stale_m:
            print('STALE manifest entry: ' + key)
        for name in stale_p:
            print('STALE verifier pin: ' + name)
        print('requalify check:', 'clean' if not (stale_m or stale_p) else 'STALE')
        return 1 if (stale_m or stale_p) else 0

    refreshed = {}
    for key in manifest:
        path = ROOT / key
        if not path.is_file():
            print('Cannot re-hash a missing file: ' + key)
            return 2
        refreshed[key] = sha256(path)
    MANIFEST.write_text(json.dumps(refreshed, indent=2) + '\n')

    semantic_digest, _ = load_verifier()
    new_pins = {name: semantic_digest(ROOT / 'assets/models' / name) for name in ADULT_PINS}
    text = VERIFIER.read_text()
    rendered = 'PINS = {' + ', '.join("'%s': '%s'" % (k, v) for k, v in new_pins.items()) + '}'
    text, count = re.subn(r"^PINS = \{[^}]*\}[^\n]*", rendered + ' # Re-qualified by tools/requalify_character_hashes.py.', text,
                          count=1, flags=re.M)
    if count != 1:
        print('Could not locate the PINS line in tools/verify_character_exports.py')
        return 2
    VERIFIER.write_text(text)

    # Verify what was just written, so a stale pin cannot survive a promotion.
    import importlib
    for module in [m for m in list(sys.modules) if m == 'verify_character_exports']:
        del sys.modules[module]
    after_manifest = json.loads(MANIFEST.read_text())
    _, after_pins = load_verifier()
    remaining = stale_entries(after_manifest) + stale_pins(after_pins)
    if remaining:
        for key in remaining:
            print('STILL STALE after re-qualification: ' + key)
        return 1

    print('REQUALIFIED manifest=%d pins=%d refreshed_manifest=%d refreshed_pins=%d'
          % (len(after_manifest), len(after_pins), len(stale_m), len(stale_p)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
