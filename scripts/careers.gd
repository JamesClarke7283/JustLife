extends RefCounted
class_name LifeCareers
## Every line of work a Lifelet can take, with a real ladder of job titles.
##
## A job has ten levels. Each level has its own title, as it would in real life,
## and its own daily pay, so a promotion is a real step rather than a raised
## number with the same name. The pay table is stated as a starting rate and a
## step, which makes each ladder one fact rather than ten that can drift apart.
##
## **The top of a ladder is the job's own rate.** The best-paid jobs reach
## ℒ1,000 a day at their tenth level. A university degree multiplies the pay of
## the jobs that need one, so a graduate earns more than an equally experienced
## colleague without one — and the ladder's own ceiling stays what the job pays.
##
## Pure static policy — no Nodes, no clock, no wallet.

## The levels a job has, and the ceiling of every ladder.
const MAX_LEVEL: int = 10

## The job a Lifelet starts out in: the lowest rung, no skill and no fee, and the
## only ladder open to somebody who has not earned anything yet. Every household
## begins here rather than in the middle of a career.
const DEFAULT_JOB: String = "waiter"

## What a degree is worth to a job that asks for one. Applied only to the jobs
## flagged `degree_pay`, because a degree is worth nothing to waiting tables.
##
## The brief asks for a university title to "upgrade the multiplier by 3". Taken
## literally that makes a doctor with a PHD earn three times a doctor without one
## at every level, which would put the top of that ladder far above the ℒ1,000
## the same brief fixes as the highest pay in the game. The ladder's own ceiling
## is kept as that fixed number and the degree is a real but bounded multiplier,
## so a graduate is meaningfully better paid without breaking the stated cap.
const DEGREE_MULTIPLIER: Dictionary = {
	"none": 1.0,
	"bachelors": 1.4,
	"masters": 1.8,
	"phd": 2.2,
}

const DEGREES: Array[String] = ["none", "bachelors", "masters", "phd"]
const DEGREE_LABELS: Dictionary = {
	"none": "No degree", "bachelors": "Bachelors", "masters": "Masters", "phd": "PHD",
}

## How much criminal detection falls with rank. A first-day thief is caught
## often; a practised one rarely.
const CRIMINAL_DETECTION_AT_ONE: float = 0.06
const CRIMINAL_DETECTION_AT_TEN: float = 0.015

## What being caught costs, as a multiple of what the criminal track pays a day.
const FINE_MULTIPLE: float = 2.0
## How long a Lifelet serves. A finer criminal serves less.
const PRISON_DAYS_BASE: int = 6
const PRISON_DAYS_AT_TEN: int = 2

