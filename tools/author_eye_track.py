"""Make the eye interiors track their lid aperture under Face_Round.

    blender -b --python tools/author_eye_track.py -- --family all

REJECTED EXPERIMENT, retained for the record: matching the eye parts'
Face_Round centroid deltas onto the upper lid's changed nothing visible at
the combined-slider extreme (evidence/face60/adult_extreme_combined_sliders.png),
because the aperture shear under Eye_Spacing dominates, not the centroid
offset. The blends were restored; the accepted limitation is documented in
docs/REVIEWS/iteration_59_contract.md.

The approach: measure each side's per-key centroid shift in world space and
move the Face_Round delta of Sclera, Iris, Iris_edge and Pupil onto the upper
lid's delta. Eye_Spacing centroids already agree across those meshes.
"""
import bpy, sys, argparse, pathlib, json
from mathutils import Vector

ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--family',choices=['adult','child','teen','elder','all'],default='all')
parser.add_argument('--save',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FAMILIES=['adult','child','teen','elder'] if args.family=='all' else [args.family]
SOURCES={'adult':'art/characters.blend','child':'art/characters_child.blend','teen':'art/characters_teen.blend','elder':'art/characters_elder.blend'}
D=bpy.data
EYE_PARTS=('Eyes_Sclera','Eyes_Iris','Eyes_Iris_edge','Eyes_Pupil')

def key_delta_world(o,key_name):
    keys=o.data.shape_keys.key_blocks
    basis=keys[0].data
    key=keys.get(key_name)
    if key is None:return None
    acc=Vector((0.0,0.0,0.0))
    n=len(basis)
    for i in range(n):
        acc = acc + (key.data[i].co - basis[i].co)
    return o.matrix_world.to_3x3()@(acc/n)

def shift_key_world(o,key_name,world_delta):
    local=o.matrix_world.inverted().to_3x3()@world_delta
    key=o.data.shape_keys.key_blocks.get(key_name)
    if key is None:return
    for i in range(len(key.data)):
        key.data[i].co += local

report={}
for family in FAMILIES:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/SOURCES[family]))
    entries=[]
    for side in ('L','R'):
        part_suffix='' if side=='L' else '.001'
        lid=D.objects.get('Skin_Upper_lid_-1' if side=='L' else 'Skin_Upper_lid_1')
        if lid is None:continue
        lid_delta=key_delta_world(lid,'Face_Round')
        if lid_delta is None:continue
        for base in EYE_PARTS:
            part=D.objects.get(base+part_suffix)
            if part is None:continue
            before=key_delta_world(part,'Face_Round')
            if before is None:continue
            correction=lid_delta-before
            shift_key_world(part,'Face_Round',correction)
            after=key_delta_world(part,'Face_Round')
            entries.append({'part':base+part_suffix,'lid':tuple(round(c,4) for c in lid_delta),
                            'before':tuple(round(c,4) for c in before),
                            'after':tuple(round(c,4) for c in after)})
    report[family]=entries
    if args.save:
        bpy.ops.wm.save_mainfile()
        print('SAVED',family)
print('EYE_TRACK_REPORT '+json.dumps(report))
