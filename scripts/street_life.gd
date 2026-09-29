extends RefCounted
class_name LifeStreetLife
## Neighbours of every age and their dogs who keep walking the sidewalk in front
## of residential homes. Each passer walks the lane, turns around at the ends of
## the street and comes back, so the walk repeats instead of being a single
## appearance. Passers keep to the right (eastbound on the street side,
## westbound on the house side), walk at the natural pace of their age
## (`LifePedestrianPace`) and are on the street only at the hours their kind of
## person would be: children between school runs, teens after school, adults at
## the start and end of the working day, elders through the middle of the day.
##
## A passer that a Lifelet is talking to is *held*: it stops where it stands
## until the conversation releases it, or a short safety timer runs out, and
## then resumes its lane at the same pace.

const LANE_Z := 8.15
const WEST := -10.0
const EAST := 10.0
## Lanes: the sidewalk is 7.9..9.1 m from the house; eastbound walkers use the
## street side, westbound the house side, each with a small personal offset.
const LANE_EAST := 8.8
const LANE_WEST := 8.3
## How quickly a passer drifts to the other lane after turning around.
const LANE_SHIFT := 0.5
## A held passer walks on by itself if nothing has renewed the hold for this
## many game minutes: no chat, cancel or save can strand somebody.
const HOLD_MINUTES := 3.0
## The dog on a lead trots this far ahead of its person.
const LEAD_LENGTH := 0.85
const CLEAR_AHEAD := 0.9
const CLEAR_ACROSS := 0.4
## How long a walker waits behind somebody standing in the way, in game minutes,
## before walking round them, and how far to the side that takes them.
const PATIENCE_MINUTES := 2.0
const DODGE_ACROSS := 0.55
const HEIGHT := 0.16

## The cast. Hours are [from, to) in hours of the day. `look` is a character
## profile (children and adults are styled like the resident neighbours) or, for
## a dog, its coat.
const ROSTER: Array = [
	{"id": "street_child_a", "kind": "child", "name": "Nia", "x": WEST, "dir": 1, "bias": 0.0, "hours": [[7.5, 19.5]],
		"look": {"frame": 0, "hair": 8, "outfit": 3, "bottom": 1, "skin_color": "8d5b3f", "hair_color": "1d1712", "eye_color": "49342b", "top_color": "e0a03b", "bottom_color": "4a6fa5", "shoe_color": "f0e8d6", "body_scale": 1.0, "height_scale": 1.0}},
	{"id": "street_child_b", "kind": "child", "name": "Theo", "x": EAST, "dir": -1, "bias": 0.14, "hours": [[7.5, 19.5]],
		"look": {"frame": 1, "hair": 0, "outfit": 4, "bottom": 1, "skin_color": "e7b98f", "hair_color": "89563a", "eye_color": "58758c", "top_color": "6f9d6a", "bottom_color": "39444f", "shoe_color": "ece4d5", "body_scale": 1.0, "height_scale": 1.0}},
	{"id": "street_pet", "kind": "pet", "name": "Biscuit", "x": -4.0, "dir": 1, "bias": -0.12, "hours": [[7.0, 20.0]],
		"look": {"species": "dog", "coat_color": "b8875a", "mark_color": "f1e3c8", "marking": "socks", "coat_length": "short"}},
	{"id": "street_teen", "kind": "teen", "name": "Kai", "x": -2.0, "dir": -1, "bias": -0.16, "hours": [[7.0, 8.75], [15.0, 21.5]],
		"look": {"frame": 1, "hair": 3, "outfit": 4, "bottom": 0, "skin_color": "c98d5f", "hair_color": "2e2620", "eye_color": "77805b", "top_color": "8f5bd6", "bottom_color": "2f3a55", "shoe_color": "f2f2f2", "body_scale": 1.0, "height_scale": 1.0}},
	{"id": "street_adult", "kind": "adult", "name": "Morgan", "x": 5.0, "dir": 1, "bias": 0.06, "hours": [[6.0, 9.5], [16.5, 21.0]],
		"look": {"frame": 0, "hair": 4, "outfit": 1, "bottom": 0, "skin_color": "b77e58", "hair_color": "3a2a20", "eye_color": "65452e", "top_color": "417a71", "bottom_color": "3c4a3a", "shoe_color": "573c37", "body_scale": 1.0, "height_scale": 1.0}},
	{"id": "street_walker_dog", "kind": "pet", "name": "Pip", "follows": "street_adult", "hours": [[6.0, 9.5], [16.5, 21.0]],
		"look": {"species": "dog", "coat_color": "3f3a36", "mark_color": "d8c9b1", "marking": "tuxedo", "coat_length": "medium"}},
	{"id": "street_elder", "kind": "elder", "name": "Mr Osei", "x": 7.0, "dir": -1, "bias": 0.0, "hours": [[9.5, 17.0]],
		"look": {"frame": 1, "hair": 5, "outfit": 2, "bottom": 0, "skin_color": "7a4e34", "hair_color": "c9c9c9", "eye_color": "49342b", "top_color": "a3554f", "bottom_color": "5a5a52", "shoe_color": "3b302c", "body_scale": 1.0, "height_scale": 1.0}},
]

