extends RefCounted
class_name LifeBabyPlan
## "Try for Baby" and the pregnancy that follows it: pure rules only.
##
## The household owns the clock, the member list and the save; this module
## decides whether a pair may try, rolls the baby at conception and validates
## the stored state. No nodes, no signals, no global randomness.

const ACTION_ID: String = "try_for_baby"
const SESSION_KIND: String = "baby"
const TOKEN_PREFIX: String = "baby_"
const DURATION: float = 40.0
const PREGNANCY_DAYS: float = 14.0
const MINUTES_PER_DAY: float = 1440.0
const PREGNANCY_MINUTES: float = PREGNANCY_DAYS * MINUTES_PER_DAY
const SAVE_VERSION: int = 1
const MAX_BIRTHS: int = 8
const SLEEP_ACTIONS: Array[String] = ["sleep", "nap"]
## Sub-stages inside the baby age stage: newborn (swaddled), sitting (mat and
## rattle), then toddler (crawl, potty, dollhouse, desk). Day counts are from
## the birth day stored on the character.
const INFANT_NEWBORN: String = "newborn"
const INFANT_SITTING: String = "sitting"
const INFANT_TODDLER: String = "toddler"
const INFANT_SITTING_DAYS: int = 14
const INFANT_TODDLER_DAYS: int = 26

const FIRST_NAMES: Array[String] = ["Wren","Finley","Kit","Rowan","Sage","Remy","Jules","Noa","Alex","Robin","Avery","Marin"]
## A baby's surname is not drawn from a pool: it inherits the family's own name
## from its parents, so a child is never named after a stranger. See `surname_of`.
const SKIN_TONES: Array[String] = ["f2d1b1","e7b98f","d9a17d","b77e58","925c40","613e30"]
const HAIR_COLORS: Array[String] = ["2a2420","54382a","89563a","c2a16b","dfccb0","784e49"]
const EYE_COLORS: Array[String] = ["547365","55738f","704b36","b18d54","77797c"]
const TOP_COLORS: Array[String] = ["c97c66","417a71","efeadb","7195b3","bd9b68","3d4145"]
const BOTTOM_COLORS: Array[String] = ["eadfc9","3e5955","51697c","493e37","b88a72","292f32"]
const FACE_KEYS: Array[String] = ["face_round","jaw_strong","nose_wide","eye_spacing","nose_length","lip_fullness","brow_arch","chin_length","face_length","mouth_width","nose_bridge"]
const SIGNED_FACE_KEYS: Array[String] = ["nose_length","lip_fullness","brow_arch","chin_length","face_length","mouth_width","nose_bridge"]
const TRAIT_NAMES: Array[String] = ["Creative","Outgoing","Active","Bookworm","Foodie","Neat"]
const ASPIRATIONS: Array[String] = ["Maker","Connected","Successful","Balanced"]
## Styles the baby family authors (Crop, Bob, Curls). Longer styles are adult
## meshes the baby model does not carry, so they are never rolled or offered.
const BABY_HAIR_STYLES: Array[int] = [0,1,2]
const HAIR_STYLES: int = 8

static func fresh() -> Dictionary:
	return {"version":SAVE_VERSION,"active":false,"pending":false,"mother_id":"","father_id":"","conceived_at":0.0,"due_at":0.0,"serial":1,"baby":{}}

static func is_beat(action_id: String) -> bool:
	return action_id == ACTION_ID

static func session_kind(session: Dictionary) -> String:
	# Homework sessions predate the kind field; they are the default meaning.
	return str(session.get("kind","homework"))

## The gender a profile actually presents: an explicit choice when one was
## declared, otherwise the authored model frame (0 female, 1 male).
static func gender_of(profile: Dictionary) -> String:
	var declared:String = str(profile.get("gender","")).strip_edges().to_lower()
	if declared in ["male","female"]:
		return declared
	return "male" if int(profile.get("frame",0)) == 1 else "female"

static func frame_for(gender: String) -> int:
	return 1 if str(gender).to_lower() == "male" else 0

static func now_of(day: int, minutes: float) -> float:
	return float(day-1) * MINUTES_PER_DAY + float(minutes)

static func remaining_minutes(state: Dictionary, day: int, minutes: float) -> float:
	return maxf(0.0, float(state.get("due_at",0.0)) - now_of(day,minutes))

