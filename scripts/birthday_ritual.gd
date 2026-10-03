extends RefCounted
class_name LifeBirthdayRitual
## Gathering round the cake: the pure rules of the birthday ritual.
##
## Every automatic birthday leaves a note that the household owes the birthday
## person a cake. When the home is calm, the family gathers round it, sings (a
## tune and a few bubbles; no words), the birthday person blows out the candles
## and everyone cheers. The household owns the note, the session and the save;
## this module names the actions, the timeline, the ring of standing spots and
## the checks. No nodes, no signals, no global randomness. The shape mirrors
## scripts/dance_plan.gd, the group form of a shared activity.
##
## Who comes first when several things want a Lifelet (the same order the
## homework and driving rules use): leaving for school or work, a booked driving
## lesson, the birthday ritual, a teen's homework, the player's own plans, then
## the Lifelet's own choices. So a birthday waits for the school or work run, and
## it does not wait for homework.

const SESSION_KIND: String = "birthday"
const TOKEN_PREFIX: String = "birthday_"
## The person whose birthday it is blows out the candles; everyone else sings.
const CELEBRANT_ACTION: String = "blow_candles"
const SINGER_ACTION: String = "sing_birthday"
const ROLE_CELEBRANT: String = "celebrant"
const ROLE_SINGER: String = "singer"
## What both actions are aimed at: the cake, whether on a table or in two hands.
const TARGET_KIND: String = "birthday_cake"

## Game minutes. At Normal speed one game minute is one second, so the sung part
## lasts as long as the tune: SING_END is the tune's seventeen seconds.
const DURATION: float = 26.0
const SING_END: float = 17.0
## The breath is drawn in the hush after the song and the flames go out here.
const BLOW_AT: float = 18.5
const CHEER_START: float = 19.5
## How long a gathering waits for everyone to arrive before it starts without the
## late ones, or gives up when the birthday person is not there yet.
const WAIT_LIMIT: float = 30.0
## Two people closer than this would stand in one body.
const MIN_SPACING: float = .55
## A birthday that could not be held is remembered this many days, then dropped.
const PENDING_DAYS: int = 2
## Nobody gathers for a cake in the small hours or late at night.
const WINDOW_OPEN: float = 420.0
const WINDOW_CLOSE: float = 1290.0
## A Lifelet who has to set off for school or work within this many minutes is not
## pulled into a cake.
const DUTY_MARGIN: float = 45.0
## A cancelled ritual is not started again straight away.
const RETRY_AFTER: float = 90.0
## At most this many birthdays are waiting at once (a household has eight members).
const MAX_PENDING: int = 8
## How far from the table a standing spot may be.
const MAX_SPOT_DISTANCE: float = 2.2
## The gap between a table's edge and the people round it.
const TABLE_MARGIN: float = .62

## Actions that a Lifelet in the middle of one of these is never pulled out of.
const BUSY_FRONTS: Array[String] = ["school_day", "career_day", "board_school_bus", "drive_to_work", "visit", "arrive_home", "driving_lesson", "sleep", "nap"]

## Original cheer lines. Not lyrics: greetings said after the song.
const CHEERS: Array[String] = ["Hooray!", "Happy birthday, %s!", "Make a wish!", "Well done, %s!", "Yay!"]
const WISH_LINES: Array[String] = ["Whoosh! Wish made.", "There. Wish made!", "I know what I wished for."]
const THANKS: String = "Thank you, everyone!"
const SING_BUBBLES: Array[String] = ["♪ ♫ ♪", "♫ ♪ ♫", "♪ ♪ ♫"]


static func fresh() -> Dictionary:
	return {"version": 1, "next_serial": 1, "pending": []}

## Whether this queued action belongs to the ritual.
static func owns(action: Dictionary) -> bool:
	return str(action.get("id", "")) in [CELEBRANT_ACTION, SINGER_ACTION]

