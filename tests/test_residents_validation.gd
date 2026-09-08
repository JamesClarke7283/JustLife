extends SceneTree
var assertions:int=0
var failures:int=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 assertions+=1
 if not ok:failures+=1;push_error(label)
func run()->void:
 var residents:=LifeResidents.new(null)
 var original:Dictionary={"version":1,"locations":{"home":{"maya":residents._default_state("maya","home")}}}
 residents.restore(original)
 check(residents.locations.home.has("maya"),"A canonical resident record loads")
 for invalid:Variant in [{},[],"1",true,INF,NAN,1.5]:
  var bad:Dictionary=original.duplicate(true);bad.version=invalid
  residents.restore(bad)
  check(residents.locations.is_empty(),"Invalid version is ignored without a cast")
 for field:String in ["direction","waypoint"]:
  for invalid:Variant in [{},[],"1",true,INF,NAN,1.5,19]:
   var bad:Dictionary=original.duplicate(true);bad.locations.home.maya[field]=invalid
   residents.restore(bad)
   check(not residents.locations.get("home",{}).has("maya"),"Invalid "+field+" is ignored without a cast")
 var missing:Dictionary=original.duplicate(true)
 missing.locations.home.maya.erase("direction");missing.locations.home.maya.erase("waypoint")
 residents.restore(missing)
 check(int(residents.locations.home.maya.direction)==1 and int(residents.locations.home.maya.waypoint)==0,"Missing optional fields receive safe defaults")
 var fractional:Dictionary=original.duplicate(true);fractional.locations.home.maya.position[0]=INF
 residents.restore(fractional)
 check(not residents.locations.home.has("maya"),"Nonfinite position does not enter the scene")
 residents=null
 print("RESIDENTS_VALIDATION_RESULT ",assertions,"/",failures);quit(0 if failures==0 else 1)
