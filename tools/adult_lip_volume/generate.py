"""Reproduce the reviewed fuller-height adult lips in a new isolated directory."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from adult_face_volume.generate import ENV_ROOTS, VARIANTS, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--repository', type=Path, help='Repository containing the pinned V4 commit')
    source.add_argument('--input-blend', type=Path, help='Byte-exact accepted V4 Blend')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--export', action='store_true', help='Also reproduce all four adult GLBs')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists() or HERE.parent == out or HERE.parent in out.parents:
        parser.error('Output must be new and outside the shared tools directory; failed attempts are retained.')
    contract = json.loads((HERE / 'contract.json').read_text())
    files = sorted(path for path in HERE.iterdir() if path.is_file())
    for name, expected in contract['shared_tools'].items():
        path = HERE.parent / name
        if not path.is_file() or sha(path) != expected:
            parser.error('Shared helper differs from its reviewed pin: ' + name)
        files.append(path)
    pins = {str(path.relative_to(HERE.parent)): sha(path) for path in files}
    if args.export and any('assets/models/' + name + '.glb' not in contract['expected_outputs']
                           for name in VARIANTS):
        parser.error('Four reviewed export pins are required before export reproduction.')
    out.mkdir(parents=True)
    (out / 'inputs').mkdir()
    (out / 'logs').mkdir()
    baseline = out / 'inputs/characters.blend'
    original = args.input_blend.resolve() if args.input_blend else None
    original_pin = None
    receipt = {'status': 'started', 'baseline': contract['baseline'], 'tools': pins,
               'phases': [], 'outputs': {}, 'exports_requested': args.export}

    def write():
        (out / 'RECEIPT.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, script, arguments, threads):
        env = os.environ.copy()
        for key, folder in ENV_ROOTS.items():
            path = out / 'environment' / name / folder
            path.mkdir(parents=True)
            env[key] = str(path)
        env['PYTHONDONTWRITEBYTECODE'] = '1'
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
                       if any(token in line.lower() for token in ('traceback', 'error', 'exception', 'warning'))]
        phase = {'phase': name, 'command': command, 'exit_code': code,
                 'seconds': time.monotonic() - started, 'error': error,
                 'log_sha256': sha(log), 'diagnostic_lines': diagnostics,
                 'environment': {key: env[key] for key in ENV_ROOTS}, 'home_unchanged': True}
        receipt['phases'].append(phase)
        write()
        print(json.dumps(phase), flush=True)
        if code:
            raise RuntimeError('Failed stage retained: ' + name)

    def require(path, expected):
        actual = sha(path)
        receipt['outputs'][str(path.relative_to(out))] = actual
        write()
        if actual != expected:
            raise ValueError('Output differs from the reviewed bytes: ' + str(path.relative_to(out)))

    write()
    try:
        if args.repository:
            baseline.write_bytes(subprocess.check_output([
                'git', '-C', str(args.repository.resolve()), 'show',
                contract['baseline']['commit'] + ':' + contract['baseline']['path']]))
        else:
            original_pin = sha(original)
            shutil.copy2(original, baseline)
        if sha(baseline) != contract['baseline']['sha256']:
            raise ValueError('Input differs from the pinned accepted V4 Blend.')
        run('author', HERE / 'author.py', ['--source', baseline, '--output', out / 'candidate'], 6)
        final = out / 'candidate/art/characters.blend'
        final_pin = sha(final)
        receipt['reviewed_native_container_sha256'] = contract['reviewed_native_container_sha256']
        receipt['native_byte_exact'] = final_pin == contract['reviewed_native_container_sha256']
        require(final, final_pin)
        for name, expected in contract['expected_reports'].items():
            require(out / 'candidate' / name, expected)
        require(final, final_pin)
        run('native_reopen', HERE.parent / 'adult_eyes/verify_native.py', ['--source', final,
            '--contract', HERE / 'contract.json', '--report', out / 'native_reopen.json'], 1)
        require(final, final_pin)
        native = json.loads((out / 'native_reopen.json').read_text())
        if (native['source_sha256'] != final_pin
            or native['objects'] != len(contract['native_contract']['object_sha256'])
            or native['differences'] or not native['usable_scene']
            or not native['material_values_exact'] or not native['read_only_input_exact']):
            raise ValueError('Fresh native report does not confirm the exact candidate contract.')
        receipt['native_report_sha256'] = sha(out / 'native_reopen.json')
        receipt['native_recorded_values_exact'] = True
        if args.export:
            for variant in VARIANTS:
                relative = 'assets/models/' + variant + '.glb'
                require(final, final_pin)
                run(variant, HERE.parent / 'adult_eyes/export_variant.py', ['--source', final,
                    '--source-sha256', final_pin, '--output-root', out / 'candidate/assets/models',
                    '--variant', variant], 1)
                require(final, final_pin)
                require(out / 'candidate' / relative, contract['expected_outputs'][relative])
        require(final, final_pin)
        receipt['status'] = 'complete'
    except Exception as exc:
        receipt['status'] = 'failed'
        receipt['error'] = str(exc)
        raise
    finally:
        receipt['input_unchanged'] = baseline.is_file() and sha(baseline) == contract['baseline']['sha256']
        receipt['tools_unchanged'] = all((HERE.parent / name).is_file()
            and sha(HERE.parent / name) == pin for name, pin in pins.items())
        if original_pin is not None:
            receipt['original_input_unchanged'] = original.is_file() and sha(original) == original_pin
        if not receipt['input_unchanged'] or not receipt['tools_unchanged'] or receipt.get('original_input_unchanged') is False:
            receipt['status'] = 'failed'
        write()
    if receipt['status'] != 'complete':
        raise RuntimeError('Input or tools changed; result retained as failed.')
    print('ADULT_LIP_REPRODUCTION_COMPLETE', out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
