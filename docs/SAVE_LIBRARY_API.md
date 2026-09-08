# Named household saves

`LifeSaveLibrary` is a static backend in `scripts/save_library.gd`. It derives every filename from a slot ID, keeps managed saves in `user://saves`, and validates the household through `LifeHousehold.restore_state()` before saving or returning loaded data.

- `save_slot(id, name, state, preview: Image = null) -> Dictionary`: returns `{ok: true, id}` or `{ok: false, error}`. Empty ID creates a new slot; an existing ID overwrites that exact slot. Names are display text, limited to sixty characters. A successful save may include an optional `warning` if its display metadata or preview could not be updated.
- `list_saves() -> Array`: newest first, with `{id, name, saved_at, day, minutes, members, preview_path, valid, error}`. `saved_at` is an ISO UTC string. `members` contains Lifelet names. `preview_path` is a derived `user://` PNG path or an empty string. Corrupt saves remain listed with `valid: false`, so the UI can offer deletion while disabling load. Invalid optional metadata falls back to validated household details.
- `read_slot(id) -> Dictionary`: returns `{ok: true, data}` or `{ok: false, error}`. The controller passes `data` to its own `household.restore_state()` and restores world state from the result. Reading does not replace any live household.
- `latest_id() -> String`: returns the newest readable slot ID, or an empty string.
- `delete_slot(id) -> Dictionary`: removes that exact slot and its own fixed preview/temporary files, returning `{ok}` and an error on failure. The UI owns the user's confirmation step.

IDs are lowercase ASCII letters, digits, underscores or hyphens, at most sixty-four characters, beginning with a letter or digit. Traversal paths, separators, uppercase and empty read/delete IDs are rejected. Symbolic save directories and symbolic save files are rejected. Preview paths from metadata are ignored.

The managed JSON file contains `{save_library_version: 1, metadata, data}`. Household data is written to a temporary file, flushed, then atomically renamed over its destination. Files larger than eight MiB are rejected before reading/parsing or writing. Optional previews are resized to fit 640 × 640 and saved separately; preview failure does not undo a successful household save.

The fixed legacy `user://justlife_save.json` appears as slot `legacy` when present. It can be read, overwritten and deleted through the same API. Its household JSON remains in the older raw format; optional display metadata is stored in `user://saves/legacy.metadata.json`. This keeps compatibility with the earlier `LifeHousehold.load_game()` loader.

Household validation enforces canonical member IDs (`player`, then `housemate_1` through `housemate_7`), matching housemate relationship names, no self relationships, finite integer selection, and consistent shared wallet/clock/speed. Malformed data is rejected before the live household changes. Legacy single-Lifelet migration removes stale housemate references.

`tests/test_save_library.gd` covers eight-member saves, queued progress, actual PNG previews, simultaneous slots, generated IDs, malformed metadata/state, path rejection, size limits, symbolic files, precise deletion, legacy compatibility and household identity failures. Run the suite in an isolated test project without the editor MCP autoload. Tests preserve and restore the exact test filenames and legacy file they touch.
