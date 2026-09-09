"""Second local eye pass: upper-lid roots and closed contact only."""
import bpy,sys,json,math,hashlib,argparse
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent));import source_facts as w
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--source-sha256',required=True);ap.add_argument('--reference',type=Path,required=True);ap.add_argument('--reference-sha256',required=True);ap.add_argument('--output-root',type=Path,required=True);a=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);source=a.source.resolve();ref=a.reference.resolve();out=a.output_root.resolve();assert not out.exists();assert out not in source.parents and out not in ref.parents;assert w.sha(source)==a.source_sha256 and w.sha(ref)==a.reference_sha256
out.mkdir();(out/'art').mkdir();(out/'evidence').mkdir();OWNED={'Skin_Upper_lid_-1','Skin_Upper_lid_1'};w.OWNED=OWNED;anchor=Vector((0,.005,1.458));scale=.91

def us(o,q):return anchor+(o.matrix_world@q-anchor)/scale
def smooth(lo,hi,v):
 t=max(0,min(1,(v-lo)/(hi-lo)));return t*t*(3-2*t)
def quant(v):return Vector(tuple(round(x/(2**-22))*(2**-22) for x in v))
def ld(o,d):return quant(o.matrix_world.to_3x3().inverted()@(d*scale))
def params(q,side):
 dx=q.x-side*.047;arch=math.sqrt(max(0,1-(dx/.030)**2))
 if arch<.1:return 1.
 target=(q.z-(1.611+dx*.065*side+.010*arch))/arch;lo=0.;hi=1.
 for _ in range(24):
  f=(lo+hi)/2
  if .012*f-.0028*(1-f)**1.5<target:lo=f
  else:hi=f
 return (lo+hi)/2
