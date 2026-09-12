extends "res://tests/test_autonomy_policy.gd"
## Doing a leisure activity while visiting a resident's home warms the
## friendship with the host — once per in-game hour, only at resident homes,
## and only for leisure or study work.

var sim: LifeSim

func run()->void:
	sim=LifeSim.new();owned.append(sim)
	sim.new_household({"name":"Host Guest","traits":[]})
	sim.set_aging("normal",false)
	sim.household_bills_enabled=false
	sim.day=1;sim.minutes=540.0
	sim.autonomy=false
	# A finished paint at Maya's home credits the host once.
	sim.visited_venue="maya_home"
	var before: float = float(sim.relationships.maya.friendship)
	complete_paint()
	var gained: float = float(sim.relationships.maya.friendship)-before
	check(gained>2.0,"A finished paint at the host's home credits the host (+%.1f)." % gained)
	# The hourly throttle: another finished activity 30 minutes later gains
	# nothing (paint itself runs 90 minutes, so the direct call isolates the
	# window from the action length).
	sim.minutes+=30.0
	var held: float = float(sim.relationships.maya.friendship)
	sim._maybe_credit_host("paint")
	check(float(sim.relationships.maya.friendship)==held,"An activity within the hour does not double the credit.")
	# After more than an hour the credit reopens.
	sim.minutes+=61.0
	complete_paint()
	check(float(sim.relationships.maya.friendship)>held,"The credit reopens after an in-game hour.")
	# At the player's own home nothing is credited.
	var home_before: float = float(sim.relationships.maya.friendship)
	sim.visited_venue="home"
	sim.minutes+=61.0
	complete_paint()
	check(float(sim.relationships.maya.friendship)==home_before,"Painting at home does not credit the host.")
	# A venue without a resident has nobody to credit.
	sim.visited_venue="park"
	sim.minutes+=61.0
	complete_paint()
	check(float(sim.relationships.maya.friendship)==home_before,"A public venue has no host to credit.")
	# A non-leisure action earns no hosted credit.
	sim.visited_venue="maya_home"
	sim.minutes+=61.0
	sim._maybe_credit_host("sleep")
	check(float(sim.relationships.maya.friendship)==home_before,"Sleep is not a hosted activity.")
	# Leo's home credits Leo: the host comes from the venue, not the roster order.
	sim.visited_venue="leo_home"
	sim.minutes+=61.0
	var leo_before: float = float(sim.relationships.leo.friendship)
	sim._maybe_credit_host("read")
	check(float(sim.relationships.leo.friendship)>leo_before,"Reading at Leo's credits Leo (+%.1f)." % (float(sim.relationships.leo.friendship)-leo_before))
	print("HOSTED_ACTIVITIES %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func complete_paint()->void:
	check(sim.queue_action("paint"),"Paint must be queueable for the hosted visit.")
	sim.begin_current_action()
	var remaining: float = float(sim.get_current_action().duration)
	while remaining>.0001:
		var step: float = minf(remaining,60.0)
		sim.tick(step)
		remaining-=step
		if sim.action_queue.is_empty():break
