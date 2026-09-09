"""Original bounded Crop adjustment from the accepted face-v23 Blender source.

Fresh author process: blender --background --factory-startup -t 6
--python-exit-code 2 --python sculpt_crop.py -- --source PINNED_BLEND
--output-root NEW_DIRECTORY
"""
import bpy, sys, json, hashlib, argparse, math, subprocess
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--output-root',type=Path,required=True)
parser.add_argument('--source-sha256',help='Exact generated seed byte hash; native seed signature is also required.')
parser.add_argument('--skip-exports',action='store_true',help='Write the native feathered seed only; clearance stage performs final exports.')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
SOURCE=args.source.resolve(); OUT=args.output_root.resolve(); TOOLS=Path(__file__).resolve().parent
PIN='70550516e89517d5396f480720117e59605ae2cbce62a67bc343adc93cefe797'
ACTUAL_SOURCE_SHA=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
assert ACTUAL_SOURCE_SHA==(args.source_sha256 or PIN)
assert OUT!=SOURCE and OUT not in SOURCE.parents
assert not OUT.exists() or not any(OUT.iterdir())
argv=sys.argv[:sys.argv.index('--')]
assert '--background' in argv and '--factory-startup' in argv
assert '-t' in argv and argv[argv.index('-t')+1]=='6'
for name in ['art','assets/models','evidence']:(OUT/name).mkdir(parents=True)
sys.path.insert(0,str(TOOLS))
from source_facts import objects, scalar_rna, serial, digest
OWNED={'Hair_Crop_Crown.004', 'Hair_Crop_Part_fan.004', 'Hair_Crop_Part_fan.002', 'Hair_Crop_Part_fan.003', 'Hair_Crop_Crown', 'Hair_Crop_Crown.005', 'Hair_Crop_Part_fan.001', 'Hair_Crop_Crown.001', 'Hair_Crop_Part_fan', 'Hair_Crop_Crown.003', 'Hair_Crop_Crown.002'}

