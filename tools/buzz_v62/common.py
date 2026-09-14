"""Scene preservation and evaluated-mesh helpers for the Buzz candidate."""
import hashlib

import bpy


def stable(value):
    """Stable native/custom-property values, including nested mouth metadata."""
    if isinstance(value,bpy.types.ID):return (value.bl_rna.identifier,value.name_full)
    if hasattr(value,'to_dict'):return stable(value.to_dict())
    if isinstance(value,dict):return tuple((k,stable(v)) for k,v in sorted(value.items()))
    if hasattr(value,'to_list'):return stable(value.to_list())
    if isinstance(value,(list,tuple)):return tuple(stable(v) for v in value)
    return value


def custom(owner):
    return tuple((k,stable(owner[k])) for k in sorted(owner.keys()))


def material_fingerprint(mat):
    """Protect non-Buzz shader values, links and packed original image bytes."""
    h=hashlib.sha256()
    def feed(value):h.update(repr(value).encode());h.update(b'\0')
    feed((mat.name,custom(mat),mat.use_nodes,tuple(mat.diffuse_color),mat.roughness,
          mat.metallic,mat.use_backface_culling))
    if mat.use_nodes:
        for node in sorted(mat.node_tree.nodes,key=lambda n:n.name):
            feed((node.name,node.bl_idname,custom(node)))
            for prop in node.bl_rna.properties:
                if prop.identifier=='rna_type' or prop.is_readonly:continue
                if prop.type in ('BOOLEAN','INT','FLOAT','STRING','ENUM'):
                    value=getattr(node,prop.identifier)
                    feed((prop.identifier,tuple(value) if getattr(prop,'is_array',False) else value))
            for socket in node.inputs:
                if hasattr(socket,'default_value'):
                    value=socket.default_value
                    try:value=tuple(value)
                    except TypeError:pass
                    feed((socket.identifier,stable(value)))
            image=getattr(node,'image',None)
            if image:
                feed((image.name,image.colorspace_settings.name,tuple(image.size),image.alpha_mode))
                if image.packed_file: h.update(bytes(image.packed_file.data))
        feed(tuple(sorted((l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier)
                          for l in mat.node_tree.links)))
    return h.hexdigest()


def descendants(root):
    for child in root.children:
        yield child
        yield from descendants(child)


def fingerprint(o):
    h = hashlib.sha256()
    def feed(value):
        h.update(repr(value).encode()); h.update(b'\0')
    feed((o.name,o.type,o.parent.name if o.parent else '',o.parent_type,o.parent_bone))
    feed(custom(o))
    feed(tuple(tuple(row) for row in o.matrix_basis))
    feed(tuple(tuple(row) for row in o.matrix_parent_inverse))
    feed((o.hide_render,o.hide_viewport))
    if o.type=='MESH':
        feed(custom(o.data))
        feed(tuple(tuple(v.co) for v in o.data.vertices))
        feed(tuple((tuple(p.vertices),p.material_index,p.use_smooth) for p in o.data.polygons))
        feed(tuple(m.name if m else '' for m in o.data.materials))
        feed(tuple((u.name,tuple(tuple(d.uv) for d in u.data)) for u in o.data.uv_layers))
        feed(tuple((a.name,a.domain,a.data_type,tuple(tuple(d.color) for d in a.data))
                   for a in o.data.color_attributes))
        feed((o.data.color_attributes.active_color_name,o.data.color_attributes.default_color_name))
        feed(tuple(g.name for g in o.vertex_groups))
        feed(tuple(tuple((g.group,g.weight) for g in v.groups) for v in o.data.vertices))
        if o.data.shape_keys:
            feed(custom(o.data.shape_keys))
            feed(tuple((k.name,k.value,k.slider_min,k.slider_max,tuple(tuple(v.co) for v in k.data))
                       for k in o.data.shape_keys.key_blocks))
    if o.type=='CURVE':
        feed(tuple((s.type,tuple(tuple(v.co) for v in s.bezier_points),tuple(tuple(v.co) for v in s.points)) for s in o.data.splines))
    if o.type=='ARMATURE':
        feed(tuple((b.name,b.parent.name if b.parent else '',tuple(tuple(row) for row in b.matrix_local),b.use_deform) for b in o.data.bones))
        feed(tuple((b.name,tuple(tuple(row) for row in b.matrix_basis),b.rotation_mode) for b in o.pose.bones))
    feed(tuple((m.name,m.type) for m in o.modifiers))
    return h.hexdigest()


def evaluated(o):
    active = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = active.to_mesh()
    transform = active.matrix_world
    normal_transform = transform.inverted().transposed().to_3x3()
    points = [transform @ v.co for v in mesh.vertices]
    normals = [(normal_transform @ v.normal).normalized() for v in mesh.vertices]
    faces = [tuple(p.vertices) for p in mesh.polygons]
    active.to_mesh_clear()
    return points,normals,faces


def bounds(points):
    return [[min(p[i] for p in points),max(p[i] for p in points)] for i in range(3)]
