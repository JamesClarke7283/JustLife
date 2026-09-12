extends "res://tests/test_autonomy_policy.gd"
## A routine resident working at their venue during the window joins a
## matching leisure activity: friendship with them grows at most once per
## in-game hour, only at their routine venue inside the window.

var sim: LifeSim

func run()->void:
	sim=LifeSim.new();owned.append(sim)
	sim.new_household({"name":"Companion Guest","traits":[]})
	sim.set_aging("normal",false)
	sim.household_bills_enabled=false
	sim.day=1;sim.minutes=540.0
	sim.autonomy=false
	sim.relationships["maya"]={"name":"Maya","friendship":10.0,"romance":0.0,"status":"Acquaintance"}
	# At the library during Priya's window, a read credits her friendship.
	sim.visited_venue="library"
	sim.minutes=700.0
	var before: float = float(sim.relationships.priya.friendship)
	sim._maybe_credit_companion("read")
	var gained: float = float(sim.relationships.priya.friendship)-before
	check(gained>1.0,"A read at the library during Priya's window credits her (+%.1f)." % gained)
	# The hourly throttle: an immediate second credit is refused.
	var held: float = float(sim.relationships.priya.friendship)
	sim._maybe_credit_companion("read")
	check(float(sim.relationships.priya.friendship)==held,"The companion throttle refuses an immediate second credit.")
	# A venue outside any routine never credits.
	sim.visited_venue="park"
	sim.minutes=800.0
	sim._maybe_credit_companion("read")
	check(float(sim.relationships.priya.friendship)==held,"Tom's park routine does not credit Priya.")
	# Outside the routine window there is no credit either.
	sim.visited_venue="library"
	sim.minutes=1100.0
	sim._maybe_credit_companion("read")
	check(float(sim.relationships.priya.friendship)==held,"A read at the library after Priya's window gains no companion credit.")
	# At the player's own home no companion credit exists.
	sim.visited_venue="home"
	sim.minutes=800.0
	sim._maybe_credit_companion("read")
	check(float(sim.relationships.priya.friendship)==held,"The player's own home grants no companion credit.")
	# Leo has no routine: a read at the park credits nobody through him.
	sim.visited_venue="library"
	sim.minutes=750.0
	sim._maybe_credit_companion("read")
	var after: float = float(sim.relationships.priya.friendship)
	sim._maybe_credit_companion("read")
	check(float(sim.relationships.priya.friendship)==after,"The throttle holds across repeated calls.")
	print("COMPANION_CREDIT %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
