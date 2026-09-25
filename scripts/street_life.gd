extends RefCounted
class_name LifeStreetLife
## Children and pets who keep walking the lane in front of residential homes.
## Each passer turns around at the ends of the street and comes back, so the
## walk repeats instead of being a single appearance.

const LANE_Z := 8.15
const WEST := -10.0
const EAST := 10.0
const SPEED := 2.4

var passers: Array = []

func _init() -> void:
	passers = [
		{"id": "street_child_a", "kind": "child", "x": WEST, "dir": 1, "trips": 0, "passed_home": 0},
		{"id": "street_child_b", "kind": "child", "x": EAST, "dir": -1, "trips": 0, "passed_home": 0},
		{"id": "street_pet", "kind": "pet", "x": -4.0, "dir": 1, "trips": 0, "passed_home": 0},
	]


func tick(game_minutes: float) -> void:
	if game_minutes <= 0.0:
		return
	for passer: Dictionary in passers:
		var before: float = float(passer.x)
		passer.x = before + float(passer.dir) * SPEED * game_minutes
		if (before < 0.0 and float(passer.x) >= 0.0) or (before > 0.0 and float(passer.x) <= 0.0):
			passer.passed_home = int(passer.passed_home) + 1
		if float(passer.dir) > 0.0 and float(passer.x) >= EAST:
			passer.x = EAST
			passer.dir = -1
			passer.trips = int(passer.trips) + 1
		elif float(passer.dir) < 0.0 and float(passer.x) <= WEST:
			passer.x = WEST
			passer.dir = 1
			passer.trips = int(passer.trips) + 1


func position_of(passer: Dictionary) -> Vector3:
	return Vector3(float(passer.x), 0.16, LANE_Z)
