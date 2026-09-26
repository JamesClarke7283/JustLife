extends RefCounted
class_name LifeSchoolBus
## The morning school bus. It is not a furnishing left on the lot: on a school
## morning it drives in from off the lot, waits at the curb, and leaves once
## the children have boarded.

const CURB := Vector3(3.2, 0.16, 8.55)
const START := Vector3(24.0, 0.16, 8.55)
## Afternoon return comes from the west, the way the morning bus drove off.
const RETURN_START := Vector3(-20.0, 0.16, 8.55)
const SPEED := 12.0
const ARRIVE_MINUTE := 450.0
const LAST_BOARD := 540.0
## School lets out at 15:00. The bus is already on its way a few minutes before.
const RETURN_MINUTE := 890.0
const DROP_LAST := 940.0
const DROP_WAIT := 12.0

static var active: LifeSchoolBus

var phase: String = "gone"
var position: Vector3 = START
var expected: int = 0
var boarded: int = 0
var dwell: float = 0.0

static func clear_active() -> void:
	active = null


func due(weekday: bool, minutes: float, pupils: int) -> bool:
	return weekday and pupils > 0 and minutes >= ARRIVE_MINUTE and minutes < LAST_BOARD


func consider(weekday: bool, minutes: float, pupils: int) -> void:
	if phase != "gone":
		return
	if due(weekday, minutes, pupils):
		phase = "approaching"
		position = START
		expected = pupils
		boarded = 0
		dwell = 0.0
		return
	# The morning run has already left. Come back at the end of school and
	# wait at the same curb so the children step off where they boarded.
	if weekday and minutes >= RETURN_MINUTE and minutes < DROP_LAST:
		phase = "returning"
		position = RETURN_START
		expected = 0
		boarded = 0
		dwell = 0.0


func tick(game_minutes: float) -> void:
	if game_minutes <= 0.0 or phase == "gone":
		return
	var step: float = SPEED * game_minutes
	if phase == "approaching" or phase == "returning":
		position.x = move_toward(position.x, CURB.x, step)
		position.z = CURB.z
		if absf(position.x - CURB.x) <= 0.05:
			phase = "waiting" if phase == "approaching" else "dropping"
			position = CURB
			dwell = 0.0
	elif phase == "dropping":
		dwell += game_minutes
		if dwell >= DROP_WAIT:
			phase = "leaving"
	elif phase == "departing":
		position.x -= step
		if position.x < -16.0:
			phase = "gone"
			position = START
	elif phase == "leaving":
		position.x += step
		if position.x > START.x:
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