static func days_remaining(state: Dictionary, day: int, minutes: float) -> int:
	var left:float = remaining_minutes(state,day,minutes)
	return 0 if left <= 0.0 else ceili(left/MINUTES_PER_DAY)

static func countdown_text(state: Dictionary, day: int, minutes: float) -> String:
	var days:int = days_remaining(state,day,minutes)
	if days <= 0:
		return "Any moment now"
	return "About %d day%s to go" % [days,"" if days==1 else "s"]

## Early / mid / late against the shared pregnancy clock, so the HUD and bump
## agree on which stage the mother is in without inventing a second calendar.
static func pregnancy_stage(progress: float) -> String:
	var amount: float = clampf(progress, 0.0, 1.0)
	if amount < 0.34:
		return "early"
	if amount < 0.67:
		return "mid"
	return "late"

static func pregnancy_stage_label(progress: float) -> String:
	return {"early": "Early pregnancy", "mid": "Mid pregnancy", "late": "Late pregnancy"}.get(pregnancy_stage(progress), "Pregnancy")

## One status line for the Lifelet panel: stage plus days left until delivery.
static func pregnancy_status_text(state: Dictionary, day: int, minutes: float) -> String:
	if not bool(state.get("active", false)):
		return ""
	var total: float = PREGNANCY_MINUTES
	var progress: float = 0.0 if total <= 0.0 else clampf(1.0 - remaining_minutes(state, day, minutes) / total, 0.0, 1.0)
	return "%s · %s" % [pregnancy_stage_label(progress), countdown_text(state, day, minutes)]

static func expecting(state: Dictionary) -> bool:
	return bool(state.get("active",false)) or bool(state.get("pending",false))

static func due(state: Dictionary, day: int, minutes: float) -> bool:
	return bool(state.get("active",false)) and remaining_minutes(state,day,minutes) <= 0.0

## The last two days of the term: the mother is on maternity leave and cannot
## start a work shift. Days 13 and 14 of a fourteen-day pregnancy.
static func on_maternity_leave(state: Dictionary, day: int, minutes: float) -> bool:
	if not bool(state.get("active",false)):return false
	return remaining_minutes(state,day,minutes) <= 2.0 * MINUTES_PER_DAY

static func has_baby(members: Array) -> bool:
	for member:Dictionary in members:
		var sim:LifeSim = member.get("sim")
		if sim == null:
			continue
		if str(sim.character.get("age_stage","")) == "baby":
			return true
	return false

## Stamp a newborn with the infant phase clock the caregiver stage reads.
static func seed_infant(character: Dictionary, day: int) -> void:
	character["infant_phase"] = INFANT_NEWBORN
	character["infant_born_day"] = int(day)

## Resolve the infant sub-stage from days since birth. Callers stamp the result
## back onto the character so HUD, actions and the actor pose agree.
static func infant_phase_for(character: Dictionary, day: int) -> String:
	if str(character.get("age_stage","")) != "baby":
		return ""
	var born: int = int(character.get("infant_born_day", day))
	var age_days: int = maxi(0, int(day) - born)
	if age_days >= INFANT_TODDLER_DAYS:
		return INFANT_TODDLER
	if age_days >= INFANT_SITTING_DAYS:
		return INFANT_SITTING
	return INFANT_NEWBORN

static func advance_infant_phase(character: Dictionary, day: int) -> String:
	var phase: String = infant_phase_for(character, day)
	if phase.is_empty():
		return ""
	if not character.has("infant_born_day"):
		seed_infant(character, day)
		phase = INFANT_NEWBORN
	character["infant_phase"] = phase
	return phase

static func sleeping_in(sim: LifeSim, bed_id: String) -> bool:
	var action:Dictionary = sim.get_current_action()
	if action.is_empty() or str(action.get("id","")) not in SLEEP_ACTIONS:
		return false
	return str(action.get("target_id","")) == bed_id and str(action.get("phase","")) == "active"

