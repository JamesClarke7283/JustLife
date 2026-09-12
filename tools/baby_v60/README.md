# Baby character family (iteration 60)

Authors JustLife's original baby — a 0.55 m rounded infant — and exports the four
game models the actor loads for the `baby` life stage. Nothing here copies a Sims
asset: every surface is a loft, tube or sphere built from the tables in
`create_baby.py`.

Run from the repository root:

```sh
blender --background --python tools/baby_v60/create_baby.py -- --family baby --export
```

Add `--evidence-dir evidence/baby60` for the front/side/crawl renders,
`--preview-dir DIR` for a studio portrait, or `--source` to rebuild only the
editable blend. The run writes:

| Output | Notes |
| --- | --- |
| `assets/models/character_baby.glb` | The default frame. |
| `assets/models/character_baby_broad.glb` | The broad frame (root `x` scale 1.12). |
| `assets/models/character_baby_lod.glb` | Live-camera LOD (decimated). |
| `assets/models/character_baby_broad_lod.glb` | Both. |
| `art/characters_baby.blend` | The editable source. |
| `manifest.json` | Blender build, generator and pose-spec hashes, contract input hashes, every export hash. |

Godot creates the `.import` files on the next import.

## The contract this model keeps

The four older age families are not rescaled copies of each other; each is a
separate authored sculpt that shares a *contract*. The baby keeps the same one,
which is why `scripts/actor.gd` needs no second code path:

- **Bone names and pivots.** `Root, Spine, Head, Arm_L/R, Forearm_L/R, Leg_L/R,
  Shin_L/R`, plus the accessory empties of the same names that carry hair, eyes
  and attached props. `_read_age_landmarks` and the joint lookup therefore work
  unchanged.
- **Root extras.** `age_stage = baby`, `height_m = 0.55`, `hip_height = 0.245`,
  `knee_height = 0.135`, `mouth_anchor`, `palm_anchor_l/r`, `bone_landmarks`,
  `hair_variants`, `identity_morphs`, `wardrobe_variants`.
- **Material names.** `Skin`, `Hair`, `Hair_highlight`, `Top`, `Top_seam`,
  `Bottom`, `Bottom_seam`, `Shoes*`, `Eyes*`, `Lips`, `Nose_detail`,
  `Ear_detail`, so `_recolor` recolours the baby with the same table.
- **Node names the runtime switches on.** `Hair_Crop`/`Hair_Bob`/`Hair_Curls`,
  `Outfit_Casual`, and both `Bottom_Continuous_*` and `Bottom_Shorts_*`.
- **Blend shapes.** `Blink`, `Smile`, `Sit`, `Face_Round`, `Jaw_Strong`,
  `Nose_Wide`, `Eye_Spacing`.

A baby has no authored hand-grip morphs, so `grip_morphs` is empty and
`_update_grips` finds nothing to drive rather than failing. It also has no shoe
mesh called `Shoes_Sole*` on a bare skeleton mismatch: the booties are parented
to the `Shin_*` pivots exactly like the older families' trainers, so the stair
and shoe-extent helpers that look for `Shoes_*` under `Shin_*` still resolve.

## The crawl

`crawl_pose.py` is the single numeric contract for the hands-and-knees crawl.
`scripts/actor.gd` mirrors it in `_baby_crawl_pose` / `_baby_crawl_offset` and
`BABY_CRAWL_*`, and `create_baby.py` applies it to the authored rig for the
crawl evidence renders, so what the game plays and what the evidence shows are
the same pose.

Two details are *solved* rather than guessed:

- `solve_offset` poses the rig and reads the armature-deformed contact geometry
  (the fists and the booties), then asserts the solved lift still matches the
  mirrored constant. If the pose drifts, the generator run fails with the two
  numbers in the message instead of silently shipping renders that disagree
  with the game.
- The head angle is the value that cancels the 70° body pitch, measured on the
  posed rig by reading the head pivot's own forward axis.

Because the body pivots about its feet, the vertical lift is what plants the
hands and knees on the floor; the hips therefore end up under 0.22 m above the
root, which is what `tests/test_baby_stage.gd` asserts to tell a crawl from a
walk on straight legs.

## Reproducibility

The generator uses no voxel remeshing and no random state, and the authored
scene is rebuilt from the same tables every run. Measured between two clean runs
of the identical command:

- **Identical:** the whole glTF JSON — every node, mesh, material, skin, morph
  target, accessor and extra — and the total decoded vertex and index counts.
  So the model is the same model.
- **Varies:** the *order* of vertices and indices in the binary buffers. Blender's
  glTF exporter reorders them while applying the modifier stack, so two runs can
  lay out identical geometry differently.

`manifest.json` therefore records the export hashes of the run that produced the
current files (the provenance trail the older tools keep), not a promise that a
hash is stable across runs. Compare `scripts/`-side behaviour — joint counts,
landmarks, morph names, node names — to verify a rebuild rather than comparing
GLB bytes.

## Retained limitations

- The romper's short sleeve caps are a separate shell from the arm, so at the
  extreme of the `body_scale` slider a thin seam can show at the shoulder.
- The hair is a single scaled shell plus detail pieces, not simulated strands;
  `Hair_Curls` reads as rounded lobes rather than individual curls at this size.
- The baby has no authored grip morphs, so it holds nothing with a closed fist.
