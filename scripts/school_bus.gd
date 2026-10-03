extends RefCounted
class_name LifeSchoolBus
## The school bus. It is not a furnishing left on the lot. On a school morning
## it drives in from off the lot, waits at the curb and leaves once the pupils
## have boarded (or when boarding time is over). It stays away all school day,
## comes back once at the end of school to set the pupils down one at a time,
## and then drives off until the next school morning.

const CURB := Vector3(3.2, 0.16, 8.55)
const START := Vector3(24.0, 0.16, 8.55)
## Afternoon return comes from the west, the way the morning bus drove off.
const RETURN_START := Vector3(-20.0, 0.16, 8.55)
const SPEED := 12.0
const ARRIVE_MINUTE := 450.0
## Nobody is waited for after 09:00, unless a pupil is already walking out to it.
const LAST_BOARD := 540.0
## A pupil on the way to the door holds the bus no later than 09:20.
const BOARD_GRACE := 560.0
## School lets out at 15:00. The bus is already on its way a few minutes before.
const RETURN_MINUTE := 890.0
## A drop-off run is not started after 15:20, and an open one ends at 15:30.
const DROP_LAST := 920.0
const DROP_GIVE_UP := 930.0
## The doors stay open this long after the last pupil has stepped off.
const DROP_HOLD := 3.0
## Pupils step off one at a time, this many game minutes apart.
const STEP_OFF_GAP := 0.5

static var active: LifeSchoolBus

var phase: String = "gone"
var position: Vector3 = START
var expected: int = 0
var boarded: int = 0
var dwell: float = 0.0
var visual: Node3D
## The day the morning run began and the day the afternoon run began. Each is
## made once a day, so the bus never comes back for a second go.
var run_day: int = 0
var drop_day: int = 0
## Pupils still at school or still aboard on the way home, as last reported.
var at_school: int = 0
## Game minutes the curb has had nobody left aboard.
var clear_for: float = 0.0
## Pupils who have stepped off this drop-off, and the time since the last one.
var dropped: int = 0
var step_gap: float = 0.0
## Members riding home who have not stepped off yet (member id to true).
var aboard: Dictionary = {}

static func clear_active() -> void:
	active = null


func due(weekday: bool, minutes: float, pupils: int) -> bool:
	return weekday and pupils > 0 and minutes >= ARRIVE_MINUTE and minutes < LAST_BOARD


## `pupils` is the school-age members still at home to go today, `riders` those
## at school or still aboard on the way home, and `boarding` those walking out to
## the bus right now. `day` keeps each run to once a day.
func consider(weekday: bool, minutes: float, pupils: int, day: int = 1, riders: int = 0, boarding: int = 0) -> void:
	at_school = riders
	if phase == "waiting":
		# It leaves when everyone has boarded, nobody is left to go, boarding time
		# is over or the run belongs to an earlier day. A pupil already walking to
		# the door is waited for a little longer.
		var done: bool = boarded >= maxi(1, expected) or pupils <= 0 or minutes >= LAST_BOARD or not weekday or run_day != day
		if done and (boarding <= 0 or minutes >= BOARD_GRACE):
			phase = "departing"
		return
	if phase == "dropping":
		if riders > 0:
			clear_for = 0.0
		if minutes >= DROP_GIVE_UP:
			phase = "leaving"
		return
	if phase != "gone":
		return
	if run_day != day and due(weekday, minutes, pupils):
		run_day = day
		phase = "approaching"
		position = START
		expected = pupils
		boarded = 0
		dwell = 0.0
		return
	# The morning run has left. Come back once at the end of school, if anyone is
	# at school to bring home, and not again the same day.
	if weekday and drop_day != day and riders > 0 and minutes >= RETURN_MINUTE and minutes < DROP_LAST:
		drop_day = day
		run_day = day
		phase = "returning"
		position = RETURN_START
		expected = 0
		boarded = 0
		dwell = 0.0
		clear_for = 0.0
		dropped = 0
		step_gap = 0.0
		aboard.clear()


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
		step_gap += game_minutes
		# The doors close a little after the last pupil is off, not on a fixed timer.
		if at_school <= 0:
			clear_for += game_minutes
			if clear_for >= DROP_HOLD:
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


## Back to a bare street. A new household or a loaded game rebuilds the bus from
## the clock and the pupils' own away states, so none of this is saved.
func reset() -> void:
	phase = "gone"
	position = START
	expected = 0
	boarded = 0
	dwell = 0.0
	run_day = 0
	drop_day = 0
	at_school = 0
	clear_for = 0.0
	dropped = 0
	step_gap = 0.0
	aboard.clear()


## A member coming home from school asks to get off. "wait" while the bus is still
## on its way or the pupil ahead is still in the doorway, "off" when it is their
## turn (they appear at the bus's exit), and "walk" when no bus is bringing them,
## as with an early return or a drop-off that is already over.
func disembark(id: String) -> String:
	if phase == "returning":
		aboard[id] = true
		return "wait"
	if phase == "dropping":
		if dropped > 0 and step_gap < STEP_OFF_GAP:
			aboard[id] = true
			return "wait"
		aboard.erase(id)
		dropped += 1
		step_gap = 0.0
		clear_for = 0.0
		return "off"
	aboard.erase(id)
	return "walk"


## What the bus needs from the household each frame, as the three counts of
## consider(): school-age members at home still to go today, those at school or
## aboard on the way home, and those walking out to the bus right now.
func census(members: Array, day: int) -> Dictionary:
	var count: Dictionary = {"waiting": 0, "riders": 0, "boarding": 0}
	var riding: bool = phase == "returning" or phase == "dropping"
	for member: Dictionary in members:
		var sim: LifeSim = member.sim
		if str(sim.away_state.get("activity", "")) == "school":
			if str(sim.away_state.get("phase", "")) == "away" or (riding and aboard.has(str(member.id))):
				count.riders += 1
			continue
		if not sim.away_state.is_empty() or str(sim.character.get("age_stage", "")) not in LifeEducation.SCHOOL_STAGES:
			continue
		if int(sim.education.get("last_attendance_day", 0)) == day or day < int(sim.education.get("first_class_day", 0)):
			continue
		count.waiting += 1
		if str(sim.get_current_action().get("id", "")) == "board_school_bus":
			count.boarding += 1
	return count


## The live model owns the actual boarding and drop-off sockets. The fallback
## keeps non-rendered simulations and loading deterministic.
func door_position() -> Vector3:
	return _socket_position("DoorSocket", LifeSchoolBusVisual.DOOR_LOCAL)


func exit_position() -> Vector3:
	return _socket_position("ExitSpawnPoint", LifeSchoolBusVisual.EXIT_LOCAL)


func _socket_position(socket: String, local: Vector3) -> Vector3:
	if is_instance_valid(visual) and visual.is_inside_tree():
		return visual.get_node(socket).global_position
	var returning: bool = phase in ["returning", "dropping", "leaving"]
	local.z = absf(local.z) if returning else -absf(local.z)
	return position+local.rotated(Vector3.UP, PI if returning else 0.0)
