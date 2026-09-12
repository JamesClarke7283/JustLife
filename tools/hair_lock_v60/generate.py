"""Hair lock v60 pipeline: pin, author, export, verify, apply, evidence.

    python3 tools/hair_lock_v60/generate.py --repository . --output dist/hair_lock_v60 --apply

Reads the pinned baseline blends out of the baseline commit recorded in
manifest.json (byte hashes must match the working tree or the run is refused),
authors candidate blends in fresh Blender processes, exports all sixteen GLBs
through the established wardrobe export path, records every hash in the output
receipt, and only with --apply copies the results into the working tree,
re-qualifies art/source/character_production_hashes.json and the adult PINS in
tools/verify_character_exports.py, and re-runs that verifier.
"""
import argparse, hashlib, json, re, shutil, struct, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FAMILIES = {'adult': 'art/characters.blend', 'child': 'art/characters_child.blend',
            'teen': 'art/characters_teen.blend', 'elder': 'art/characters_elder.blend'}
VARIANTS = ['{base}', '{base}_broad', '{base}_lod', '{base}_broad_lod']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def glb_node_mesh_vert_counts(path, needle):
    """Map node names containing `needle` to their mesh POSITION vertex counts."""
    raw = Path(path).read_bytes()
    assert struct.unpack_from('<III', raw) == (0x46546c67, 2, len(raw))
    at = 12
    chunks = {}
    while at < len(raw):
        size, kind = struct.unpack_from('<II', raw, at)
        at += 8
        chunks[kind] = raw[at:at + size]
        at += size
    doc = json.loads(chunks[0x4e4f534a])
    counts = {}
    for node in doc.get('nodes', []):
        name = node.get('name', '')
        if needle in name and 'mesh' in node:
            mesh = doc['meshes'][node['mesh']]
            prim = mesh['primitives'][0]
            acc = doc['accessors'][prim['attributes']['POSITION']]
            counts[name] = acc['count']
    return counts


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
    contract = json.loads((HERE / 'manifest.json').read_text())
    blender = shutil.which(args.blender)
    assert blender, 'Blender executable not found'

    # 1. pinned inputs, extracted from the baseline commit, hash-verified
    inputs = out / 'inputs'
    inputs.mkdir(parents=True)
    receipt = {'status': 'started', 'baseline': contract['baseline'], 'inputs': {}, 'stages': [],
               'exports': {}, 'evidence': {}, 'applied': bool(args.apply)}
    for rel, pin in contract['inputs'].items():
        blob = subprocess.run(['git', '-C', str(repo), 'show', f"{contract['baseline']['commit']}:{rel}"],
                              capture_output=True, check=True).stdout
        assert hashlib.sha256(blob).hexdigest() == pin['sha256'], f'Pinned input drift: {rel}'
        work = repo / rel
        assert work.exists() and sha(work) == pin['sha256'], f'Working tree differs from the pinned baseline: {rel}'
        target = inputs / Path(rel).name
        target.write_bytes(blob)
        receipt['inputs'][rel] = pin['sha256']
    (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(label, argv, logname):
        started = time.monotonic()
        result = subprocess.run(argv, capture_output=True, text=True)
        (out / (logname + '.log')).write_text(result.stdout[-20000:] + '\n--- STDERR ---\n' + result.stderr[-20000:])
        entry = {'label': label, 'returncode': result.returncode, 'seconds': round(time.monotonic() - started, 1)}
        receipt['stages'].append(entry)
        (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
        assert result.returncode == 0, f'Failed stage retained: {label}'
        return result

    # 2. author candidates
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
            'hood': report['hood'],
            'lock_vert_counts': sorted({e['verts'] for st in report['locks'].values() for e in st}),
        }
        assert report['changed_objects'] == contract['expected']['changed_objects_per_family']
        assert report['hood']['edge_max_after'] <= contract['expected']['hood_edge_max_after']

    # 3. export the sixteen GLBs through the established path
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
            locks = glb_node_mesh_vert_counts(glb, '_Lock')
            assert locks, f'{variant}: no lock nodes found'
            floor = 12 if variant.endswith('_lod') else 60
            assert min(locks.values()) >= floor, f'{variant}: lock decimated to nothing: {min(locks.values())}'
            receipt['exports'][variant + '.glb'] = {
                'sha256': sha(glb), 'bytes': glb.stat().st_size,
                'lock_nodes': len(locks), 'lock_verts_min': min(locks.values()), 'lock_verts_max': max(locks.values())}

    # 4. evidence renders: before = pinned input, after = candidate
    if not args.skip_evidence:
        evidence = repo / 'evidence/hair60'
        evidence.mkdir(parents=True, exist_ok=True)
        for family, rel in FAMILIES.items():
            run('evidence_' + family,
                [blender, '--background', '--python-exit-code', '2', '--python',
                 str(HERE / 'render_evidence.py'), '--', '--family', family,
                 '--before', str(inputs / Path(rel).name), '--after', str(candidates[family]),
                 '--out', str(evidence)],
                'evidence_' + family)
        receipt['evidence']['directory'] = str(evidence.relative_to(repo))
        receipt['evidence']['images'] = len(list(evidence.glob('*.png')))

    # 5. apply: candidate blends, GLBs, production hashes, verifier PINS
    if args.apply:
        for family, rel in FAMILIES.items():
            shutil.copyfile(candidates[family], repo / rel)
        for glb in exports.glob('*.glb'):
            shutil.copyfile(glb, repo / 'assets/models' / glb.name)
        hashes = {}
        glb_names = [base + suffix for base in ('character', 'character_child', 'character_teen', 'character_elder')
                     for suffix in ('', '_broad', '_lod', '_broad_lod')]
        for name in glb_names:
            hashes['assets/models/' + name + '.glb'] = sha(repo / 'assets/models' / (name + '.glb'))
        for rel in FAMILIES.values():
            hashes[rel] = sha(repo / rel)
        assert len(hashes) == 20, f'expected 20 manifest entries, got {len(hashes)}'
        (repo / 'art/source/character_production_hashes.json').write_text(json.dumps(hashes, indent=1) + '\n')
        # re-qualify the adult decoded PINS from the freshly exported files
        sys.path.insert(0, str(repo / 'tools'))
        from verify_character_exports import semantic_digest
        pins = {}
        for name in ['character.glb', 'character_broad.glb', 'character_lod.glb', 'character_broad_lod.glb']:
            pins[name] = semantic_digest(repo / 'assets/models' / name)
        verifier = repo / 'tools/verify_character_exports.py'
        text = verifier.read_text()
        rendered = 'PINS = {' + ', '.join(f"'{k}': '{v}'" for k, v in pins.items()) + '}'
        text, n = re.subn(r"PINS = \{[^}]*\}[^#\n]*(#.*)?", rendered + " # Qualified hair-lock v60 rounded tapered locks and seated hood; rig18/surface2 retained.", text, count=1)
        assert n == 1, 'PINS line not found'
        verifier.write_text(text)
        check = subprocess.run([sys.executable, '-c',
                                'import sys; sys.path.insert(0, "tools");'
                                'from verify_character_exports import verify_all;'
                                'verify_all("assets/models"); print("VERIFY_OK")'],
                               cwd=repo, capture_output=True, text=True)
        assert 'VERIFY_OK' in check.stdout, 'verify_character_exports failed after re-qualification: ' + check.stderr[-2000:]
        receipt['verify'] = 'VERIFY_OK'
        # established single-variant path must reproduce the qualified bytes
        scratch = out / 'repro_check'
        run('repro_export_character',
            [blender, '--background', '--factory-startup', '--python-exit-code', '2', '--python',
             str(repo / 'tools/export_character_variant.py'), '--', '--source', str(repo / FAMILIES['adult']),
             '--source-sha256', sha(repo / FAMILIES['adult']), '--output-root', str(scratch),
             '--variant', 'character'],
            'repro_export_character')
        assert semantic_digest(scratch / 'character.glb') == pins['character.glb'], 'established export path drifted'
    receipt['status'] = 'complete'
    (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('HAIR_LOCK_V60_COMPLETE', out, 'applied' if args.apply else 'dry-run')


if __name__ == '__main__':
    main()
