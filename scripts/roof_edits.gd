extends RefCounted
class_name LifeRoofEdits
## Replace one existing roof with validated dimensions; keep its identity and
## charge only the difference in the original area price. No live mutation.
const Building=preload("res://scripts/building_state.gd")
static func propose(current:Dictionary,operation:Variant,funds:Variant)->Dictionary:
	var error:String=Building.validate(current)
	if not error.is_empty():return {"ok":false,"error":error}
	if not operation is Dictionary or operation.get("op")!="roof_edit" or not Building.identifier(operation.get("id")) or not operation.get("record") is Dictionary or not Building.number(funds,0,1e9,true):return {"ok":false,"error":"Invalid roof replacement."}
	if int(current.revision)>=1000000000:return {"ok":false,"error":"Building revision limit reached."}
	var old:Dictionary=Building.find(current,operation.id)
	if old.is_empty() or Building._group_of(current,operation.id)!="roofs":return {"ok":false,"error":"That roof is no longer available."}
	var record:Dictionary=operation.record.duplicate(true)
	if record.has("id"):return {"ok":false,"error":"The roof's existing identity must be preserved."}
	record["id"]=str(old.id)
	if record==old:return {"ok":false,"error":"Move a corner, rotate, or choose a different pitch or finish."}
	var after:Dictionary=current.duplicate(true)
	for index:int in range(after.roofs.size()):
		if str(after.roofs[index].id)==str(old.id):after.roofs[index]=record
	error=Building.validate(after)
	if not error.is_empty():return {"ok":false,"error":error}
	var cost:int=roundi(float(record.w)*float(record.d)*18)-roundi(float(old.w)*float(old.d)*18)
	if int(funds)<cost or int(funds)-cost>1000000000:return {"ok":false,"error":"The roof replacement exceeds the available wallet."}
	after.revision=int(current.revision)+1
	return {"ok":true,"operation":operation.duplicate(true),"before":Building.fingerprint(current),"after":after,"cost":cost,"funds_before":int(funds),"funds_after":int(funds)-cost}
