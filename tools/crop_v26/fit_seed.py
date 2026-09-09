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
parser.add_argument('--skip-exports',action='store_true',help='Write the native seed only; final flow stage performs four exports.')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
SOURCE=args.source.resolve(); OUT=args.output_root.resolve(); TOOLS=Path(__file__).resolve().parent
PIN='e8e9d64944d4640659fad856a42cb46858a3a59b8a6e5db84cbd31d2cc6ce3fd'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==PIN
assert OUT!=SOURCE and OUT not in SOURCE.parents
assert not OUT.exists() or not any(OUT.iterdir())
argv=sys.argv[:sys.argv.index('--')]
assert '--background' in argv and '--factory-startup' in argv
assert '-t' in argv and argv[argv.index('-t')+1]=='6'
for name in ['art','assets/models','evidence']:(OUT/name).mkdir(parents=True)
sys.path.insert(0,str(TOOLS))
from source_facts import objects, scalar_rna, serial, digest
OWNED={'Hair_Crop_Crown.004', 'Hair_Crop_Swept_lock', 'Hair_Crop_Sideburn.001', 'Hair_Crop_Swept_lock.003', 'Hair_Crop_Crown.001', 'Hair_Crop_Swept_lock.005', 'Hair_Crop_Sideburn', 'Hair_Crop_Swept_lock.007', 'Hair_Crop_Crown.002', 'Hair_Crop_Crown', 'Hair_Crop_Part_fan.002', 'Hair_Crop_Swept_lock.006', 'Hair_Crop_Cap', 'Hair_Crop_Part_fan.004', 'Hair_Crop_Swept_lock.008', 'Hair_Crop_Part_fan', 'Hair_Crop_Part_fan.003', 'Hair_Crop_Swept_lock.004', 'Hair_Crop_Crown.003', 'Hair_Crop_Swept_lock.001', 'Hair_Crop_Crown.005', 'Hair_Crop_Swept_lock.002', 'Hair_Crop_Part_fan.001'}

