"""Continuous original trouser pattern with accepted-surface skin/Sit transfer."""
import bpy,math,json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

def smooth(a,b,t):
 t=max(0,min(1,(t-a)/(b-a)));return t*t*(3-2*t)
def lerp(a,b,t):return a+(b-a)*t

def surface(o):
 me=o.data;me.calc_loop_triangles()
 points=[v.co.copy() for v in me.vertices];tris=[tuple(t.vertices) for t in me.loop_triangles]
 weights=[{o.vertex_groups[g.group].name:g.weight for g in v.groups} for v in me.vertices]
 keys=me.shape_keys.key_blocks
 deltas=[keys['Sit'].data[i].co-keys['Basis'].data[i].co for i in range(len(points))]
 return dict(points=points,tris=tris,weights=weights,deltas=deltas,bvh=BVHTree.FromPolygons(points,tris,all_triangles=True))

def sample(src,point):
 hit,normal,index,distance=src['bvh'].find_nearest(point)
 assert index is not None
 ids=src['tris'][index];a,b,c=[src['points'][i] for i in ids]
 bary=barycentric_transform(hit,a,b,c,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
 bary=[max(0,min(1,v)) for v in bary];total=sum(bary);bary=[v/total for v in bary]
 weights={};delta=Vector()
 for i,w in zip(ids,bary):
  for name,value in src['weights'][i].items():weights[name]=weights.get(name,0)+value*w
  delta+=src['deltas'][i]*w
 weight_sum=sum(weights.values());weights={k:v/weight_sum for k,v in weights.items() if v>0}
 return weights,delta,distance,index,bary

def bind_from(o,src,rig):
 names=[b.name for b in rig.data.bones]
 for name in names:
  if o.vertex_groups.get(name) is None:o.vertex_groups.new(name=name)
 o.shape_key_add(name='Basis');sit=o.shape_key_add(name='Sit');sit.value=0
 records=[];maximum=0
 for i,v in enumerate(o.data.vertices):
  weights,delta,distance,tri,bary=sample(src,v.co);maximum=max(maximum,distance)
  for name,weight in weights.items():o.vertex_groups[name].add([i],weight,'REPLACE')
  sit.data[i].co=v.co+delta
  records.append(dict(vertex=i,triangle=tri,barycentric=bary,distance=distance,weights=weights,sit_delta=list(delta)))
 if not any(m.type=='ARMATURE' for m in o.modifiers):
  mod=o.modifiers.new('Soft skeletal deformation','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
 return dict(vertices=len(records),max_source_distance_m=maximum,transfer=records)

def uv(o):
 layer=o.data.uv_layers.new(name='SurfaceUV')
 for poly in o.data.polygons:
  for i in poly.loop_indices:
   p=o.data.vertices[o.data.loops[i].vertex_index].co
   layer.data[i].uv=(p.x+0.5,p.z)

def rebuild(pants,output):
 accepted=surface(pants);rig=bpy.data.objects['LifeRig'];ma=list(pants.data.materials)
 verts=[];faces=[];unique={}
 def add(point):
  key=tuple(round(v,7) for v in point)
  if key not in unique:unique[key]=len(verts);verts.append(point)
  return unique[key]
 n=48;rows=[]
 # One waist loop flows continuously into a crotch saddle and two leg loops.
 # The shared crotch vertex is welded, eliminating overlapping fused thigh caps.
 for row in range(13):
  t=row/12;blend=smooth(.20,1,t);indices=[]
  width=lerp(.139,.165,math.sin(t*math.pi/2));depth=lerp(.081,.095,t)
  for j in range(n*2):
   a=2*math.pi*j/(n*2);side=1 if j<n else -1
   b=(-math.pi/2+2*a) if side==1 else (math.pi/2+2*(a-math.pi))
   xx=side*.081+.081*math.sin(b);yy=.012-.084*math.cos(b)
   z=lerp(1.05,.880+.025*(math.sin(b)*side),t)
   x=lerp(width*math.sin(a),xx,blend);y=lerp(.008-depth*math.cos(a),yy,blend)
   indices.append(add((x,y,z)))
  rows.append(indices)
 for upper,lower in zip(rows,rows[1:]):
  for j in range(n*2):faces.append((upper[j],lower[j],lower[(j+1)%(n*2)],upper[(j+1)%(n*2)]))
 faces.append(tuple(rows[0]))
 # Leg radius varies over the full length; there is no authored knee seam/ring.
 for leg in range(2):
  side=1 if leg==0 else -1;previous=rows[-1][leg*n:(leg+1)*n]
  for row in range(1,29):
   t=row/28;z=lerp(.88,.122,t)
   width=lerp(.081,.049,t)+.0018*math.sin(t*math.pi)
   depth=lerp(.084,.048,t)
   center=lerp(.081,.09,t)
   current=[]
   for j in range(n):
    b=(-math.pi/2 if side==1 else math.pi/2)+2*math.pi*j/n
    x=side*center+width*math.sin(b);y=.012-depth*math.cos(b)
    # Front fabric has a broad, subtle plane, not a row of surface grooves.
    front=max(0,math.cos(b));y-=.002*front**6*math.sin(t*math.pi)
    zz=z+.025*math.sin(b)*side*(1-smooth(0,.10,t))
    current.append(add((x,y,zz)))
   for j in range(n):faces.append((previous[j],current[j],current[(j+1)%n],previous[(j+1)%n]))
   previous=current
  faces.append(tuple(reversed(previous)))
 mesh=bpy.data.meshes.new('Bottom_Continuous_v22');mesh.from_pydata(verts,[],faces);mesh.update()
 # Reject actual construction mistakes instead of exporting a broken saddle.
 assert not mesh.validate(verbose=True),'Pattern produced invalid mesh'
 for material in ma:mesh.materials.append(material)
 for poly in mesh.polygons:poly.use_smooth=True
 pants.data=mesh
 # One subdivision improves the physical crotch/waist transition before transfer.
 mod=pants.modifiers.new('Continuous cloth finish','SUBSURF');mod.levels=1;mod.render_levels=1
 bpy.context.view_layer.objects.active=pants
 # The old armature is neutral, but apply only the new surface subdivision.
 bpy.ops.object.modifier_apply(modifier=mod.name)
 uv(pants)
 report={'method':'Continuous welded waist/crotch/legs; nearest accepted triangle barycentric weights and Sit displacement','pants':bind_from(pants,accepted,rig),'trim':{},'accepted_vertices':len(accepted['points'])}
 bpy.context.view_layer.update();new_surface=surface(pants)
 for name in ['Bottom_Pocket','Bottom_Pocket.001']:
  curve=bpy.data.objects[name]
  # Convert the original authored trim in place, preserving its object identity.
  bpy.ops.object.select_all(action='DESELECT');curve.select_set(True);bpy.context.view_layer.objects.active=curve
  bpy.ops.object.convert(target='MESH');trim=bpy.context.object
  for v in trim.data.vertices:
   hit,normal,index,distance=new_surface['bvh'].ray_cast(Vector((v.co.x,-1,v.co.z)),Vector((0,1,0)))
   assert hit is not None,(name,list(v.co))
   v.co.y=hit.y-.0015
  trim.data.update();uv(trim)
  report['trim'][name]=bind_from(trim,new_surface,rig)
 output.write_text(json.dumps(report,indent=2))
 return ['Bottom_Continuous_trousers','Bottom_Pocket','Bottom_Pocket.001']
