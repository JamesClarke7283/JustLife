"""Make the eye interiors ride the eyeball at every slider value.

    blender -b --python tools/author_eye_rigid.py -- --family all --save

After the iris enlargement (tools/author_iris.py) the Eye_Spacing shape key
carried the negative of the growth: at spacing zero the enlarged disc showed,
and sliding toward one shrank it back to the pre-enlargement size, so the
spacing slider doubled as an accidental iris size slider while the disc
sheared up to fifteen millimetres across its face. The same history left a
wide Face_Round shear on the eye parts.

This replaces the Eye_Spacing and Face_Round deltas of Iris, Iris_edge and
Pupil with one rigid translation per key, sampled from the SCLERA's own delta
field at the iris centre, so the disc stays a single rigid piece riding the
eyeball: grown at rest, translated under spacing and face round, never
warped. Blink keeps its original delta; the sclera itself is untouched.

Shape-key data is edited through each mesh's Basis block and key data pair so
the evaluator and the exporter see the same geometry.
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
KEYS=('Eye_Spacing','Face_Round')

report={}
for family in FAMILIES:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/SOURCES[family]))
    entries=[]
    for side in ('L','R'):
        part_suffix='' if side=='L' else '.001'
        sclera=D.objects.get('Eyes_Sclera'+part_suffix)
        iris=D.objects.get('Eyes_Iris'+part_suffix)
        edge=D.objects.get('Eyes_Iris_edge'+part_suffix)
        pupil=D.objects.get('Eyes_Pupil'+part_suffix)
        if None in (sclera,iris,pupil):continue
        skeys=sclera.data.shape_keys.key_blocks
        sbasis=skeys[0].data
        ipts=[iris.matrix_world@v.co for v in iris.data.vertices]
        icentre=sum(ipts,Vector())/len(ipts)
        # Sample the sclera's delta nearest the iris centre.
        nearest={}
        for key_name in KEYS:
            key=skeys.get(key_name)
            if key is None:continue
            best_i=0;best_d=1e9
            for i in range(len(sbasis)):
                w=sclera.matrix_world@sbasis[i].co
                d=(w-icentre).length
                if d<best_d:best_d=d;best_i=i
            nearest[key_name]=sclera.matrix_world.to_3x3()@(Vector(key.data[best_i].co)-Vector(sbasis[best_i].co))
        for key_name in KEYS:
            if key_name not in nearest:continue
            world_delta=nearest[key_name]
            for part in (iris,edge,pupil):
                if part is None or part.data.shape_keys is None:continue
                pkeys=part.data.shape_keys.key_blocks
                key=pkeys.get(key_name)
                pb=pkeys[0].data
                if key is None:continue
                inv=part.matrix_world.inverted()
                rot=part.matrix_world.to_3x3()
                shift=inv.to_3x3()@world_delta
                # Key data holds absolute positions of the OLD small shape;
                # replace them with grown basis plus the rigid translation so
                # the disc stays grown and rigid at every slider value.
                for i in range(len(key.data)):
                    key.data[i].co = pb[i].co + shift
                part.data.update()
        pts=[iris.matrix_world@v.co for v in iris.data.vertices]
        entries.append({'side':side,'iris_centre':tuple(round(c,4) for c in icentre),
                        'verts':len(iris.data.vertices)})
    report[family]=entries
    if args.save:
        bpy.ops.wm.save_mainfile()
        print('SAVED',family)
print('EYE_RIGID_REPORT '+json.dumps(report))
