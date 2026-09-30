extends "res://tests/test_sustained_play.gd"
## Private qualification of one full day of the unchanged real-frame loop.
## Start from an existing paired home checkpoint with a lonely household dog.
var began:float=0.0
var attempts:int=0
var rotation:int=0
var initial_social:float=0.0
var initial_training:Dictionary={}

func _checkpoint(label:String)->void:
 if label=="session_start":
  began=_now();attempts=int(journal.pet_attempts);rotation=int(journal.get("pet_rotation",attempts))
  var care:Dictionary=app.household.pet_care(str(app.household.pets.pets[0].id))
  initial_social=float(care.needs.social);initial_training=care.skills.social.duplicate(true)
  check(initial_social<45.0,"The saved dog naturally needs social care")
 if label=="segment_end":
  check(_now()-began>=1440.0,"The household played a full natural day")
  var trained:int=0;var normal:int=0;var completed:int=0
  for request:Dictionary in journal.pet_requests:
   if int(request.attempt)<=attempts:continue
   if str(request.action)=="pet_train_social":
    trained+=1
    if str(request.status)=="completed":completed+=1
   if str(request.get("selection","rotation"))=="rotation":normal+=1
  check(trained>0 and completed>0,"Visible social-training requests were accepted and completed")
  check(int(journal.pet_rotation)==rotation+normal,"Priority care preserves the normal care rotation")
  var care:Dictionary=app.household.pet_care(str(app.household.pets.pets[0].id))
  var skill:Dictionary=care.skills.social
  check(int(skill.level)>int(initial_training.level) or float(skill.xp)>float(initial_training.xp),"Real training increased the dog's social skill")
  var trend:Dictionary=_pet_daily_trend()
  var pet_id:String=str(app.household.pets.pets[0].id)
  check(trend.has(pet_id) and int(trend[pet_id].samples)>=90 and float(trend[pet_id].max)>initial_social,"Quarter-hour observations retain the full day's social recovery")
  check(not pet_low_social_since.has(pet_id) or _now()-float(pet_low_social_since[pet_id])<1440.0,"The dog did not remain critically lonely all day")
  print("SUSTAINED_SOCIAL_QUALIFICATION ",JSON.stringify({"at":_now(),"began":began,"initial_social":initial_social,"initial_training":initial_training,"final_care":care,"training_attempts":trained,"training_completed":completed,"normal_attempts":normal,"rotation_before":rotation,"rotation_after":journal.pet_rotation,"trend":trend}))
 await super._checkpoint(label)
