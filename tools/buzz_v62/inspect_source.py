"""Read-only native Buzz/skull topology, transforms and material inspection."""
import argparse
import json
import sys
from pathlib import Path

import bpy

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--')+1:])
bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'bob_v62'))
from fit import evaluated_mesh, bounds


def descendants(o):
    for c in o.children:
        yield c
        yield from descendants(c)


def facts(o):
    record = {'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,
              'matrix':[list(row) for row in o.matrix_world],
              'modifiers':[{'name':m.name,'type':m.type,
                            **{key:getattr(m,key) for key in ('thickness','offset','levels','render_levels','use_even_offset') if hasattr(m,key)}} for m in o.modifiers]}
    if o.type=='MESH':
        ps, fs = evaluated_mesh(o)
        record.update({'data_vertices':len(o.data.vertices),'data_faces':len(o.data.polygons),
                       'evaluated_vertices':len(ps),'evaluated_faces':len(fs),'evaluated_bounds':bounds(ps),
                       'data_world_bounds':bounds([o.matrix_world@v.co for v in o.data.vertices]),
                       'materials':[m.name if m else None for m in o.data.materials],
                       'shape_keys':[{'name':k.name,'value':k.value,'min':k.slider_min,'max':k.slider_max} for k in o.data.shape_keys.key_blocks] if o.data.shape_keys else [],
                       'vertex_groups':[g.name for g in o.vertex_groups],
                       'uv_layers':[l.name for l in o.data.uv_layers]})
    return record


D = bpy.data.objects
head = D['Skin_Head_continuous']
hp,_ = evaluated_mesh(head)
span = max(pt.z for pt in hp)-D['Head'].matrix_world.translation.z
cross_sections = []
for fraction in (.40,.50,.60,.70,.80,.90,.97):
    z = D['Head'].matrix_world.translation.z+span*fraction
    row = [pt for pt in hp if abs(pt.z-z)<span*.013]
    cross_sections.append({'fraction':fraction,'samples':len(row),'bounds':bounds(row) if row else []})
hair = bpy.data.materials['Hair']
bsdf = hair.node_tree.nodes.get('Principled BSDF')
report = {'source':str(a.source.resolve()), 'head':facts(head),'attachment':facts(D['Head']),
          'buzz_root':facts(D['Hair_Buzz']), 'buzz_objects':[facts(o) for o in descendants(D['Hair_Buzz'])],
          'head_cross_sections':cross_sections,
          'hair_material':{'diffuse_color':list(hair.diffuse_color),
                           'base_color':list(bsdf.inputs['Base Color'].default_value),
                           'roughness':bsdf.inputs['Roughness'].default_value,
                           'specular':bsdf.inputs['Specular IOR Level'].default_value}}
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(report,indent=2)+'\n')
print('BUZZ_SOURCE_FACTS',json.dumps(report),flush=True)
