"""Original close-cut stubble, directional grain and density fade fields."""
import math

import bpy
import numpy as np

# Front, recessed front corners, short temple point, over-ear arch, nape.
HAIRLINE = [(0,.77),(.35,.776),(.55,.782),(.74,.75),(.95,.685),
            (1.10,.60),(1.22,.565),(1.38,.62),(1.65,.59),(1.94,.45),
            (2.40,.36),(math.pi,.34)]


def smooth(value):
    value = np.clip(value,0,1)
    return value*value*(3-2*value)


def hairline(angle):
    """Small, deliberate asymmetry; no repeating scalloped front rim."""
    a = np.abs((angle+math.pi)%(2*math.pi)-math.pi)
    value = np.interp(a,[v[0] for v in HAIRLINE],[v[1] for v in HAIRLINE])
    return value+.0025*np.sin(angle*2+.4)*np.exp(-(a/.9)**2)


def write_image(name,rgba,folder,space):
    height,width = rgba.shape[:2]
    previous=bpy.data.images.get(name)
    if previous is not None and previous.users==0:bpy.data.images.remove(previous)
    im = bpy.data.images.new(name,width=width,height=height,alpha=True,float_buffer=False)
    im.colorspace_settings.name = space
    im.alpha_mode = 'STRAIGHT'
    im.pixels.foreach_set(np.asarray(rgba,dtype=np.float32).reshape(-1))
    im.file_format = 'PNG'; im.filepath_raw = str((folder/(name+'.png')).resolve())
    im.save(); im.pack()
    return im


def follicles(width,height):
    """Scatter short strokes without a lattice or harmonic interference grid.

    Uniformly random positions are deterministic original artwork. Tangent
    direction varies around the scalp; independent width, length and angle
    keep the cropped carpet from becoming regular parallel fabric.
    """
    rng=np.random.default_rng(621409)
    count=110000
    x=rng.uniform(0,width,count); y=rng.uniform(0,height,count)
    direction=.24*np.sin(x/width*2*math.pi)+rng.normal(0,.37,count)
    along=rng.uniform(1.05,1.95,count)
    across=rng.uniform(.40,.70,count)
    amplitude=rng.uniform(.68,1,count)
    c=np.cos(direction); s=np.sin(direction)
    field=np.zeros((height,width),dtype=np.float64)
    for dy in range(-6,7):
        py=np.floor(y).astype(np.int32)+dy
        valid=(py>=0)&(py<height)
        for dx in range(-4,5):
            px=np.floor(x).astype(np.int32)+dx
            a=px+.5-x; b=py+.5-y
            radius=((a*c-b*s)/across)**2+((a*s+b*c)/along)**2
            value=np.exp(-radius*.5)*amplitude
            np.maximum.at(field,(py[valid],px[valid]%width),value[valid])
    # Rank supplies a uniform coverage threshold regardless of stroke overlap.
    # It avoids both cell outlines and a sudden jump to opaque at high density.
    order=np.argsort(field,axis=None,kind='stable')
    rank=np.empty(field.size,dtype=np.float64)
    rank[order]=(np.arange(field.size)+.5)/field.size
    coverage=rank.reshape(field.shape)
    return field,coverage


