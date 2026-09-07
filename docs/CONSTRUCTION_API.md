# Construction

The house's original walls and new walls are editable `LifeConstruction` records. Its models and navigation share structural data, and tests independently inspect physical geometry for routing regressions.

- `world.begin_construction("wall"|"room"|"door"|"erase")` selects a tool. Walls and rooms use two clicks; doors and erase use one. `world.clear_placement()` cancels the tool.
- `world.construction_requested(data)` emits a validated proposal or an `error` message. Preview is green/red and snaps to a half-meter grid.
- A valid proposal includes `cost`, `walls`, optional `floors`, and optional `remove_id`. The UI checks funds and snapshots undo state before calling `world.construction.commit(data)`, then charges the quoted cost. Erasing refunds a portion of construction cost.
- Door openings split a wall into two actual segments. Rooms add floors which accept furnishings beyond the original footprint. Changes rebuild navigation.
- `world.serialize_items()` includes a `kind="__construction"` marker. `create_home()` automatically restores it. In-place undo needs to send this marker to `world.construction.restore()` and regular furnishings to `world.add_item()`.

Current limits: one story, rectangular floors, straight walls, and open doorways. Roofing, stairs and terrain editing remain future work.
