# Original JustLife gable roof kit

Private art/geometry preparation, qualified for the next private runtime integration. This is not a promoted game feature. The independent critic rated the two Blender views about **7.5/10 directional static art**; the full-game score remains unchanged at7.2.

The editable source is `art/architecture/justlife_roof_kit.blend`; the portable generator is `tools/create_roof_kit.py`. The source contains two independently named roof roots and a native module catalog, all at the origin. Isolate one root in Blender when editing: `Roof_representative`, `Roof_small_rotated`, or `RoofModules`. `tools/render_roof_kit.py` isolates each fixture automatically, adds temporary studio walls/lights, renders, and never saves those preview objects into the source or exports.

## Transform and geometry contract

Read `art/architecture/roof_geometry_contract.json` for formulas, bounds, palette, source/export hashes and per-mesh audit. Godot uses metres, Y up. The root origin is the center of the **support footprint at wall-top Y0**. Place it at `(record.x, Building.level_y(level)+2.6, record.z)`.

- `record.w/d` remain the world-axis support dimensions.
- At rotation0, canonical span=w, ridge length=d and the ridge points +Z.
- At rotation90, canonical span=d, ridge length=w, followed by +90° about GodotY, so the ridge points +X.
- **The two dimensioned fixture GLBs already contain their named rotation. Translate them only; do not rotate the small fixture a second time.** A runtime rebuild should construct canonical geometry and apply the record rotation once.
- Pitch is rise/run. Structural ridge rise=`pitch*span/2`.
- Total plan overhang is exactly0.28m on each side, inclusive of the normal shell extrusion. Shell thickness is0.10m perpendicular to the roof plane.
- The full cream gable triangles meet Y0 across the support span and extend to the structural ridge. They are0.08m deep inside the two support ends.
- The outer rake fascia occupies the last0.10m of each ridge end. Roof decks stop0.012m behind its outer face, and eave fascia/lips stop0.10m behind, avoiding coplanar external trim faces.
- Roof tiles are actual closed, bevel-edged original geometry with a mild crown and thicker leading butt. Tile count changes with dimensions; shell/trim/tile thickness is never stretched with the whole roof.

| Fixture | Support w×d | Pitch / yaw | Actual imported bounds relative to wall top | Meshes / triangles |
|---|---|---|---|---|
| representative |8×10m|0.5 /0°|X±4.28, Z±5.28, Y−0.2331966…2.1768034|29 /42,512|
| small_rotated |4×6m|0.75 /90°|X±2.28, Z±3.28, Y−0.29…2.44|21 /16,116|

These are two tested parameter fixtures, not an exhaustive size/pitch or runtime performance certification. The record material is stored as metadata; this study uses the fixed sage/cream/oak palette from the contract. Runtime recoloring is integration work.

## Reusable parts

`assets/models/roof_gable_modules.glb` is a catalog, not an assembled roof. Its three named nodes deliberately overlap at the origin; instantiate the required child mesh separately.

- `Tile_036x032`:0.36m width,0.32m depth,0.020m maximum height; origin at base center. NativeX along ridge, nativeY outward from roof, nativeZ downslope. Contract gives the right-handed slope basis and placement formula.
- `Fascia_100`:0.06m wide,0.18m tall,1m long alongZ; origin at the upper edge center. Scale only the length.
- `OakLip_100`:0.017m wide,0.035m tall,1m long alongZ; origin at upper edge center. Scale only the length.

Variable-size roof decks, gable triangles, rake profiles and segmented ridge must be rebuilt from the contract, with native tiles/modules repeated or cropped. Stretching a complete fixture would violate the thickness/eave contract.

## Reproduce in a private copy

Run from this project root. The generator uses relative paths and no external artwork or add-ons. These commands overwrite generated local evidence, so copy this frozen checkpoint before rerunning.

```sh
blender --background --threads 4 --python-exit-code 23 --python tools/create_roof_kit.py
blender --background --threads 4 --python-exit-code 23 --python tools/render_roof_kit.py
XDG_DATA_HOME="$PWD/evidence/userdata" godot --headless --path . --editor --import
XDG_DATA_HOME="$PWD/evidence/userdata" godot --headless --path . --script res://tests/test_roof_kit.gd
```

`art/.gdignore` prevents Godot from attempting to reimport editable Blender files. `evidence/.gdignore` excludes archived source copies. Actual GLBs are imported through Godot's editor and instantiated as PackedScenes. The test writes its report under `res://evidence`; it belongs in a private test copy, not a player installation.

The final source/build/render hashes match. The final Godot test passed258checks, covering imported geometry bounds, actual yaw/translation at a level1 wall-top5.76m, gable infill, named support/ridge markers, material presence/roughness, true normal shell thickness, trim end separation and native module dimensions/origins. It is not a public Build flow test. No actual Godot roof image was captured in this bounded study.

The first nominal0.10m shell projection check used a20µm tolerance and failed one imported deck at26.25µm deviation. The actual default compressed import is now measured against a documented50µm bound for that projection only. The original failure/test/log and all four measured thicknesses remain in evidence. Other dimension checks retain20µm tolerance. This small numerical precision adjustment is not evidence of visual quality.

## Scope and next integration gates

The kit covers standalone rectangular gables only. Public placement, dynamic rebuild, support/eave adjacency, actual headroom, game-camera/material appearance, performance/LOD and packaged save/reload remain runtime integration gates. Current building-state validation checks only support rectangles; it must check the complete overhang and vertical envelope separately. Valleys, dormers and intersecting roof junctions are not supplied or qualified.

All80 shared model files pinned in `evidence/input_manifest.json` remain byte-identical. The frozen design and building-state input copies match their recorded hashes. No production models, shared world/main files, commits or pushes were changed by this task.

Documentation fetched via Context7: Blender's [glTF exporter API](https://docs.blender.org/api/current/bpy.ops.export_scene.html), Godot's [command-line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html) and [scene instantiation](https://docs.godotengine.org/en/4.7/tutorials/scripting/nodes_and_scene_instances.html).
