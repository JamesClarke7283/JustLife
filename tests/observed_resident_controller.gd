extends "res://scripts/main.gd"
## Observe synchronous local position assignments, including all legal waypoints
## traversed in one long rendered frame. Movement itself is production code.
var record_resident_steps:bool=false
var resident_last:Dictionary={}
var resident_steps:Array=[]

class ObservedActor extends LifeActor:
 var observer:Node
 var resident_id:String
 func _ready()->void:
  super._ready();set_notify_local_transform(true)
 func _notification(what:int)->void:
  if what==NOTIFICATION_LOCAL_TRANSFORM_CHANGED and observer!=null and observer.record_resident_steps:
   observer.observe_step(resident_id,position)

func observe_step(id:String,to:Vector3)->void:
 var from:Vector3=resident_last.get(id,to)
 if from==to:return
 resident_steps.append({"id":id,"from":from,"to":to,"geometry":world.lot_navigation.segment_clear(0,from,to),"bodies":traversal._step_clear(id,from,to)})
 resident_last[id]=to

func spawn_actor(id:String,person:Dictionary,p:Vector3)->LifeActor:
 # Match the public controller's resident factory, substituting only an actor
 # with local-transform notifications. Appearance, collision and services stay.
 var actor:=ObservedActor.new();actor.observer=self;actor.resident_id=id
 actor.name=id.capitalize();world.house.add_child(actor)
 var actor_profile:Dictionary=person.duplicate(true);actor_profile["low_detail"]=true
 actor.configure(actor_profile);actor.voice_enabled=sound_enabled and mode=="live" and sim.speed>0
 actor.position=p;actor.set_meta("display_name",person.name);world.actors[id]=actor
 var body:=StaticBody3D.new();body.collision_layer=2;body.set_meta("item_id",id);actor.add_child(body)
 var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new()
 capsule.height=1.8;capsule.radius=.35;shape.shape=capsule;shape.position.y=.9;body.add_child(shape)
 return actor
