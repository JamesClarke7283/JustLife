"""Reopen the authored source in a fresh Blender process and verify evaluated bounds."""
from pathlib import Path
import bpy,json,math,hashlib
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"art/recipes/recipe_variants.blend"
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
report={"blender":bpy.app.version_string,"source_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"assets":{},"checks":0,"failures":[]}
def check(value,label):
    report["checks"]+=1
    if not value:report["failures"].append(label)
deps=bpy.context.evaluated_depsgraph_get()
for name in ["HerbPastaServing","HerbPastaPlate","HarvestBakeServing","HarvestBakePlate"]:
    obj=bpy.data.objects.get(name)
    check(obj is not None,name+" authored root exists")
    if obj is None:continue
    points=[];meshes=[];inverse=obj.matrix_world.inverted()
    for part in obj.children_recursive:
        if part.type!="MESH":continue
        meshes.append(part);evaluated=part.evaluated_get(deps);data=evaluated.to_mesh()
        points.extend(inverse@part.matrix_world@v.co for v in data.vertices)
        evaluated.to_mesh_clear()
    low=Vector([min(p[i] for p in points) for i in range(3)])
    high=Vector([max(p[i] for p in points) for i in range(3)])
    size=high-low;serving=name.endswith("Serving")
    check(all(math.isfinite(x) for p in points for x in p),name+" finite evaluated mesh")
    check(abs(low.z)<.00001,name+" Blender underside Z=0")
    check(size.x<=(.50 if serving else .30)+.00001,name+" width within carry contract")
    check(size.y<=(.335 if serving else .30)+.00001,name+" depth within support contract")
    food=[o for o in obj.children if o.name.split('.')[0]=="Food"]
    check(len(food)==1,name+" separate consumable Food parent")
    check(any(m.parent==obj for m in meshes),name+" independent ceramic meshes")
    check(len(meshes)>10,name+" editable individual food components remain")
    report["assets"][name]={"min_blender_z_up":list(low),"size_blender_z_up":list(size),"editable_meshes":len(meshes),"food_pivot":list(food[0].location) if food else None}
output=ROOT/"art/recipes/studio/blender_reopen_report.json"
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(report,indent=2))
print("RECIPE_SOURCE_REOPEN",json.dumps(report))
if report["failures"]:raise RuntimeError("Source contract failed")
