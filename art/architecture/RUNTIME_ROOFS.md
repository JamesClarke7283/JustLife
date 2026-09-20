# Parameterized roof integration

This private slice adds original rectangular gable roofs to the accepted Build editing slice. It does not complete upstairs movement, household persistence, or a finished two-storey home. The original Blender study and its static-art limitations remain recorded separately in `ROOF_KIT.md` and `roof_art_handoff.json`.

`LifeRoofGeometry` builds the chosen footprint, pitch, elevation and ridge direction from the record. It repeats the native tile mesh in `roof_gable_modules.glb`, rebuilds cropped edge tiles from the authored profile, and generates fitted decks, closed gables, rakes and ridge pieces. Fascia and oak-lip modules change only in length. It never stretches either dimensioned fixture GLB. The editable Blender source, three original GLBs and generator are unchanged from the art handoff.

The runtime retains the art contract: 0.28m full eaves, 0.10m normal deck thickness, original cream/oak trim and native tile thickness. Rotation 0 has its ridge along world Z; rotation 90 exchanges canonical span/length and applies one Y rotation. World height is the selected floor surface plus 2.6m. The public pitch choices are 0.25, 0.5 and 0.75; the validated record range remains 0.2–1.0. Sage uses four original tile shades. Slate recolors the tiles uniformly while retaining the original trim and dark ridge; it has no independent art-quality rating.

`LifeRoofRules` validates complete eave and height envelopes before purchase or world replacement. Separate roofs must remain clear of each other's envelopes. Upper slabs/walls cannot cut through a lower roof; neighboring walls must leave the overhang clear beyond the 8cm bearing band. Furniture uses the union of actual imported mesh bounds and its declared footprint/height. A furnishing wholly under the ridge can use the real slope clearance rather than the remote low eave height. Full gable infills still obstruct the ends above wall top. Actor clearance is rechecked at confirmation using a body footprint and displayed height. These are conservative building checks, not a continuous physical collision or structural-engineering system.

Build controls provide New roof, Edit roof and Remove roof. New roofs take two corners. Editing selects the existing roof, then two replacement corners; R changes ridge direction, while pitch/finish choices update the same preview. The existing roof is hidden while the replacement preview is shown and returns on cancellation. Preview validity, price and the rejection reason appear before confirmation. Roof view switches presentation only.

Roof area costs the existing ℒ18/m², rounded to whole currency. Replacement preserves the roof ID and charges or refunds the difference between the two rounded area prices; pitch, finish, rotation and translation alone are free. Demolition has no resale value. The detached quote is recomputed against current geometry, actors, food, furniture and wallet at confirmation. LIFO undo restores the validated former record and reverses its exact transaction once. Paid activities, later instructions, needs and clock are unchanged by building transactions.

The public engineering fixture begins with two bearing frames, a real refrigerator and the original resident/neighbors at their existing positions. It uses actual Build buttons, pointer corners, R/Esc, visible quotes and undo. Its bare walls are test scaffolding rather than a finished home design. World-node JSON controls reconstruct the roof and reject malformed ingress before replacing the old scene; they are not named household save/restart evidence. The inherited temporary upper-draft Live/save guard remains until the root controller/persistence integration replaces it.

## Reproduce in an isolated copy

Both runners create a fresh source snapshot, private userdata and source manifest. Set TMPDIR to an ignored work directory on a disk with room; no user editor or player saves are opened.

```sh
TMPDIR="$PWD/dist/test-work" python tools/run_roof_controls.py --source .
TMPDIR="$PWD/dist/test-work" python tools/run_roof_scene.py --source .
TMPDIR="$PWD/dist/test-work" python tests/run_playthrough.py --source . --suite roof_build
```

The first uses headless geometry/state and affected Build regressions. The second and third require the actual display and Forward+ renderer. New roof tests write only into the isolated source or private userdata. Preserve failed snapshots rather than rerunning into them.

## Scope limits

Only separate rectangular gables are supported. Intersecting roof junctions, valleys, dormers, attics and exposed-wall automatic cleanup are absent. No broad roof performance/LOD, weather enclosure, public second-floor roof journey, packaged household save or full-game quality claim is made. Hidden roofs retain their records and placement restrictions. The standalone world view tests do not advance or place an actor upstairs.

Current API references fetched through Context7: Godot 4.7 [ArrayMesh and clockwise front faces](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html), [MultiMesh instance transforms](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html), [polygon triangulation](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html), and [AABB transform direction](https://docs.godotengine.org/en/4.7/classes/class_aabb.html).
