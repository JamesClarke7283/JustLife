"""Independent read-only Blender witness. Opens frozen copies; never saves/exports."""
import bpy, hashlib, json, math
from pathlib import Path
P=Path(__file__).resolve().parent
OWNED={'Outfit_Casual_Shirt'}
def serial(v):
    if v is None or isinstance(v,(str,int,float,bool)):return v
    if hasattr(v,'to_list'):return v.to_list()
    if hasattr(v,'items'):return {str(k):serial(x) for k,x in v.items()}
    try:return [serial(x) for x in v]
    except TypeError:return {'type':type(v).__name__,'name':str(getattr(v,'name',''))}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def digest(v):return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def scalar_rna(value):
    out={}
    for prop in value.bl_rna.properties:
        key=prop.identifier
        # Reopening a Blend allocates new session IDs/evaluation caches. Those
        # read-only runtime fields are not authored curve/modifier data.
        if key=='rna_type' or prop.type=='COLLECTION' or prop.is_readonly:continue
        if prop.type=='POINTER':
            item=getattr(value,key,None)
            if item is not None:out[key]={'type':type(item).__name__,'name':str(getattr(item,'name',''))}
            else:out[key]=None
        else:
            try:out[key]=serial(getattr(value,key))
            except (AttributeError,TypeError):pass
    return out
def matrix(value):return [list(row) for row in value]
def objects():
    facts={};owned={}
    for o in bpy.data.objects:
        f={'type':o.type,'matrix_local':matrix(o.matrix_local),'matrix_world':matrix(o.matrix_world),'parent':o.parent.name if o.parent else None,'parent_type':o.parent_type,'parent_bone':o.parent_bone,'props':serial(dict(o.items())),'vertex_groups':[g.name for g in o.vertex_groups],'modifiers':[scalar_rna(m) for m in o.modifiers],'constraints':[scalar_rna(c) for c in o.constraints]}
        if o.type=='ARMATURE':
            f['bones']={b.name:{'matrix':matrix(b.matrix_local),'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None,'props':serial(dict(b.items()))} for b in o.data.bones}
            f['pose']={b.name:{'matrix_basis':matrix(b.matrix_basis),'rotation_mode':b.rotation_mode,'constraints':[scalar_rna(c) for c in b.constraints]} for b in o.pose.bones}
        if o.type in ('MESH','CURVE'):f['materials']=[m.name if m else None for m in o.data.materials]
        if o.type=='MESH':
            data=o.data
            geometry={'mesh_positions':[list(v.co) for v in data.vertices],'edges':[list(e.vertices) for e in data.edges],'polygons':[{'vertices':list(p.vertices),'material':p.material_index,'smooth':p.use_smooth} for p in data.polygons],'loops':[{'vertex':l.vertex_index,'edge':l.edge_index} for l in data.loops],'uv':{a.name:[list(v.uv) for v in a.data] for a in data.uv_layers},'weights':[[[g.group,g.weight] for g in v.groups] for v in data.vertices]}
            if data.shape_keys:
                geometry['keys']={k.name:[list(v.co) for v in k.data] for k in data.shape_keys.key_blocks}
                f['key_metadata']={k.name:{'relative':k.relative_key.name,'slider_min':k.slider_min,'slider_max':k.slider_max,'value':k.value,'mute':k.mute,'vertex_group':k.vertex_group,'interpolation':k.interpolation} for k in data.shape_keys.key_blocks}
            f['geometry_sha256']=digest(geometry)
            f['geometry_contract_sha256']=digest({k:v for k,v in geometry.items() if k not in ('mesh_positions','keys')})
            f['mesh_datablock']=data.name
            f['mesh_props']=serial(dict(data.items()))
            if o.name in OWNED:
                owned[o.name]=geometry
        elif o.type=='CURVE':
            f['curve']=digest({'settings':scalar_rna(o.data),'props':serial(dict(o.data.items())),'splines':[{'settings':scalar_rna(s),'bezier':[{'co':list(p.co),'left':list(p.handle_left),'right':list(p.handle_right),'left_type':p.handle_left_type,'right_type':p.handle_right_type,'radius':p.radius,'tilt':p.tilt} for p in s.bezier_points],'points':[{'co':list(p.co),'radius':p.radius,'tilt':p.tilt} for p in s.points]} for s in o.data.splines]})
        facts[o.name]=f
    return {'objects':facts,'owned':owned}