## The single refusal path for the whole feature. Empty means the pair may try.
static func try_error(sim: LifeSim, bed_id: String, members: Array, pregnancy: Dictionary) -> String:
	if sim == null or str(sim.character.get("life_stage","adult")) != "adult":
		return "Only an adult Lifelet can try for a baby."
	var partner_id:String = str(sim.romantic_partner)
	var partner:LifeSim = null
	for member:Dictionary in members:
		if str(member.get("id","")) == partner_id:
			partner = member.get("sim")
	var mine:String = _member_id_of(sim,members)
	if partner_id.is_empty() or partner == null or partner == sim or mine.is_empty():
		return "Try for Baby needs your household partner."
	if str(partner.romantic_partner) != mine:
		return "Try for Baby needs your household partner."
	if str(partner.character.get("life_stage","adult")) != "adult":
		return "Try for Baby needs two adults."
	if gender_of(sim.character) == gender_of(partner.character):
		return "Try for Baby needs a male and a female partner."
	if not sleeping_in(sim,bed_id) or not sleeping_in(partner,bed_id):
		return "Both partners must be asleep in the same bed first."
	if bool(pregnancy.get("active",false)):
		return "Your household is already expecting a baby."
	if has_baby(members):
		return "Your household already has a baby."
	if members.size() >= LifeHousehold.MAX_MEMBERS:
		return "Your household already has eight Lifelets."
	if str(bed_id).is_empty():
		return "Choose the bed both partners are sleeping in."
	return ""

static func _member_id_of(sim: LifeSim, members: Array) -> String:
	for member:Dictionary in members:
		if member.get("sim") == sim:
			return str(member.get("id",""))
	return ""

static func mother_of(a: LifeSim, a_id: String, b: LifeSim, b_id: String) -> Array:
	# The female partner carries the pregnancy; the pair is opposite-gender by
	# the time this is called.
	if gender_of(a.character) == "female":
		return [a_id,b_id]
	return [b_id,a_id]

## Decide the baby at conception, exactly once. Appearance leans on the
## parents and the rest is a seeded, reproducible roll of the creator palette.
static func surname_of(profile: Dictionary) -> String:
	# A Lifelet's surname is the last word of their own name. The household has no
	# separate family-name field, so the parents' names are what the child inherits
	# from: a baby shares the family name rather than drawing a stranger's.
	var parts:PackedStringArray=str(profile.get("name","")).strip_edges().split(" ",false)
	return str(parts[parts.size()-1]) if parts.size()>1 else ""

static func roll(mother: Dictionary, father: Dictionary, serial: int) -> Dictionary:
	var rng:=RandomNumberGenerator.new()
	rng.seed = abs(str(mother.get("name","Mother")).hash()*31 + str(father.get("name","Father")).hash()*17 + clampi(serial,1,1000000)*7919)
	var male:bool = rng.randi()%2 == 0
	var gender:String = "male" if male else "female"
	var skin:String = _inherit([mother,father],rng,SKIN_TONES,"skin_color")
	var hair_color:String = _inherit([mother,father],rng,HAIR_COLORS,"hair_color")
	var eye:String = _inherit([mother,father],rng,EYE_COLORS,"eye_color")
	var top:String = _inherit([mother,father],rng,TOP_COLORS,"top_color")
	var bottom:String = _inherit([mother,father],rng,BOTTOM_COLORS,"bottom_color")
	var aspiration:String = str([mother,father][rng.randi()%2].get("aspiration","Balanced"))
	if not aspiration in ASPIRATIONS:
		aspiration = "Balanced"
	# The child takes the mother's surname first — she is the primary parent of
	# the pregnancy — then the father's, so a single-parent household still names
	# the baby after its family rather than after nobody.
	var family:String = surname_of(mother)
	if family.is_empty():family = surname_of(father)
	var first:String = FIRST_NAMES[rng.randi()%FIRST_NAMES.size()]
	var profile:Dictionary = {
		"name": (first+" "+family) if not family.is_empty() else first,
		"age_stage":"baby", "life_stage":"minor", "gender":gender, "frame":frame_for(gender),
		"hair": BABY_HAIR_STYLES[rng.randi()%BABY_HAIR_STYLES.size()], "skin_color":skin, "hair_color":hair_color, "eye_color":eye,
		"top_color":top, "bottom_color":bottom, "outfit":0, "bottom":0,
		"body_scale":1.0, "height_scale":1.0, "traits":[], "aspiration":aspiration
	}
	for key:String in FACE_KEYS:
		profile[key] = snappedf(rng.randf_range(-.65,.65) if key in SIGNED_FACE_KEYS else rng.randf_range(0.0,0.75),0.01)
	return profile

