# JustLife original character assets

Generated and sculpted specifically for JustLife in Blender. No EA meshes, textures, screenshots or other third-party game assets are included in the exported characters.

## Files

- `assets/models/character.glb`: standard adult frame, ready for Godot 4.
- `assets/models/character_broad.glb`: 12% broader frame with the same hierarchy and materials.
- `assets/models/character_lod.glb` and `character_broad_lod.glb`: reduced meshes for the live gameplay camera, with identical materials and pivots.
- `art/character_lod_preview.png`: round-trip import/render check of the gameplay LOD.
- `art/character_bob_preview.png` and `character_curls_preview.png`: checks of the other hairstyles.
- `art/characters.blend`: editable source, all three hairstyles and studio portrait lighting.
- `art/character_preview.png`: full-length character quality-control render.
- `art/character_face.png`: face quality-control render.
- `tools/create_characters.py`: deterministic Blender generator.

Regenerate with `blender --background --python tools/create_characters.py`. Run from a separate process; it creates its own scene and does not change another open Blender session.

## Godot contract

Front is **+Z**, up is **+Y**, with feet at approximately zero and height around 1.78 m. The top root is named `Character`. glTF transforms preserve the following nested pivot nodes:

| Node | Parent | Purpose |
| --- | --- | --- |
| Head | Character | Head turn and nod; all face/hair details follow |
| Arm_L / Arm_R | Character | Shoulder swing |
| Forearm_L / Forearm_R | Arm_L / Arm_R | Elbow bend |
| Leg_L / Leg_R | Character | Hip swing and seated pose |
| Shin_L / Shin_R | Leg_L / Leg_R | Knee bend; includes sneakers |

Rotate pivot **X** for forward/backward walking and seated bends. Use modest angles for elbow bends: exposed arm geometry overlaps under the short sleeves. These are articulated mesh node pivots, not a skinned skeletal rig; there are no embedded animation clips. Procedural locomotion and interaction poses are expected from the game.

## Hair variants

The GLBs deliberately include every hairstyle so one imported scene supports customization. Find these groups recursively under `Head` and show **exactly one**:

- `Hair_Crop`: asymmetric side-swept crop with raised crown locks.
- `Hair_Bob`: jaw-length layered bob with fringe and sculpted strand ridges.
- `Hair_Curls`: textured rounded curls with individual coils and ridges.

`Hair_Crop` is the default in the Blender preview. Blender source keeps the other groups hidden for rendering only. glTF exports all three. Do not hide every node with a `Hair_` prefix: eyebrow and eyelash meshes also use this prefix and should remain visible.

## Appearance materials

Duplicate material resources per character instance before recoloring. The principal exact material names are `Skin`, `Hair`, `Top`, `Bottom`, `Shoes`, and `Eyes`. Optional related materials preserve detail:

- `Hair_highlight`, `Hair_shadow`: subtle strand and lash variation.
- `Top_seam`, `Top_inner`: blouse stitch shading and light collar/cuff trims.
- `Bottom_seam`: tailored seams and pocket edging.
- `Shoes_sole`, `Shoes_accent`: rubber and leather accent.
- `Eyes_white`, `Eyes_edge`, `Eyes_pupil`, `Eyes_catchlight`: sclera, iris rim, pupil and reflection. Change only `Eyes` for iris color.
- `Lips`, `Ear_detail`, `Nose_detail`: facial color accents. Skin-tone changes may also gently tint these for a coherent result.
- `Jewelry`: small earrings and trouser fastening.

The asset uses smooth PBR materials and authored geometry; it needs no texture files. The source converts palette sRGB colors to Blender linear values before export. Recoloring in Godot should use ordinary sRGB `Color` values in `StandardMaterial3D.albedo_color`.

## Form and detail

Continuous sculpted head rings establish the jaw, chin, cheekbones and forehead. Separate formed geometry gives the nose bridge, tip and nostril wings, cupid-bow upper lip, lower lip, almond-shaped eyes, raised lids, eye creases, irises, pupils, catchlights, brows and ear helix. Hair uses irregular shells, interlocking locks and directional ridges. Clothing includes a fitted blouse, bound neckline and cuffs, button placket, folded hem, tailored trouser yoke with two leg openings, pockets and pressed creases. Hands have separate tapering fingers and thumbs. Low-top sneakers include tongue, laces, rubber sole and side accent.

## Practical limits

The detailed files prioritize character-creation detail. Use the reduced files for the normal live camera: approximately **35,625 visible triangles with the Crop hairstyle**, compared with 146,104 in the detailed version. Each file includes all three hairstyles, but the game hides the two not selected. The full LOD file contains 62,727 triangles across all styles and is about 1.6 MB. A fully skinned deformation rig remains future production work. Body-frame variation is horizontal proportion scaling, not independently authored anatomy. The trouser yoke has a visible seam near the upper thigh. Expressions are static; there are no facial morph targets. Face shape and wardrobe are not modular beyond the named color groups and hairstyle selection.

Blender API references used: [Mesh.from_pydata](https://docs.blender.org/api/current/bpy.types.Mesh.html), [glTF exporter](https://docs.blender.org/api/current/bpy.ops.export_scene.html), and [smooth shading](https://docs.blender.org/api/current/bpy.ops.object.html), fetched using Context7.
