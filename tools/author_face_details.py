"""Seat the brows and deepen the mouth seam for close-up readability.

    blender -b --python tools/author_face_details.py -- --family all --save

The week-60 review found the brows hovering slightly off the forehead and the
smile seam receding behind the lip fronts, so mouths washed out at portrait
zoom. This nudges each brow toward the skull and brings the seam forward to
just behind the upper-lip front, measured per family and clamped so the seam
never pokes past the lip.

Every touched mesh carries relative shape keys whose first block ("Basis") is
what the evaluator and the exporter actually draw, so the move is applied to
that block and to the mesh basis together.
"""
import bpy, sys, argparse, pathlib, json
from mathutils import Vector

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--family',choices=['adult','child','teen','elder','all'],default='all')
parser.add_argument('--save',action='store_true')
parser.add_argument('--brow',type=float,default=0.0018,help='world shift toward the skull')
parser.add_argument('--seam',type=float,default=0.0015,help='world shift toward the viewer')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FAMILIES=['adult','child','teen','elder'] if args.family=='all' else [args.family]
SOURCES={'adult':'art/characters.blend','child':'art/characters_child.blend','teen':'art/characters_teen.blend','elder':'art/characters_elder.blend'}
D=bpy.data

def world_bbox(o):
    src=o.data.shape_keys.key_blocks[0].data if o.data.shape_keys else o.data.vertices
    pts=[o.matrix_world@v.co for v in src]
    return (Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))),
            Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts))))

def move_part(o, world_delta: Vector) -> None:
    local=o.matrix_world.inverted().to_3x3()@world_delta
    for store in [o.data.vertices] + ([o.data.shape_keys.key_blocks[0].data] if o.data.shape_keys else []):
        for v in store:v.co+=local
    o.data.update()

report={}
for family in FAMILIES:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/SOURCES[family]))
    entry={}
    brows=[]
    for suffix in ('','.001'):
        brow=D.objects.get('Hair_Brow'+suffix)
        if brow:brows.append(brow)
    seam=D.objects.get('Lips_Smile_seam')
    lip=D.objects.get('Lips_Upper_soft')
    if brows:
        shift=Vector((0,args.brow,0))
        for brow in brows:move_part(brow,shift)
        bmin,bmax=world_bbox(brows[0])
        entry['brow_front_after']=round(bmin.y,4)
    if seam and lip:
        lmin,lmax=world_bbox(lip)
        smin,smax=world_bbox(seam)
        shift=args.seam
        # The seam may approach the lip front but keeps a small setback.
        shift=min(shift,max(0.0,smin.y-(lmin.y+0.0006)))
        move_part(seam,Vector((0,-shift,0)))
        nmin,nmax=world_bbox(seam)
        entry['seam']={'shift':round(shift,4),'front_after':round(nmin.y,4),'lip_front':round(lmin.y,4)}
    report[family]=entry
    if args.save:
        bpy.ops.wm.save_mainfile()
        print('SAVED',family)
print('FACE_DETAILS_REPORT '+json.dumps(report))