static func _inherit(parents: Array, rng: RandomNumberGenerator, palette: Array[String], key: String) -> String:
	for parent:Dictionary in parents:
		if rng.randf() < 0.45:
			var value:Variant = parent.get(key)
			# Creator palettes may expand without changing family resemblance.
			# Validate the actual value before converting it: numeric or object
			# lookalikes must not become acceptable colour strings through a cast.
			if _color(value):
				return str(value)
	return palette[rng.randi()%palette.size()]

## Conception state for the household. The baby profile is stored immediately
## (hidden from play) so a save taken mid-pregnancy restores the same child.
static func conceive(mother: LifeSim, mother_id: String, father: LifeSim, father_id: String, day: int, minutes: float, serial: int) -> Dictionary:
	var state:Dictionary = fresh()
	state.active = true
	state.mother_id = mother_id
	state.father_id = father_id
	state.serial = clampi(serial,1,MAX_BIRTHS)
	state.conceived_at = now_of(day,minutes)
	state.due_at = float(state.conceived_at) + PREGNANCY_MINUTES
	state.baby = roll(mother.character,father.character,int(state.serial))
	return state

## The birth resolves into a pending baby: the rolled child waits for the
## player to name it in the creator. due_at becomes the moment of birth.
static func resolve_birth(state: Dictionary, day: int, minutes: float) -> Dictionary:
	var settled:Dictionary = state.duplicate(true)
	settled.active = false
	settled.pending = true
	settled.due_at = now_of(day,minutes)
	return settled

static func pending_birth(state: Dictionary, day: int, minutes: float) -> Dictionary:
	var baby:Dictionary = state.get("baby",{}).duplicate(true)
	if str(baby.get("age_stage","")) != "baby":
		baby = roll({},{},int(state.get("serial",1)))
		baby.age_stage = "baby"
		baby.life_stage = "minor"
	return {"mother_id":str(state.get("mother_id","")),"father_id":str(state.get("father_id","")),"day":day,"minutes":minutes,"serial":int(state.get("serial",1)),"baby":baby}

static func profile_error(profile: Variant) -> String:
	if not profile is Dictionary:
		return "Save contains an invalid baby."
	var baby:Dictionary = profile
	if not baby.get("name") is String or str(baby.name).strip_edges().is_empty() or str(baby.name).length() > 48:
		return "Save contains an invalid baby name."
	if str(baby.get("age_stage","")) != "baby" or str(baby.get("life_stage","")) != "minor":
		return "Save contains a baby of the wrong age stage."
	if not _whole(baby.get("frame"),0,1) or not _whole(baby.get("hair"),0,HAIR_STYLES-1) or not _whole(baby.get("outfit"),0,4) or not _whole(baby.get("bottom"),0,1):
		return "Save contains invalid baby styling."
	# The baby model authors three hairstyles and one romper: a profile may not
	# record a style the model would silently substitute at load.
	if not int(baby.get("hair",0)) in BABY_HAIR_STYLES:
		return "Save contains a baby hairstyle the model does not have."
	if int(baby.get("outfit",0))!=0 or int(baby.get("bottom",0))!=0:
		return "Save contains baby clothing the model does not have."
	for key:String in ["skin_color","hair_color","eye_color","top_color","bottom_color"]:
		if not _color(baby.get(key)):
			return "Save contains an invalid baby colour."
	for key:String in FACE_KEYS:
		# Missing optional features remain neutral in saves predating the sculpted
		# nose/lip/brow/chin controls; their negative half is an authored shape.
		if not _number(baby.get(key,0.0),-1.0 if key in SIGNED_FACE_KEYS else 0.0,1.0):
			return "Save contains an invalid baby face."
	if not _number(baby.get("body_scale",1.0),0.85,1.15) or not _number(baby.get("height_scale",1.0),0.93,1.08):
		return "Save contains an invalid baby build."
	if not baby.get("traits") is Array or baby.traits.size() > 3:
		return "Save contains invalid baby traits."
	for entry:Variant in baby.traits:
		if not entry is String or str(entry) not in TRAIT_NAMES:
			return "Save contains an invalid baby trait."
	if str(baby.get("aspiration","")) not in ASPIRATIONS:
		return "Save contains an invalid baby aspiration."
	if baby.has("gender") and str(baby.gender).to_lower() not in ["male","female"]:
		return "Save contains an invalid baby gender."
	return ""

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value,float(low),float(high)) and float(value) == floorf(float(value))

static func _color(value: Variant) -> bool:
	if not value is String:
		return false
	var hex:String = str(value).trim_prefix("#").to_lower()
	if hex.length() not in [6,8]:
		return false
	for character:String in hex:
		if character not in "0123456789abcdef":
			return false
	return true

