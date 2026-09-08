extends SceneTree
const Actor = preload("res://scripts/actor.gd")
var checks:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func run()->void:
	for stage:String in ["child","teen","adult"]:
		var actor:LifeActor=Actor.new();root.add_child(actor)
		actor.configure({"name":"Birthday QA","age_stage":stage,"low_detail":true})
		actor.voice_enabled=false
		var root_before:Transform3D=actor.transform
		for i:int in range(160):actor.animate(1.0/60.0,1,false,"birthday")
		check(actor._birthday_cake.visible and actor._cake_flames.size()==3,"A birthday must visibly hold the original cake with three candles.")
		check(actor._cake_flames.all(func(n:Node3D)->bool:return n.visible),"Candles must remain lit before the blowing moment.")
		check(actor._joints.Head.rotation.x > .15,"The Lifelet must lean their head toward the candles.")
		var cake:Transform3D=actor._birthday_cake.global_transform
		var head:Transform3D=actor._joints.Head.transform
		actor.animate(.6,0,true,"")
		check(actor._birthday_cake.global_transform.is_equal_approx(cake) and actor._joints.Head.transform.is_equal_approx(head),"Pause must freeze the cake, hands, and blowing pose.")
		for i:int in range(45):actor.animate(1.0/60.0,1,false,"birthday")
		check(actor._cake_flames.all(func(n:Node3D)->bool:return not n.visible),"The blowing moment must extinguish all three candle flames.")
		for i:int in range(95):actor.animate(1.0/60.0,1,false,"birthday")
		check(not actor._birthday_cake.visible and actor._smile > .5,"The cake must be put away for the smiling applause pose.")
		check(actor.transform.is_equal_approx(root_before),"Birthday presentation must preserve the navigation root.")
		for i:int in range(60):actor.animate(1.0/60.0,1,true,"")
		check(not actor._birthday_cake.visible,"Birthday props must stay hidden during the next walk.")
		actor.queue_free()
	await process_frame;await create_timer(.2).timeout
	print("BIRTHDAY ACTOR TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
