# Original JustLife oven

`oven.blend` is the current editable stove source. It replaces the earlier solid-door stove in `art/furniture.blend`. The accepted runtime export is `assets/models/stove.glb`; `oven_manifest.json` pins its authoring inputs and export.

Regenerate only this appliance from the project root:

```sh
blender -b --python tools/create_furniture.py -- --only stove --source-out art/furniture/oven.blend
```

The generator's default still rebuilds the full furniture collection. Use the command above when changing the oven alone. Production loads the exported GLB and does not require Blender.

The original enamel body contains a real dark cavity, support rails and a rack. `OvenDoor` is the lower hinge; its children include the window, handle and `OvenHandleGrip`. `OvenRackCarrier` holds the rack meshes, dish support anchor `OvenRack` and hand anchor `OvenRackGrip`. Godot moves the rack carrier 22 cm toward the front while the door is open. The appliance footprint and cooktop support height remain compatible with the existing room and furniture layout.

`scripts/oven_sequence.gd` evaluates the door, rack and dish positions from the current paid recipe's progress. The actor carries the dish during preparation and transfer; the world owns one noninteractive interior dish while baking. No separate oven timer or edible food batch exists before cooking finishes.

The static cavity/support check, continuous motion probes and public save/restart evidence are described in `docs/REVIEWS/iteration_16_oven.md`. Failed sculpt and motion studies remain local under `dist/game-work/`; they are not runtime assets. The supported silhouettes and conservative collision measurements do not establish clearance for every possible garment, hairstyle or body configuration.