## Every job. `base` is the first-level daily rate and `step` the rise per level,
## so level N pays `base + (N-1) * step`. `titles` has exactly MAX_LEVEL entries,
## lowest first, in the order a real career would use them.
##
## `entry` names what it takes to be *taken on*: a skill and the level it must
## already be at, and any fee. An empty skill means anyone may walk in — which is
## what makes waiting tables the way into work for a Lifelet with nothing yet.
const JOBS: Dictionary = {
	# ---------------------------------------------------- minimum-wage tier
	# The way in. No skill, no fee, and the lowest pay in the game: a Lifelet who
	# has just grown up takes one of these first. The entry asks for nothing, but
	# the work itself is still plied with a skill, so a waiter who keeps at it
	# grows the Charisma that opens the better-paid doors.
	"waiter": {
		"label": "Waiting staff", "workplace": "The Riverside Brasserie", "skill": "charisma", "base": 85, "step": 16, "entry": {"skill": "", "level": 0, "cost": 0},
		"titles": ["Trainee waiter", "Waiter", "Waiting staff", "Senior waiter",
			"Head waiter", "Restaurant supervisor", "Duty manager", "Assistant restaurant manager",
			"Restaurant manager", "General manager"],
	},
	"barista": {
		"label": "Coffee shop", "workplace": "Bay Window Café", "skill": "charisma", "base": 90, "step": 17, "entry": {"skill": "", "level": 0, "cost": 0},
		"titles": ["Trainee barista", "Barista", "Coffee shop assistant", "Senior barista",
			"Shift leader", "Coffee shop supervisor", "Assistant manager", "Coffee shop manager",
			"Area manager", "Head of coffee"],
	},
	"retail": {
		"label": "Retail", "workplace": "Harbourgate Shopping Centre", "skill": "charisma", "base": 88, "step": 16, "entry": {"skill": "", "level": 0, "cost": 0},
		"titles": ["Retail assistant", "Sales assistant", "Retail associate", "Senior sales assistant",
			"Team leader", "Department supervisor", "Assistant store manager", "Store manager",
			"Regional manager", "Head of retail"],
	},
	"cleaner": {
		"label": "Cleaning", "workplace": "Juniper Bay Council depot", "skill": "fitness", "base": 82, "step": 15, "entry": {"skill": "", "level": 0, "cost": 0},
		"titles": ["Cleaning assistant", "Cleaner", "Facilities assistant", "Senior cleaner",
			"Cleaning supervisor", "Facilities coordinator", "Facilities manager", "Operations manager",
			"Head of facilities", "Director of operations"],
	},
	"delivery": {
		"label": "Delivery", "workplace": "The depot on Rowan Close", "skill": "fitness", "base": 95, "step": 19, "entry": {"skill": "", "level": 0, "cost": 0},
		"titles": ["Delivery assistant", "Delivery driver", "Van driver", "Senior driver",
			"Route leader", "Depot supervisor", "Depot manager", "Logistics manager",
			"Head of logistics", "Director of logistics"],
	},

	# ------------------------------------------------------------- trades
	"hairdresser": {
		"label": "Hairdressing", "workplace": "The Cutting Room", "skill": "charisma", "base": 150, "step": 30, "entry": {"skill": "charisma", "level": 1, "cost": 120},
		"titles": ["Salon assistant", "Junior stylist", "Stylist", "Senior stylist",
			"Colour specialist", "Salon supervisor", "Assistant salon manager", "Salon manager",
			"Salon owner", "Creative director"],
	},
	"chef": {
		"label": "Culinary arts", "workplace": "The Riverside Brasserie kitchen", "skill": "cooking", "base": 170, "step": 34, "entry": {"skill": "cooking", "level": 2, "cost": 0},
		"titles": ["Kitchen assistant", "Prep cook", "Commis chef", "Chef de partie",
			"Sous chef", "Head chef", "Kitchen manager", "Executive chef",
			"Head of kitchens", "Culinary director"],
	},
	"gardener": {
		"label": "Gardening", "workplace": "Juniper Gardens", "skill": "gardening", "base": 140, "step": 26, "entry": {"skill": "gardening", "level": 1, "cost": 0},
		"titles": ["Garden centre assistant", "Gardener", "Plant technician", "Senior gardener",
			"Horticulturist", "Head gardener", "Grounds supervisor", "Landscape manager",
			"Head of grounds", "Director of horticulture"],
	},
	"fitness": {
		"label": "Wellness club", "workplace": "The Movement Rooms", "skill": "fitness", "base": 150, "step": 28, "entry": {"skill": "fitness", "level": 1, "cost": 0},
		"titles": ["Gym assistant", "Fitness instructor", "Personal trainer", "Senior trainer",
			"Studio coordinator", "Fitness manager", "Wellness lead", "Club manager",
			"Head of wellness", "Operations director"],
	},
	"musician": {
		"label": "Music", "workplace": "Common Ground Studio", "skill": "music", "base": 130, "step": 30, "entry": {"skill": "music", "level": 2, "cost": 0},
		"titles": ["Session hand", "Cover musician", "Recording musician", "Touring musician",
			"Soloist", "Musical director", "Composer", "Head of music",
			"Artistic director", "Royal composer"],
	},
	"studio": {
		"label": "Creative studio", "workplace": "Common Ground Studio", "skill": "creativity", "base": 180, "step": 40, "entry": {"skill": "creativity", "level": 1, "cost": 0},
		"titles": ["Studio assistant", "Project coordinator", "Creative specialist", "Senior creative",
			"Art director", "Creative lead", "Studio manager", "Head of creative",
			"Creative director", "Chief creative officer"],
	},

	# --------------------------------------------------------- public service
	"community": {
		"label": "Community work", "workplace": "Juniper Bay community hall", "skill": "charisma", "base": 150, "step": 32, "entry": {"skill": "charisma", "level": 1, "cost": 0},
		"titles": ["Community assistant", "Outreach worker", "Event organiser", "Community officer",
			"Programme coordinator", "Programme manager", "Community lead", "Head of community",
			"Director of community", "Chief executive"],
	},
	"teacher": {
		"label": "Teaching", "workplace": "Juniper Bay School", "skill": "logic", "base": 210, "step": 45, "entry": {"skill": "logic", "level": 4, "cost": 0},
		"titles": ["Teaching assistant", "Cover supervisor", "Class teacher", "Subject teacher",
			"Head of subject", "Head of year", "Deputy head", "Head teacher",
			"Executive head", "Director of education"],
	},
	"nurse": {
		"label": "Nursing", "workplace": "Juniper Bay clinic", "skill": "logic", "base": 220, "step": 48, "entry": {"skill": "logic", "level": 4, "cost": 0},
		"titles": ["Care assistant", "Student nurse", "Staff nurse", "Senior staff nurse",
			"Sister", "Ward manager", "Matron", "Head of nursing",
			"Director of nursing", "Chief nurse"],
	},
	"firefighter": {
		"label": "Fire service", "workplace": "Juniper Bay fire station", "skill": "fitness", "base": 230, "step": 50, "entry": {"skill": "fitness", "level": 4, "cost": 0},
		"titles": ["Fire service recruit", "Firefighter", "Firefighter (competent)", "Crew manager",
			"Watch manager", "Station manager", "Area manager", "Group manager",
			"Assistant chief officer", "Chief fire officer"],
	},
	"police": {
		"label": "Police service", "workplace": "Juniper Bay police station", "skill": "logic", "base": 240, "step": 52, "entry": {"skill": "logic", "level": 4, "cost": 0},
		"titles": ["Police cadet", "Constable", "Constable (response)", "Sergeant",
			"Inspector", "Chief inspector", "Superintendent", "Chief superintendent",
			"Assistant chief constable", "Chief constable"],
	},
	"accountant": {
		"label": "Accountancy", "workplace": "Rowan Close offices", "skill": "logic", "base": 280, "step": 80, "entry": {"skill": "logic", "level": 5, "cost": 0, "degree": "bachelors"},
		"titles": ["Accounts assistant", "Bookkeeper", "Assistant accountant", "Accountant",
			"Senior accountant", "Audit manager", "Finance manager", "Financial controller",
			"Finance director", "Chief financial officer"],
	},
	"architect": {
		"label": "Architecture", "workplace": "The design practice on Willow Lane", "skill": "creativity", "base": 325, "step": 75, "entry": {"skill": "creativity", "level": 5, "cost": 0, "degree": "bachelors"},
		"titles": ["Architectural assistant", "Part-qualified architect", "Architect", "Senior architect",
			"Associate architect", "Principal architect", "Design director", "Practice director",
			"Managing partner", "Head of practice"],
	},
	"lawyer": {
		"label": "Law", "workplace": "Chambers on Rowan Close", "skill": "charisma", "base": 325, "step": 75, "entry": {"skill": "charisma", "level": 6, "cost": 0, "degree": "bachelors"},
		"titles": ["Paralegal", "Trainee solicitor", "Solicitor", "Associate solicitor",
			"Senior associate", "Salaried partner", "Equity partner", "Senior partner",
			"Head of chambers", "Lord of appeal"],
	},
	"doctor": {
		"label": "Medicine", "workplace": "Juniper Bay clinic", "skill": "logic", "base": 370, "step": 70, "entry": {"skill": "logic", "level": 6, "cost": 0, "degree": "bachelors"},
		"titles": ["Foundation doctor", "Senior house officer", "Registrar", "Specialty registrar",
			"Consultant", "Clinical lead", "Head of department", "Medical director",
			"Chief medical officer", "Dean of medicine"],
	},

	# -------------------------------------------------------------- technology
	"technology": {
		"label": "Technology", "workplace": "The technology park", "skill": "logic", "base": 190, "step": 90, "entry": {"skill": "logic", "level": 3, "cost": 0},
		"titles": ["Support specialist", "Junior developer", "Software engineer", "Senior engineer",
			"Technical lead", "Engineering manager", "Head of engineering", "Director of engineering",
			"VP of engineering", "Chief technology officer"],
	},
	## The trade that walks in with a course fee and leaves as the head of a company.
	## Software engineer is the step where a technical worker becomes an engineer,
	## and the tenth level is the chief executive of a technology company.
	"technical": {
		"label": "Technical work", "workplace": "The technology park", "skill": "logic", "base": 280, "step": 80, "entry": {"skill": "logic", "level": 8, "cost": 900, "degree": "bachelors"},
		"titles": ["Apprentice technician", "Bench technician", "Systems technician", "Software engineer",
			"Senior software engineer", "Lead engineer", "Engineering manager", "Director of engineering",
			"Chief technology officer", "CEO of a technology company"],
	},

	# ------------------------------------------------------------- criminal
	## Pays as well as the best-paid honest work and asks for nothing at all —
	## which is exactly why it is a gamble. `LifeCareers.detection_chance` owns the
	## odds and the prison term, and the household owns the fine.
	##
	## The entry asks for nothing, but the trade itself is plied with Charisma,
	## so a practised thief climbs the ladder the same way anybody else does and
	## a shift on the wrong side of the law still teaches something.
	"criminal": {
		"label": "Criminal", "workplace": "Wherever the night takes them", "skill": "charisma", "base": 1000, "step": 0, "criminal": true,
		"entry": {"skill": "", "level": 0, "cost": 0},
		"titles": ["Lookout", "Shopbreaker", "Runner", "Bagman",
			"Fence", "Safe-cracker", "Fixer", "Inside man",
			"Crime boss", "Kingpin"],
	},
}

