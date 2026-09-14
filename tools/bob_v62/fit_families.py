"""Sequential candidate-only five-family Bob authoring, detail and clearance QA."""
import argparse
import json
import runpy
import sys
from pathlib import Path

import bpy

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-root', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--families', default='adult,teen,child,elder,baby')
a = p.parse_args(sys.argv[sys.argv.index('--')+1:])
here = Path(__file__).resolve().parent
sys.path.insert(0, str(here))
from fit import bounds, evaluated_mesh
from mathutils.bvhtree import BVHTree


def run(script, args):
    sys.argv = ['blender', '--']+args
    runpy.run_path(str(here/script), run_name='__main__')


def clearance():
    D = bpy.data.objects
    points, faces = evaluated_mesh(D['Skin_Head_continuous'])
    skull = BVHTree.FromPolygons(points, faces)
    cap = D['Hair_Bob_Cap']
    scale = cap['bob_fit_linear_scale']
    size = (scale[0]*scale[1]*scale[2])**(1/3)
    outer = [cap.matrix_world @ v.co for v in cap.data.vertices]
    inner, _ = evaluated_mesh(cap)
    measures = {}
    for label, vertices in [('outer',outer), ('evaluated_shell',inner)]:
        nearest = [skull.find_nearest(p) for p in vertices]
        signed = [(p-hit).dot(normal) for p,(hit,normal,_,_) in zip(vertices,nearest)]
        penetrated = [list(vertices[i]) for i,value in enumerate(signed) if value < -.0003*size]
        measures[label] = {'vertices':len(vertices), 'min_signed_clearance':min(signed),
                           'penetrating_count':len(penetrated), 'first_penetrations':penetrated[:8]}
    hem = outer[-224:]
    edges = [(hem[(i+1)%224]-hem[i]).length for i in range(224)]
    measures['hem'] = {'closed_ring_vertices':224, 'max_adjacent_edge':max(edges),
                        'bounds':bounds(hem), 'world_thickness':cap.modifiers[0].thickness*abs(cap.matrix_world.to_scale().x)}
    measures['bob_bounds'] = bounds([p for o in D['Hair_Bob'].children for p in evaluated_mesh(o)[0]])
    measures['head_bounds'] = bounds(points)
    measures['head_shape_keys'] = [k.name for k in D['Skin_Head_continuous'].data.shape_keys.key_blocks]
    return measures


reports = {}
for family in a.families.split(','):
    source = a.source_root/('characters_identity.blend' if family=='adult' else 'characters_'+family+'_identity.blend')
    folder = a.output/family
    base = folder/'bob_fit.blend'
    final = folder/'bob_surface.blend'
    run('author.py', ['--input',str(source),'--output',str(base),'--report',str(folder/'author_report.json'),'--fit-family'])
    run('surface.py', ['--input',str(base),'--output',str(final),'--report',str(folder/'surface_report.json')])
    reports[family] = clearance()
    (folder/'clearance.json').write_text(json.dumps(reports[family],indent=2)+'\n')
    print('BOB_FAMILY_CLEARANCE', family, json.dumps(reports[family]), flush=True)
a.output.mkdir(parents=True, exist_ok=True)
(a.output/'clearance_summary.json').write_text(json.dumps(reports,indent=2)+'\n')
print('BOB_FAMILIES_FINISHED', str(a.output.resolve()), flush=True)
