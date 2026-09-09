"""Fresh read-only native witness, preserving authored data and source bytes."""
import argparse,bpy,hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from source_facts import objects,scalar_rna,serial,digest
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.source=a.source.resolve();a.output=a.output.resolve();assert not a.output.exists()
def materials():
    return {m.name: {'rna':scalar_rna(m),'props':serial(dict(m.items())),
        'nodes': {n.name: {'rna':scalar_rna(n),'inputs':{s.identifier:serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},
        'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier) for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}

pin=hashlib.sha256(a.source.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(a.source));bpy.context.view_layer.update()
f=objects();m=materials();scene={'name':bpy.context.scene.name,'objects':sorted(o.name for o in bpy.context.scene.objects),'camera':bpy.context.scene.camera.name if bpy.context.scene.camera else None}
result={'source_sha256':pin,'facts':f,'materials':m,'scene':scene,'native_signature':digest({'objects':f['objects'],'materials':m})}
assert hashlib.sha256(a.source.read_bytes()).hexdigest()==pin
assert scene['name']=='Scene' and len(scene['objects'])==362 and scene['camera']=='Character_Portrait'
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,sort_keys=True)+'\n');print('CHILD_NATIVE_WITNESS_OK',result['native_signature'])
