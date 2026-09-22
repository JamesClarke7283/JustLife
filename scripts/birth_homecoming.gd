extends RefCounted
class_name LifeBirthHomecoming
## Hospital stay and welcome-home arrival after a birth.
##
## Pure rules: the household owns the live members and the save; this module
## describes the phase machine the phone and the lot cinematic drive.

const SAVE_VERSION: int = 1
const PHASE_HOSPITAL: String = "hospital"
const PHASE_PARTNER: String = "partner_choice"
const PHASE_READY: String = "ready_home"
const PHASE_ARRIVING: String = "arriving"
const PHASE_DONE: String = "done"

const DAD_SEND: String = "send"
const DAD_NOTIFY: String = "notify"

static func fresh() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"active": false,
		"phase": "",
		"mother_id": "",
		"father_id": "",
		"baby_id": "",
		"dad_choice": "",
		"arrival_started": false,
	}

static func begin(mother_id: String, father_id: String, baby_id: String) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"active": true,
		"phase": PHASE_PARTNER,
		"mother_id": str(mother_id),
		"father_id": str(father_id),
		"baby_id": str(baby_id),
		"dad_choice": "",
		"arrival_started": false,
	}

static func choose_dad(state: Dictionary, choice: String) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	if not bool(next.get("active", false)):
		return next
	var picked: String = str(choice)
	if picked != DAD_SEND and picked != DAD_NOTIFY:
		return next
	next["dad_choice"] = picked
	next["phase"] = PHASE_READY
	return next

static func start_arrival(state: Dictionary) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	if not bool(next.get("active", false)):
		return next
	if str(next.get("phase", "")) != PHASE_READY and str(next.get("phase", "")) != PHASE_ARRIVING:
		return next
	next["phase"] = PHASE_ARRIVING
	next["arrival_started"] = true
	return next

static func finish(state: Dictionary) -> Dictionary:
	var next: Dictionary = fresh()
	next["phase"] = PHASE_DONE
	return next

static func can_welcome(state: Dictionary) -> bool:
	return bool(state.get("active", false)) and str(state.get("phase", "")) == PHASE_READY

static func in_hospital(state: Dictionary) -> bool:
	if not bool(state.get("active", false)):
		return false
	return str(state.get("phase", "")) in [PHASE_HOSPITAL, PHASE_PARTNER, PHASE_READY, PHASE_ARRIVING]

static func party_ids(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key: String in ["mother_id", "baby_id"]:
		var id: String = str(state.get(key, ""))
		if not id.is_empty():
			ids.append(id)
	if str(state.get("dad_choice", "")) == DAD_SEND:
		var father: String = str(state.get("father_id", ""))
		if not father.is_empty():
			ids.append(father)
	return ids

static func validate(state: Dictionary) -> String:
	if state == null or state.is_empty():
		return ""
	if not bool(state.get("active", false)):
		return ""
	if int(state.get("version", 0)) != SAVE_VERSION:
		return "Birth homecoming version is unsupported."
	if str(state.get("phase", "")) not in [PHASE_HOSPITAL, PHASE_PARTNER, PHASE_READY, PHASE_ARRIVING, PHASE_DONE]:
		return "Birth homecoming phase is unknown."
	for key: String in ["mother_id", "father_id", "baby_id"]:
		if str(state.get(key, "")).is_empty():
			return "Birth homecoming is missing %s." % key
	return ""
