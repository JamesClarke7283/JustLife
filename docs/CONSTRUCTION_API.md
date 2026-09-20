# Construction

`LifeBuildingState` is the canonical building data. A `kind="__construction"`, `version=2` record contains `revision`, `next_serial`, `levels`, `walls`, `floors`, `stairs`, `openings` and `roofs`. Each element has a stable ID and a floor level. Ground and upper walk surfaces are at Y=0.16 and Y=3.16 metres. Legacy wall/floor markers migrate into this representation, including the authored starter floor.

`LifeConstruction` renders these records and supplies previews and floor/support queries. `LifeLotNavigation` builds floor-aware walking routes; `LifeTraversal` owns stair admission, movement and landing clearance. Visual cutaway and view-level choices change presentation without deleting structural records or their navigation restrictions.

Use `LifeBuildTransactions.prepare(operation)` for a detached quote, then `commit(quote)` at confirmation. It rechecks the building revision, shared wallet, furnishings, actual actors, owned routes and food against current state. An old preview cannot spend money or apply geometry after its context changes. Rejection leaves the live building and simulation untouched. A successful edit updates the shared wallet immediately and records one history entry.

Structural operations cover rooms, walls, door openings, floors and straight stairs. A stair has fifteen 0.20m risers, a 3.75m run and 1.25m width, with a reserved upper opening, supported landings and original Juniper rails. Upper slabs require lower support and opposite bearing walls; edits cannot strand a resident or cut through an occupied stair route. Furnishing moves, sales and undo also preserve active destinations, waiting places and carried food.

A staircase's own rails need slab under their posts, but a wall standing in the rail's band is itself the barrier at that edge and does not refuse the placement: the run and both landings are still kept clear of every wall, so a stair may legitimately hug an upstairs wall rather than needing clear slab beside it. When no spot within the search radius can take a stair, the notice names the concrete cause — the run or a landing leaving the lot, having no floor beneath it, a wall or furnishing in the way, the opening needing clear slab for its rail, or a `Lifelet` using the space — instead of one general sentence. The search keeps the reason belonging to the nearest candidate it examined, so the message describes the spot under the pointer.

Roofs use `LifeRoofEdits`, `LifeRoofRules` and `LifeRoofGeometry`. A record controls the support rectangle, level, ridge direction, pitch and finish. Geometry repeats native Blender-authored tiles and trim, retaining 0.28m eaves and 0.10m deck thickness. Placement checks the complete envelope and actual furnishing bounds. The public pitch choices are 0.25, 0.5 and 0.75; only separate rectangular gables are supported.

The UI offers Ground/Upper, wall/room/door/erase, stair tools and New/Edit/Remove roof. Roof creation and replacement use two corners; R turns the ridge. Cancelling a replacement restores the original roof. New roof area costs ℒ18/m²; replacement charges or refunds the rounded area difference. Pitch, rotation and finish changes alone are free. Floor area costs ℒ12/m² and stairs cost ℒ650.

An upper-floor drag does not have to trace the walls exactly: the slab is fitted to the largest rectangle spanned by two complete opposite ground bearing walls and clipped to the drag and to the ground floor below, so one rough rectangle buys the whole storey. The Stairs tool then finds the nearest structurally valid spot within three metres of the click and quotes it through the same public transaction as a confirm, so a slightly misplaced click still lands one stair with its opening and supported guard. Pressing Upper with no slab starts the Floor tool automatically.

Build history is LIFO and shared with furnishing operations. Undo validates the former geometry against current physical constraints and refunds its recorded amount exactly once. History is cleared when leaving Build mode; it is not a persisted unlimited undo stack.

`world.serialize_items()` includes the canonical marker alongside furnishings. Saved household loads prepare the complete world and routes off-tree before adoption. See [SAVE_LIBRARY_API.md](SAVE_LIBRARY_API.md) for the load boundary and [HOUSEHOLD_API.md](HOUSEHOLD_API.md) for physical snapshots.

The lot a building is validated against is the household's own land, owned by `LifeLand` and read live through `LifeBuildingState.lot()`, so a house can be built on a plot bought next door. Every geometric bound — building rectangles, stairs, roofs, furnishings, the navigation region and the camera pan — moves with it. See [LAND_PROPERTY_VENUES.md](LAND_PROPERTY_VENUES.md).

Two rooms drawn side by side share the wall between them rather than stacking a second one on the same line, so the dividing wall can be broken to merge the rooms into one bigger space, or given a doorway. See `tests/test_room_extension.gd`.

Current limits: two levels, rectangular slabs, axis-aligned walls, straight stairs and separate gable roofs. Curved stairs, basements, terrain editing, intersecting roof junctions, valleys, dormers and a general structural-engineering simulation are not implemented.