var passers: Array = []
var _seeded: bool = false


func _init() -> void:
	passers = []
	for entry: Dictionary in ROSTER:
		var passer: Dictionary = entry.duplicate(true)
		var pace: String = pace_kind(passer)
		passer["pace"] = pace
		passer["speed"] = LifePedestrianPace.metres_per_second(pace)
		passer["stage"] = stage_of(passer)
		passer["trips"] = 0
		passer["passed_home"] = 0
		passer["active"] = true
		passer["hold_left"] = 0.0
		passer["holder"] = ""
		passer["waiting"] = false
		var leader: String = str(passer.get("follows", ""))
		if leader.is_empty():
			passer["lane"] = lane_for(passer)
		else:
			var walker: Dictionary = find(leader)
			passer["x"] = float(walker.get("x", 0.0))
			passer["dir"] = int(walker.get("dir", 1))
			passer["lane"] = float(walker.get("lane", LANE_WEST))
		passers.append(passer)
	# Followers copy their person's dir/x on the next tick; make that true now.
	_follow()


## Which pace table entry this passer walks at.
static func pace_kind(passer: Dictionary) -> String:
	return "dog" if str(passer.get("kind", "")) == "pet" else str(passer.get("kind", "adult"))


## The `age_stage` a passer's body is built at; dogs have none.
static func stage_of(passer: Dictionary) -> String:
	return "" if str(passer.get("kind", "")) == "pet" else str(passer.get("kind", "adult"))


static func lane_for(passer: Dictionary) -> float:
	return (LANE_EAST if int(passer.get("dir", 1)) > 0 else LANE_WEST) + float(passer.get("bias", 0.0))


func find(id: String) -> Dictionary:
	for passer: Dictionary in passers:
		if str(passer.id) == id:
			return passer
	return {}


## Passers on the street right now (off-duty ones are out of sight).
func visible_passers() -> Array:
	return passers.filter(func(passer: Dictionary) -> bool: return bool(passer.active))


func is_held(id: String) -> bool:
	var passer: Dictionary = find(id)
	return not passer.is_empty() and float(passer.hold_left) > 0.0


## Whether the kind of person is out at this time of day. A negative time means
## no clock is running (a probe or an old caller): everybody is out.
static func on_duty(passer: Dictionary, minutes: float) -> bool:
	if minutes < 0.0:
		return true
	var hour: float = minutes / 60.0
	for window: Array in passer.get("hours", []):
		if hour >= float(window[0]) and hour < float(window[1]):
			return true
	return false