def material(source,folder,span):
    previous=bpy.data.materials.get('Hair_Buzz_Surface')
    if previous is not None:
        assert previous.users==0, 'Buzz material is still used outside the replaced Buzz subtree'
        bpy.data.materials.remove(previous)
    width=2048; height=1024
    u,v = np.meshgrid((np.arange(width)+.5)/width,(np.arange(height)+.5)/height)
    angle = (u-.5)*2*math.pi
    z_fraction = .15+.89*v
    relative = (z_fraction-hairline(angle))*span
    side = smooth((np.abs(angle)-.68)/.9)
    # Front edge softly breaks up over 4 mm; sides/nape fade over ~20 mm.
    density = smooth((relative+.0015+side*.006)/( .004+side*.018))
    grain,coverage=follicles(width,height)
    # Alpha is a deterministic density mask. Skin beneath the patch remains
    # the real independently recolored skin, never a baked skin-color blend.
    alpha = np.clip((density-(1-coverage))*6+.5,0,1)
    alpha = np.where(density<=0,0,np.where(density>=1,1,alpha))
    tone = np.clip(.87+.105*grain,.82,1)
    rgba = np.stack((tone,tone,tone,alpha),axis=-1)
    color_image = write_image('JustLife_Buzz_StubbleFade',rgba,folder,'sRGB')
    height_field = .00006*grain
    du = (np.roll(height_field,-1,axis=1)-np.roll(height_field,1,axis=1))*width/2/.60
    dv = np.gradient(height_field,axis=0)*height/(span*.89)
    normal = np.stack((-du,-dv,np.ones_like(du)),axis=-1)
    normal /= np.linalg.norm(normal,axis=-1,keepdims=True)
    normals = np.ones((height,width,4)); normals[:,:,:3] = normal*.5+.5
    normal_image = write_image('JustLife_Buzz_GrainNormal',normals,folder,'Non-Color')
    roughness = np.clip(.85+.025*(1-grain)+.015*side,.82,.92)
    rough = np.ones((height,width,4)); rough[:,:,:3]=roughness[:,:,None]
    rough_image = write_image('JustLife_Buzz_Roughness',rough,folder,'Non-Color')
    mat = source.copy(); mat.name = 'Hair_Buzz_Surface'; mat.use_nodes=True
    mat['recolor_role']='Hair'; mat['artwork']='Original JustLife scattered follicles and barber fade, revision62B'
    nodes=mat.node_tree.nodes; links=mat.node_tree.links
    bsdf=nodes.get('Principled BSDF')
    color=tuple(bsdf.inputs['Base Color'].default_value)
    for name in ('Base Color','Alpha','Normal','Roughness'):
        for link in list(bsdf.inputs[name].links):
            links.remove(link)
    tone_node=nodes.new('ShaderNodeTexImage'); tone_node.image=color_image; tone_node.extension='REPEAT'
    tone_node.name='Original stubble tone and density'
    mix=nodes.new('ShaderNodeMix'); mix.data_type='RGBA'; mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=1
    input_a=next(s for s in mix.inputs if s.identifier=='A_Color')
    input_b=next(s for s in mix.inputs if s.identifier=='B_Color'); input_b.default_value=color
    output=next(s for s in mix.outputs if s.type=='RGBA')
    links.new(tone_node.outputs['Color'],input_a); links.new(output,bsdf.inputs['Base Color'])
    # Blender 5.2's glTF exporter recognizes Math:Round as alphaMode MASK with
    # cutoff 0.5. Native previews and glTF therefore use the same density mask.
    clip=nodes.new('ShaderNodeMath'); clip.operation='ROUND'; clip.name='Portable stubble density mask'
    links.new(tone_node.outputs['Alpha'],clip.inputs[0]); links.new(clip.outputs[0],bsdf.inputs['Alpha'])
    tex_n=nodes.new('ShaderNodeTexImage'); tex_n.image=normal_image; tex_n.extension='REPEAT'
    normal_node=nodes.new('ShaderNodeNormalMap'); normal_node.inputs['Strength'].default_value=.32
    links.new(tex_n.outputs['Color'],normal_node.inputs['Color']); links.new(normal_node.outputs['Normal'],bsdf.inputs['Normal'])
    tex_r=nodes.new('ShaderNodeTexImage'); tex_r.image=rough_image; tex_r.extension='REPEAT'
    links.new(tex_r.outputs['Color'],bsdf.inputs['Roughness'])
    bsdf.inputs['Specular IOR Level'].default_value=.23
    mat.use_backface_culling=False
    return mat
