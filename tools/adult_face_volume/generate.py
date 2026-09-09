"""Reproduce the reviewed adult lower-face neutral, Smile and four exports.

Every stage is a separate background Blender process. All results, logs and
environment roots are new output files; the repository and input stay unchanged.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV_ROOTS = {
    'XDG_DATA_HOME': 'data',
    'JUSTLIFE_DATA_DIR': 'save_data',
    'XDG_CONFIG_HOME': 'config',
    'XDG_CACHE_HOME': 'cache',
    'TMPDIR': 'tmp',
    'BLENDER_USER_CONFIG': 'blender_config',
}
VARIANTS = ('character', 'character_broad', 'character_lod', 'character_broad_lod')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--repository', type=Path, help='Git repository containing the pinned production commit')
    source.add_argument('--input-blend', type=Path, help='Byte-exact production Blend instead of Git')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--blender', default='blender')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        parser.error('Output must not exist; previous attempts are retained.')
    if args.input_blend and out in args.input_blend.resolve().parents:
        parser.error('Output must not contain the input.')
    contract = json.loads((HERE / 'contract.json').read_text())
    tool_paths = [path for path in HERE.iterdir() if path.is_file()]
    for name, pin in contract['shared_tools'].items():
        path = HERE.parent / name
        if sha(path) != pin:
            parser.error('Shared helper differs from the reviewed version: ' + name)
        tool_paths.append(path)
    pins = {str(path.relative_to(HERE.parent)): sha(path) for path in sorted(tool_paths)}
    out.mkdir(parents=True)
    (out / 'inputs').mkdir()
    (out / 'logs').mkdir()
    receipt = {'status': 'started', 'baseline': contract['baseline'], 'tools': pins,
               'phases': [], 'outputs': {}, 'input_unchanged': None, 'tools_unchanged': None}

    def write():
        (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')

    baseline = out / 'inputs/characters.blend'
    original = args.input_blend.resolve() if args.input_blend else None
    original_pin = None
    write()

    def run(name, script, arguments, threads):
        env = os.environ.copy()
        for key, folder in ENV_ROOTS.items():
            path = out / 'environment' / name / folder
            path.mkdir(parents=True)
            env[key] = str(path)
        assert env.get('HOME') == os.environ.get('HOME')
        command = [args.blender, '--background', '--factory-startup', '-t', str(threads),
                   '--python-exit-code', '2', '--python', str(script), '--', *map(str, arguments)]
        log = out / 'logs' / (name + '.log')
        started = time.monotonic()
        error = ''
        try:
            with log.open('x') as stream:
                code = subprocess.run(command, env=env, stdout=stream,
                                      stderr=subprocess.STDOUT, timeout=240).returncode
        except subprocess.TimeoutExpired:
            code, error = 124, 'Owned stage exceeded 240 seconds and was killed/reaped.'
        except OSError as exc:
            code, error = 127, str(exc)
        diagnostics = [line for line in log.read_text(errors='replace').splitlines()
                       if any(token in line.lower() for token in ('traceback', 'error', 'exception'))]
        phase = {'phase': name, 'command': command, 'exit_code': code,
                 'seconds': time.monotonic() - started, 'error': error,
                 'log_sha256': sha(log), 'diagnostic_lines': diagnostics,
                 'environment': {key: env[key] for key in ENV_ROOTS}, 'home_unchanged': True}
        receipt['phases'].append(phase)
        write()
        print(json.dumps(phase), flush=True)
        if code:
            raise RuntimeError('Failed stage retained: ' + name)

    try:
        if args.repository:
            raw = subprocess.check_output(['git', '-C', str(args.repository.resolve()), 'show',
                                           contract['baseline']['commit'] + ':' + contract['baseline']['path']])
            baseline.write_bytes(raw)
        else:
            original_pin = sha(original)
            shutil.copy2(original, baseline)
        if sha(baseline) != contract['baseline']['sha256']:
            raise ValueError('Input differs from the pinned production Blend.')

        run('neutral', HERE / 'author_neutral.py', ['--source', baseline, '--output', out / 'neutral'], 6)
        neutral = out / 'neutral/art/characters.blend'
        neutral_facts = json.loads((out / 'neutral/object_facts.json').read_text())['after']
        for name, pin in contract['neutral_owned_geometry_sha256'].items():
            if neutral_facts[name]['geometry_sha256'] != pin:
                raise ValueError('Neutral geometry differs: ' + name)
        run('measure', HERE / 'measure_spec.py', ['--source', neutral, '--anchor-report',
            out / 'neutral/mouth_anchor.json', '--output', out / 'SPEC.json'], 1)
        run('finish', HERE / 'finish_face.py', ['--spec', out / 'SPEC.json', '--output', out / 'final'], 6)
        final = out / 'final/art/characters.blend'
        final_pin = sha(final)
        run('native_reopen', HERE.parent / 'adult_eyes/verify_native.py', ['--source', final,
            '--contract', HERE / 'contract.json', '--report', out / 'final/native_reopen.json'], 1)
        receipt['native_recorded_values_exact'] = True
        for variant in VARIANTS:
            run(variant, HERE.parent / 'adult_eyes/export_variant.py', ['--source', final,
                '--source-sha256', final_pin, '--output-root', out / 'final/assets/models',
                '--variant', variant], 1)
            relative = 'assets/models/' + variant + '.glb'
            actual = sha(out / 'final' / relative)
            receipt['outputs'][relative] = actual
            write()
            if actual != contract['expected_outputs'][relative]:
                raise ValueError('Export differs from the reviewed asset: ' + relative)
        if sha(final) != final_pin:
            raise ValueError('Export or verification changed the native source.')
        receipt['outputs']['art/characters.blend'] = final_pin
        receipt['native_byte_exact'] = final_pin == contract['expected_outputs']['art/characters.blend']
        receipt['status'] = 'complete'
    except Exception as exc:
        receipt['status'] = 'failed'
        receipt['error'] = str(exc)
        raise
    finally:
        receipt['input_unchanged'] = baseline.is_file() and sha(baseline) == contract['baseline']['sha256']
        if original_pin is not None:
            receipt['original_input_unchanged'] = original.is_file() and sha(original) == original_pin
        receipt['tools_unchanged'] = all(sha(HERE.parent / name) == pin for name, pin in pins.items())
        if not receipt['input_unchanged'] or not receipt['tools_unchanged'] or receipt.get('original_input_unchanged') is False:
            receipt['status'] = 'failed'
        write()
    if receipt['status'] != 'complete':
        raise RuntimeError('Input or tools changed; result retained as failed.')
    print('ADULT_FACE_REPRODUCTION_COMPLETE', out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