## The jobs a Lifelet can walk straight into with no skill and no fee. These are
## the way into work, so at least one must always exist.
static func unskilled() -> Array[String]:
	var out: Array[String] = []
	for id: String in JOBS:
		var entry: Dictionary = JOBS[id].get("entry", {})
		if str(entry.get("skill", "")).is_empty() and int(entry.get("cost", 0)) == 0 and not bool(JOBS[id].get("criminal", false)):
			out.append(id)
	return out


static func has(job_id: String) -> bool:
	return JOBS.has(job_id)


static func job(job_id: String) -> Dictionary:
	return JOBS.get(job_id, {})


static func label(job_id: String) -> String:
	return str(job(job_id).get("label", job_id.capitalize()))


## Where this job is actually done. A Lifelet leaves for a real workplace
## rather than a generic "work", so the commute and its notices name the place.
static func workplace(job_id: String) -> String:
	return str(job(job_id).get("workplace", "Work"))


static func titles(job_id: String) -> Array:
	return (job(job_id).get("titles", []) as Array).duplicate()


## The title at one level, clamped so a save from before the ladder grew cannot
## ask for a rung that is not there.
static func title_at(job_id: String, level: int) -> String:
	var ladder: Array = titles(job_id)
	if ladder.is_empty(): return label(job_id)
	return str(ladder[clampi(level, 1, ladder.size()) - 1])