## Stop a passer where they stand for a conversation. `holder` is the Lifelet
## talking to them. A dog on a lead holds its person too, and the reverse. The
## hold expires by itself unless somebody renews it.
func hold(id: String, holder: String, minutes: float = HOLD_MINUTES) -> bool:
	var passer: Dictionary = find(id)
	if passer.is_empty() or not bool(passer.active):
		return false
	for entry: Dictionary in _party(passer):
		entry["hold_left"] = maxf(float(entry.hold_left), minutes)
		entry["holder"] = holder
	return true


func release(id: String) -> void:
	var passer: Dictionary = find(id)
	if passer.is_empty():
		return
	for entry: Dictionary in _party(passer):
		entry["hold_left"] = 0.0
		entry["holder"] = ""


## The passer and the dog on their lead (or the person walking the dog): everybody
## a conversation with one of them stops.
func party_of(id: String) -> Array:
	var passer: Dictionary = find(id)
	return [] if passer.is_empty() else _party(passer)


## Everybody who moves as one: the passer and their dog on a lead.
func _party(passer: Dictionary) -> Array:
	var party: Array = [passer]
	var leader: String = str(passer.get("follows", ""))
	if not leader.is_empty():
		party.append(find(leader))
	else:
		for other: Dictionary in passers:
			if str(other.get("follows", "")) == str(passer.id):
				party.append(other)
	return party.filter(func(entry: Dictionary) -> bool: return not entry.is_empty())


## Advance every passer by `delta` real seconds at game speed `game_speed`.
## Distance walked uses the natural pace of their age and the same clock scale
## as their gait animation; hold timers count game minutes. `minutes` is the
## time of day (negative for none) and `obstacles` are body positions a walker
## waits behind instead of walking through.
func tick(delta: float, game_speed: float = 1.0, minutes: float = -1.0, obstacles: Array = []) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	# Seeded on the very first call, paused or not, so a paused load shows only the
	# people who are out at this hour and not the whole cast.
	if not _seeded:
		_seed(minutes)
	if game_speed <= 0.0:
		return
	var game_minutes: float = delta * game_speed * LifeSim.GAME_MINUTES_PER_SECOND
	var scale: float = LifePedestrianPace.clock_scale(game_speed)
	for passer: Dictionary in passers:
		passer["hold_left"] = maxf(0.0, float(passer.hold_left) - game_minutes)
		if float(passer.hold_left) <= 0.0:
			passer["holder"] = ""
	for passer: Dictionary in passers:
		if not str(passer.get("follows", "")).is_empty():
			continue
		var duty: bool = on_duty(passer, minutes)
		if not bool(passer.active):
			if duty and not _party_held(passer):
				_enter(passer)
			continue
		passer["waiting"] = false
		if float(passer.hold_left) > 0.0 or _party_held(passer):
			continue
		if _blocked(passer, obstacles):
			passer["waiting"] = true
			# Somebody standing in the way is waited behind for a little, then walked
			# round: a Lifelet idling on the sidewalk must not stop the street for good.
			passer["waited"] = float(passer.get("waited", 0.0)) + game_minutes
			if float(passer.waited) < PATIENCE_MINUTES:
				continue
			passer["waited"] = 0.0
			passer["waiting"] = false
			passer["past"] = CLEAR_AHEAD + .6
			passer["dodge"] = 1.0 if str(passer.id).hash() % 2 == 0 else -1.0
		else:
			passer["waited"] = 0.0
		_walk(passer, float(passer.speed) * delta * scale, duty)
	_follow()


func _party_held(passer: Dictionary) -> bool:
	for entry: Dictionary in _party(passer):
		if float(entry.hold_left) > 0.0:
			return true
	return false


## Start of the run: whoever is off duty waits at the far end, out of sight.
func _seed(minutes: float) -> void:
	_seeded = true
	for passer: Dictionary in passers:
		if not str(passer.get("follows", "")).is_empty():
			continue
		if not on_duty(passer, minutes):
			_park(passer)
	_follow()


