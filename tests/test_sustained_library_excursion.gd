extends "res://tests/test_sustained_play.gd"
## Qualification only: run from a private copy of an existing paired household.
## The normal sustained loop retains its original target and advances engine
## frames until admission; stop through its existing checkpoint-request channel.
var verified_resume:bool=false

func _library_excursion_due()->bool:
 var due:bool=super._library_excursion_due()
 if "--verify-excursion-resume" in OS.get_cmdline_user_args() and not verified_resume:
  verified_resume=true
  var retained:bool=str(journal.get("library_excursion",{}).get("status",""))=="completed"
  check(retained and not due,"A fresh opted-in resume retains success before any new outing")
  if not retained or due:_issue("Fresh resume lost once-only excursion success.",{})
  _request_qualification_stop()
  return false
 return due

func _library_excursion()->void:
 await super._library_excursion()
 var record:Dictionary=journal.get("library_excursion",{})
 if str(record.get("status",""))=="completed":
  check(not _library_excursion_due(),"The successful excursion is once-only")
  check(FileAccess.get_sha256(str(record.home_checkpoint.backup))==str(record.home_checkpoint.sha256),"The prior paired home save remains immutable after both trips")
  check(str(journal.checkpoints.back().label)=="after_library_excursion","The returned household has a newly paired home checkpoint")
  _request_qualification_stop()

func _excursion_travel(destination:String)->bool:
 if "--interrupt-at-library" in OS.get_cmdline_user_args() and destination=="home":
  _request_qualification_stop();_excursion_observe()
  check(excursion_interrupted and not stop_reason.is_empty(),"An external checkpoint request interrupts the outing promptly")
  return false
 if "--fail-at-library" in OS.get_cmdline_user_args() and destination=="home":
  _issue("Controlled qualification halt after real library arrival.",_excursion_evidence())
  return false
 return await super._excursion_travel(destination)

func _request_qualification_stop()->void:
 var request:=FileAccess.open("res://checkpoint.request",FileAccess.WRITE)
 check(request!=null,"Qualification can request a normal home checkpoint stop")
 if request!=null:request.close()
