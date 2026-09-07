extends RefCounted
class_name LifeCatalog

const ITEMS = {
	"sofa": {"label":"Sunday sofa", "category":"Comfort", "price":620, "size":Vector2(2.6,1.0), "height":1.1, "color":"78a599"},
	"bed": {"label":"Slow morning bed", "category":"Comfort", "price":840, "size":Vector2(1.95,2.3), "height":1.4, "color":"c58a73"},
	"fridge": {"label":"Fresh start fridge", "category":"Kitchen", "price":520, "size":Vector2(.9,.85), "height":1.9, "color":"86ada0"},
	"stove": {"label":"Home chef range", "category":"Kitchen", "price":480, "size":Vector2(1.05,.85), "height":1.2, "color":"e6dec9"},
	"counter": {"label":"Sage cabinet", "category":"Kitchen", "price":150, "size":Vector2(1.05,.8), "height":1.0, "color":"417a71"},
	"sink": {"label":"Brass & stone sink", "category":"Kitchen", "price":230, "size":Vector2(1.05,.8), "height":1.3, "color":"c8a562"},
	"dining": {"label":"Gathering table", "category":"Kitchen", "price":280, "size":Vector2(1.6,1.12), "height":1.0, "color":"d7ae7e"},
	"chair": {"label":"Everyday chair", "category":"Comfort", "price":85, "size":Vector2(.6,.6), "height":1.0, "color":"d7ae7e"},
	"toilet": {"label":"Porcelain toilet", "category":"Bathroom", "price":240, "size":Vector2(.7,.9), "height":1.1, "color":"eee8d9"},
	"shower": {"label":"Rainfall shower", "category":"Bathroom", "price":410, "size":Vector2(1.3,1.25), "height":2.3, "color":"8aada3"},
	"desk": {"label":"A little ambition", "category":"Activities", "price":540, "size":Vector2(1.65,.8), "height":1.3, "color":"ab7951"},
	"bookshelf": {"label":"Stories bookcase", "category":"Activities", "price":220, "size":Vector2(1.4,.5), "height":1.9, "color":"ab7951"},
	"easel": {"label":"Daydream easel", "category":"Activities", "price":180, "size":Vector2(.95,.85), "height":1.85, "color":"c97c66"},
	"tv": {"label":"Evening television", "category":"Activities", "price":650, "size":Vector2(2,.6), "height":1.5, "color":"406c72"},
	"table": {"label":"Chapter coffee table", "category":"Decor", "price":160, "size":Vector2(1.85,.9), "height":.8, "color":"d7ae7e"},
	"lamp": {"label":"Warm glow floor lamp", "category":"Decor", "price":95, "size":Vector2(.75,.75), "height":1.8, "color":"c8a562"},
	"nightstand": {"label":"Bedside companion", "category":"Decor", "price":130, "size":Vector2(.6,.55), "height":1, "color":"d7ae7e"},
	"plant": {"label":"A breath of green", "category":"Decor", "price":45, "size":Vector2(.8,.8), "height":1.5, "color":"749752"},
	"rug": {"label":"Sunwoven rug", "category":"Decor", "price":110, "size":Vector2(3.4,2.2), "height":.04, "color":"decfaf"},
	"painting": {"label":"Hills at dusk", "category":"Decor", "price":75, "size":Vector2(1.2,.1), "height":1.5, "color":"c97c66"}
}

static func get_item(kind: String) -> Dictionary:
	return ITEMS.get(kind, {})

static func starter_layout(lot: int = 0) -> Array:
	var a: Array = []
	var entries = [
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["stove",-3.1,-4.4,0],["sink",-2.02,-4.4,0],["counter",-0.94,-4.4,0],
		["dining",-3.5,-1.85,0],["chair",-3.5,-2.8,0],["chair",-3.5,-.92,180],
		["rug",-2.9,2.43,0],["sofa",-3.4,3.75,180],["table",-3.1,2.17,0],["tv",-4.95,.65,90],["lamp",-5.1,3.9,0],
		["plant",-.05,4.15,0],["bookshelf",-.05,-2.8,0],["easel",-.05,.0,-35],
		["bed",3.5,1.5,0],["nightstand",2.03,.65,0],["nightstand",4.98,.65,0],
		["desk",3.4,4.3,180],["chair",3.4,3.48,0],["plant",5.2,4.2,180],
		["shower",4.9,-4.13,0],["toilet",2.35,-4.1,0],["sink",5.15,-2.13,-90],
		["painting",-2.1,-4.91,0]
	]
	if lot == 2:
		entries = [["fridge",-5.2,-4.3,0],["bed",3.5,2.1,0],["toilet",2.35,-4.1,0],["shower",4.9,-4.13,0],["stove",-3.1,-4.4,0]]
	elif lot == 1:
		entries = [
			["fridge",-5.28,-4.3,0],["sink",-4.18,-4.4,0],["counter",-3.10,-4.4,0],["stove",-2.02,-4.4,0],
			["rug",-3.65,2.0,90],["sofa",-4.85,2.0,90],["table",-2.85,2.0,90],["tv",0,2.0,-90],["lamp",-5.15,4.1,0],
			["dining",-3.7,-1.4,90],["chair",-4.85,-1.4,90],["chair",-2.6,-1.4,-90],
			["easel",-.1,-.05,-35],["bookshelf",-.05,-2.8,0],["plant",-1.6,4.3,180],
			["bed",4.65,1.6,-90],["nightstand",5.3,-.1,0],["plant",2,3.7,0],
			["desk",3.6,4.3,180],["chair",3.6,3.48,0],
			["shower",4.9,-4.13,0],["toilet",2.35,-4.1,0],["sink",5.15,-2.13,-90],
			["painting",-3.6,-4.91,0]
		]
	for i in range(entries.size()):
		var e: Array = entries[i]
		a.append({"id":"item_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return a
