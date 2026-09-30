extends "res://tests/test_sustained_play.gd"
## Private real-frame qualification from the maintained dirty-dog home save.
## Finish only after a UI bath and a subsequent UI social lesson both complete.
var began:float=0.0
var attempts:int=0
var rotation:int=0
var original_target:float=0.0
var care_completions:Array=[]
var requested_stop:bool=false

func _connect_observers()->void:
 super._connect_observers()
 app.household.member_action_finished.connect(func(member:String,action:Dictionary):
  if str(action.id) not in ["bathe_pet","pet_train_social"]:return
  for request:Dictionary in journal.pet_requests:
   if int(request.attempt)<=attempts or str(request.member)!=member or str(request.action)!=str(action.id) or str(request.status)!="completed":continue
   if absf(float(request.completed_at)-_now())>.01:continue
   var care:Dictionary=app.household.pet_care(str(request.pet))
   care_completions.append({"at":_now(),"action":action.id,"attempt":request.attempt,"selection":request.selection,"needs":care.needs.duplicate(true)})
   print("SUSTAINED_PRIORITY_COMPLETION ",JSON.stringify(care_completions.back()))
   break)

func _ready_to_finish()->bool:
 var bath_at:float=-1.0
 var social_after:bool=false
 for completed:Dictionary in care_completions:
  if str(completed.action)=="bathe_pet" and str(completed.selection)=="low_hygiene" and float(completed.needs.hygiene)>=80.0:bath_at=float(completed.at)
  if str(completed.action)=="pet_train_social" and bath_at>=0.0 and float(completed.at)>bath_at:social_after=true
 for request:Dictionary in journal.pet_requests:
  if int(request.attempt)>attempts and bool(request.accepted) and str(request.status)!="completed":return false
 return social_after

func _sample()->void:
 super._sample()
 if began<=0.0 or requested_stop or not _ready_to_finish():return
 requested_stop=true
 var request:=FileAccess.open("res://checkpoint.request",FileAccess.WRITE)
 check(request!=null,"Qualified care can request a normal paired home stop")
 if request!=null:request.close()

func _checkpoint(label:String)->void:
 if label=="session_start":
  began=_now();attempts=int(journal.pet_attempts);rotation=int(journal.pet_rotation);original_target=float(journal.target)
  check(float(app.household.pet_care(str(app.household.pets.pets[0].id)).needs.hygiene)<35.0,"The exact saved dog naturally needs an urgent bath")
 if label=="segment_end":
  check(_ready_to_finish(),"An urgent bath materially restored hygiene and social training subsequently completed")
  var requests:Array=journal.pet_requests.filter(func(request:Dictionary)->bool:return int(request.attempt)>attempts)
  check(not requests.is_empty() and str(requests[0].selection)=="low_hygiene" and str(requests[0].action)=="bathe_pet","The first new care request prioritizes the visible bath command")
  var normal:int=0
  for request:Dictionary in requests:
   if str(request.selection)=="rotation":normal+=1
  check(int(journal.pet_rotation)==rotation+normal,"Priority bathing and training preserve the ordinary care cursor")
  check(float(journal.target)==original_target and app.current_venue=="home","Qualification retains the original target and home")
  var trend:Dictionary=_pet_daily_trend()
  var pet_id:String=str(app.household.pets.pets[0].id)
  check(trend.has(pet_id) and trend[pet_id].needs.has("hygiene") and float(trend[pet_id].needs.hygiene.max)>=80.0,"Daily need trends retain the observed hygiene recovery")
  check(not pet_low_hygiene_since.has(pet_id),"Successful bathing clears the persistent low-hygiene timer")
  print("SUSTAINED_HYGIENE_QUALIFICATION ",JSON.stringify({"began":began,"at":_now(),"completions":care_completions,"requests":requests,"rotation_before":rotation,"rotation_after":journal.pet_rotation,"trend":trend}))
 await super._checkpoint(label)
 if label=="segment_end" and not journal.checkpoints.is_empty():
  var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(journal.checkpoints.back().observations_backup)))
  check(saved.tracker.has("pet_low_hygiene_since") and equivalent(saved.tracker.pet_low_hygiene_since,pet_low_hygiene_since),"The paired checkpoint preserves the hygiene watchdog")
