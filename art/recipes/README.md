# Original recipe artwork

`recipe_variants.blend` is the editable original source for herb garden pasta and harvest vegetable bake. Rebuild with Blender 5.2.1 LTS from the project root:

```sh
blender -b --python tools/create_recipe_props.py
```

The generator exports four metre-scaled, Y-up models: `meal_herb_pasta_serving.glb`, `meal_herb_pasta_plate.glb`, `meal_harvest_bake_serving.glb` and `meal_harvest_bake_plate.glb`. Each has separate `Food` and `DishGeometry` nodes, so consuming food leaves its ceramic intact. Serving dishes stay within 0.50 × 0.335 m and plates within 0.30 × 0.30 m, with underside Y=0. Serving grips are (±0.2395, 0.046, 0) and plate grip is (0, 0.009, 0). Existing garden skillet and fork assets are not replaced.

The pasta bowl uses one closed ceramic shell with teal exterior faces and cream interior/rim faces. The rejected overlapping inner bowl caused visible triangular patches in Godot. The bake now has deeper vegetable filling and one uneven browned surface rather than eight thin rectangular panels. All meshes and materials are authored for JustLife, without imported game assets.

Fresh verification of this exact source passed 32 Blender reopen checks and 42 actual Godot import checks. See `manifest.json` for source/export hashes and verification provenance. Reproduce with `tools/verify_recipe_source.py` in a fresh Blender process and `tools/verify_recipe_import.gd` after Godot import. The project must ignore `art/` with `art/.gdignore`: editable `.blend` files are authoring sources, and importing them headlessly requires an independently configured Blender path. The runtime uses exported GLBs. No user editor configuration is required or changed.

The matched studio preview is a local review artifact, excluded from the maintained asset set. The critic inspected the repaired props in the actual game world and rated pasta 7.5/10, bake 6.5/10, the batch about 7/10. The bake is still stylized and visibly constructed; these assets do not imply final character/game quality, photorealism, or 10/10. Recipe selection, ingredients, progression and runtime serving behavior belong to the game integration, not this generator.