def materials():
    return {m.name: {'rna':scalar_rna(m),'props':serial(dict(m.items())),
        'nodes': {n.name: {'rna':scalar_rna(n),'inputs':{s.identifier:serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},
        'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier) for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3.-2.*t)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
before=objects(); material_before=digest(materials())
head=bpy.data.objects['Skin_Head_continuous']
tree=BVHTree.FromPolygons([head.matrix_world@v.co for v in head.data.shape_keys.key_blocks['Basis'].data], [list(p.vertices) for p in head.data.polygons])
cap=bpy.data.objects['Hair_Crop_Cap']; inv=cap.matrix_world.inverted()
report={'source_sha256':PIN,'owned':sorted(OWNED),'changes':{},'scope':'Twenty-three Crop coordinate edits; all original topology, UVs, modifiers, transforms, materials and non-Crop source protected.'}
original_coords={n:[v.co.copy() for v in bpy.data.objects[n].data.vertices] for n in OWNED}

def edge_height(angle):
    # A shallow temple notch rises over the ear, then drops behind it to the
    # actual nape. Unequal left/right progression keeps the swept identity.
    deg=abs((math.degrees(angle)+180.)%360.-180.)
    points=[(0.,1.673),(25.,1.667),(48.,1.645),(72.,1.624),(94.,1.622),(116.,1.590),(150.,1.541),(180.,1.530)]
    for (a,z),(b,w) in zip(points,points[1:]):
        if a<=deg<=b:return z+(w-z)*smooth(a,b,deg)+.002*math.sin(angle)*math.sin(math.radians(deg))
    return points[-1][1]

for v in cap.data.vertices:
    ring=v.index//96; angle=(v.index%96)*2.*math.pi/96.
    if ring<5:continue
    old=v.co.copy(); bottom=original_coords[cap.name][19*96+v.index%96]
    probe=old.copy();probe.z+=(edge_height(angle)-bottom.z)*smooth(5.,19.,ring)
    # Close sides are fitted to the actual accepted head, not an ideal sphere.
    # The cap is inward-wound; its retained negative-offset solidify therefore
    # grows outward. A1.5mm embedded base leaves roughly5mm outer clearance
    # so interpolation around the temple does not cut through the skin.
    world=cap.matrix_world@probe
    hit,normal,poly,distance=tree.find_nearest(world)
    if normal.dot(world-(head.matrix_world@Vector((0,.012,1.62))))<0:normal=-normal
    fitted=hit-normal*.0015
    blend=smooth(7.,19.,ring)*(.45+.55*smooth(.12,.55,(1.-math.cos(angle))*.5))
    v.co=inv@world.lerp(fitted,blend)
cap.data.update();bpy.context.view_layer.update()
eval_cap=cap.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=eval_cap.to_mesh()
cap_tree=BVHTree.FromPolygons([cap.matrix_world@v.co for v in mesh.vertices],[list(p.vertices) for p in mesh.polygons])
eval_cap.to_mesh_clear()
center=cap.matrix_world@Vector((0,.012,1.623))

def surface(point):
    # Shoot from outside so the shell's outer wall supplies the common root.
    world=cap.matrix_world@Vector(point); direction=(world-center).normalized()
    hit,normal,_,_=cap_tree.ray_cast(center+direction*.4,-direction,.395)
    if hit is None:
        hit,normal,_,_=cap_tree.find_nearest(world+direction*.004)
    assert hit is not None and (hit-center).dot(direction)>0,point
    if normal.dot(direction)<0:normal=-normal
    return inv@hit, normal

def ribbon(name,points,widths,depths,lifts=None):
    obj=bpy.data.objects[name]; count=len(obj.data.vertices)//len(points)
    assert count in [10,12] and len(obj.data.vertices)==count*len(points)
    samples=[surface(p) for p in points]
    lifts=lifts or [0.]*len(samples)
    samples=[(p+normal*lifts[i],normal)for i,(p,normal)in enumerate(samples)]
    pts=[p for p,n in samples]
    # Broad low relief clumps are half embedded in the cap, with tapered ends.
    for i,(p,normal) in enumerate(samples):
        tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        side=tangent.cross(normal).normalized();depth=tangent.cross(side).normalized()
        for j in range(count):
            t=2.*math.pi*j/count
            obj.data.vertices[i*count+j].co=p+side*(widths[i]*math.cos(t))+depth*(depths[i]*math.sin(t))
    obj.data.update()

# Six distinct crown streams continue from the part to separate side/back
# destinations. Their spacing/width vary; no repeated narrow comb grooves.
crown_paths=[
[(.055,.005,1.74),(.010,.035,1.76),(-.050,.067,1.72),(-.075,.085,1.68)],
[(-.047,.067,1.72),(-.075,.090,1.68),(-.089,.090,1.625),(-.085,.065,1.589)],
[(.040,.035,1.745),(.000,.082,1.735),(-.020,.116,1.685),(-.010,.124,1.642)],
[(-.020,.106,1.70),(-.005,.121,1.66),(.018,.112,1.599),(.022,.092,1.548)],
[(.060,.037,1.735),(.070,.067,1.714),(.080,.096,1.67),(.075,.106,1.63)],
[(.079,.087,1.69),(.087,.090,1.65),(.091,.076,1.610),(.090,.041,1.603)]]
for i,points in enumerate(crown_paths):
    name='Hair_Crop_Crown'+('' if i==0 else '.%03d'%i)
    if i%2==0:
        ribbon(name,points,[.014,.026,.023,.012],[.004,.009,.007,.003],[.001,.009,.008,.001])
    else:
        ribbon(name,points,[.021,.026,.020,.006],[.004,.008,.006,.002],[.003,.007,.005,-.001])

# The accepted broad asymmetric forehead sweep is retained exactly. It is
# already a visible overlapping mass; the attempted re-projection flattened
# that identity and could send near-edge endpoints to the far cap surface.
# Its existing roots overlap the new connected crown streams.

# The short side follows the same surface rather than leaving layered fins.
for i in range(5):
    name='Hair_Crop_Part_fan'+('' if i==0 else '.%03d'%i)
    d=i/4.
    points=[(.051+.009*d,-.016+.038*d,1.742),(.086+.006*d,-.039+.074*d,1.707),(.108,-.051+.103*d,1.659),(.108-.010*d,-.044+.105*d,1.631-.018*d)]
    if i in [0,2,4]:
        ribbon(name,points,[.012,.023,.019,.006],[.002,.006,.004,.0015],[0.,.003,.001,-.001])
    else:
        ribbon(name,points,[.011,.019,.016,.005],[.002,.004,.003,.001],[0.,0.,-.001,-.002])

# Sideburn ribbons join below the front of the ear arch; their broad root is
# embedded instead of hovering over it. Both have rounded short ends.
for i,side in enumerate([-1.,1.]):
    name='Hair_Crop_Sideburn'+('' if i==0 else '.001')
    points=[(side*.105,-.052,1.654),(side*.111,-.045,1.634),(side*.108,-.035,1.615)]
    ribbon(name,points,[.013,.011,.005],[.002,.003,.0015],[0.,.001,-.001])
for name in sorted(OWNED):
    pairs=list(zip(original_coords[name],[v.co.copy() for v in bpy.data.objects[name].data.vertices]))
    report['changes'][name]={'changed_vertices':sum(a!=b for a,b in pairs),'maximum_local_delta_mm':max((b-a).length*1000. for a,b in pairs),'before':[list(a) for a,b in pairs],'after':[list(b) for a,b in pairs]}
bpy.context.view_layer.update()
after=objects(); material_after=digest(materials())
checks=[]
def check(ok,label):checks.append({'ok':bool(ok),'label':label})
check(set(before['objects'])==set(after['objects']),'Exact object inventory')
check(material_before==material_after,'Every material and shader graph exact')
for name, original in before['objects'].items():
    current=after['objects'][name]
    if name in OWNED:
        check({k:v for k,v in original.items() if k!='geometry_sha256'}=={k:v for k,v in current.items() if k!='geometry_sha256'},'Owned topology, groups, transforms, modifiers and metadata exact: '+name)
        for key,value in before['owned'][name].items():
            if key!='mesh_positions':check(value==after['owned'][name][key],'Owned geometry field exact: '+name+'.'+key)
    else:check(original==current,'Protected source object exact: '+name)

contract=json.loads((TOOLS/'native_contract.json').read_text())
check(digest({'objects':after['objects'],'materials':materials()})==contract['native_signature']['seed'],'Portable seed equals frozen native signature')
report['checks']=checks;report['failures']=[c for c in checks if not c['ok']]
report['materials_sha256']=material_before
(OUT/'evidence/authoring_edit.json').write_text(json.dumps(report,indent=2)+'\n')
assert not report['failures'],report['failures']
bpy.context.preferences.filepaths.save_version=0
blend=OUT/'art/characters.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
blend_sha=hashlib.sha256(blend.read_bytes()).hexdigest()
launch={'argv':sys.argv,'blender_version':bpy.app.version_string,'blender_build_hash':bpy.app.build_hash.decode(),'binary_sha256':hashlib.sha256(Path(bpy.app.binary_path).read_bytes()).hexdigest(),'source_sha256':PIN,'blend_sha256':blend_sha,'exports':[]}
for stem in ([] if args.skip_exports else ['character','character_broad','character_lod','character_broad_lod']):
    cmd=[bpy.app.binary_path,'--background','--factory-startup','-t','1','--python-exit-code','2','--python',str(TOOLS/'export_variant.py'),'--','--source',str(blend),'--source-sha256',blend_sha,'--output-root',str(OUT/'assets/models'),'--variant',stem]
    item={'variant':stem,'command':cmd,'returncode':None};launch['exports'].append(item)
    (OUT/'evidence/export_launch.json').write_text(json.dumps(launch,indent=2)+'\n')
    with (OUT/'evidence'/('export_'+stem+'.log')).open('w') as logfile:
        proc=subprocess.run(cmd,stdout=logfile,stderr=subprocess.STDOUT)
    item['returncode']=proc.returncode
    (OUT/'evidence/export_launch.json').write_text(json.dumps(launch,indent=2)+'\n')
    assert proc.returncode==0,'Raw failed export retained: '+stem
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==PIN
print('CROP_AUTHOR_COMPLETE',len(checks),'checks',len(report['failures']),'failures')