## What one level of this job pays a day, before any degree. The tenth level of
## the best-paid jobs is the ℒ1,000 the brief names as the ceiling.
static func base_pay(job_id: String, level: int) -> int:
	var data: Dictionary = job(job_id)
	if data.is_empty(): return 0
	var rank: int = clampi(level, 1, MAX_LEVEL)
	return int(data.get("base", 0)) + (rank - 1) * int(data.get("step", 0))


## What this job pays a Lifelet at this level, including what their degree is
## worth to it. A job that asks for a degree pays more for one; a job that does
## not is unaffected, because a degree is worth nothing to waiting tables.
static func pay(job_id: String, level: int, degree: String = "none") -> int:
	var amount: int = base_pay(job_id, level)
	if not needs_degree(job_id): return amount
	var multiplier: float = float(DEGREE_MULTIPLIER.get(normalise_degree(degree), 1.0))
	return roundi(float(amount) * multiplier)


## Whether a job treats a degree as worth paying more for.
static func needs_degree(job_id: String) -> bool:
	return not str((job(job_id).get("entry", {}) as Dictionary).get("degree", "")).is_empty()


## The degree a job is best served by, or "" when it asks for none.
static func required_degree(job_id: String) -> String:
	return str((job(job_id).get("entry", {}) as Dictionary).get("degree", ""))


