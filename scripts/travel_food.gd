extends LifeMealFlow
class_name LifeTravelFood
## Reuse the real supported-placement rules against a detached meal ledger.
## Earlier releases reserve their actual dish footprint for the next carrier.
var ledger:LifeMeals=LifeMeals.new()
func food() -> LifeMeals:return ledger

static func departure_error(controller:Node,members:Array=[]) -> String:
 var probe:=LifeTravelFood.new();probe.app=controller
 probe.ledger.restore(controller.household.meals.get_state())
 var error:String=""
 for member:Dictionary in controller.household.members:
  var id:String=str(member.id)
  if not members.is_empty() and not members.has(id):continue
  var held:Dictionary=probe.ledger.carried_by(id)
  if held.is_empty():continue
  var current:Dictionary=member.sim.get_current_action()
  if str(current.get("id","")) not in LifeMealFlow.ACTIONS or str(current.get("meal_plate",current.get("meal_source","")))!=str(held.id):
   error="Put down the food you are carrying before leaving.";break
  var body:LifeActor=controller.world.actors[id]
  probe.ledger.release_member(id,body.position)
  if not probe._settle_food(held,body.position):
   error="Clear a supported place to put down the food before leaving.";break
 probe.free()
 return error
