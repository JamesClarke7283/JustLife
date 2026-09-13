"""Author the eye's iris proportion, one family blend.

The iris family is authored so large that it fills almost the whole visible
aperture. Measured on the production source: the iris is 0.031 wide against a
0.051 sclera, and the lid opening is about 0.026, so the iris covers around 86%
of the opening where a human eye reads as roughly 45-55%. That oversize disc is
what makes the eye look wide and unblinking, and it is the dominant reason the
character reads as "googly" in the creator's Face tab.

`tools/probe_eye_coverage.py` shows the lid itself is correct — every height band
of the sclera sits behind the surrounding skin by 3-12 mm — so the fix is the
iris proportion, not the lid or the socket.

Each disc is scaled radially toward its own centre, which keeps the limbal ring,
iris and pupil concentric and leaves the layering depth untouched. The catchlight
is deliberately NOT scaled: it keeps its authored size, so the highlight stays
readable on the smaller iris.

Ownership is declared and asserted: exactly the six iris-family discs change.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

IRIS_SCALE = 0.70
IRIS_OBJECTS = ('Eyes_Iris_edge', 'Eyes_Iris', 'Eyes_Pupil')


def digest_object(o):
    h = hashlib.sha256()

    def feed(s):
        h.update(str(s).encode())
        h.update(b'\x00')

    feed(o.name)
    feed(o.parent.name if o.parent else '')
    for attr in ('location', 'rotation_euler', 'scale'):
        feed(tuple(round(c, 7) for c in getattr(o, attr)))
    feed(o.hide_render); feed(o.hide_viewport)
    if o.type == 'MESH':
        me = o.data
        feed(me.name)
        feed([s.material.name if s.material else '' for s in o.material_slots])
        feed(tuple(round(c, 7) for v in me.vertices for c in v.co))
        feed(tuple(tuple(e.vertices) for e in me.edges))
        feed(tuple((tuple(p.vertices), p.material_index, p.use_smooth) for p in me.polygons))
        for layer in me.uv_layers:
            feed(('uv', layer.name, tuple(round(c, 6) for d in layer.data for c in d.uv)))
        feed(tuple(g.name for g in o.vertex_groups))
        if me.shape_keys:
            feed(tuple(k.name for k in me.shape_keys.key_blocks))
            feed(tuple(round(k.value, 7) for k in me.shape_keys.key_blocks))
    for m in o.modifiers:
        feed((m.name, m.type))
        if m.type == 'ARMATURE':
            feed('armature:' + (m.object.name if m.object else ''))
    return h.hexdigest()


def measure(o):
    """Disc centre and radius in the eye's own plane (X/Z, since it faces -Y)."""
    mw = o.matrix_world
    points = [mw @ v.co for v in o.data.vertices]
    centre = sum(points, Vector()) / len(points)
    radii = [(Vector((p.x - centre.x, 0.0, p.z - centre.z))).length for p in points]
    return centre, max(radii)


def rescale_iris(o, factor):
    """Shrink one eye disc radially about its own centre, keeping it concentric."""
    me = o.data
    mw = o.matrix_world
    inverse = mw.inverted()
    before_centre, before_radius = measure(o)
    centre = sum((mw @ v.co for v in me.vertices), Vector()) / len(me.vertices)
    for vertex in me.vertices:
        point = mw @ vertex.co
        vertex.co = inverse @ (centre + (point - centre) * factor)
    me.update()
    after_centre, after_radius = measure(o)
    return {'name': o.name, 'factor': factor, 'verts': len(me.vertices),
            'radius_before': round(before_radius, 6), 'radius_after': round(after_radius, 6),
            'centre_shift': round((after_centre - before_centre).length, 9)}


bpy.ops.wm.open_mainfile(filepath=str(args.input))
D = bpy.data
before = {o.name: digest_object(o) for o in D.objects}
report = {'input': str(args.input), 'iris_scale': IRIS_SCALE}

owned = []
entries = []
for name in IRIS_OBJECTS:
    for suffix in ('', '.001'):
        key = name + suffix
        o = D.objects.get(key)
        assert o is not None, f'{key} missing'
        assert o.type == 'MESH', f'{key} is not a mesh'
        entries.append(rescale_iris(o, IRIS_SCALE))
        owned.append(key)
report['iris'] = entries

# Every disc must stay concentric on its own centre and actually shrink.
for entry in entries:
    # The centre is preserved by construction; the residual is float32 mesh
    # storage rounding on the re-read coordinates (the eyes sit ~1.6 m up, so
    # one ulp is around 1e-7).
    assert entry['centre_shift'] <= 1e-5, f"{entry['name']}: disc moved off centre {entry['centre_shift']}"
    assert entry['radius_after'] < entry['radius_before'], f"{entry['name']}: disc did not shrink"
    assert abs(entry['radius_after'] / entry['radius_before'] - IRIS_SCALE) < 1e-3, \
        f"{entry['name']}: shrink factor wrong"

after = {o.name: digest_object(o) for o in D.objects}
assert set(after) == set(before), 'object set changed'
changed = sorted(n for n in before if before[n] != after[n])
assert changed == sorted(owned), f'unexpected changed objects: {set(changed) ^ set(owned)}'
report['changed_objects'] = len(changed)
report['unchanged_objects'] = len(D.objects) - len(changed)
assert report['changed_objects'] == 6, 'expected six iris-family discs to change'

args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(args.output), copy=False)
report['output'] = str(args.output)
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('IRIS_AUTHOR_COMPLETE ' + json.dumps({'changed': report['changed_objects'],
                                            'unchanged': report['unchanged_objects']}))
