"""Read the actual family skull, eye and existing Bob geometry for adaptation."""
import argparse
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source-root', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--')+1:])


def descendants(o):
    for child in o.children:
        yield child
        yield from descendants(child)


def points(o, evaluated=False):
    if o.type != 'MESH':
        return []
    if not evaluated:
        return [o.matrix_world @ v.co for v in o.data.vertices]
    active = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = active.to_mesh()
    result = [active.matrix_world @ v.co for v in mesh.vertices]
    active.to_mesh_clear()
    return result


def bounds(ps):
    return [[min(p[i] for p in ps), max(p[i] for p in ps)] for i in range(3)] if ps else []


reports = {}
for family in ('adult', 'teen', 'child', 'elder', 'baby'):
    path = a.source_root / ('characters_identity.blend' if family == 'adult' else 'characters_'+family+'_identity.blend')
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    D = bpy.data.objects
    head, root, bob = D['Skin_Head_continuous'], D['Head'], D['Hair_Bob']
    hp = points(head, True)
    hb = bounds(hp)
    pivot = root.matrix_world.translation
    eye_objects = [o for o in D if o.name.startswith('Eyes_Sclera')]
    ep = [p for o in eye_objects for p in points(o, True)]
    hair = list(descendants(bob))
    bp = [p for o in hair for p in points(o, True)]
    rows = []
    span = hb[2][1] - pivot.z
    for f in (.12, .25, .40, .55, .70, .82, .91, .97):
        z = pivot.z+span*f
        row = [p for p in hp if abs(p.z-z) < span*.012]
        rows.append({'fraction':f, 'z':z, 'bounds':bounds(row)})
    reports[family] = {'path':str(path.resolve()), 'head_pivot':list(pivot),
                       'head_matrix':[list(r) for r in root.matrix_world],
                       'bob_matrix':[list(r) for r in bob.matrix_world],
                       'head_data_bounds':bounds(points(head)), 'head_evaluated_bounds':hb,
                       'eye_names':[o.name for o in eye_objects], 'eye_bounds':bounds(ep),
                       'bob_bounds':bounds(bp), 'head_rows':rows,
                       'bob_descendants':[{'name':o.name,'type':o.type,'verts':len(o.data.vertices) if o.type=='MESH' else 0,
                                           'parent':o.parent.name,'modifiers':[(m.name,m.type) for m in o.modifiers],
                                           'materials':[m.name if m else '' for m in o.data.materials] if o.type=='MESH' else [],
                                           'groups':[g.name for g in o.vertex_groups]} for o in hair]}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(reports, indent=2)+'\n')
print('FAMILY_HEAD_FACTS', json.dumps({name:{k:v for k,v in data.items() if k not in ('bob_descendants','head_rows','head_matrix','bob_matrix')} for name,data in reports.items()}))
