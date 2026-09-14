"""Author a scalp-derived close crop, preserving every non-Buzz scene object."""
import argparse
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path

import bpy
import numpy as np

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--input',type=Path,required=True)
p.add_argument('--source-sha256',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
assert a.input.resolve()!=a.output.resolve(), 'Candidate cannot replace source'
assert hashlib.sha256(a.input.read_bytes()).hexdigest()==a.source_sha256
sys.path.insert(0,str(Path(__file__).resolve().parent))
from common import bounds, descendants, evaluated, fingerprint, material_fingerprint
from surface import hairline, material, smooth

bpy.ops.wm.open_mainfile(filepath=str(a.input.resolve()))
D=bpy.data.objects
assert D['Character'].get('age_stage','adult')=='adult', 'Initial Buzz qualification is adult-only'
root=D['Hair_Buzz']; head=D['Skin_Head_continuous']
old=list(descendants(root)); old_names={o.name for o in old}
protected={o.name:fingerprint(o) for o in D if o.name not in old_names}
protected_materials={m.name:material_fingerprint(m) for m in bpy.data.materials if m.name!='Hair_Buzz_Surface'}
root_matrix=root.matrix_world.copy()
old_bounds=bounds([point for o in old if o.type=='MESH' for point in evaluated(o)[0]])
keys=head.data.shape_keys.key_blocks
saved={k.name:k.value for k in keys}
for k in keys:k.value=0
bpy.context.view_layer.update()
points,normals,faces=evaluated(head)
assert len(points)==len(head.data.vertices), 'Scalp correspondence requires stable evaluated topology'
head_bounds=bounds(points)
pivot=D['Head'].matrix_world.translation.copy()
span=head_bounds[2][1]-pivot.z
detail_scale=span/.263725042343
centers=[]
for fraction in (.60,.75,.85):
    band=[pt for pt in points if abs(pt.z-(pivot.z+span*fraction))<span*.02]
    assert band
    centers.append((min(pt.y for pt in band)+max(pt.y for pt in band))/2)
center_y=statistics.median(centers)
angle=np.array([math.atan2(pt.x-pivot.x,-(pt.y-center_y)) for pt in points])
z_fraction=np.array([(pt.z-pivot.z)/span for pt in points])
distance=(z_fraction-hairline(angle))*span
# Keep a generously invisible margin below the density fade, so the native
# triangle boundary never becomes the visible haircut edge.
kept_faces=[face for face in faces if all(distance[i]>-.030*detail_scale for i in face)
            and any(distance[i]>-.018*detail_scale for i in face)]
indices=sorted({i for face in kept_faces for i in face})
assert 300<len(indices)<len(points)*.75, 'Unexpected scalp-patch selection'
mapping={old:i for i,old in enumerate(indices)}
patch_faces=[tuple(mapping[i] for i in face) for face in kept_faces]
heights=(.00035+.0018*smooth(distance/(.022*detail_scale))+.0011*smooth((z_fraction-.72)/.20))*detail_scale
world_points=[points[i]+normals[i]*float(heights[i]) for i in indices]
center=pivot.copy();center.y=center_y;center.z=pivot.z+span*.60
assert min(normals[i].dot((points[i]-center).normalized()) for i in indices)>.1, 'Unexpected inward scalp normals'
for o in reversed(old):bpy.data.objects.remove(o,do_unlink=True)
inv=root.matrix_world.inverted()
mesh=bpy.data.meshes.new('Hair_Buzz_ScalpPatch')
mesh.from_pydata([inv@point for point in world_points],[],patch_faces);mesh.update()
cap=bpy.data.objects.new('Hair_Buzz_Cap',mesh);bpy.context.collection.objects.link(cap);cap.parent=root
cap['buzz_source_head_indices']=indices
cap['buzz_detail_scale']=detail_scale
cap['buzz_head_axis_y']=center_y
cap['buzz_fade_backing']='Actual Skin_Head_continuous, independently recolored'
for poly in mesh.polygons:poly.use_smooth=True
uv=mesh.uv_layers.new(name='SurfaceUV')
for poly in mesh.polygons:
    us=[float(angle[indices[mesh.loops[li].vertex_index]]/(2*math.pi)+.5) for li in poly.loop_indices]
    seam=max(us)-min(us)>.5
    for li,u in zip(poly.loop_indices,us):
        index=indices[mesh.loops[li].vertex_index]
        if seam and u<.5:u+=1
        uv.data[li].uv=(u,float((z_fraction[index]-.15)/.89))
    # UV longitude is undefined at the crown pole; use its face's neighboring
    # longitudes, avoiding a texture fan seam without inventing mesh topology.
    regular=[uv.data[li].uv.x for li in poly.loop_indices
             if math.hypot(points[indices[mesh.loops[li].vertex_index]].x-pivot.x,
                           points[indices[mesh.loops[li].vertex_index]].y-center_y)>.003]
    if regular:
        for li in poly.loop_indices:
            index=indices[mesh.loops[li].vertex_index]
            if math.hypot(points[index].x-pivot.x,points[index].y-center_y)<=.003:
                uv.data[li].uv.x=sum(regular)/len(regular)
assert all(0<d.uv.y<1 for d in uv.data), 'V must remain interior when U uses repeat wrapping'
cap.shape_key_add(name='Basis',from_mix=False)
copied=[]
for source_key in keys:
    if source_key.name in ('Basis','Blink','Smile'):continue
    source_key.value=1
    bpy.context.view_layer.update()
    target,_,target_faces=evaluated(head)
    assert target_faces==faces
    delta=[target[i]-points[i] for i in indices]
    amplitude=max(d.length for d in delta)
    if amplitude>1e-7:
        key=cap.shape_key_add(name=source_key.name,from_mix=False)
        key.slider_min=source_key.slider_min;key.slider_max=source_key.slider_max;key.value=0
        for datum,point,change in zip(key.data,world_points,delta):datum.co=inv@(point+change)
        copied.append({'name':source_key.name,'max_world_displacement':amplitude})
    source_key.value=0
for key in keys:key.value=saved[key.name]
bpy.context.view_layer.update()
a.output.parent.mkdir(parents=True,exist_ok=True)
folder=a.output.parent/'textures';folder.mkdir(parents=True,exist_ok=True)
styled=material(bpy.data.materials['Hair'],folder,span)
mesh.materials.append(styled)
bpy.context.view_layer.update()
assert root.matrix_world==root_matrix
assert {o.name:fingerprint(o) for o in D if o!=cap}==protected, 'Non-Buzz object changed'
assert {m.name:material_fingerprint(m) for m in bpy.data.materials if m.name!='Hair_Buzz_Surface'}==protected_materials, 'Non-Buzz material changed'
assert not cap.modifiers and cap.parent==root
assert hashlib.sha256(a.input.read_bytes()).hexdigest()==a.source_sha256, 'Input changed during candidate authoring'
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()))
report={'input':str(a.input.resolve()),'output':str(a.output.resolve()),'source_sha256':a.source_sha256,
        'candidate_sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),
        'scope':'Hair_Buzz descendants only; new material/maps and scalp-coupled morphs',
        'protected_objects':len(protected),'protected_materials':len(protected_materials),
        'vertex_colors_custom_metadata_and_material_nodes_exact':True,'removed':sorted(old_names),
        'created':{'name':cap.name,'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'copied_identity_keys':copied},
        'old_buzz_evaluated_bounds':old_bounds,'new_buzz_bounds':bounds(world_points),'head_bounds':head_bounds,
        'scalp_offset_range':[float(min(heights[i] for i in indices)),float(max(heights[i] for i in indices))],
        'material':styled.name,'runtime_recolor_role':'Hair','requires_recolor_mapping':True,
        'alpha_mode_contract':'Math Round -> glTF MASK, cutoff 0.5','external_pixels_used':False}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print('BUZZ_CLOSE_CROP_CANDIDATE',json.dumps(report),flush=True)
