# Original JustLife architecture

The Juniper stair, landing rails and sage gable roof kit are original Blender artwork used by the two-storey home system. The editable files are `juniper_stair.blend`, `juniper_guardrails.blend` and `justlife_roof_kit.blend`. Runtime uses the four GLBs listed in `publication_manifest.json`; source scenes, previews and studio objects are excluded from Godot import by `art/.gdignore`.

The stair rises 3m along local +Z, with fifteen 0.20m risers, 0.25m going and a 1.25m overall width. Its lower-front origin is relative to the selected floor datum; add the world height once. The source preserves 107 editable parts and 19 surface/landing markers; the runtime asset batches them into five material meshes. The rail kit uses separate posts and spans so a shared corner needs one post.

The roof kit provides native tile and trim modules. `LifeRoofGeometry` repeats or crops these parts and rebuilds decks, gables and ridges for the chosen dimensions. It does not stretch the dimensioned study roofs. Geometry and palette details are in `roof_geometry_contract.json`; supported gameplay and current limits are in [Construction](../../docs/CONSTRUCTION_API.md).

Generators live in `tools/create_stair.py`, `tools/create_guardrails.py` and `tools/create_roof_kit.py`. Run Blender generators in a separate source copy: they overwrite the corresponding authored/export files, and the roof generator also produces two optional whole-roof study GLBs. Those study exports are not runtime dependencies. Regenerating does not update the publication manifest or qualify a new asset automatically.

The original static studies were reviewed at about 7.5/10 for their limited art scope. Thin rail shadows, terminal-post detailing and overall character/environment polish remain open; that rating does not certify the entire game. The historical notes in GUARDRAILS.md and ROOF_KIT.md record the original studies and their limitations. Their private evidence paths are historical references, not required release inputs.