## Which part of the ritual `elapsed` game minutes into it falls in.
static func phase_at(elapsed: float) -> String:
	if elapsed < SING_END: return "sing"
	if elapsed < BLOW_AT: return "hush"
	if elapsed < CHEER_START: return "blow"
	return "cheer"

## Whether the candles are still lit this far into the ritual.
static func candles_lit(elapsed: float) -> bool:
	return elapsed < BLOW_AT

## Whether the clock of the day allows a gathering.
static func window_open(minutes: float) -> bool:
	return minutes >= WINDOW_OPEN and minutes <= WINDOW_CLOSE

## The spots round a table, as offsets in the table's own space, on its floor.
## `half` is half the table top's width and depth. They are spread evenly along a
## ring a little way out from the table's edge. The first is in front of the table
## on a long side (where the birthday person stands) and the rest follow round it,
## so the caller can take the first few that turn out to be clear.
static func ring_slots(half: Vector2, count: int = 12) -> Array[Vector3]:
	var reach: Vector2 = half + Vector2.ONE * TABLE_MARGIN
	# Walk the ring in small steps, and put a slot down every ring-length / count.
	var samples: int = 360
	var track: Array[Vector2] = []
	var lengths: Array[float] = [0.0]
	var total: float = 0.0
	for step: int in samples + 1:
		var angle: float = TAU * float(step) / float(samples)
		track.append(Vector2(sin(angle) * reach.x, cos(angle) * reach.y))
		if step > 0:
			total += track[step].distance_to(track[step - 1])
			lengths.append(total)
	var slots: Array[Vector3] = []
	var cursor: int = 0
	for index: int in count:
		var wanted: float = total * float(index) / float(count)
		while cursor < samples and lengths[cursor + 1] < wanted: cursor += 1
		slots.append(Vector3(track[cursor].x, 0.0, track[cursor].y))
	return slots

## The spots round a held cake, as offsets from the birthday person: a ring of
## everyone else facing them. Nobody is placed behind the birthday person's
## back more than they are in front.
static func held_offsets(count: int) -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	if count <= 0: return offsets
	var radius: float = 1.0 + .07 * float(maxi(0, count - 3))
	for index: int in count:
		var angle: float = TAU * (float(index) + .5) / float(count)
		offsets.append(Vector3(sin(angle) * radius, 0.0, cos(angle) * radius))
	return offsets

## Whether the ids name a legal group: the birthday person first, at least them,
## no duplicates and every id a real member.
static func group_error(member_ids: Array, known_ids: Array) -> String:
	if member_ids.is_empty(): return "A birthday needs the birthday person."
	var unique: Array = []
	for id: Variant in member_ids:
		var member_id: String = str(id)
		if unique.has(member_id): return "A Lifelet cannot join the same cake twice."
		if not known_ids.has(member_id): return "That Lifelet is not part of this household."
		unique.append(member_id)
	if unique.size() > 8: return "There are not that many places round a cake."
	return ""

## Why this Lifelet cannot be pulled into the ritual now, or "" when they can.
## `facts` is a plain description of them, made by the household:
##   living, home (not away at school or work), in_session (already sharing an
##   activity), baby, front_id, front_active (the front action has begun),
##   front_by_player (the front action was chosen by the player), until_duty
##   (game minutes until they must set off for school or work; INF for never).
## A birthday never waits for homework, so nothing here looks at it.
static func member_error(facts: Dictionary) -> String:
	if not bool(facts.get("living", true)): return "has passed on"
	if bool(facts.get("baby", false)): return "is too small to sing"
	if not bool(facts.get("home", true)): return "is away from home"
	if bool(facts.get("in_session", false)): return "is already sharing an activity"
	var front: String = str(facts.get("front_id", ""))
	if front in BUSY_FRONTS: return "is busy"
	if float(facts.get("until_duty", INF)) <= DUTY_MARGIN: return "has to leave soon"
	if bool(facts.get("front_active", false)) and bool(facts.get("front_by_player", false)): return "is busy"
	return ""

