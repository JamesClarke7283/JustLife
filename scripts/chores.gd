extends RefCounted
## How dirty the home is. Nothing ticks: every zone remembers the game minute it was
## last cleaned, and its dirt is how far along its own period that is. A zone met for the
## first time (a new game, an older save, a freshly bought piece) is stamped "now", so
## the home always starts spotless rather than suddenly filthy.
##
## Zone keys are `<kind>:<scope>:<id>` (see `LifeChoreDefs`): `fvac:0:1:-2` is the
## vacuum patch of floor on level 0 at lattice cell (1, -2); `win_out:win_-425_-495`
## is the outside of a window. `toys` counts the toys a child has left out of a box.

const Defs = preload("res://scripts/chore_defs.gd")
const MAX_TOYS: int = 8
const SAVE_VERSION: int = 1

## key -> absolute game minute ((day - 1) * 1440 + minutes) of the last cleaning
var cleaned: Dictionary = {}
## toy container item id -> toys left out of it, 0..MAX_TOYS
var toys: Dictionary = {}
## member id -> game minute before which that Lifelet will not start cleaning unasked
var auto_next: Dictionary = {}
## key -> the dirt kind ("fvac", "win_out", ...) that gives it its period
var kinds: Dictionary = {}


## Absolute game minute from a day count and the minutes into it.
static func minute_of(day: int, minutes: float) -> float:
	return float(day - 1) * 1440.0 + minutes

## Percent dirty (0..100) of a zone of this kind that was cleaned at `since`.
static func dirt_percent(kind: String, since: float, now: float, factor: float = 1.0) -> float:
	var period: float = float(Defs.PERIOD.get(kind, 4.0)) * 1440.0 / maxf(.25, factor)
	return clampf(100.0 * (now - since) / period, 0.0, 100.0)

## Dirt of a keyed zone. A zone never seen is spotless.
func dirt(key: String, kind: String, now: float, factor: float = 1.0) -> float:
	if not cleaned.has(key): return 0.0
	return dirt_percent(kind, float(cleaned[key]), now, factor)

## Stamp a zone this has not seen. True when it was new.
func ensure(key: String, kind: String, now: float) -> bool:
	kinds[key] = kind
	if cleaned.has(key): return false
	cleaned[key] = now
	return true

## A zone has just been cleaned.
func clean(key: String, kind: String, now: float) -> void:
	kinds[key] = kind
	cleaned[key] = now

## Make a zone dirtier by `minutes` of its own period (never past fully dirty, never before the epoch).
func soil(key: String, minutes: float) -> void:
	if not cleaned.has(key): return
	cleaned[key] = float(cleaned[key]) - minutes

func toys_out(box_id: String) -> int:
	return int(toys.get(box_id, 0))

func add_toys(box_id: String, count: int) -> void:
	toys[box_id] = clampi(int(toys.get(box_id, 0)) + count, 0, MAX_TOYS)

func put_toys_away(box_id: String) -> void:
	toys.erase(box_id)

## Forget zones that no longer exist. `valid` is key -> true for what is still in the home.
func prune(valid: Dictionary) -> int:
	var removed: int = 0
	for key: Variant in cleaned.keys():
		if not valid.has(key):
			cleaned.erase(key); kinds.erase(key); removed += 1
	return removed

func reset() -> void:
	cleaned = {}; toys = {}; auto_next = {}; kinds = {}

func get_state() -> Dictionary:
	var stamps: Dictionary = {}
	for key: Variant in cleaned: stamps[str(key)] = float(cleaned[key])
	return {"version": SAVE_VERSION, "cleaned": stamps, "toys": toys.duplicate(true), "auto_next": auto_next.duplicate(true)}

## Take a saved record back. Anything missing or malformed leaves the home spotless.
func restore(data: Variant) -> void:
	reset()
	if not data is Dictionary: return
	var saved: Variant = data.get("cleaned", {})
	if saved is Dictionary:
		for key: Variant in saved:
			if Defs.key_valid(key) and (saved[key] is float or saved[key] is int) and is_finite(float(saved[key])): cleaned[str(key)] = float(saved[key])
	var box_counts: Variant = data.get("toys", {})
	if box_counts is Dictionary:
		for key: Variant in box_counts:
			if box_counts[key] is float or box_counts[key] is int: toys[str(key)] = clampi(int(box_counts[key]), 0, MAX_TOYS)
	var due: Variant = data.get("auto_next", {})
	if due is Dictionary:
		for key: Variant in due:
			if due[key] is float or due[key] is int: auto_next[str(key)] = float(due[key])

## Why a saved `chores` record cannot be taken, or "". `ids` is every item id and kind
## (id -> kind) the saved layout holds; `now` bounds the stamps.
static func validate(data: Variant, ids: Dictionary, now: float, members: Array) -> String:
	if data == null: return ""
	if not data is Dictionary: return "The saved cleaning record is invalid."
	if data.has("version") and (not (data.version is int or data.version is float) or int(data.version) != SAVE_VERSION): return "The saved cleaning record has an unknown version."
	var saved: Variant = data.get("cleaned", {})
	if not saved is Dictionary or saved.size() > Defs.MAX_KEYS: return "The saved cleaning stamps are invalid."
	for key: Variant in saved:
		if not Defs.key_valid(key): return "A saved cleaning stamp has an invalid name."
		var value: Variant = saved[key]
		if not (value is float or value is int) or not is_finite(float(value)): return "A saved cleaning stamp is not a time."
		if float(value) > now + 1.0 or float(value) < -2000000.0: return "A saved cleaning stamp lies in the future."
	var left_out: Variant = data.get("toys", {})
	if not left_out is Dictionary or left_out.size() > 256: return "The saved toys left out are invalid."
	for key: Variant in left_out:
		var count: Variant = left_out[key]
		if not key is String or not (count is float or count is int) or float(count) != floorf(float(count)) or float(count) < 0.0 or float(count) > MAX_TOYS: return "A saved toy count is impossible."
		if not ids.is_empty() and str(ids.get(str(key), "")) not in ["toybox", "toy_chest", "train_set", "baby_toys", "dollhouse"]: return "Saved toys left out refer to a missing toy box."
	var due: Variant = data.get("auto_next", {})
	if not due is Dictionary or due.size() > 16: return "The saved cleaning cooldowns are invalid."
	for key: Variant in due:
		if not key is String or not (due[key] is float or due[key] is int) or not is_finite(float(due[key])): return "A saved cleaning cooldown is invalid."
		if not members.is_empty() and str(key) not in members: return "A saved cleaning cooldown names a missing Lifelet."
	return ""