static func normalise_degree(value: String) -> String:
	return value if DEGREES.has(value) else "none"


static func degree_label(value: String) -> String:
	return str(DEGREE_LABELS.get(normalise_degree(value), "No degree"))


## The multiplier a degree gives a job that wants one, as the player reads it.
static func degree_multiplier(degree: String) -> float:
	return float(DEGREE_MULTIPLIER.get(normalise_degree(degree), 1.0))


## Whether this job is the criminal track, which is the one that carries risk.
static func is_criminal(job_id: String) -> bool:
	return bool(job(job_id).get("criminal", false))


## Why this Lifelet may not take this job, as the reason a player reads. Empty
## means the door is open. The picker, the queue and the taking-up all read this
## one answer, so a greyed-out button and a refused call never disagree.
##
## `skills` is the Lifelet's own skill table, `degree` their highest completed
## qualification, and `funds` the household purse for any course fee.
static func entry_error(job_id: String, stage: String, skills: Dictionary, degree: String, funds: int) -> String:
	if not has(job_id): return "That line of work is not offered here."
	if stage != "adult": return "Careers become available in young adulthood."
	var entry: Dictionary = job(job_id).get("entry", {})
	var wanted_degree: String = str(entry.get("degree", ""))
	if not wanted_degree.is_empty() and not degree_at_least(degree, wanted_degree):
		return "Needs a %s. This Lifelet holds %s." % [degree_label(wanted_degree), degree_label(degree)]
	var skill_name: String = str(entry.get("skill", ""))
	var required: int = int(entry.get("level", 0))
	if not skill_name.is_empty() and required > 0:
		var have: int = int((skills.get(skill_name, {}) as Dictionary).get("level", 1))
		if have < required:
			return "Requires %s level %d. This Lifelet is at %s level %d." % [
				skill_name.capitalize(), required, skill_name.capitalize(), have]
	var fee: int = int(entry.get("cost", 0))
	if funds < fee: return "The ℒ%d course fee needs ℒ%d more." % [fee, fee - funds]
	return ""


## The skills a job asks for, as player-readable text for the picker.
static func requirement_text(job_id: String) -> String:
	var entry: Dictionary = job(job_id).get("entry", {})
	var parts: Array[String] = []
	var skill_name: String = str(entry.get("skill", ""))
	var required: int = int(entry.get("level", 0))
	if not skill_name.is_empty() and required > 0:
		parts.append("%s level %d" % [skill_name.capitalize(), required])
	var wanted_degree: String = str(entry.get("degree", ""))
	if not wanted_degree.is_empty(): parts.append("a %s" % degree_label(wanted_degree))
	var fee: int = int(entry.get("cost", 0))
	if fee > 0: parts.append("ℒ%d course fee" % fee)
	if parts.is_empty(): return "No qualifications needed"
	return "Requires " + ", ".join(PackedStringArray(parts))


## Whether one degree is at least as high as another on the qualification ladder.
static func degree_at_least(have: String, wanted: String) -> bool:
	if wanted.is_empty(): return true
	return DEGREES.find(normalise_degree(have)) >= DEGREES.find(normalise_degree(wanted))


## What it costs in time and money to study for one degree, and what it needs
## first. A higher degree needs the one below it, so the ladder is real.
static func degree_step(degree: String) -> Dictionary:
	match normalise_degree(degree):
		"bachelors": return {"label": "Bachelors", "days": 6, "fee": 4000, "needs": "none"}
		"masters": return {"label": "Masters", "days": 8, "fee": 9000, "needs": "bachelors"}
		"phd": return {"label": "PHD", "days": 12, "fee": 20000, "needs": "masters"}
	return {}


## Why this Lifelet may not start this degree, or "" when they may.
static func degree_error(degree: String, stage: String, current: String, funds: int) -> String:
	var step: Dictionary = degree_step(degree)
	if step.is_empty(): return "That is not a qualification on offer."
	if stage != "adult": return "Higher education is open to adults."
	if normalise_degree(current) == normalise_degree(degree): return "This Lifelet already holds a %s." % degree_label(degree)
	if DEGREES.find(normalise_degree(current)) > DEGREES.find(normalise_degree(degree)):
		return "This Lifelet already holds a higher qualification."
	var needs: String = str(step.needs)
	if not needs.is_empty() and needs != "none" and not degree_at_least(current, needs):
		return "A %s comes first. This Lifelet holds %s." % [degree_label(needs), degree_label(current)]
	if funds < int(step.fee): return "That course costs ℒ%d and needs ℒ%d more." % [int(step.fee), int(step.fee) - funds]
	return ""


