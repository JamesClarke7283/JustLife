"""Reopen, inspect and never save the authored native source."""
import argparse,json,sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import source_facts as w
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--contract',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);source=a.source.resolve();report=a.report.resolve();contract=a.contract.resolve()
assert not report.exists() and report not in (source,contract)
original=w.sha(source);expected=json.loads(contract.read_text())['native_contract']
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.view_layer.update();actual=w.objects()['objects']
materials={m.name:{'rna':w.scalar_rna(m),'props':w.serial(dict(m.items())),'nodes':{n.name:{'type':n.bl_idname,'rna':w.scalar_rna(n),'inputs':{s.name:w.serial(s.default_value) for s in n.inputs if hasattr(s,'default_value')}} for n in m.node_tree.nodes} if m.node_tree else {},'links':[[l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name] for l in m.node_tree.links] if m.node_tree else []} for m in bpy.data.materials}
differences=[]
if set(actual)!=set(expected['object_sha256']):differences.append('object inventory')
for name,pin in expected['object_sha256'].items():
 if w.digest(actual.get(name))!=pin:differences.append(name)
material_exact=w.digest(materials)==expected['material_sha256']
if not material_exact:differences.append('material values')
usable=bpy.context.scene.name=='Scene' and 'Character' in bpy.context.scene.objects and 'LifeRig' in bpy.context.scene.objects
result={'source_sha256':original,'objects':len(actual),'scene':bpy.context.scene.name,'usable_scene':usable,'differences':differences,'material_values_exact':material_exact,'read_only_input_exact':w.sha(source)==original}
report.write_text(json.dumps(result,indent=2)+'\n');assert not differences and usable and result['read_only_input_exact'],differences
print('ADULT_EYE_NATIVE_EXACT',len(actual))
