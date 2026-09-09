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
parser.add_argument('--source-sha256',help='Exact generated feathered seed byte hash; its full native signature is also required.')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
SOURCE=args.source.resolve(); OUT=args.output_root.resolve(); TOOLS=Path(__file__).resolve().parent
PIN='c19747545b00715b655e3e67c2b51714d080a230d21a02114c671c3547d1a32d'
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
OWNED={'Hair_Crop_Cap'}

def materials():
    return {m.name: {'rna':scalar_rna(m),'props':serial(dict(m.items())),
        'nodes': {n.name: {'rna':scalar_rna(n),'inputs':{s.identifier:serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},
        'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier) for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3.-2.*t)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE));bpy.context.view_layer.update()
before=objects(); material_before=digest(materials())
contract=json.loads((TOOLS/'clearance_native_contract.json').read_text())
assert digest({'objects':before['objects'],'materials':materials()})==contract['input_native_signature'],'Clearance seed native data differs from qualified feathered source'
cap=bpy.data.objects['Hair_Crop_Cap'];head=bpy.data.objects['Skin_Head_continuous'];inv=cap.matrix_world.inverted();center=cap.matrix_world@Vector((0,.012,1.623))
original=[v.co.copy() for v in cap.data.vertices];keys=head.data.shape_keys.key_blocks
identity=['Face_Round','Jaw_Strong','Nose_Wide','Eye_Spacing'];head_trees=[]
for smile in [.1,.34]:
    points=[v.co.copy() for v in keys['Basis'].data]
    for name in identity+['Smile']:
        key=keys[name];weight=smile if name=='Smile' else 1.
        for i,v in enumerate(key.data):points[i]+=(v.co-key.relative_key.data[i].co)*weight
    head_trees.append(BVHTree.FromPolygons([head.matrix_world@v for v in points],[list(f.vertices) for f in head.data.polygons]))

def cap_tree(low):
    mod=None
    if low:
        mod=cap.modifiers.new('Temporary clearance LOD probe','DECIMATE');mod.ratio=.12
    bpy.context.view_layer.update();e=cap.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=e.to_mesh()
    tree=BVHTree.FromPolygons([cap.matrix_world@v.co for v in mesh.vertices],[list(f.vertices) for f in mesh.polygons]);e.to_mesh_clear()
    if mod is not None:cap.modifiers.remove(mod)
    bpy.context.view_layer.update();return tree

def sample():
    trees=[cap_tree(False),cap_tree(True)];rows=[]
    for v in cap.data.vertices:
        world=cap.matrix_world@v.co;direction=(world-center).normalized();start=center+direction*.4
        heads=[tree.ray_cast(start,-direction,.395)[0] for tree in head_trees];heads=[h for h in heads if h is not None]
        if not heads:continue
        head_radius=max((h-center).length for h in heads)
        gaps=[]
        for tree in trees:
            hit=tree.ray_cast(start,-direction,.395)[0]
            gaps.append(((hit-center).length-head_radius) if hit is not None else None)
        finite=[g for g in gaps if g is not None]
        if finite:rows.append({'index':v.index,'ring':v.index//96,'angle':(v.index%96)*3.75,'gap':min(finite),'full_gap':gaps[0],'lod_gap':gaps[1]})
    return rows

start_samples=sample();passes=[]
for iteration in range(3):
    samples=start_samples if iteration==0 else sample()
    boundary=[0. for _ in range(96)]
    for row in samples:
        if row['ring']>=18:
            boundary[row['index']%96]=max(boundary[row['index']%96],max(0.,.003-row['gap']))
    if max(boundary)<.0002:break
    # Max-Gaussian spread keeps the local target clearance while avoiding
    # a scalloped edge. Only the final four authored rows move horizontally.
    profile=[max(boundary[(j+d)%96]*math.exp(-.5*(d/1.6)**2) for d in range(-6,7)) for j in range(96)]
    for v in cap.data.vertices:
        row=v.index//96;col=v.index%96
        if row<16 or col<=8 or col>=88:continue
        factor={16:.16,17:.45,18:.82,19:1.08}[row]
        world=cap.matrix_world@v.co;radial=(world-center).normalized();horizontal=Vector((radial.x,radial.y,0.)).normalized()
        amount=profile[col]*factor/max(.5,horizontal.dot(radial))
        if amount<=.00001:continue
        result=inv@(world+horizontal*amount)
        result.z=original[v.index].z
        v.co=result
    cap.data.update();bpy.context.view_layer.update()
    passes.append({'iteration':iteration,'minimum_gap_mm':min(s['gap'] for s in samples)*1000,'maximum_boundary_target_mm':max(boundary)*1000})
end_samples=sample();after=objects();checks=[]
def check(ok,label):checks.append({'ok':bool(ok),'label':label})
check(set(before['objects'])==set(after['objects']),'Exact source object inventory')
check(material_before==digest(materials()),'Exact all shared material/node/shader data')
for name,old in before['objects'].items():
    now=after['objects'][name]
    if name=='Hair_Crop_Cap':
        check({k:v for k,v in old.items() if k!='geometry_sha256'}=={k:v for k,v in now.items() if k!='geometry_sha256'},'Cap topology, UVs, transforms, material and original modifiers exact')
        for key,value in before['owned'][name].items():
            if key!='mesh_positions':check(value==after['owned'][name][key],'Cap nonposition geometry exact '+key)
    else:check(old==now,'Protected source object exact '+name)
changes=[i for i,v in enumerate(cap.data.vertices) if v.co!=original[i]]
check(all(i//96>=16 for i in changes),'Only final four cap rows changed')
check(all(8<i%96<88 for i in changes),'Central front cap columns exact')
check(all(v.co.z==original[i].z for i,v in enumerate(cap.data.vertices)),'Every cap vertex height exact')
maximum=max(((cap.matrix_world@v.co)-(cap.matrix_world@original[i])).length for i,v in enumerate(cap.data.vertices))
check(maximum<.025,'Local correction remains under25mm world-space displacement')
check(digest({'objects':after['objects'],'materials':materials()})==contract['output_native_signature'],'Portable clearance native data equals frozen candidate')
report={'source_sha256':ACTUAL_SOURCE_SHA,'owned':['Hair_Crop_Cap'],'scope':'Static lower-cap horizontal envelope for actual all1 identity with Smile.1/.34; full and production-ratio .12 LOD radial probes. No keys, transforms, material, topology, UV, runtime or other hair changes.','passes':passes,'samples_before':start_samples,'samples_after':end_samples,'changed_vertices':changes,'maximum_world_delta_mm':maximum*1000,'checks':checks,'failures':[c for c in checks if not c['ok']],'materials_sha256':material_before}
(OUT/'evidence/authoring_edit.json').write_text(json.dumps(report,indent=2)+'\n');assert not report['failures'],report['failures']
bpy.context.preferences.filepaths.save_version=0
blend=OUT/'art/characters.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
blend_sha=hashlib.sha256(blend.read_bytes()).hexdigest()
launch={'argv':sys.argv,'blender_version':bpy.app.version_string,'blender_build_hash':bpy.app.build_hash.decode(),'binary_sha256':hashlib.sha256(Path(bpy.app.binary_path).read_bytes()).hexdigest(),'source_sha256':ACTUAL_SOURCE_SHA,'blend_sha256':blend_sha,'exports':[]}
for stem in ['character','character_broad','character_lod','character_broad_lod']:
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