func _park(passer: Dictionary) -> void:
	passer["active"] = false
	passer["x"] = EAST if float(passer.x) >= 0.0 else WEST
	passer["dir"] = -1 if float(passer.x) > 0.0 else 1
	passer["lane"] = lane_for(passer)


func _enter(passer: Dictionary) -> void:
	passer["active"] = true
	passer["x"] = EAST if float(passer.x) >= 0.0 else WEST
	passer["dir"] = -1 if float(passer.x) > 0.0 else 1
	passer["lane"] = lane_for(passer)


func _blocked(passer: Dictionary, obstacles: Array) -> bool:
	if float(passer.get("past", 0.0)) > 0.0:
		return false
	var at: Vector3 = position_of(passer)
	var dir: float = float(passer.dir)
	for body: Variant in obstacles:
		if not body is Vector3:
			continue
		var ahead: float = (float(body.x) - at.x) * dir
		if ahead > 0.0 and ahead < CLEAR_AHEAD and absf(float(body.z) - at.z) < CLEAR_ACROSS:
			return true
	return false


## Walk `distance` metres. The lane drifts toward the lane of the new direction
## while walking, and the forward speed shrinks by the sideways share, so the
## total ground speed stays the natural pace.
func _walk(passer: Dictionary, span: float, duty: bool) -> void:
	var before: float = float(passer.x)
	var target: float = lane_for(passer)
	# Walking round somebody: a step to the side while they are alongside.
	var past: float = float(passer.get("past", 0.0))
	if past > 0.0:
		target += float(passer.get("dodge", 1.0)) * DODGE_ACROSS
		passer["past"] = maxf(0.0, past - span)
	var lateral: float = clampf(target - float(passer.lane), -LANE_SHIFT * span / maxf(0.0001, float(passer.speed)), LANE_SHIFT * span / maxf(0.0001, float(passer.speed)))
	var forward: float = sqrt(maxf(0.0, span * span - lateral * lateral))
	passer["lane"] = float(passer.lane) + lateral
	passer["x"] = before + float(passer.dir) * forward
	if (before < 0.0 and float(passer.x) >= 0.0) or (before > 0.0 and float(passer.x) <= 0.0):
		passer["passed_home"] = int(passer.passed_home) + 1
	if float(passer.dir) > 0.0 and float(passer.x) >= EAST:
		passer["x"] = EAST
		passer["dir"] = -1
		passer["trips"] = int(passer.trips) + 1
		if not duty:
			_park(passer)
	elif float(passer.dir) < 0.0 and float(passer.x) <= WEST:
		passer["x"] = WEST
		passer["dir"] = 1
		passer["trips"] = int(passer.trips) + 1
		if not duty:
			_park(passer)


## Dogs on a lead trot just ahead of their person and share their lane.
func _follow() -> void:
	for passer: Dictionary in passers:
		var leader_id: String = str(passer.get("follows", ""))
		if leader_id.is_empty():
			continue
		var leader: Dictionary = find(leader_id)
		if leader.is_empty():
			continue
		passer["active"] = bool(leader.active)
		passer["dir"] = int(leader.dir)
		passer["x"] = float(leader.x) + float(leader.dir) * LEAD_LENGTH
		passer["lane"] = float(leader.lane) - 0.18 * float(leader.dir)
		passer["waiting"] = bool(leader.get("waiting", false))
		passer["trips"] = int(leader.trips)
		passer["passed_home"] = int(leader.passed_home)


func position_of(passer: Dictionary) -> Vector3:
	return Vector3(float(passer.x), HEIGHT, float(passer.get("lane", LANE_Z)))


## Where a body should face while walking: along the lane, bending slightly
## with the sideways drift when a lane change is under way.
func heading_of(passer: Dictionary) -> float:
	var target: float = lane_for(passer) if str(passer.get("follows", "")).is_empty() else float(passer.lane)
	var side: float = clampf(target - float(passer.lane), -0.4, 0.4)
	return atan2(float(passer.dir), side * 0.6)