## The same, as a plain yes or no.
static func eligible(facts: Dictionary) -> bool:
	return member_error(facts).is_empty()

## Whether a waiting birthday is too old to hold now.
static func expired(entry: Dictionary, today: int) -> bool:
	return today - int(entry.get("day", today)) > PENDING_DAYS

## The mood the birthday person is left with, and what each singer gets.
static func moodlet(role: String, singers: int) -> Dictionary:
	if role == ROLE_CELEBRANT:
		if singers >= 2: return {"label": "Best birthday ever", "emotion": "Happy", "description": "Everyone gathered round and sang.", "duration": 480.0, "strength": 3}
		return {"label": "Make a wish", "emotion": "Happy", "description": "A quiet cake and a wish.", "duration": 240.0, "strength": 2}
	return {"label": "Birthday wishes", "emotion": "Happy", "description": "Singing a birthday song with the family.", "duration": 240.0, "strength": 2}

## The friendship a song adds, in both directions, between the birthday person and
## each singer.
const FRIENDSHIP_GAIN: float = 4.0

## Whether a number from a save is a finite number in a range (and a whole one when asked).
static func _number(value: Variant, minimum: float, maximum: float, whole: bool = false) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)): return false
	if float(value) < minimum or float(value) > maximum: return false
	return not whole or float(value) == floorf(float(value))

## Whether a saved record of waiting birthdays can be believed. `data` is the
## household's save: its members, and its day. Nothing is adopted until this says "".
static func validate(value: Variant, data: Dictionary) -> String:
	if value == null: return ""
	if not value is Dictionary: return "Save contains an invalid birthday record."
	var record: Dictionary = value
	if not _number(record.get("version", 1), 1, 1, true): return "Save contains an unknown birthday record version."
	if not _number(record.get("next_serial", 1), 1, 1000000000, true): return "Save contains an invalid birthday counter."
	var pending: Variant = record.get("pending", [])
	if not pending is Array or pending.size() > MAX_PENDING: return "Save contains too many waiting birthdays."
	var states: Dictionary = {}
	for member: Variant in data.get("members", []):
		if member is Dictionary and member.get("id") is String and member.get("state") is Dictionary: states[str(member.id)] = member.state
	var today: int = int(data.get("day", 1))
	var seen: Array = []
	var serials: Array = []
	for entry: Variant in pending:
		if not entry is Dictionary: return "Save contains an invalid waiting birthday."
		for key: String in ["member_id", "from", "to"]:
			if not entry.get(key) is String: return "Save contains an invalid waiting birthday."
		var member_id: String = str(entry.member_id)
		if not states.has(member_id) or seen.has(member_id): return "Save contains a birthday for the wrong Lifelet."
		seen.append(member_id)
		if str(entry.from) not in LifeLifecycle.STAGES or LifeLifecycle.next_stage(str(entry.from)) != str(entry.to): return "Save contains a birthday that skips a life stage."
		var character: Variant = states[member_id].get("character", {})
		if not character is Dictionary or str(character.get("age_stage", "")) != str(entry.to) or str(character.get("life_status", "living")) != "living": return "Save contains a birthday that no longer matches the Lifelet."
		if not _number(entry.get("serial"), 1, float(record.get("next_serial", 1)) - 1.0, true) or serials.has(int(entry.serial)): return "Save contains a repeated or invalid birthday number."
		serials.append(int(entry.serial))
		if not _number(entry.get("day"), float(maxi(1, today - PENDING_DAYS)), float(today), true): return "Save contains an out-of-date waiting birthday."
		if not _number(entry.get("minutes"), 0.0, 1440.0): return "Save contains an invalid birthday time."
		if not _number(entry.get("party_serial", 0), 0, 1000000000, true): return "Save contains an invalid party number on a birthday."
		if entry.has("hold_until") and not _number(entry.hold_until, 0.0, 1000000000.0): return "Save contains an invalid birthday hold."
	return ""
