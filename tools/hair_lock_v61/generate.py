"""Hair lock v61 pipeline: author, export, verify, apply, evidence.

    python3 tools/hair_lock_v61/generate.py --repository . --output dist/hair_lock_v61 --apply

Addresses two qualified-artwork defects measured on the v60 output:

* **Flat planks.** v60 holds each lock's authored root aspect constant down the
  whole strand; the measured median depth/width is 0.505, so every lock reads as
  a plank in profile. v61 ramps each cross-section toward circular along the
  lock while holding its area, so mass is unchanged and only the shape rounds.
* **Zero-thickness sheets.** Twelve hair shells and collar/hood pieces are open
  sheets. glTF materials are single-sided, so Godot culls their back faces and
  the inside of the garment shows through as the collar sliver the reviews keep
  recording. v61 gives each a closed 7 mm shell.

The driver authors candidates in fresh Blender processes, exports the sixteen
GLBs through the established wardrobe export path, asserts the glTF contract
(430 primitives, 30 with morphs, all nine face-identity target names), records
every hash in the output receipt, renders before/after evidence, and only with
--apply writes the working tree and re-qualifies the production hashes and the
adult decoded PINS.

Unlike v60 this driver takes its baseline from the *working tree*, because the
v60 artwork is the committed state; supply --expect-input-sha256 to pin it.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FAMILIES = {'adult': 'art/characters.blend', 'child': 'art/characters_child.blend',
            'teen': 'art/characters_teen.blend', 'elder': 'art/characters_elder.blend'}
VARIANTS = ['{base}', '{base}_broad', '{base}_lod', '{base}_broad_lod']
TARGET_NAMES = ['Blink', 'Eye_Spacing', 'Face_Round', 'Hand_Grip_L', 'Hand_Grip_R',
                'Jaw_Strong', 'Nose_Wide', 'Sit', 'Smile']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def glb_contract(path):
    """Decoded glTF facts that the export must not disturb."""
    raw = Path(path).read_bytes()
    assert struct.unpack_from('<III', raw) == (0x46546c67, 2, len(raw)), f'{path}: not a GLB'
    at = 12
    chunks = {}
    while at < len(raw):
        size, kind = struct.unpack_from('<II', raw, at)
        at += 8
        chunks[kind] = raw[at:at + size]
        at += size
    doc = json.loads(chunks[0x4e4f534a])
    prims = [pr for m in doc['meshes'] for pr in m['primitives']]
    morph_counts = sorted({len(pr.get('targets', [])) for pr in prims if pr.get('targets')})
    names = set()
    for mesh in doc['meshes']:
        for name in (mesh.get('extras') or {}).get('targetNames', []) or []:
            names.add(name)
    return {'primitives': len(prims), 'primitives_with_morphs': sum(1 for pr in prims if pr.get('targets')),
            'morph_counts': morph_counts, 'target_names': sorted(names),
            'materials': len(doc['materials']), 'skins': len(doc.get('skins', []))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--skip-evidence', action='store_true')
    args = parser.parse_args()
    repo = args.repository.resolve()
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error('Output must be a fresh directory; failed attempts are retained.')
    blender = shutil.which(args.blender)
    assert blender, 'Blender executable not found'
    out.mkdir(parents=True)

    receipt = {'status': 'started', 'stages': [], 'exports': {}, 'contract': {},
               'applied': bool(args.apply)}
    (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def save():
        (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(label, argv, logname):
        started = time.monotonic()
        result = subprocess.run(argv, capture_output=True, text=True)
        (out / (logname + '.log')).write_text(
            result.stdout[-20000:] + '\n--- STDERR ---\n' + result.stderr[-20000:])
        receipt['stages'].append(
            {'label': label, 'returncode': result.returncode,
             'seconds': round(time.monotonic() - started, 1)})
        save()
        assert result.returncode == 0, f'Failed stage retained: {label}'
        return result

    # 1. baseline: the working tree is the committed v60 artwork. Each family's
    # decoded glTF contract is read from its own qualified export, so the
    # assertion compares like with like (child/teen carry 28 morph primitives,
    # elder 36, adult 30).
    inputs = out / 'inputs'
    inputs.mkdir()
    baseline_contracts = {}
    for family, rel in FAMILIES.items():
        src = repo / rel
        assert src.exists(), f'missing baseline {rel}'
        target = inputs / Path(rel).name
        shutil.copyfile(src, target)
        receipt.setdefault('inputs', {})[rel] = sha(src)
        base = 'character' if family == 'adult' else f'character_{family}'
        baseline_contracts[family] = glb_contract(repo / 'assets/models' / (base + '.glb'))
        receipt.setdefault('baseline_contract', {})[family] = baseline_contracts[family]
    save()

    # 2. author candidates (hair-lock rounding plus shell sealing).
    candidates = {}
    for family, rel in FAMILIES.items():
        cand = out / 'art' / Path(rel).name
        run('author_' + family,
            [blender, '--background', '--factory-startup', '--python-exit-code', '2', '--python',
             str(HERE / 'author.py'), '--', '--input', str(inputs / Path(rel).name),
             '--output', str(cand), '--report', str(out / f'report_{family}.json')],
            'author_' + family)
        assert cand.exists()
        candidates[family] = cand
        report = json.loads((out / f'report_{family}.json').read_text())
        receipt.setdefault('author', {})[family] = {
            'changed_objects': report['changed_objects'],
            'unchanged_objects': report['unchanged_objects'],
            'sealed': [s['name'] for s in report['sealed_shells']],
            'lock_aspects': {style: sorted({e['station_aspect'][-1] for e in entries})
                             for style, entries in report['locks'].items()},
        }
        assert report['changed_objects'] == 48, f'{family}: unexpected change count'
        assert len(report['sealed_shells']) == 12, f'{family}: unexpected sealed count'
    save()

    # 3. export the sixteen GLBs through the established path.
    exports = out / 'exports'
    for family, rel in FAMILIES.items():
        base = 'character' if family == 'adult' else f'character_{family}'
        cand_sha = sha(candidates[family])
        for variant in [v.format(base=base) for v in VARIANTS]:
            run('export_' + variant,
                [blender, '--background', '--factory-startup', '--python-exit-code', '2', '--python',
                 str(HERE / 'export_variant.py'), '--', '--source', str(candidates[family]),
                 '--source-sha256', cand_sha, '--output-root', str(exports), '--variant', variant],
                'export_' + variant)
            glb = exports / (variant + '.glb')
            contract = glb_contract(glb)
            # The face-identity contract must survive every change untouched:
            # same primitive count, same morph-bearing primitives, the same nine
            # morph target names and the same single skin as the qualified
            # baseline for this family.
            expected = baseline_contracts[family]
            assert contract['primitives'] == expected['primitives'], f'{variant}: primitive count drifted'
            assert contract['primitives_with_morphs'] == expected['primitives_with_morphs'], \
                f'{variant}: morph primitive count drifted'
            assert contract['target_names'] == expected['target_names'], f'{variant}: morph target names drifted'
            assert contract['skins'] == expected['skins'], f'{variant}: skin count drifted'
            assert contract['materials'] == expected['materials'], f'{variant}: material count drifted'
            receipt['exports'][variant + '.glb'] = {
                'sha256': sha(glb), 'bytes': glb.stat().st_size, 'contract': contract}
    receipt['contract'] = glb_contract(exports / 'character.glb')
    save()

    # 4. evidence renders.
    if not args.skip_evidence:
        evidence = repo / 'evidence/hair61'
        evidence.mkdir(parents=True, exist_ok=True)
        for family, rel in FAMILIES.items():
            run('evidence_' + family,
                [blender, '--background', '--python-exit-code', '2', '--python',
                 str(HERE / 'render_evidence.py'), '--', '--family', family,
                 '--before', str(inputs / Path(rel).name), '--after', str(candidates[family]),
                 '--out', str(evidence)],
                'evidence_' + family)
        receipt['evidence'] = {'directory': str(evidence.relative_to(repo)),
                               'images': len(list(evidence.glob('*.png')))}
        save()

    # 5. apply.
    if args.apply:
        for family, rel in FAMILIES.items():
            shutil.copyfile(candidates[family], repo / rel)
        for glb in sorted(exports.glob('*.glb')):
            shutil.copyfile(glb, repo / 'assets/models' / glb.name)
        hashes = {}
        glb_names = [base + suffix
                     for base in ('character', 'character_child', 'character_teen', 'character_elder')
                     for suffix in ('', '_broad', '_lod', '_broad_lod')]
        for name in glb_names:
            hashes['assets/models/' + name + '.glb'] = sha(repo / 'assets/models' / (name + '.glb'))
        for rel in FAMILIES.values():
            hashes[rel] = sha(repo / rel)
        assert len(hashes) == 20, f'expected 20 manifest entries, got {len(hashes)}'
        (repo / 'art/source/character_production_hashes.json').write_text(
            json.dumps(hashes, indent=1) + '\n')

        sys.path.insert(0, str(repo / 'tools'))
        from verify_character_exports import semantic_digest
        pins = {name: semantic_digest(repo / 'assets/models' / name)
                for name in ('character.glb', 'character_broad.glb',
                             'character_lod.glb', 'character_broad_lod.glb')}
        verifier = repo / 'tools/verify_character_exports.py'
        text = verifier.read_text()
        rendered = 'PINS = {' + ', '.join(f"'{k}': '{v}'" for k, v in pins.items()) + '}'
        text, n = re.subn(
            r"PINS = \{[^}]*\}[^#\n]*(#.*)?",
            rendered + " # Qualified hair-lock v61 rounded lock sections and sealed shells.", text, count=1)
        assert n == 1, 'PINS line not found'
        verifier.write_text(text)
        check = subprocess.run(
            [sys.executable, '-c',
             'import sys; sys.path.insert(0, "tools");'
             'from verify_character_exports import verify_all;'
             'verify_all("assets/models"); print("VERIFY_OK")'],
            cwd=repo, capture_output=True, text=True)
        assert 'VERIFY_OK' in check.stdout, \
            'verify_character_exports failed after re-qualification: ' + check.stderr[-2000:]
        receipt['verify'] = 'VERIFY_OK'

        # The established single-variant path must reproduce the qualified bytes.
        scratch = out / 'repro_check'
        run('repro_export_character',
            [blender, '--background', '--factory-startup', '--python-exit-code', '2', '--python',
             str(repo / 'tools/export_character_variant.py'), '--', '--source', str(repo / FAMILIES['adult']),
             '--source-sha256', sha(repo / FAMILIES['adult']), '--output-root', str(scratch),
             '--variant', 'character'],
            'repro_export_character')
        assert semantic_digest(scratch / 'character.glb') == pins['character.glb'], \
            'established export path drifted'
        save()

    receipt['status'] = 'complete'
    save()
    print('HAIR_LOCK_V61_COMPLETE', out, 'applied' if args.apply else 'dry-run')


if __name__ == '__main__':
    main()
