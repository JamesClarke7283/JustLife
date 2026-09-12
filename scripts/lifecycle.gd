extends RefCounted
class_name LifeLifecycle
## Progress is a fraction of a stage, so changing lifespan preserves age.

const STAGES: Array[String] = ["baby", "child", "teen", "young_adult", "adult", "elder"]
const LABELS: Dictionary = {"baby":"Baby", "child":"Child", "teen":"Teen", "young_adult":"Young adult", "adult":"Adult", "elder":"Elder", "unknown":"Age unspecified"}
const NORMAL_DAYS: Dictionary = {"baby":7, "child":14, "teen":21, "young_adult":28, "adult":42, "elder":28}
const SPANS: Dictionary = {"short":0.5, "normal":1.0, "long":4.0}

static func stage_for(profile: Dictionary) -> String:
	if profile.has("age_stage"):
		return str(profile.age_stage) if str(profile.age_stage) in STAGES else "unknown"
	match str(profile.get("life_stage", "adult")):
		"minor": return "teen"
		"adult": return "young_adult"
	return "unknown"

static func eligibility(stage: String) -> String:
	if stage in ["baby", "child", "teen"]: return "minor"
	if stage in ["young_adult", "adult", "elder"]: return "adult"
	return "unknown"

static func fresh() -> Dictionary:
	return {"progress":0.0, "lifespan":"normal", "auto_age":true, "history":[]}

static func duration(stage: String, lifespan: String) -> float:
	return float(NORMAL_DAYS.get(stage, 28)) * float(SPANS.get(lifespan, 1.0))

static func next_stage(stage: String) -> String:
	var index: int = STAGES.find(stage)
	return STAGES[index + 1] if index >= 0 and index < STAGES.size() - 1 else ""

static func with_article(stage: String) -> String:
	var label: String = str(LABELS.get(stage, "Lifelet")).to_lower()
	return ("an " if stage in ["adult", "elder"] else "a ") + label

static func description(stage: String, state: Dictionary) -> String:
	if stage == "unknown": return "Age unspecified"
	if stage == "elder": return "Elder · enjoying the golden years"
	if not bool(state.auto_age): return "%s · aging paused" % LABELS[stage]
	var days_left: int = ceili(maxf(0.0, 1.0 - float(state.progress)) * duration(stage, str(state.lifespan)))
	return "%s · birthday in %d %s" % [LABELS[stage], days_left, "day" if days_left == 1 else "days"]

static func validate(profile: Dictionary, state: Variant) -> String:
	var stage: String = stage_for(profile)
	if profile.has("age_stage") and str(profile.age_stage) not in STAGES and str(profile.age_stage) != "unknown":
		return "Save contains an invalid age stage."
	if profile.has("age_stage") and eligibility(stage) != str(profile.get("life_stage", "adult")):
		return "Save contains inconsistent age information."
	if not state is Dictionary: return "Save contains invalid aging data."
	var progress: Variant = state.get("progress")
	if not (progress is float or progress is int) or not is_finite(float(progress)) or float(progress) < 0.0 or float(progress) > 1.0:
		return "Save contains invalid age progress."
	if str(state.get("lifespan", "")) not in SPANS or not state.get("auto_age") is bool:
		return "Save contains invalid aging settings."
	if not state.get("history") is Array or state.history.size() > 8: return "Save contains invalid birthday history."
	var previous_day: int = 0
	var previous_stage: String = ""
	for entry: Variant in state.history:
		if not entry is Dictionary or str(entry.get("from", "")) not in STAGES or str(entry.get("to", "")) != next_stage(str(entry.get("from", ""))):
			return "Save contains an invalid birthday."
		var birthday: Variant = entry.get("day")
		if not (birthday is float or birthday is int) or not is_finite(float(birthday)) or float(birthday) != floorf(float(birthday)) or float(birthday) < 1 or float(birthday) > 1000000:
			return "Save contains an invalid birthday date."
		if int(birthday) < previous_day or (not previous_stage.is_empty() and str(entry.from) != previous_stage):
			return "Save contains inconsistent birthday history."
		previous_day = int(birthday)
		previous_stage = str(entry.to)
	if not previous_stage.is_empty() and previous_stage != stage: return "Save birthday history does not match this Lifelet's age."
	return ""