## The professional title a degree earns. A PHD is a doctor, whatever the job.
static func honorific(degree: String, fallback: String = "") -> String:
	if normalise_degree(degree) == "phd": return "Dr"
	return fallback if not fallback.is_empty() else "Mr/Mrs"


## Whether this Lifelet is caught today. A first-day thief is caught far more
## often than a practised one, which is what the ladder buys besides the money.
static func detection_chance(job_id: String, level: int) -> float:
	if not is_criminal(job_id): return 0.0
	var rank: int = clampi(level, 1, MAX_LEVEL)
	var span: float = CRIMINAL_DETECTION_AT_TEN - CRIMINAL_DETECTION_AT_ONE
	var t: float = float(rank - 1) / float(MAX_LEVEL - 1)
	return CRIMINAL_DETECTION_AT_ONE + span * t


## How long a caught criminal serves, in game days. A practised one serves less.
static func prison_days(job_id: String, level: int) -> int:
	if not is_criminal(job_id): return 0
	var rank: int = clampi(level, 1, MAX_LEVEL)
	var t: float = float(rank - 1) / float(MAX_LEVEL - 1)
	return roundi(float(PRISON_DAYS_BASE) + float(PRISON_DAYS_AT_TEN - PRISON_DAYS_BASE) * t)


## What being caught costs, as a fine. Two days' pay, so the gamble is symmetric:
## a good week pays well and one bad night takes it back.
static func fine(job_id: String, level: int) -> int:
	if not is_criminal(job_id): return 0
	return roundi(float(base_pay(job_id, level)) * FINE_MULTIPLE)


## Every job a Lifelet could be shown, in the order a picker should offer them:
## the way in first, then by what the ladder can pay at its top.
static func ordered() -> Array[String]:
	var ids: Array[String] = []
	for id: String in JOBS: ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var unskilled_a: bool = entry_error(a, "adult", {}, "none", 1 << 30).is_empty()
		var unskilled_b: bool = entry_error(b, "adult", {}, "none", 1 << 30).is_empty()
		if unskilled_a != unskilled_b: return unskilled_a
		return base_pay(a, MAX_LEVEL) > base_pay(b, MAX_LEVEL))
	return ids


## Validate one career record as a save restores it.
static func career_error(value: Variant) -> String:
	if not value is Dictionary: return "Save contains an invalid career."
	var career: Dictionary = value
	var track: String = str(career.get("track", ""))
	if not has(track): return "Save contains an unknown career track."
	if not integer(career.get("level", 0), 1, MAX_LEVEL): return "Save contains an impossible career level."
	var level: int = int(career.level)
	if str(career.get("title", "")) != title_at(track, level):
		return "Save contains a career title that does not match its level."
	if not integer(career.get("salary", 0), 0, 1000000): return "Save contains an invalid salary."
	if int(career.salary) != base_pay(track, level): return "Save contains a salary that does not match its level."
	var performance: Variant = career.get("performance", -1.0)
	if not (performance is float or performance is int) or not is_finite(float(performance)) or float(performance) < 0.0 or float(performance) > 1000000.0:
		return "Save contains invalid career performance."
	return ""


## Validate a criminal record as a save restores it.
static func criminal_error(value: Variant) -> String:
	if value == null: return ""
	if not value is Dictionary: return "Save contains an invalid criminal record."
	var record: Dictionary = value
	# Never having been caught is an empty record, which is a valid state.
	if record.is_empty(): return ""
	if int(record.get("version", 0)) != 1: return "The saved criminal record uses an unsupported version."
	if not integer(record.get("caught_count", 0), 0, 1000000): return "Save contains an impossible arrest count."
	if not integer(record.get("prison_until_day", 0), 0, 1000000): return "Save contains an invalid release day."
	if not integer(record.get("fines_paid", 0), 0, 100000000): return "Save contains an invalid fine total."
	return ""


static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
