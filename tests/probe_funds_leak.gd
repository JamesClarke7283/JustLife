extends SceneTree
## A household that is only living — nobody shopping, nobody ordering — keeps
## its purse except for the scheduled break-in. A bill is not taken by the clock.

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL ", message)
	else:
		print("PASS ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var home := LifeHousehold.new()
	root.add_child(home)
	home.new_household([
		{"name": "Ada", "age_stage": "adult"},
		{"name": "Ben", "age_stage": "adult"},
		{"name": "Cara", "age_stage": "child"},
	])
	home.set_home_value_provider(func() -> int: return 20000)
	for member: Dictionary in home.members:
		member.sim.set_home_value_provider(func() -> int: return 20000)
		member.sim.autonomy = false
		member.sim.wants.clear()
	var start: int = home.funds
	var robberies: int = 0
	var last: int = start
	for step: int in 14 * 24:
		home.tick(60.0 / LifeSim.GAME_MINUTES_PER_SECOND)
		if home.funds != last:
			var drop: int = last - home.funds
			check(drop == LifeSim.ROBBERY_LOSS and home.day % LifeSim.ROBBERY_PERIOD_DAYS == 0,
				"Purse moved only for a scheduled break-in (day %d, %d -> %d)." % [home.day, last, home.funds])
			check(home.last_purse_note.contains("burglar"), "The purse says a burglar took the money.")
			robberies += 1
			last = home.funds
	check(not home.bill().is_empty(), "The weekly bill is still waiting for the player.")
	check(home.funds == start - robberies * LifeSim.ROBBERY_LOSS, "Nothing but break-ins left the purse (ℒ%d, %d nights)." % [home.funds, robberies])
	check(robberies == 5, "Fourteen days include the break-in nights only, not a drain every morning.")
	print("PURSE_LEAK ", checks, " assertions; ", failures, " failures")
	quit(1 if failures else 0)
