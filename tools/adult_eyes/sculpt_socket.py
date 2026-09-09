"""Original adult eye/socket prototype. Positions and affected Blink only, no runtime edits."""
import bpy,sys,json,math,hashlib,argparse
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent));import source_facts as witness
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--source-sha256',required=True);ap.add_argument('--output-root',type=Path,required=True);a=ap.parse_args(sys.argv[sys.argv.index('--')+1:]);source=a.source.resolve();out=a.output_root.resolve();assert not out.exists();assert out not in source.parents;assert witness.sha(source)==a.source_sha256
out.mkdir();(out/'art').mkdir();(out/'evidence').mkdir();bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.view_layer.update()
OWNED={o.name for o in bpy.data.objects if o.name.startswith(('Eyes_','Skin_Upper_lid')) or o.name=='Skin_Head_continuous'};assert len(OWNED)==13
witness.OWNED=OWNED;before=witness.objects()
def materials():
 return {m.name:{'rna':witness.scalar_rna(m),'props':witness.serial(dict(m.items())),'nodes':{n.name:{'type':n.bl_idname,'rna':witness.scalar_rna(n),'inputs':{s.name:witness.serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},'links':[[l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name] for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}
mat_before=materials();anchor=Vector((0,.005,1.458));scale=.91
head=bpy.data.objects['Skin_Head_continuous'];base=head.data.shape_keys.key_blocks['Basis']
def unscaled(o,p):return anchor+(o.matrix_world@p-anchor)/scale
headpoints=[unscaled(head,v.co) for v in base.data];headtree=BVHTree.FromPolygons(headpoints,[list(p.vertices) for p in head.data.polygons],all_triangles=False)
def surface(x,z,default=-.095):
 co,no,idx,dist=headtree.ray_cast(Vector((x,-1,z)),Vector((0,1,0)),2.)
 return co.y if co is not None and co.y<-.084 else default

def smooth(a,b,v):
 t=max(0,min(1,(v-a)/(b-a)));return t*t*(3-2*t)
def quant(v):return Vector(tuple(round(c/(2**-22))*(2**-22) for c in v))
def local_delta(o,d):return quant(o.matrix_world.to_3x3().inverted()@(d*scale))
def globe_front(dx,dz):return -.0825-.017*math.sqrt(max(0,1-(dx/.028)**2-(dz/.014)**2))
report={'input_sha256':a.source_sha256,'owned_objects':sorted(OWNED),'scope':'Thirteen adult eye/head meshes; source topology/UV/weights, materials and every other object exact. Head changes only local orbital vertex positions. Eye globe depth/center and coherent eight-mm Blink retreat; upper-lid neutral and closed surface authored as a coupled volume. Existing non-Blink relative identity/Smile vectors exact except explicitly recorded owned sclera/catchlight depth rounding from the shared float32 Basis translation; X/Z vectors exact.','coordinate_system':'millimetre comments refer to pre-.91 head-scale authored coordinates; anterior is negative y','changes':{},'failures':[],'owned_identity_depth_rounding':[]}
for name in sorted(OWNED):
 o=bpy.data.objects[name];keys=o.data.shape_keys.key_blocks;basis=[p.co.copy() for p in keys['Basis'].data];old={k.name:[p.co.copy() for p in k.data] for k in keys};oldmesh=[p.co.copy() for p in o.data.vertices]
 ds=[];blinkds=[]
 for i,co in enumerate(basis):
  p=unscaled(o,co);x,y,z=p;d=Vector();bd=None
  if name.startswith('Eyes_'):
   # Preserve width/height/identity. Make the globe a shallower ellipsoid,
   # with the iris/catchlight laminated to the same affine depth surface.
   target_y=-.0825+(y+.0775)*(17./26.);d.y=target_y-y
   # Re-author the existing Blink target around this new Basis, rather than
   # preserving a twelve-mm depth jump inherited from the deeper globe.
   bd=Vector((0,target_y+.008-(unscaled(o,old['Blink'][i])).y,0))
  elif name.startswith('Skin_Upper_lid'):
   side=-1 if name.endswith('-1') else 1;dx=x-side*.047;arch=math.sqrt(max(0,1-(dx/.030)**2));corner=smooth(.40,.90,arch)
   if corner>0 and old['Blink'][i]!=co:
    tilt=dx*.065*side;inner=1.611+tilt+.010*arch
    # Recover the existing patch's across-lid coordinate after v23's margin
    # lowering. Finite solidified-edge deviations are retained in the source.
    target=(z-inner)/max(.0001,arch);lo=0.;hi=1.
    for _ in range(24):
     f=(lo+hi)/2;pred=.012*f-.0028*(1-f)**1.5
     if pred<target:lo=f
     else:hi=f
    f=(lo+hi)/2;attach=1-smooth(.78,.98,f)
    dz=.0026*arch*(1-f)**1.5*corner
    new_inner_dz=tilt+.0098*arch
    margin_y=globe_front(dx,new_inner_dz)-.00075
    outer_y=surface(x,1.611+tilt+.0235*arch)+.0004
    target_y=margin_y*(1-f)+outer_y*f-.0003*math.sin(math.pi*f)
    d=Vector((0,(target_y-y)*corner*attach,dz))
    closedp=unscaled(o,old['Blink'][i]);low_y=surface(x,1.611+tilt-.024*arch)
    closed_y=(low_y-.0012)*(1-f)+outer_y*f-.0002*math.sin(math.pi*f)
    bd=Vector((0,(closed_y-closedp.y)*corner*attach,0))
  else:
   side=-1 if x<0 else 1;dx=x-side*.047;arch=math.sqrt(max(0,1-(dx/.032)**2));dz=z-1.611-dx*.065*side
   front=1-smooth(-.088,-.075,y);corner=smooth(.08,.40,arch)
   # Calm the fused lower orbital ridge and a small upper cut-edge ledge.
   lower=.0026*math.exp(-((dz+.011)/.008)**2)*smooth(-.029,-.023,dz)*(1-smooth(-.007,-.004,dz))
   upper=.0009*math.exp(-((dz-.0115)/.0045)**2)*smooth(.005,.008,dz)*(1-smooth(.017,.022,dz))
   d.y=(lower+upper)*arch*front*corner
  ld=local_delta(o,d);ds.append(ld)
  for k in keys:k.data[i].co=old[k.name][i]+ld
  o.data.vertices[i].co=oldmesh[i]+ld
  if bd is not None:
   lbd=local_delta(o,bd);keys['Blink'].data[i].co=old['Blink'][i]+lbd;blinkds.append(lbd)
  else:blinkds.append(ld)
 o.data.update()
 # No floating tolerance: all protected morph displacements and source mesh
 # versus Basis offsets must remain the same scalar subtraction results.
 for k in keys:
  if k.name in ['Basis','Blink']:continue
  for i,v in enumerate(k.data):
   prior=tuple(float(old[k.name][i][j])-float(basis[i][j]) for j in range(3));now=tuple(float(v.co[j])-float(keys['Basis'].data[i].co[j]) for j in range(3))
   if prior!=now:
    item=[name,k.name,i,{'old':prior,'new':now,'old_basis':list(basis[i]),'new_basis':list(keys['Basis'].data[i].co)}]
    if name.startswith(('Eyes_Sclera','Eyes_Catchlight')) and prior[0]==now[0] and prior[2]==now[2]:
     # Record exact depth-only float32 arithmetic from applying one shared
     # Basis translation. No epsilon test or generic channel tolerance.
     assert v.co==old[k.name][i]+ds[i]
     report['owned_identity_depth_rounding'].append(item)
    else:report['failures'].append(item)
 for i,v in enumerate(o.data.vertices):
  if tuple(float(v.co[j])-float(keys['Basis'].data[i].co[j]) for j in range(3))!=tuple(float(oldmesh[i][j])-float(basis[i][j]) for j in range(3)):report['failures'].append([name,i,'mesh_basis_offset'])
 changed=[i for i,d in enumerate(ds) if d.length>0];report['changes'][name]={'basis_ids':changed,'max_basis_local_delta':max(d.length for d in ds),'maximum_basis_point':{'index':max(range(len(ds)),key=lambda i:ds[i].length),'old_unscaled':list(unscaled(o,basis[max(range(len(ds)),key=lambda i:ds[i].length)])),'delta_local':list(ds[max(range(len(ds)),key=lambda i:ds[i].length)])},'blink_target_ids':[i for i,d in enumerate(blinkds) if d.length>0],'max_blink_target_local_delta':max(d.length for d in blinkds)}
bpy.context.view_layer.update();after=witness.objects();assert before['objects'].keys()==after['objects'].keys()
for name,f in before['objects'].items():
 for field,old in f.items():
  if name in OWNED and field=='geometry_sha256':continue
  if old!=after['objects'][name][field]:report['failures'].append([name,field,'object_fact'])
assert mat_before==materials(),'Material data changed'
(out/'evidence/author_report.json').write_text(json.dumps(report,indent=2)+'\n')
assert not report['failures'],str(len(report['failures']))+' exact differences retained in report'
(out/'evidence/before.json').write_text(json.dumps({'objects':before['objects'],'materials':mat_before},indent=2)+'\n');(out/'evidence/after.json').write_text(json.dumps({'objects':after['objects'],'materials':materials()},indent=2)+'\n')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out/'art/characters.blend'))
assert witness.sha(source)==a.source_sha256
print('EYE_PROTOTYPE_AUTHORED',len(OWNED),'owned meshes; all other object facts and protected channels exact; material data exact')
