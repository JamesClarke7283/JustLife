extends RefCounted
class_name LifeSchoolBus
## The morning school bus. It is not a furnishing left on the lot: on a school
## morning it drives in from off the lot, waits at the curb, and leaves once
## the children have boarded.

const CURB := Vector3(3.2, 0.16, 8.55)
const START := Vector3(24.0, 0.16, 8.55)
const SPEED := 12.0
const ARRIVE_MINUTE := 450.0
const LAST_BOARD := 540.0

static var active: LifeSchoolBus

var phase: String = "gone"
var position: Vector3 = START
var expected: int = 0
var boarded: int = 0

static func clear_active() -> void:
	active = null


func due(weekday: bool, minutes: float, pupils: int) -> bool:
	return weekday and pupils > 0 and minutes >= ARRIVE_MINUTE and minutes < LAST_BOARD


func consider(weekday: bool, minutes: float, pupils: int) -> void:
	if phase != "gone":
		return
	if not due(weekday, minutes, pupils):
		return
	phase = "approaching"
	position = START
	expected = pupils
	boarded = 0


func tick(game_minutes: float) -> void:
	if game_minutes <= 0.0 or phase == "gone":
		return
	var step: float = SPEED * game_minutes
	if phase == "approaching":
		position.x = move_toward(position.x, CURB.x, step)
		position.z = CURB.z
		if absf(position.x - CURB.x) <= 0.05:
			phase = "waiting"
			position = CURB
	elif phase == "departing":
		position.x -= step
		if position.x < -16.0:
			phase = "gone"
			position = START


func waiting() -> bool:
	return phase == "waiting"


func off_lot(lot: Rect2) -> bool:
	return not lot.has_point(Vector2(position.x, position.z))


func note_boarded() -> void:
	boarded += 1
	if phase == "waiting" and boarded >= maxi(1, expected):
		phase = "departing"