def materials():
    return {m.name: {'rna':scalar_rna(m),'props':serial(dict(m.items())),
        'nodes': {n.name: {'rna':scalar_rna(n),'inputs':{s.identifier:serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},
        'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier) for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3.-2.*t)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
before=objects();material_before=digest(materials())
contract=json.loads((TOOLS/'native_contract.json').read_text())
assert digest({'objects':before['objects'],'materials':materials()})==contract['native_signature']['seed'],'Generated seed native data differs from frozen visual source'
cap=bpy.data.objects['Hair_Crop_Cap'];inv=cap.matrix_world.inverted()
center=cap.matrix_world@Vector((0,.012,1.623));dg=bpy.context.evaluated_depsgraph_get()
e=cap.evaluated_get(dg);me=e.to_mesh()
cap_tree=BVHTree.FromPolygons([cap.matrix_world@v.co for v in me.vertices],[list(p.vertices)for p in me.polygons]);e.to_mesh_clear()
report={'source_sha256':ACTUAL_SOURCE_SHA,'owned':sorted(OWNED),'scope':'Only eleven Crown and Part_fan meshes are rebuilt with thirteen longitudinal sections, feathered relief and generated SurfaceUV. Improved cap, two sideburns, accepted front sweep and all non-Crop data are exact against the pinned preceding native source.','rebuilt':{}}

def surface(point):
    world=cap.matrix_world@Vector(point);direction=(world-center).normalized()
    hit,normal,_,_=cap_tree.ray_cast(center+direction*.4,-direction,.395)
    if hit is None:hit,normal,_,_=cap_tree.find_nearest(world+direction*.004)
    assert hit is not None and (hit-center).dot(direction)>0
    if normal.dot(direction)<0:normal=-normal
    return inv@hit,normal

def bezier(points,t):
    a,b,c,d=[Vector(p)for p in points];u=1.-t
    return a*u*u*u+b*3.*u*u*t+c*3.*u*t*t+d*t*t*t

def ribbon(name,points,widths,peak):
    obj=bpy.data.objects[name];assert obj.data.shape_keys is None
    assert not any(v.groups for v in obj.data.vertices)
    nr=13;nt=12;verts=[];faces=[]
    samples=[surface(bezier(points,i/(nr-1)))for i in range(nr)]
    for i,(point,normal)in enumerate(samples):
        t=i/(nr-1);u=1.-t
        tangent=(samples[min(i+1,nr-1)][0]-samples[max(0,i-1)][0]).normalized()
        side=tangent.cross(normal).normalized()
        width=widths[0]*u**3+3.*widths[1]*u*u*t+3.*widths[2]*u*t*t+widths[3]*t**3
        envelope=smooth(0.,.18,t)*(1.-smooth(.72,1.,t))
        for j in range(nt):
            angle=2.*math.pi*j/nt
            edge,edge_normal=surface(point+side*width*math.cos(angle))
            # Both lateral edges and the whole underside blend below the cap.
            # Middle relief follows its surface instead of lifting a flat plate.
            rise=-.0018+peak*envelope*max(0.,-math.sin(angle))**1.35
            verts.append(edge+edge_normal*rise)
    for i in range(nr-1):
        for j in range(nt):faces.append((i*nt+j,i*nt+(j+1)%nt,(i+1)*nt+(j+1)%nt,(i+1)*nt+j))
    faces.extend([tuple(range(nt-1,-1,-1)),tuple((nr-1)*nt+j for j in range(nt))])
    # Owned geometry is deliberately replaced. Keep the same object, data
    # datablock, material slots, transforms and smoothing modifier.
    obj.data.clear_geometry();obj.data.from_pydata(verts,[],faces,shade_flat=False)
    for poly in obj.data.polygons:poly.use_smooth=True
    layer=obj.data.uv_layers.get('SurfaceUV')or obj.data.uv_layers.new(name='SurfaceUV')
    for loop in obj.data.loops:
        index=loop.vertex_index;layer.data[loop.index].uv=(index%nt/nt,index//nt/(nr-1))
    obj.data.update()
    report['rebuilt'][name]={'vertices':len(verts),'polygons':len(faces),'peak_authored_mm':peak*1000,'edge_embed_mm':1.8,'widths_mm':[w*1000 for w in widths],'path':[list(p)for p in points]}

# Three whole uninterrupted primary flows replace the paired plate joins.
# Three smaller broad overlaps provide unequal directional shading without
# a second oval crown pad or repeated parallel closed finger outlines.
paths=[
[(.055,.005,1.740),(-.045,.038,1.755),(-.088,.100,1.660),(-.084,.062,1.584)],
[(.036,.033,1.746),(-.026,.055,1.733),(-.054,.092,1.694),(-.062,.104,1.649)],
[(.040,.025,1.741),(-.006,.088,1.736),(.006,.123,1.642),(.018,.090,1.549)],
[(.045,.043,1.736),(.021,.079,1.722),(.036,.113,1.672),(.044,.105,1.621)],
[(.059,.030,1.733),(.090,.087,1.699),(.095,.088,1.650),(.094,.039,1.600)],
[(.064,.038,1.728),(.076,.052,1.718),(.101,.064,1.684),(.108,.047,1.649)]]
for i,points in enumerate(paths):
    name='Hair_Crop_Crown'+(''if i==0 else '.%03d'%i)
    primary=i%2==0
    ribbon(name,points,[.007,.027 if primary else .018,.023 if primary else .015,.003],.008 if primary else .005)
for i in range(5):
    d=i/4.;name='Hair_Crop_Part_fan'+(''if i==0 else '.%03d'%i)
    points=[(.051+.009*d,-.016+.038*d,1.742),(.086+.006*d,-.039+.074*d,1.707),(.108,-.051+.103*d,1.659),(.108-.010*d,-.044+.105*d,1.631-.018*d)]
    main=i in [0,2,4]
    ribbon(name,points,[.006,.024 if main else .018,.018 if main else .013,.003],.006 if main else .0035)
bpy.context.view_layer.update();after=objects();material_after=digest(materials());checks=[]
def check(ok,label):checks.append({'ok':bool(ok),'label':label})
check(set(before['objects'])==set(after['objects']),'Exact source object inventory')
check(material_before==material_after,'Every shared material and shader graph exact')
for name,original in before['objects'].items():
    current=after['objects'][name]
    if name in OWNED:
        check({k:v for k,v in original.items()if k not in ['geometry_sha256','geometry_contract_sha256']}=={k:v for k,v in current.items()if k not in ['geometry_sha256','geometry_contract_sha256']},'Owned object metadata, data identity, transforms, groups, modifiers and materials exact '+name)
    else:check(original==current,'Protected source object exact '+name)

check(digest({'objects':after['objects'],'materials':materials()})==contract['native_signature']['final'],'Portable final equals frozen visual native signature')
report['checks']=checks;report['failures']=[c for c in checks if not c['ok']]
report['materials_sha256']=material_before
(OUT/'evidence/authoring_edit.json').write_text(json.dumps(report,indent=2)+'\n')
assert not report['failures'],report['failures']
bpy.context.preferences.filepaths.save_version=0
blend=OUT/'art/characters.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
blend_sha=hashlib.sha256(blend.read_bytes()).hexdigest()
launch={'argv':sys.argv,'blender_version':bpy.app.version_string,'blender_build_hash':bpy.app.build_hash.decode(),'binary_sha256':hashlib.sha256(Path(bpy.app.binary_path).read_bytes()).hexdigest(),'source_sha256':ACTUAL_SOURCE_SHA,'blend_sha256':blend_sha,'exports':[]}
for stem in ([] if args.skip_exports else ['character','character_broad','character_lod','character_broad_lod']):
    cmd=[bpy.app.binary_path,'--background','--factory-startup','-t','1','--python-exit-code','2','--python',str(TOOLS/'export_variant.py'),'--','--source',str(blend),'--source-sha256',blend_sha,'--output-root',str(OUT/'assets/models'),'--variant',stem]
    item={'variant':stem,'command':cmd,'returncode':None};launch['exports'].append(item)
    (OUT/'evidence/export_launch.json').write_text(json.dumps(launch,indent=2)+'\n')
    with (OUT/'evidence'/('export_'+stem+'.log')).open('w') as logfile:
        proc=subprocess.run(cmd,stdout=logfile,stderr=subprocess.STDOUT)
    item['returncode']=proc.returncode
    (OUT/'evidence/export_launch.json').write_text(json.dumps(launch,indent=2)+'\n')
    assert proc.returncode==0,'Raw failed export retained: '+stem
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==ACTUAL_SOURCE_SHA
print('CROP_AUTHOR_COMPLETE',len(checks),'checks',len(report['failures']),'failures')
