# Child casual-shirt shoulder refinement

This original-art stage lowers the child's rounded sleeve crowns and softens the
upper shoulder transition. It changes vertex positions on `Outfit_Casual_Shirt`
(`Top_Blouse`) only. The other 361 native child objects, all face/anatomy/hair data,
other garments, trims, UVs, rig weights, transforms and metadata remain exact.
Adult, teen and elder assets are outside this stage.

The source has 6,002 shirt vertices: 2,678 move, at most 10.360 mm. All 881 vertices
within 9 mm of the retained collar, placket or cuff surfaces remain exact. There
is one separately approved source-maintenance change:
`Hair_shadow.use_fake_user` changes from false to true. Its material content and
every other material property remain exact. The flag keeps this original unused
material through an ordinary main-file save. The source opens the populated
`Scene`, with all 362 objects and the original `Character_Portrait` camera.

## Reproduce

Use ordinary Python and Blender 5.2.1 LTS, build `9e2066aef7ef`. The immutable
inputs are pinned in `native_contract.json`: the former child source and four
accepted GLBs from commit `1fd7a0c1d4c8b2196c23eef29f8c04a2757ec59e`.
The input extractor reads local Git objects and verifies every byte hash. It
does not fetch, modify existing tracked files, or depend on an ignored private archive.
A shallow source checkout needs these five pinned objects available locally, or
equivalent separately archived files with the same hashes.

```sh
python tools/child_shirt_v31/extract_inputs.py --repository . --output /absolute/new/shirt-inputs
python tools/child_shirt_v31/generate.py --source /absolute/new/shirt-inputs/art/characters_child.blend --baseline-models /absolute/new/shirt-inputs/assets/models --output /absolute/new/shirt-output
```

The output must be new. The driver reopens the input, authors the bounded mesh
change, then reopens the saved source in another read-only Blender process. It
compares the recorded native facts and the usable startup scene. Four separate
single-thread Blender processes export standard/broad and full/LOD variants.
The final files are `art/characters_child.blend` and `assets/models/*.glb`.
Intermediate native files, raw exports, process logs and protection receipts
remain in that output directory. It does not promote files into the repository.

Every final GLB must match the visually reviewed candidate bytes recorded in the
contract. A new `.blend` container may differ due to save provenance; the recorded
object/geometry/UV/rig/morph/material signature must match exactly on fresh reopen.
This is a same-environment reproduction claim, not a cross-version promise or an
assertion about every Blender RNA field. The installed environment emits a
`cattrs` addon-registration traceback despite successful author/export processes;
logs are retained, with process results and explicit verification markers.

## Strict export boundary

A fresh unchanged standard child LOD export differed from the accepted asset in
seven U values on `Hair_Crop_Swept_lock.004`. Thread-count and export-order trials
did not justify changing that unrelated hair data. `transfer_shirt.py` therefore
copies only the six accessor payloads of the freshly authored shirt primitive
into the exact original GLB, retaining every other buffer payload. It validates
the node/material/skin mapping, accessor ownership and sharing, then compares
all 338 other decoded mesh records exactly. It does not round, reorder triangles,
normalize indices or repair hair UVs.

Detailed shirt indices, UVs and skin weights remain exact; positions and derived
normals change. Its 7,083 exported vertices and 12,000 triangles are unchanged.
The production LOD decimator derives a new shirt tessellation: exported vertices
change from 1,859 to 1,848, while triangles remain 2,640. Its derived UV/weight
interpolation and topology changes are allowed only on this shirt. The final
shirt primitive must be exactly the one produced by its fresh Blender export.
The original rig/contact revision metadata is deliberately retained.

The historical `tools/create_characters.py --surface-repair --age child` command
regenerates the older child art and does not reproduce this garment refinement.
Use this bounded pipeline for the current child source.

## Visual boundary and retained limits

Review uses 18 paired contextual Creator/Live/seated views plus six isolated
actual carry/stair rig inspection pairs. The latter hide scene geometry after
placing the real actor and dish; they establish visible garment clearance at
those held poses, not completed routes, custody or stair traversal. The rejected
occluded compositions are retained as failed visual evidence even though their
numerical capture checks passed. Camera, lighting, recorded input flags, profiles, complete pose traces and source
inputs are matched within each pair. Historical captures set
`root.gui_disable_input` and disable process/input/unhandled-input on the existing
node tree. They do not establish exclusion of future-node key/shortcut handlers.

This is a modest reduction of the padded shoulder silhouette. The broad-frame
sculpted join and small profile improvement remain limits. There is no cloth
simulation or arbitrary-pose clearance guarantee, no change to child anatomy,
and no new character-family or whole-game quality score from this small stage.
