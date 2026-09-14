"""Read-only cap/scalp verification across neutral and silhouette morphs."""
import argparse
from collections import Counter
import json
import sys
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

p = argparse.ArgumentParser(description=__doc__)
inputs = p.add_mutually_exclusive_group(required=True)
inputs.add_argument('--root', type=Path)
inputs.add_argument('--source', type=Path, help='Verify one later composed native source')
p.add_argument('--families', default='adult,teen,child,elder,baby')
p.add_argument('--report', type=Path, required=True)
p.add_argument('--diagnostic-only', action='store_true', help='Write failing measurements without a nonzero exit')
a = p.parse_args(sys.argv[sys.argv.index('--')+1:])
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fit import assert_runtime_contract, evaluated_mesh, runtime_expansion
assert_runtime_contract()

reports = {}
sources = [(family,a.root/family/'bob_surface.blend') for family in a.families.split(',')] if a.root else [('candidate',a.source)]
for family, source in sources:
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()))
    if family == 'candidate':
        family = str(bpy.data.objects['Character'].get('age_stage','adult'))
    head = bpy.data.objects['Skin_Head_continuous']
    cap = bpy.data.objects['Hair_Bob_Cap']
    root = bpy.data.objects['Hair_Bob']
    root_scale = root.scale.copy()
    keys = head.data.shape_keys.key_blocks
    original_values = {k.name:k.value for k in keys}
    cases = {'neutral':{}, 'round':{'Face_Round':1.0},
             'strong_jaw':{'Jaw_Strong':1.0}, 'round_and_jaw':{'Face_Round':1.0,'Jaw_Strong':1.0}}
    records = {}
    for name, settings in cases.items():
        for k in keys:
            k.value = settings.get(k.name,0.0)
        # Reproduce scripts/actor.gd set_face_feature, using the saved rest
        # scale and not accumulating scale between independent cases.
        expansion = runtime_expansion(settings)
        root.scale = root_scale
        root.scale.x *= expansion
        bpy.context.view_layer.update()
        points, faces = evaluated_mesh(cap)
        edge_uses = Counter(tuple(sorted((face[i],face[(i+1)%len(face)])))
                            for face in faces for i in range(len(face)))
        manifold = all(count == 2 for count in edge_uses.values())
        assert manifold, 'Evaluated Bob cap has an open/nonmanifold edge'
        scalp_points, scalp_faces = evaluated_mesh(head)
        scalp = BVHTree.FromPolygons(scalp_points,scalp_faces)
        values = []
        for pt in points:
            hit, normal, _, distance = scalp.find_nearest(pt)
            values.append((pt-hit).dot(normal))
        penetrations = [i for i,value in enumerate(values) if value < -.0001]
        records[name] = {'runtime_bob_x_expansion':expansion, 'closed_two_manifold':manifold,
                         'minimum_signed_clearance':min(values), 'penetrating_vertices':len(penetrations),
                         'first_positions':[list(points[i]) for i in penetrations[:8]]}
    for k in keys:
        k.value = original_values[k.name]
    root.scale = root_scale
    reports[family] = records
    print('BOB_FIT_MORPHS',family,json.dumps(records),flush=True)
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(reports,indent=2)+'\n')
print('BOB_FIT_MORPHS_FINISHED',str(a.report.resolve()),flush=True)
assert a.diagnostic_only or not any(case['penetrating_vertices'] for family in reports.values() for case in family.values()), \
    'Bob shell intersects a runtime-expanded silhouette case; see saved report'
