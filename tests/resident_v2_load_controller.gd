extends "res://scripts/main.gd"
static var reject_preparation:bool=false
func _restore_journeys() -> Dictionary:
 var result:Dictionary=super._restore_journeys()
 if bool(result.ok) and reject_preparation:
  if residents==null or residents.active_place!=current_venue or not world.actors.has("maya"):return {"ok":false,"error":"Fixture did not prepare the candidate residents."}
  return {"ok":false,"error":"Controlled rejection after candidate residents and physical journeys were prepared."}
 return result
