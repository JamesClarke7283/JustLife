extends "res://tests/test_autonomy_policy.gd"
## The hug and share-interests interactions carry conditional outcomes: a hug
## needs real friendship and cools down when repeated, and sharing interests
## connects deeply only with shared traits.

var sim: LifeSim

func run()->void:
	sim=LifeSim.new();owned.append(sim)
	sim.new_household({"name":"Social Lifelet","age_stage":"adult","traits":["Creative","Outgoing"]})
	sim.set_aging("normal",false)
	sim.household_bills_enabled=false
	sim.day=1;sim.minutes=540.0
	sim.autonomy=false
	sim.relationships["maya"]={"name":"Maya","friendship":40.0,"romance":0.0,"status":"Friend","bond":"none","milestones":[],"family_role":"none","life_stage":"adult"}
	sim.set_social_context("player",{},{"maya":true},{"maya":{"friendship":40.0,"traits":["Creative","Geek"]}}, {})
	# A hug below 25 friendship adds only a small nudge.
	var cold:Dictionary={"id":"hug","target_id":"maya","target_position":Vector3.ZERO}
	sim.relationships["maya"].friendship=10.0
	check(sim._apply_social(cold),"A hug on a cold target still completes.")
	var cold_gain:float=float(sim.relationships["maya"].friendship)-10.0
	check(cold_gain>0.0 and cold_gain<6.0,"A hug below 25 friendship adds only the small nudge (+%.1f)." % cold_gain)
	# A real friend: the full gain.
	sim.relationships["maya"].friendship=40.0
	var hug:Dictionary={"id":"hug","target_id":"maya","target_position":Vector3.ZERO}
	check(sim._apply_social(hug),"A hug on a real friend completes.")
	var full:float=float(sim.relationships["maya"].friendship)-40.0
	check(full>12.0,"The first hug adds the full friendship gain (+%.1f)." % full)
	# An immediate second hug gains less than the first.
	var before:float=float(sim.relationships["maya"].friendship)
	check(sim._apply_social(hug),"The immediate second hug completes.")
	var repeat:float=float(sim.relationships["maya"].friendship)-before
	check(repeat>0.0 and repeat<full,"An immediate repeat hug gains less (+%.1f vs %.1f)." % [repeat,full])
	# Sharing interests with a shared trait lands deeply.
	sim.relationships["maya"].friendship=30.0
	var interests:Dictionary={"id":"share_interests","target_id":"maya","target_position":Vector3.ZERO}
	check(sim._apply_social(interests),"Sharing interests with shared traits completes.")
	var gained:float=float(sim.relationships["maya"].friendship)-30.0
	check(gained>15.0,"Shared traits make the conversation land deeply (+%.1f)." % gained)
	# The "met" milestone is recorded by the interaction.
	check(sim.relationships["maya"].milestones.has("met"),"The interaction records the met milestone.")
	# Sympathy comforts a struggling friend most.
	sim.relationships["maya"].friendship=20.0
	sim.set_social_context("player",{},{"maya":true},{"maya":{"friendship":20.0,"traits":["Creative"],"fun":30.0}}, {})
	var low:Dictionary={"id":"sympathize","target_id":"maya","target_position":Vector3.ZERO}
	check(sim._apply_social(low),"Sympathy on a struggling friend completes.")
	var comforted:float=float(sim.relationships["maya"].friendship)-20.0
	check(comforted>14.0,"Sympathy on a low-mood friend gains the full comfort (+%.1f)." % comforted)
	# Sympathy on a cheerful friend gains less.
	sim.relationships["maya"].friendship=20.0
	sim.set_social_context("player",{},{"maya":true},{"maya":{"friendship":20.0,"traits":["Creative"],"fun":90.0}}, {})
	check(sim._apply_social(low),"Sympathy on a cheerful friend completes.")
	var mild:float=float(sim.relationships["maya"].friendship)-20.0
	check(mild>5.0 and mild<comforted,"Sympathy on a cheerful friend gains less (+%.1f vs %.1f)." % [mild,comforted])
	# Gossip: fresh story gains well; an immediate repeat lands flat.
	sim.relationships["maya"].friendship=30.0
	var story:Dictionary={"id":"gossip","target_id":"maya","target_position":Vector3.ZERO}
	check(sim._apply_social(story),"Fresh gossip completes.")
	var fresh:float=float(sim.relationships["maya"].friendship)-30.0
	check(fresh>7.0,"Fresh gossip gains well (+%.1f)." % fresh)
	var before_gossip:float=float(sim.relationships["maya"].friendship)
	check(sim._apply_social(story),"The immediate repeat gossip completes.")
	var stale:float=float(sim.relationships["maya"].friendship)-before_gossip
	check(stale>0.0 and stale<fresh,"A repeated story gains less (+%.1f vs %.1f)." % [stale,fresh])
	# The new platonic interactions record the first-meeting milestone too.
	var fresh_rel:Dictionary={"name":"Maya","friendship":0.0,"romance":0.0,"status":"Acquaintance","bond":"none","milestones":[],"family_role":"none","life_stage":"adult"}
	for act:String in ["sympathize","gossip"]:
		sim.relationships["maya"]=fresh_rel.duplicate(true);sim.relationships["maya"].milestones=[]
		sim.set_social_context("player",{},{"maya":true},{"maya":{"friendship":0.0,"traits":[],"fun":90.0}}, {})
		sim.last_gossip.clear()
		check(sim._apply_social({"id":act,"target_id":"maya","target_position":Vector3.ZERO}),"A first %s completes." % act)
		check(sim.relationships["maya"].milestones.has("met"),"A first %s records the met milestone." % act)
	print("SOCIAL_VARIETY %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
