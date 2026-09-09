# Iteration 34 — child casual-shirt shoulders

The child's casual shirt had conspicuously padded sleeve crowns in the actual
Creator. This bounded original-art change lowers that volume and softens the
upper shoulder join. The independent critic inspected all 24 matched pairs
(48 images) and accepts v3 as a modest incremental improvement, subject to the
separate source and release gate. No new visible sleeve skin breakthrough or
cuff collapse appeared in the sampled poses. The rounded volume and sculpted
shoulder seam remain limitations; there is no new character-family or whole-game
score from this small garment change.

## Exact scope

Only native positions on `Outfit_Casual_Shirt`, mesh `Top_Blouse`, change:
2,678 of 6,002 vertices, at most 10.360 mm. All 881 vertices within 9 mm of the
retained collar, placket and cuff surfaces remain exact. The other 361 child
objects, face/anatomy/hair, trims, all native UVs/topology/rig weights and metadata
are protected. Other age families and runtime code are unchanged by this stage.

One explicit source-maintenance exception sets `Hair_shadow.use_fake_user` from
false to true. All material contents and other flags remain exact. This keeps
the original unused material through a normal editable-source save. Fresh reopen
retains the populated `Scene`, its 362 objects and `Character_Portrait` camera.

Four fresh single-thread Blender exports supply the authored shirt. A guarded
primitive/accessor transfer into the original child GLBs preserves all 338 other
decoded mesh records and their payloads, material/node/skin mapping and sharing.
The detailed shirt retains exact UVs, weights and indices: 7,083 vertices and
12,000 triangles. Only the shirt's derived LOD tessellation/UV/weight interpolation
may change: 1,859 to 1,848 vertices, with 2,640 triangles retained. The transferred
shirt primitive must exactly equal its fresh Blender export.

## Matched visual evidence

Both sides use the same committed runtime, `1fd7a0c1d4c8b2196c23eef29f8c04a2757ec59e`;
only the four child GLBs differ in the input maps. The private capture fixtures
use 1440 × 900 Forward+/Vulkan on the RTX 5090, `root.gui_disable_input` and
existing nodes’ process/input/unhandled-input flags disabled, private
data/config/cache/temp/save directories, explicit draws, fixed lighting
and complete held-pose traces. Standard uses body/height 0.85/0.93; broad uses
1.15/1.08. Complete recorded baseline/candidate reports match exactly. Historical freeze
does not cover later-added nodes or explicitly disable unhandled-key/shortcut
handlers. The captured canonical scripts define neither omitted handler; no
contamination is established, and no broader input-exclusion claim is made.

| Selected evidence | Pairs | Scope |
| --- | ---: | --- |
| Creator front/profile/back, both bodies, full/LOD | 12 | LOD is an explicit inspection override |
| Directed seated meal, both bodies, full/LOD | 4 | Real meal anchor and 138 fixed 1/60-second rig steps |
| Ordinary paused Live | 2 | Pinned authored home layout and ordinary camera |
| Isolated held-plate walking rig, both bodies, full/LOD | 4 | 60 fixed steps; house context hidden after pose placement |
| Isolated standard-descending/broad-ascending stair rig | 2 | Actual LOD gait sample at 0.53 route fraction; staircase context hidden afterward |

The first 18 pairs retain contextual views. The last six establish garment
appearance in unobstructed actual rig poses only. The fixture records the exact
hidden scene children, actor/dish transforms and camera/light controls; it does
not establish route completion, meal custody or stair traversal. Initial carry
and stair cameras were obscured by furniture and railings. Their six pairs and
the first failed clarity replacement remain rejected visual evidence despite
clean numerical capture checks. The selected manifest maps each replacement.

The contextual runs each completed 189 checks with zero failures, rendering 24
frames of which 18 are credited here. The final isolated runs each completed
69 checks with zero failures and six frames. Their Godot diagnostics are clean.
This is sampled clearance, not cloth simulation or an arbitrary-pose guarantee.

## Reproduction and retained failures

[The maintained source guide](../../tools/child_shirt_v31/README.md) gives the
portable input-extraction and reproduction commands. The input extractor reads
and hashes five pinned local Git objects; no ignored private source dependency
or duplicate archive of former production GLBs is required. Two independent
fresh pipelines reproduced the four qualified output GLBs byte for byte in
Blender 5.2.1 LTS build `9e2066aef7ef`. New `.blend` save containers differ, while
fresh read-only recorded source facts and the usable scene match exactly.
This is same-environment reproduction of recorded facts, not every Blender RNA
field or a cross-version guarantee. Blender's installed `cattrs` addon traceback
is retained in logs alongside successful processes and explicit proof markers.

The initial native save dropped the unused material. An explicit library write
preserved it but opened an empty scene; that source was rejected. The approved
fake-user flag resolved both preservation and usability. Fresh standard LOD
export drifted in seven unrelated U values on `Hair_Crop_Swept_lock.004`; no
tolerance was granted. Guarded shirt-only transfer retains the original hair.
An attempted second shoulder shape clipped the unchanged arm (126 negative or
missing samples in the finite neutral ray grid) and was rejected. V3 retained
the first version's neutral minimum sampled clearance of 0.854 mm while raising
the inner join. Actual full/LOD pose images remain the relevant visual gate.

Private evidence is retained under:

- `dist/test-work/child-shirt-v31-prototype-x_sd3f3i/final_visual_gate/`: selected
  24-pair manifest and 84 pinned visual/source artifacts.
- `dist/test-work/child-shirt-final-critic-jor63gs_/REVIEW.md`: independent
  48-image visual acceptance, SHA-256
  `e62a9b719e242ccedf84d253ab2b3ab40e62ce0ab6ee2d5c2e77ead5798433a1`.
  Its 87-pin freeze is
  `46754b99f436d1acd44540db6bb309dc67c6cc179b785464a5e500e3a7264e4e`.
- `dist/test-work/child-shirt-v31-portable-a_54sxge/`: source reproduction,
  qualified native reopen, decoded transfer proof and retained failure record;
  `SOURCE_FROZEN.json` pins 57 artifacts.

The large native fact dumps, rejected binaries, raw logs and screenshots remain
ignored local evidence. Production receives the five revised art files, compact
portable source tools and documentation only. The accepted shoulder change does
not establish parity with a commercial life simulator or a 10/10 game rating.

## Current-source integration

Root also checked exact `9dcbd52` runtime with the qualified child-art overlay in
`dist/test-work/child-shirt-current-v9lk6upd`. A clean import took 22.91 seconds;
the actual Forward+ Creator capture passed **22 checks, zero failures**, in
15.21 seconds. All three standard-front/profile and broad-front images were
directly inspected. The private harness adds recursive exclusion and assertions
for all four Node input modes, including newly added nodes; GUI input is disabled.
No production input behavior changes. Source and runtime input hashes remained
exact. This focused check establishes integration with the current UI/runtime;
it does not replace the older matched pose study or qualify the held Linux build.
