extends SceneTree
## Prove careers really progress: a promotion requirement moves from unmet to
## met, a promotion fires, and pay rises with the level.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_career_progress.gd

const LifeSim = preload("res://scripts/life_sim.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(4)
	app.start_household(); await frames(16)
	app.household.set_speed(0)

	var sim: Object = app.sim
	check(str(sim.character.age_stage) == "adult", "The adult can hold a career")
	# Choose a career through the public picker.
	sim.choose_career("studio")
	await frames(6)
	var track: String = str(sim.career.get("track", ""))
	var skill_name: String = str(LifeSim.CAREER_TRACKS[track].skill)
	var title_before: String = str(sim.career.title)
	var level_before: int = int(sim.career.level)
	var salary_before: int = int(sim.career.salary)

	# --- The first unmet requirement, walked up to honestly -------------------
	# The level-1 requirement is already satisfied by a starting skill, so take
	# the first promotion to reach a requirement that is genuinely unmet.
	var requirement: Dictionary = sim.promotion_requirement()
	check(not requirement.is_empty(), "A fresh career has a promotion requirement")
	if bool(requirement.met):
		sim.career["performance"] = 100.0
		sim._check_promotion()
		await frames(4)
		requirement = sim.promotion_requirement()
	check(not requirement.is_empty(), "The promoted career still has a next requirement")
	check(not bool(requirement.met), "A requirement is genuinely unmet at %s level %d (skill is %d)" % [skill_name, int(requirement.level), int(sim.skills[skill_name].level)])
	var needed: int = int(requirement.level)
	var next_title: String = str(requirement.next_title)
	title_before = str(sim.career.title)
	level_before = int(sim.career.level)
	salary_before = int(sim.career.salary)
	print("career %s: %s lvl %d, needs %s %d for %s, pay %d" % [track, title_before, level_before, skill_name, needed, next_title, salary_before])

	# --- Meet it through the skill's own gain path ---------------------------
	while int(sim.skills[skill_name].level) < needed:
		sim._gain_skill(skill_name, float(int(sim.skills[skill_name].level) * 50 + 10))
		await frames(2)
	var requirement_after: Dictionary = sim.promotion_requirement()
	print("skill %s is now level %d; requirement met=%s" % [skill_name, int(sim.skills[skill_name].level), str(requirement_after.met)])
	check(bool(requirement_after.met), "Reaching %s level %d really meets the requirement" % [skill_name, needed])

	# --- Perform well, and the promotion must fire ---------------------------
	sim.career["performance"] = 100.0
	sim._check_promotion()
	await frames(6)
	var level_after: int = int(sim.career.level)
	var title_after: String = str(sim.career.title)
	var salary_after: int = int(sim.career.salary)
	print("after: %s lvl %d at §%d -> %s lvl %d at §%d" % [title_before, level_before, salary_before, title_after, level_after, salary_after])
	check(level_after > level_before, "Excellent performance with the requirement met really promoted (level %d -> %d)" % [level_before, level_after])
	check(title_after != title_before, "The job title really changed (%s -> %s)" % [title_before, title_after])
	check(salary_after > salary_before, "Pay really rose with the promotion (§%d -> §%d)" % [salary_before, salary_after])

	# --- The record the player reads agrees ----------------------------------
	app.show_career_record()
	await frames(5)
	check(app.overlay_open, "The career record opens")
	var shown: bool = false
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if node is Label and str((node as Label).text).contains(title_after):
			shown = true
	check(shown, "The career record shows the promoted title (%s)" % title_after)
	app.close_overlay()

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://career"))
	root.get_texture().get_image().save_png("user://career/01_after_promotion.png")
	print("CAREER_SHOT ", ProjectSettings.globalize_path("user://career/01_after_promotion.png"))

	print("CAREER_PROGRESS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
