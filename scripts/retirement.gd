extends RefCounted
class_name LifeRetirement
## When an elder may stop working, and the pension they live on afterwards.
##
## Pure rules: no nodes, no clock and no wallet. The Lifelet keeps a small record
## and asks these functions what it means. How long someone has been an elder is
## not stored here: it is `LifeLifecycle.days_in_stage`, so it counts calendar
## days (they keep counting when automatic birthdays are off) and a Lifelet who
## was created as an elder is dated from how far into the stage they began. The
## number of days scales with the lifespan setting like every age-tied threshold:
## fourteen at the normal pace, seven on a short life, fifty-six on a long one.
##
## The pension is a fixed seven-day cycle of a fixed amount. The first payment is
## seven days after retiring, then one every seven days. `next_pension_day` is
## advanced in the same step that credits the money, so a save and a reload can
## never pay a period twice.

const VERSION: int = 1
## Days as an elder before retiring opens, at the normal lifespan.
const ELIGIBLE_AFTER_DAYS: int = 14
const PENSION_AMOUNT: int = 1000
const PENSION_PERIOD_DAYS: int = 7
## What a retired Lifelet is no longer asked to do. Freelance work at a computer
## is a hobby and stays open.
const WORK_ACTIONS: Array[String] = ["career_day", "job", "drive_to_work"]
const KEYS: Array[String] = ["version", "eligible_noticed", "retired", "retired_day", "next_pension_day", "pension_paid"]
const RETIRED_REASON: String = "Retired: no more shifts, and a pension of ℒ1,000 arrives every 7 days."
const RETIRED_DETAIL: String = "No longer required to work · ℒ1,000 pension every 7 days"


static func fresh() -> Dictionary:
	return {"version": VERSION, "eligible_noticed": false, "retired": false, "retired_day": 0, "next_pension_day": 0, "pension_paid": 0}

## Whole days an elder must have been an elder before they may retire.
static func needed_days(lifespan: String) -> int:
	return maxi(1, ceili(LifeLifecycle.scaled_days(float(ELIGIBLE_AFTER_DAYS), lifespan) - 0.000001))

static func days_as_elder(lifecycle: Dictionary, day: int) -> int:
	return LifeLifecycle.days_in_stage(lifecycle, "elder", day)

static func is_retired(record: Dictionary) -> bool:
	return bool(record.get("retired", false))

## Whether this elder has been one long enough. Retiring is a separate choice.
static func eligible(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool) -> bool:
	if stage != "elder" or passed or is_retired(record): return false
	return days_as_elder(lifecycle, day) >= needed_days(str(lifecycle.get("lifespan", "normal")))

## Days still to go before retiring opens; 0 once it has.
static func days_until_eligible(lifecycle: Dictionary, day: int) -> int:
	return maxi(0, needed_days(str(lifecycle.get("lifespan", "normal"))) - days_as_elder(lifecycle, day))

## Why this Lifelet cannot retire right now, in words a player can read. Empty
## means the door is open. The Retire button, the household and the Lifelet all
## read this one answer, so a greyed button and a refused call never disagree.
static func retire_error(record: Dictionary, stage: String, lifecycle: Dictionary, day: int, passed: bool, away: bool, imprisoned: bool, current_action_id: String) -> String:
	if passed: return "A spirit has finished that chapter of life."
	if stage != "elder": return "Retirement is for elders."
	if is_retired(record): return "Already retired."
	var to_go: int = days_until_eligible(lifecycle, day)
	if to_go > 0: return "Retirement opens after %d days as an elder (%d to go)." % [needed_days(str(lifecycle.get("lifespan", "normal"))), to_go]
	if imprisoned: return "Serve the sentence before retiring."
	if away: return "This Lifelet can retire after coming home."
	if current_action_id in WORK_ACTIONS: return "Finish or cancel the current shift before retiring."
	return ""

## The record after retiring today. The first pension is a full period away.
static func retire(record: Dictionary, day: int) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["retired"] = true
	next["eligible_noticed"] = true
	next["retired_day"] = day
	next["next_pension_day"] = day + PENSION_PERIOD_DAYS
	next["pension_paid"] = 0
	return next

static func pension_due(record: Dictionary, day: int) -> bool:
	return is_retired(record) and day >= int(record.get("next_pension_day", 0))

## The record after one payment has been credited.
static func paid(record: Dictionary) -> Dictionary:
	var next: Dictionary = record.duplicate(true)
	next["next_pension_day"] = int(next.get("next_pension_day", 0)) + PENSION_PERIOD_DAYS
	next["pension_paid"] = int(next.get("pension_paid", 0)) + PENSION_AMOUNT
	return next

## 1000 as "ℒ1,000".
static func amount_text(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return "ℒ" + ("-" if amount < 0 else "") + digits + out

## A record as a save gives it back: JSON turns every whole number into a float.
## Anything that is not a record is the start of a Lifelet who has never retired.
static func migrate(value: Variant) -> Dictionary:
	if not value is Dictionary: return fresh()
	var record: Dictionary = fresh()
	for key: String in ["version", "retired_day", "next_pension_day", "pension_paid"]: record[key] = int((value as Dictionary).get(key, record[key]))
	for key: String in ["eligible_noticed", "retired"]: record[key] = bool((value as Dictionary).get(key, false))
	return record

## What a save says about retirement, as the reason it cannot be loaded (empty
## when it can). Missing or null is an older save and is fine. `lifecycle` is the
## Lifelet's saved aging record, which dates the start of the elder stage.
static func validate(value: Variant, stage: String, lifecycle: Dictionary, day: int) -> String:
	if value == null: return ""
	if not value is Dictionary: return "Save contains invalid retirement data."
	var record: Dictionary = value
	if record.size() != KEYS.size(): return "Save contains invalid retirement data."
	for key: String in KEYS:
		if not record.has(key): return "Save contains invalid retirement data."
	for key: String in ["version", "retired_day", "next_pension_day", "pension_paid"]:
		if not _whole(record[key], 0, 1000000000): return "Save contains an invalid retirement date or amount."
	if int(record.version) != VERSION: return "Save contains an unsupported retirement record."
	if not record.eligible_noticed is bool or not record.retired is bool: return "Save contains invalid retirement data."
	if not bool(record.retired):
		if int(record.retired_day) != 0 or int(record.next_pension_day) != 0 or int(record.pension_paid) != 0: return "Save pays a pension to someone who has not retired."
		if bool(record.eligible_noticed) and stage != "elder": return "Save announces retirement to someone who is not an elder."
		return ""
	if stage != "elder": return "Save retires someone who is not an elder."
	var retired_day: int = int(record.retired_day)
	var next: int = int(record.next_pension_day)
	if retired_day < 1 or retired_day > day: return "Save retires a Lifelet on an impossible day."
	var began: int = LifeLifecycle.stage_start_day(lifecycle, "elder")
	if began > 0 and retired_day < began: return "Save retires a Lifelet before they became an elder."
	if next < retired_day + PENSION_PERIOD_DAYS or next > day + PENSION_PERIOD_DAYS or (next - retired_day) % PENSION_PERIOD_DAYS != 0: return "Save contains a pension day that does not follow the retirement."
	if int(record.pension_paid) != PENSION_AMOUNT * (floori(float(next - retired_day) / float(PENSION_PERIOD_DAYS)) - 1): return "Save contains pension payments that do not match the days."
	if not bool(record.eligible_noticed): return "Save retires a Lifelet who was never told they could."
	return ""

static func _whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float): return false
	var number: float = float(value)
	return is_finite(number) and number == floorf(number) and number >= float(low) and number <= float(high)
