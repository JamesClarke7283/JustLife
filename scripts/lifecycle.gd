extends RefCounted
class_name LifeLifecycle
## Progress is a fraction of a stage, so changing lifespan preserves age.

const STAGES: Array[String] = ["baby", "child", "teen", "young_adult", "adult", "elder"]


## Whether one life stage is the same rank or older than another. Every age gate
## reads this, so a stage added to the roster cannot silently lock a whole age out
## of a feature that names an older one.
static func at_least(stage: String, minimum: String) -> bool:
	var have: int = STAGES.find(stage)
	var need: int = STAGES.find(minimum)
	if have < 0 or need < 0: return false
	return have >= need


## Whether one life stage is older than another, strictly. An upper age bound
## reads this so that "for children and teenagers" includes teenagers.
static func above(stage: String, ceiling: String) -> bool:
	var have: int = STAGES.find(stage)
	var top: int = STAGES.find(ceiling)
	if have < 0 or top < 0: return false
	return have > top
const LABELS: Dictionary = {"baby":"Baby", "child":"Child", "teen":"Teen", "young_adult":"Young adult", "adult":"Adult", "elder":"Elder", "unknown":"Age unspecified"}
## Baby covers newborn → sitting → toddler (14 + 12 days) before the child stage.
const NORMAL_DAYS: Dictionary = {"baby":28, "child":20, "teen":21, "young_adult":28, "adult":42, "elder":28}
const SPANS: Dictionary = {"short":0.5, "normal":1.0, "long":4.0}
## How the big centre banner names each stage. A teen is "a teenager" there.
const MILESTONE_WORDS: Dictionary = {"baby":"a baby", "child":"a child", "teen":"a teenager", "young_adult":"a young adult", "adult":"an adult", "elder":"an elder"}
## "elder" is the last stage, so next_stage() has nowhere to send them and a
## completed stage has no birthday to become. That completion is the end of the
## life instead: once an elder's stage progress reaches this value the Lifelet
## passes on, at the first moment they are home and idle. It is a fixed
## threshold and not a chance roll, so a test can force the whole rule by
## setting the progress. A Lifelet who is created as an elder lives one full
## elder stage from that day, exactly like one who reaches it by ageing.
const MAX_ELDER_PROGRESS: float = 1.0

## An elder whose stage has completed is due to pass away: the completion that
## would have been a birthday has nowhere left to send them. This is a threshold
## on state the save already carries, so a test, a restored save and a live game
## all reach the same decision, and the household only has to wait for a moment
## when the Lifelet is home and idle.
static func due_to_pass(stage: String, state: Dictionary) -> bool:
	return not bool(state.get("passed", false)) and due_to_pass_on(stage, state)

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

static func due_to_pass_on(stage: String, state: Dictionary) -> bool:
	return stage == "elder" and float(state.get("progress", 0.0)) >= MAX_ELDER_PROGRESS - 0.0000001

static func next_stage(stage: String) -> String:
	var index: int = STAGES.find(stage)
	return STAGES[index + 1] if index >= 0 and index < STAGES.size() - 1 else ""

static func with_article(stage: String) -> String:
	var label: String = str(LABELS.get(stage, "Lifelet")).to_lower()
	return ("an " if stage in ["adult", "elder"] else "a ") + label

## The words on the centre banner when someone reaches a stage.
static func milestone_text(first_name: String, stage: String) -> String:
	return "%s is now %s!" % [first_name, str(MILESTONE_WORDS.get(stage, with_article(stage)))]

## Days that depend on how old a Lifelet is (the teen's twenty days, the elder's
## fourteen) shrink and stretch with the lifespan setting, so a short life does
## not outrun its own milestones. Fixed spans such as a seven-day course do not
## call this.
static func scaled_days(normal_days: float, lifespan: String) -> float:
	return normal_days * float(SPANS.get(lifespan, 1.0))

## The calendar day this stage began, or 0 when the record cannot say. Calendar
## days keep counting while automatic birthdays are off, so this reads a day
## and never the stage progress. `stage_day` is written when a Lifelet is first
## seen at a stage, at every birthday and when Change Age picks a stage, so it
## is the newest of the three sources. The last birthday in the history is the
## same day in a save that has no `stage_day` yet.
static func stage_start_day(state: Dictionary, stage: String) -> int:
	var start: int = 0
	var history: Variant = state.get("history", [])
	if history is Array and not (history as Array).is_empty():
		var last: Variant = (history as Array).back()
		if last is Dictionary and str(last.get("to", "")) == stage: start = int(last.get("day", 0))
	var saved: Variant = state.get("stage_day")
	if saved is int or saved is float: start = maxi(start, int(saved))
	return start

## How many whole calendar days a Lifelet has been in `stage` as of `day`. A save
## from before `stage_day` that has no birthday in this stage is a Lifelet who
## was created here part of the way through, so the stage progress says how many
## days of it are already behind them. Ask about the stage the Lifelet is in now:
## the record keeps only when the current one began.
static func days_in_stage(state: Dictionary, stage: String, day: int) -> int:
	var start: int = stage_start_day(state, stage)
	if start > 0: return maxi(0, day - start)
	return maxi(0, _whole_days(state, stage))

## The whole days of this stage the progress says are behind a Lifelet. A hair of
## rounding is forgiven, so progress 20/21 of a 21-day stage is 20 days, not 19.
static func _whole_days(state: Dictionary, stage: String) -> int:
	return floori(float(state.get("progress", 0.0)) * duration(stage, str(state.get("lifespan", "normal"))) + 0.000001)

## Record the day this stage began if the state does not already say. Called
## once a Lifelet exists on a real calendar (the first tick, a save, a restore),
## because the household sets the clock only after a Lifelet is created.
static func anchor_stage_day(state: Dictionary, stage: String, day: int) -> void:
	if state.has("stage_day"): return
	var start: int = stage_start_day(state, stage)
	state["stage_day"] = start if start > 0 else maxi(1, day - _whole_days(state, stage))

## The birthday history that describes a Lifelet whose stage was changed by hand
## (Extend / Change Age). A younger stage drops the birthdays that led past it;
## an older one adds the birthdays between, all on `day`. Without this the save
## no longer matches the Lifelet's age and refuses to load.
static func history_after_change(history: Array, from_stage: String, to_stage: String, day: int) -> Array:
	var kept: Array = history.duplicate(true)
	var from_index: int = STAGES.find(from_stage)
	var to_index: int = STAGES.find(to_stage)
	if from_index < 0 or to_index < 0 or from_index == to_index: return kept
	if to_index < from_index:
		while not kept.is_empty() and str((kept.back() as Dictionary).get("to", "")) != to_stage: kept.pop_back()
		return kept
	for index: int in range(from_index, to_index): kept.append({"from":STAGES[index], "to":STAGES[index + 1], "day":day})
	return kept

static func description(stage: String, state: Dictionary) -> String:
	if stage == "unknown": return "Age unspecified"
	if bool(state.get("passed", false)):
		return "%s · a gentle spirit" % LABELS.get(stage, "Lifelet")
	if stage == "elder":
		return "Elder · enjoying the golden years"
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
	# The day this stage began is optional: an older save has none, and gets one on load.
	if state.has("stage_day"):
		var began: Variant = state.get("stage_day")
		if not (began is float or began is int) or not is_finite(float(began)) or float(began) != floorf(float(began)) or float(began) < 1 or float(began) > 1000000:
			return "Save contains an invalid stage date."
		if not previous_stage.is_empty() and int(began) < previous_day: return "Save contains an inconsistent stage date."
	return ""
