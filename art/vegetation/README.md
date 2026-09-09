# Original JustLife field maples

Two original tree silhouettes replace the repeated ball crowns. The Blender source retains editable bough paths and unequal foliage fans in hidden SOURCE A/B collections. EXPORT A/B contain one connected trunk and one connected canopy each, with identity transforms and ground-contact origins. A is visible when opening the native file; unhide B's export meshes to inspect it. No reference pixels, meshes or textures are used in the artwork.

Generate into a fresh directory with Blender 5.2.1 LTS:

```sh
blender --background --factory-startup -t 4 --python-exit-code 2 \
  --python tools/create_vegetation.py -- --output-root /absolute/new/output
```

The generator reads no private files and refuses to overwrite its three artwork outputs. It writes native Blender data, two GLBs and an unqualified generation report. The reviewed manifest beside this README records the qualified artifacts and integration evidence. Preserve the tracked GLB import presets when regenerating models. A fresh native inspection can be run with:

```sh
blender --background --factory-startup -t 1 --python-exit-code 2 \
  --python tools/verify_vegetation.py -- \
  --source art/vegetation/field_maples.blend --out /absolute/new/native-check.json
```

Each GLB has two immediate MeshInstance3D children after Godot import: 740 trunk and 1,700 canopy triangles. Native Z-up maps to Godot Y-up. The existing placement and scale inputs are preserved; coordinate-derived variation and yaw consume no shared random draws. The existing camera-fade loop remains unchanged, including fading in Build mode and restoring opacity when live_enabled is false.

The tree() integration enables imported vertex colors only on the four materials owned by these two tree assets. Actual capture checks confirm no non-tree mesh or MultiMesh shares those material instances. Per-mesh import overrides disable generated LODs only for the two connected canopies. Branch LODs, optimized shadow meshes, normal shadow casting and default instance LOD bias remain enabled. Reduced canopy shadow detail previously cut jagged dark marks into the visible canopy; four controlled diagnostic frames isolated this interaction. The native surfaces were already closed, so the correction preserves every native and GLB byte.

Fresh independent generation reproduces both GLBs byte for byte. Read-only Blender checks match all recorded source facts across 26 objects and two materials; re-saved .blend containers differ. This verifies the documented object, geometry, color, UV, material and collection facts, not every Blender property or cross-version determinism. All four runtime meshes have consistent winding, positive volume and no boundary, nonmanifold or zero-area faces. Godot's canopy buffer order changes after the import override, but exact decoded vertex attributes and oriented triangle multisets remain identical without rounding or numeric tolerance; branch buffers and their seven LODs are byte-exact.

The six paired views use one exact runtime commit and one authored starter layout with literal stable wall IDs. All recorded non-tree controls, actors, lighting, camera, RNG and tree-root transforms match exactly: 684 checks, zero failures; baseline 2,144/0 and candidate 970/0. Direct venue setup and held poses are disclosed art fixtures, not travel or gameplay completion. The independent critic inspected all 12 images and verified all 40 frozen visual pins, accepting the incremental replacement. Root's release validation remains separate.

In held 1440×900 Home/park benchmarks on an RTX 5090, corrected trees used 335,893/163,475 reported frame primitives versus 336,033/165,767 for existing trees, and 3,896/1,663 draw calls versus 4,028/1,763. GPU rendering medians were 0.4065/0.292 ms versus 0.409/0.295 ms. CPU rendering medians were 3.8495/1.1665 ms versus 3.4785/1.1475 ms. These are sequential rendering measurements with fixed simulation, not low-end performance or a performance-win claim.

The crowns still have a soft sculpted appearance; the broad silhouette has an umbrella-like lower shelf. Garden planting is unchanged. This is an incremental art improvement, not a 10/10 game claim. Prior white-material, import-key/default-insertion, benchmark parse and unsuccessful raw-buffer comparison attempts remain recorded in the handoff. Blender logs retain cattrs and extension re-registration tracebacks, the unavailable optional MeshOptimizer bridge notice, and use_nodes deprecation; explicit generation/inspection commands nevertheless exited successfully and reproduced the qualified data. Godot qualification logs are clean.