static func validate(value: Variant, data: Dictionary) -> String:
	# A household without the field is an older save: no pregnancy, no pending birth.
	if value == null:
		return ""
	if not value is Dictionary:
		return "Save contains invalid pregnancy data."
	var state:Dictionary = value
	for key:String in state:
		if key not in ["version","active","pending","mother_id","father_id","conceived_at","due_at","serial","baby"]:
			return "Save contains an unknown pregnancy field."
	if not _whole(state.get("version"),SAVE_VERSION,SAVE_VERSION) or not _whole(state.get("serial"),1,MAX_BIRTHS) or not state.get("active") is bool or not state.get("pending") is bool:
		return "Save contains an invalid pregnancy record."
	if bool(state.active) and bool(state.pending):
		return "Save holds a pregnancy that has also already given birth."
	for key:String in ["conceived_at","due_at"]:
		if not _number(state.get(key,0.0),0.0,1000000000.0):
			return "Save contains an invalid pregnancy date."
	if not state.get("mother_id") is String or not state.get("father_id") is String or not state.get("baby") is Dictionary:
		return "Save contains invalid pregnancy identities."
	var by_id:Dictionary = {}
	for entry:Dictionary in data.get("members",[]):
		if entry is Dictionary:
			by_id[str(entry.get("id",""))] = entry
	var now:float = now_of(int(data.get("day",1)),float(data.get("minutes",0.0)))
	if not bool(state.active) and not bool(state.pending):
		if not str(state.mother_id).is_empty() or not str(state.father_id).is_empty() or not state.baby.is_empty() or float(state.conceived_at) != 0.0 or float(state.due_at) != 0.0:
			return "Save contains an inactive pregnancy with leftover details."
		return ""
	if not by_id.has(str(state.mother_id)) or not by_id.has(str(state.father_id)) or state.mother_id == state.father_id:
		return "Save makes a pregnancy without its two household parents."
	if LifeLifecycle.eligibility(LifeLifecycle.stage_for(by_id[str(state.mother_id)].state.character)) != "adult" or LifeLifecycle.eligibility(LifeLifecycle.stage_for(by_id[str(state.father_id)].state.character)) != "adult":
		return "Save makes a pregnancy without two adult parents."
	if float(state.conceived_at) > now + .001:
		return "Save contains a pregnancy conceived in the future."
	if bool(state.active):
		# `due_at` is `conceived_at + term` in floating point, so subtracting a
		# fractional conception minute back out need not give the term exactly.
		if absf(float(state.due_at) - float(state.conceived_at) - PREGNANCY_MINUTES) > .001:
			return "Save contains an impossible pregnancy term."
		if float(state.due_at) < now - .001:
			return "Save holds a pregnancy past its due date without a birth."
	else:
		if float(state.due_at) < float(state.conceived_at) or float(state.due_at) > now + .001:
			return "Save contains a birth at an impossible moment."
	var error:String = profile_error(state.baby)
	if not error.is_empty():
		return error
	# The conception roll took the household's next birth serial, which was
	# advanced at the same moment (clamped at MAX_BIRTHS). A live pregnancy
	# therefore claims `mini(serial+1, MAX_BIRTHS)` — for the eighth birth the
	# counter stays equal to the pregnancy serial rather than climbing past it.
	var next_serial: int = mini(int(state.serial) + 1, MAX_BIRTHS)
	if int(data.get("birth_serial", 1)) != next_serial:
		return "Save contains a pregnancy that disagrees with its birth counter."
	return ""

static func validate_pending(value: Variant, data: Dictionary, pregnancy: Dictionary) -> String:
	# The birth moment is stored in the same record, so a pending birth is just
	# the pregnancy past its due date. The rolled baby has not changed.
	if not bool(pregnancy.get("pending",false)):
		return ""
	if bool(pregnancy.get("active",false)):
		return "Save holds a pending birth while a pregnancy is still running."
	var now:float = now_of(int(data.get("day",1)),float(data.get("minutes",0.0)))
	if float(pregnancy.get("due_at",0.0)) > now + .001:
		return "Save contains a pending birth from the future."
	if float(pregnancy.get("due_at",0.0)) < float(pregnancy.get("conceived_at",0.0)):
		return "Save contains a birth before its conception."
	return ""
