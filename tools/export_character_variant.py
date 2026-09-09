"""One variant in a fresh Blender process; read-only input and original geometry."""
import bpy,json,hashlib,sys,argparse,os,tempfile
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--source-sha256',required=True);parser.add_argument('--output-root',type=Path,required=True);parser.add_argument('--variant',choices=['character','character_broad','character_lod','character_broad_lod'],required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);blend=args.source.resolve()
assert args.output_root.resolve() not in blend.parents,'Output tree must not contain source'
assert hashlib.sha256(blend.read_bytes()).hexdigest()==args.source_sha256,'Generated source hash mismatch'
assert not (args.output_root.resolve()/(args.variant+'.glb')).exists(),'Refuse existing variant destination'
def descendants(node):
 yield node
 for child in node.children:yield from descendants(child)
for name,width,low in [(args.variant,1.12 if 'broad' in args.variant else 1.0,args.variant.endswith('_lod'))]:
 bpy.ops.wm.open_mainfile(filepath=str(blend));root=bpy.data.objects['Character'];root.scale.x=width
 for o in descendants(root):
  if o.type=='MESH' and o.data.shape_keys:
   for key in o.data.shape_keys.key_blocks:key.value=0
  if low:
   if o.type=='MESH' and o.data.shape_keys is None:
    mod=o.modifiers.new('Live camera reduction','DECIMATE');mod.ratio=.12 if o.name.endswith('_Cap') else .22
    if o.modifiers.find('Soft skeletal deformation')>=0:
     bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_move_up(modifier=mod.name)
   elif o.type=='CURVE':o.data.resolution_u=2;o.data.bevel_resolution=1
 for bone in bpy.data.objects['LifeRig'].pose.bones:bone.rotation_euler=(0,0,0)
 bpy.ops.object.select_all(action='DESELECT')
 for o in descendants(root):o.select_set(True)
 bpy.context.view_layer.objects.active=root;bpy.context.view_layer.update();bpy.context.evaluated_depsgraph_get().update()
 out=args.output_root.resolve();out.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='.export-',dir=out) as folder:
  path=Path(folder)/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_animations=False,export_morph=True,export_skins=True,export_extras=True,export_cameras=False,export_lights=False);os.replace(path,out/path.name)

sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_character_exports import semantic_digest,PINS
assert semantic_digest(args.output_root/(args.variant+'.glb'))==PINS[args.variant+'.glb'],'Decoded variant drift; raw output retained'
print('ONE_VARIANT_COMPLETE',args.variant)
