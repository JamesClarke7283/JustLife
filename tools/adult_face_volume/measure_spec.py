"""Read the new native seam; emit the reviewed finish specification without saving.

The Smile guide uses float32 native world coordinates followed by float64 fsum
ring means, exactly as the reviewed V4 measurement. Anchor transport retains the
separate affine measurement emitted by author_neutral and verified by finish_face.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'adult_eyes'))
import source_facts as witness


def authored(point):
    pivot = [0, .005, 1.458]
    return [pivot[j] + (point[j] - pivot[j]) / .91 for j in range(3)]


def finish_parameters(centers, center_index, half_width):
    """Keep the mean of the two endpoint ratios, not a ratio of their means."""
    center = centers[center_index]
    ends = [authored(centers[0]), authored(centers[-1])]
    rises = [(point[2] - center[2]) / .91 for point in (centers[0], centers[-1])]
    coefficient = sum(rise / (point[0] / half_width) ** 2
                      for rise, point in zip(rises, ends)) / 2
    return {
        'mouth_half_width': half_width,
        'mouth_center_z': authored(center)[2],
        'neutral_corner_rise': coefficient,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--anchor-report', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    source = args.source.resolve()
    assert not args.output.exists()
    pin = witness.sha(source)
    contract = json.loads((HERE / 'contract.json').read_text())
    anchor = json.loads(args.anchor_report.read_text())
    ids = contract['native_seam_ring_ids']
    assert anchor['native_basis_ring_ids'] == ids == list(range(384, 392))
    assert anchor['property_changed'] is False
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.context.view_layer.update()
    seam = bpy.data.objects['Lips_Smile_seam']
    points = [seam.matrix_world @ v.co for v in seam.data.shape_keys.key_blocks['Basis'].data]
    assert len(points) % 8 == 0
    rings = [list(range(i, i + 8)) for i in range(0, len(points), 8)]
    edges = {tuple(sorted(edge.vertices)) for edge in seam.data.edges}
    assert all(tuple(sorted((ids[i], ids[(i + 1) % 8]))) in edges for i in range(8))
    centers = [[math.fsum(float(v[j]) for v in points[i:i + 8]) / 8
                for j in range(3)] for i in range(0, len(points), 8)]
    center_index = min(range(len(rings)), key=lambda i: abs(centers[i][0]))
    assert rings[center_index] == ids
    measured = finish_parameters(centers, center_index, .033)
    # Fixed reviewed art parameters are verified, never silently fitted afresh.
    assert measured == contract['smile_parameters'], (measured, contract['smile_parameters'])
    assert anchor['proposed_property_round6'] == contract['new_mouth_anchor']
    assert list(bpy.data.objects['Character']['mouth_anchor']) == anchor['old_property']
    to_godot = lambda point: [point[0], point[2], -point[1]]
    spec = {
        'source': str(source),
        'source_sha256': pin,
        'native_seam_ring_ids': ids,
        'old_seam_center_head_godot': to_godot(anchor['old_head_local_blender']),
        'new_seam_center_head_godot': to_godot(anchor['new_head_local_blender']),
        'old_mouth_anchor': anchor['old_property'],
        'new_mouth_anchor': anchor['proposed_property_round6'],
        'smile_parameters': contract['smile_parameters'],
        'native_measurement_sha256': witness.sha(args.anchor_report),
        'measured_smile_parameters': measured,
        'seam_scope': 'Endpoint-matched quadratic guide within the shared 10 mm mouth-band plateau; not exact intermediate mixed quadratic/smootherstep ring geometry.',
    }
    assert witness.sha(source) == pin
    args.output.write_text(json.dumps(spec, indent=2) + '\n')
    print('ADULT_FACE_SPEC', json.dumps(measured))


if __name__ == '__main__':
    main()
