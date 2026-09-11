extends "res://tests/test_autonomy_policy.gd"
## The needs panel's "click to take care of it" shares the autonomy chooser: the
## public choice equals the autonomous one, names a real target, and the queue
## accepts it directly.

func run() -> void:
	var sim:LifeSim=setup()
	comfortable(sim)
	sim.register_targets(targets())
	sim.needs.bladder=22.0;sim.needs.energy=18.0;sim.needs.hygiene=30.0;sim.needs.hunger=25.0
	var bladder:Dictionary=sim.autonomy_need_choice("bladder")
	check(bladder==sim._autonomy_need_choice("bladder") and str(bladder.get("id"))=="toilet" and str(bladder.get("target_id"))=="toilet",
		"The bladder click resolves to the toilet exactly as autonomy would (%s)." % str(bladder))
	var energy:Dictionary=sim.autonomy_need_choice("energy")
	check(str(energy.get("id")) in ["sleep","nap"] and str(energy.get("target_id")) in ["bed","sofa"],
		"The energy click resolves to rest at a bed or sofa (%s)." % str(energy))
	var hygiene:Dictionary=sim.autonomy_need_choice("hygiene")
	check(str(hygiene.get("id"))=="shower" and str(hygiene.get("target_id"))=="shower",
		"The hygiene click resolves to the shower (%s)." % str(hygiene))
	var hunger:Dictionary=sim.autonomy_need_choice("hunger")
	check(str(hunger.get("id")) in ["eat_meal","snack","cook"] and str(hunger.get("target_id"))=="fridge",
		"The hunger click resolves to food at the fridge (%s)." % str(hunger))
	check(sim.queue_action(str(bladder.id),str(bladder.target_id),bladder.position) and str(sim.action_queue[0].id)=="toilet" and str(sim.action_queue[0].target_id)=="toilet",
		"The resolved bladder choice queues directly as a toilet visit.")
	check(sim.queue_action(str(energy.id),str(energy.target_id),energy.position),
		"The resolved energy choice queues directly.")
	var fun:Dictionary=sim.autonomy_need_choice("fun")
	check(not fun.is_empty() and sim._actions.has(str(fun.get("id"))),
		"The fun click resolves to a known pastime (%s)." % str(fun.get("id")))
	var social:Dictionary=sim.autonomy_need_choice("social")
	check(str(social.get("id")) in ["friendly","joke","deep_talk"],
		"The social click resolves to a conversation opener (%s)." % str(social.get("id","<none>")))
	for node:Node in owned:node.free()
	print("NEED_CLICK %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
