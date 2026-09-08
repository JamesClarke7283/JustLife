# JustLife garden supper props

Original editable artwork: cream ceramic with a muted teal glaze, toasted grains, roasted squash and tomato, carrots, zucchini, peas and basil. The grain bed has an irregular, lobed perimeter and tapers into the dish; individual grains and vegetables follow its uneven piled surface. Warm grain colors distinguish the food from the cream ceramic, and the fork uses a darker brushed-steel material. No third-party images, textures or models are used. Colors follow JustLife's existing furniture and celebration palette.

`garden_supper.blend` contains all three original models in the **JustLife Garden Supper — editable originals** collection. Vegetables, seeds, individual grains, ceramic profiles and fork pieces remain editable. The **Studio — excluded from exports** collection contains review lighting and camera. Scene root placement is for this review composition; exported game origins are canonical.

The portable generator is `tools/create_meal_props.py`, invoked from the project with `blender -b --python tools/create_meal_props.py`. It recreates the collection source, three GLBs and studio preview. It exports evaluated, batched geometry while keeping all original component meshes in the source. `art/.gdignore` excludes editable Blender sources and studio evidence from Godot's automatic import scan.

| GLB | Godot content node | Actual size, metres | Runtime meshes / material surfaces |
| --- | --- | --- | --- |
| `assets/models/meal_serving.glb` | `MealServing` | 0.499 wide × 0.081 high × 0.335 deep | 2 / 15 |
| `assets/models/meal_plate.glb` | `MealPlate` | 0.300 wide × 0.051 high × 0.300 deep | 2 / 15 |
| `assets/models/meal_fork.glb` | `MealFork` | 0.028 wide × 0.0058 thick × 0.198 long | 1 / 2 |

Godot adds its usual outer scene node (`meal_serving`, `meal_plate`, `meal_fork`). The named content nodes are beneath it. All GLBs are metre scale and **+Y up**.

## Food and table placement

Both dishes have an exact named `Food` child with one `FoodGeometry` mesh beneath it. Ceramic is a separate `DishGeometry` sibling. Hide `Food` at zero servings, or shrink its local Y scale to represent consumption; the food pivot sits at the food bed, at y=0.026 for the serving dish and y=0.015 for the plate. The ceramic remains unchanged. Both dishes have an actual bottom at y=0 for direct table placement.

Serving handles are open ceramic loops, with exact `GripLeft` and `GripRight` marker nodes at (-0.2395, 0.046, 0) and (0.2395, 0.046, 0). The plate has a `Grip` marker at (0, 0.009, 0). Root glTF extras also carry these coordinates, units, nominal serving count, and the food-node name.

## Fork contact contract

The fork handle grip is the origin. Its four separated tines point toward **Godot -Z**; **+Y** is the food-facing normal. Exact marker nodes:

- `Grip`: (0, 0, 0).
- `BitePoint`: (0, 0.003, -0.14).

The rounded tine geometry reaches z=-0.13971, within 0.3 mm of the bite marker. The handle extends to z=+0.058. Because its origin is at the grip centre, the fork's underside is y=-0.0014; use a 0.0015 m placement offset if laying it directly on a table. Its source is a short, forged, four-tine fork with a teal handle inlay, rather than a generic rod.

## Inspection

`studio/garden_supper_studio.png` is the generated, local three-prop studio view, rendered from the editable source at 1200×900, Cycles 48 samples. `tests/test_meal_props.gd` loads the actual imported GLBs and checks sizes, finite bounds, bottom contact, Food isolation, canonical marker names and fork axis. The asset review passed **23 checks, 0 failures**; the maintained test writes measured bounds to `user://meal_import_report.json`. Raw studio renders and reports are local evidence, excluded from Git.

The bounded mound/material refinement retains the original camera, lighting, ceramic geometry and grip markers. Blender completed all file writes and the matched render, then exited with a shutdown crash on this host. A fresh Blender process reopened the resulting editable source successfully with exit code 0 (`studio/blend_reopen.log`), and Godot reimported and verified all three final GLBs. Source, generator and export hashes match the final manifest.

In an isolated project without editor MCP services, import the project, then run `godot --headless --path . --script res://tests/test_meal_props.gd`. `manifest.json` pins the source, generator and exported GLB hashes. Production character geometry is unchanged; the meal gestures and connected gameplay are reviewed in `docs/REVIEWS/iteration_12_meals.md`.
