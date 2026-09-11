"""Enlarge the Lifelet irises so close-ups read as focused and expressive.

    blender -b --python tools/author_iris.py -- --family all --save

The week-60 macro renders show centered but small irises: about a third of the
sclera width, leaving wide white wedges at both corners that read as a distant,
sideways gaze at portrait zoom. Sims-style characters carry larger irises. The
disc grows sideways about its centre into the corner wedges and rises from its
fixed bottom edge, each axis guarded to stay inside its sclera, so the disc
never droops below the lower lid line. Catchlights keep their position.

Every touched mesh carries relative shape keys whose first block ("Basis") is
what the evaluator and the exporter actually draw, so the scale is applied to
that block and to the mesh basis together; Blink and the identity keys keep
their deltas and stay usable.
"""
import bpy, sys, argparse, pathlib, json
from mathutils import Vector

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--family',choices=['adult','child','teen','elder','all'],default='all')
parser.add_argument('--save',action='store_true')
parser.add_argument('--scale',type=float,default=1.32)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FAMILIES=['adult','child','teen','elder'] if args.family=='all' else [args.family]
SOURCES={'adult':'art/characters.blend','child':'art/characters_child.blend','teen':'art/characters_teen.blend','elder':'art/characters_elder.blend'}
D=bpy.data
SAFETY=0.0012    # keep this world gap between the grown iris and the sclera rim

def world_bbox(o, keys=None):
    src=keys[0].data if keys else o.data.vertices
    pts=[o.matrix_world@v.co for v in src]
    return (Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))),
            Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts))))

def scale_part(o, local_centre: Vector, factor_x: float, factor_z: float) -> None:
    for store in [o.data.vertices] + ([o.data.shape_keys.key_blocks[0].data] if o.data.shape_keys else []):
        for v in store:
            p=v.co-local_centre
            p.x*=factor_x;p.z*=factor_z
            v.co=local_centre+p
    o.data.update()

report={}
for family in FAMILIES:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/SOURCES[family]))
    entries=[]
    for side in ('L','R'):
        suffix='' if side=='L' else '.001'
        sclera=D.objects.get('Eyes_Sclera'+suffix)
        iris=D.objects.get('Eyes_Iris'+suffix)
        edge=D.objects.get('Eyes_Iris_edge'+suffix)
        pupil=D.objects.get('Eyes_Pupil'+suffix)
        if None in (sclera,iris,pupil):
            print('SKIP',family,side,'missing eye parts');continue
        keys=iris.data.shape_keys.key_blocks if iris.data.shape_keys else None
        smin,smax=world_bbox(sclera)
        imin,imax=world_bbox(iris,keys)
        icentre=(imin+imax)*.5
        # Sideways growth into the corner wedges about the centre; vertical
        # growth rises from the fixed bottom edge so the disc never hangs
        # below the lower lid.
        factor_x=args.scale
        span=imax[0]-imin[0]
        room=min(icentre[0]-smin[0],smax[0]-icentre[0])-SAFETY
        if span>1e-6:factor_x=min(factor_x,1.0+room/(span*.5))
        height=max(imax[2]-imin[2],1e-6)
        factor_z=min(args.scale,(smax[2]-SAFETY-imin[2])/height)
        if factor_x<args.scale or factor_z<args.scale:
            print('GUARD',family,side,'x',round(factor_x,3),'z',round(factor_z,3))
        for part in (iris,edge,pupil):
            if part:scale_part(part,part.matrix_world.inverted()@icentre,factor_x,factor_z)
        nmin,nmax=world_bbox(iris,keys)
        entries.append({"side":side,"x":round(factor_x,4),"z":round(factor_z,4),
                        "iris_width":round(nmax.x-nmin.x,4),"sclera_width":round(smax.x-smin.x,4),
                        "iris_top":round(nmax.z,4),"sclera_top":round(smax.z,4),
                        "iris_bottom":round(nmin.z,4),"old_bottom":round(imin.z,4)})
    report[family]=entries
    if args.save:
        bpy.ops.wm.save_mainfile()
        print('SAVED',family)
print('IRIS_REPORT '+json.dumps(report))