bpy.ops.wm.open_mainfile(filepath=str(ref));uv={}
for name in OWNED:
 o=bpy.data.objects[name];side=-1 if name.endswith('-1') else 1;uv[name]=[params(us(o,q.co),side) for q in o.data.shape_keys.key_blocks['Basis'].data]
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.view_layer.update();before=w.objects()
def materials():
 return {m.name:{'rna':w.scalar_rna(m),'props':w.serial(dict(m.items())),'nodes':{n.name:{'type':n.bl_idname,'rna':w.scalar_rna(n),'inputs':{s.name:w.serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},'links':[[l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name] for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}
mb=materials();head=bpy.data.objects['Skin_Head_continuous'];keys=head.data.shape_keys.key_blocks;hb=keys['Basis'];polys=[list(f.vertices) for f in head.data.polygons];trees={}
for blink in [0,1]:
 co=[us(head,q.co+(keys['Blink'].data[i].co-q.co)*blink) for i,q in enumerate(hb.data)];trees[blink]=BVHTree.FromPolygons(co,polys,all_triangles=False)
def surface(x,z,blink,lower=False):
 vals=[]
 offsets=[(0,0,4),(-.0006,0,1),(.0006,0,1),(0,-.0005,1),(0,.0005,1)]
 if lower:offsets += [(0,-.0010,1),(-.0006,-.0006,1),(.0006,-.0006,1)]
 for dx,dz,weight in offsets:
  hit,n,i,t=trees[blink].ray_cast(Vector((x+dx,-1,z+dz)),Vector((0,1,0)),2.)
  if hit is not None and hit.y<-.084:
   if dx==0 and dz==0:return hit.y
   vals.append((hit.y,weight))
 # At an opening boundary, averaging valid surface and cavity-wall samples
 # invents an unsupported depth. Use the direct actual surface, or the nearest
 # anterior supporting envelope only when the centre ray has no front skin.
 return min(v for v,t in vals) if vals else None
report={'source_sha256':a.source_sha256,'parameter_reference_sha256':a.reference_sha256,'scope':'Exactly two upper lid meshes: Basis changes only depth at outer/root/corner region, with corresponding closed Blink attachment and thin lower contact fit. Head and all ten Eyes pieces exact. Topology/UV/weights/materials/rig/key metadata exact. All non-Blink relative identity vectors exact.','owned_objects':sorted(OWNED),'head_mask':[],'changes':{},'failures':[],'protected_inner_basis_ids':{}}
for name in sorted(OWNED):
 o=bpy.data.objects[name];ks=o.data.shape_keys.key_blocks;old={k.name:[q.co.copy() for q in k.data] for k in ks};basis=old['Basis'];mesh=[q.co.copy() for q in o.data.vertices];normal=[q.normal.copy() for q in o.data.vertices];side=-1 if name.endswith('-1') else 1;ds=[];bs=[];fixed=[];samples=[]
 for i,base in enumerate(basis):
  p=us(o,base);q=us(o,old['Blink'][i]);f=uv[name][i];dx=p.x-side*.047;arch=math.sqrt(max(0,1-(dx/.030)**2));corn=smooth(.023,.0295,abs(dx));root_weight=max(smooth(.42,.88,f),corn);n=normal[i];frontback=max(0,min(1,(n.y+1)/2));d=Vector();bd=Vector()
  for blink,point in [(0,p),(1,q)]:
   sy=surface(point.x,point.z,blink)
   if sy is not None and root_weight>0:
    # Terminal front sheet lies .5mm beneath actual head; the rear sheet is
    # deeper, retaining finite volume instead of collapsing both surfaces.
    target=sy+.0005+.0008*frontback;dy=(target-point.y)*root_weight
    if blink==0:d.y=dy
    else:bd.y=dy
  # Preserve the improved neutral opening exactly away from terminal corners.
  if root_weight==0:fixed.append(i)
  contact=(1-smooth(.07,.27,f))*(1-smooth(.023,.028,abs(dx)))
  if contact>0 and arch>.15:
   # A smooth shallow lower closure edge overlaps the existing lower rim.
   # Read support below the opening; a ray through the closing panel itself
   # can hit the deeper socket wall rather than its supporting lower edge.
   # Root contact is untouched by this disjoint inner-band correction.
   idealz=1.611+dx*.065*side+arch*(-.0083+.0365*f)
   dz=(idealz-q.z)*contact
   support_z=1.611+dx*.065*side-.0125*max(.45,arch)
   sy=surface(q.x,support_z,1,True)
   if sy is not None:
    target=sy-.00025+.0008*frontback;bd.y+=(target-q.y-bd.y)*contact;bd.z=dz
  delta=ld(o,d);blinkdelta=ld(o,bd);ds.append(delta);bs.append(blinkdelta)
  for k in ks:k.data[i].co=old[k.name][i]+delta
  o.data.vertices[i].co=mesh[i]+delta;ks['Blink'].data[i].co=old['Blink'][i]+blinkdelta
  if delta.length>0 or blinkdelta.length>0:samples.append({'index':i,'across':f,'root_weight':root_weight,'contact_weight':contact,'basis_delta':list(delta),'blink_target_delta':list(blinkdelta)})
 o.data.update()
 for i in fixed:
  assert ks['Basis'].data[i].co==basis[i] and o.data.vertices[i].co==mesh[i]
 for i in range(len(basis)):
  assert ks['Basis'].data[i].co.x==basis[i].x and ks['Basis'].data[i].co.z==basis[i].z
  assert tuple(float(o.data.vertices[i].co[j])-float(ks['Basis'].data[i].co[j]) for j in range(3))==tuple(float(mesh[i][j])-float(basis[i][j]) for j in range(3))
 for k in ks:
  if k.name in ['Basis','Blink']:continue
  for i,pnt in enumerate(k.data):
   prior=tuple(float(old[k.name][i][j])-float(basis[i][j]) for j in range(3));now=tuple(float(pnt.co[j])-float(ks['Basis'].data[i].co[j]) for j in range(3))
   if prior!=now:report['failures'].append([name,k.name,i,'relative_identity',prior,now])
 report['protected_inner_basis_ids'][name]=fixed;report['changes'][name]={'basis_ids':[i for i,d in enumerate(ds) if d.length>0],'blink_target_ids':[i for i,d in enumerate(bs) if d.length>0],'max_basis_local':max(d.length for d in ds),'max_blink_local':max(d.length for d in bs),'per_vertex':samples}
bpy.context.view_layer.update();after=w.objects();assert set(before['objects'])==set(after['objects'])
for name,ob in before['objects'].items():
 for k,v in ob.items():
  if name in OWNED and k=='geometry_sha256':continue
  if v!=after['objects'][name][k]:report['failures'].append([name,k,'object_fact'])
assert mb==materials()
(out/'evidence/author_report.json').write_text(json.dumps(report,indent=2)+'\n');assert not report['failures'],report['failures'][:5]
for name,data in [('before',before),('after',after)]:(out/'evidence'/f'{name}.json').write_text(json.dumps({'objects':data['objects'],'materials':mb},indent=2)+'\n')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out/'art/characters.blend'));assert w.sha(source)==a.source_sha256 and w.sha(ref)==a.reference_sha256
print('LID_ROOT_BLEND_AUTHORED',len(OWNED),'owned, 360 other objects exact; no head or globe changes')
