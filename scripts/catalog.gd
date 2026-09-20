extends RefCounted
class_name LifeCatalog

const ITEMS = {
	"bench": {"label":"Garden conversation bench", "category":"Comfort", "price":140, "size":Vector2(2,.72), "height":1.05, "color":"bb946c"},
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
	"painting": {"label":"Hills at dusk", "category":"Decor", "price":75, "size":Vector2(1.2,.1), "height":1.5, "color":"c97c66"},
	"armchair": {"label":"Reading nook armchair", "category":"Comfort", "price":260, "size":Vector2(1.0,.92), "height":1.0, "color":"d2a24b"},
	"loveseat": {"label":"Two-together loveseat", "category":"Comfort", "price":440, "size":Vector2(1.9,1.0), "height":1.1, "color":"6e5470"},
	"stool": {"label":"Kitchen stool", "category":"Comfort", "price":60, "size":Vector2(.5,.5), "height":.78, "color":"417a71"},
	"wardrobe": {"label":"Everyday wardrobe", "category":"Comfort", "price":380, "size":Vector2(1.25,.62), "height":2.05, "color":"ab7951"},
	"bathtub": {"label":"Long soak bathtub", "category":"Bathroom", "price":560, "size":Vector2(1.75,.9), "height":.62, "color":"faf6ea"},
	"computer": {"label":"Home office computer", "category":"Activities", "price":900, "size":Vector2(1.45,.75), "height":1.4, "color":"ab7951"},
	"piano": {"label":"Parlour upright piano", "category":"Activities", "price":1200, "size":Vector2(1.55,1.3), "height":1.36, "color":"624435"},
	"chess": {"label":"Quiet strategy games table", "category":"Activities", "price":240, "size":Vector2(.85,2.0), "height":.85, "color":"ab7951"},
	"treadmill": {"label":"Morning miles treadmill", "category":"Activities", "price":780, "size":Vector2(.85,1.95), "height":1.45, "color":"4a4f55"},
	"yoga_mat": {"label":"Sunrise yoga mat", "category":"Activities", "price":60, "size":Vector2(.7,1.85), "height":.05, "color":"6e5470"},
	"stereo": {"label":"Record night stereo", "category":"Activities", "price":300, "size":Vector2(.95,.45), "height":1.0, "color":"624435"},
	"toybox": {"label":"Toy chest of wonders", "category":"Activities", "price":90, "size":Vector2(.85,.55), "height":.65, "color":"9ec1cf"},
	"mirror": {"label":"Full-length mirror", "category":"Decor", "price":120, "size":Vector2(.75,.45), "height":1.75, "color":"c8a562"},
	"dressing_table": {"label":"Dressing table", "category":"Decor", "price":320, "size":Vector2(1.10,.72), "height":1.50, "color":"d7ae7e"},
	"garden_bed": {"label":"Kitchen garden bed", "category":"Decor", "price":140, "size":Vector2(1.65,.9), "height":.7, "color":"42352d"},
	"fireplace": {"label":"Hearth & home fireplace", "category":"Decor", "price":620, "size":Vector2(1.5,.55), "height":1.6, "color":"8c5a4a"},
	"side_table": {"label":"Corner side table", "category":"Decor", "price":70, "size":Vector2(.55,.55), "height":.95, "color":"d7ae7e"},
	"shelf": {"label":"Little things shelf", "category":"Decor", "price":85, "size":Vector2(.92,.26), "height":1.7, "color":"ab7951"},
	"wall_clock": {"label":"Steady hours wall clock", "category":"Decor", "price":40, "size":Vector2(.45,.1), "height":1.9, "color":"624435"},
	"book_nook": {"label":"Storybook reading nook", "category":"Activities", "price":240, "size":Vector2(1.5,.75), "height":1.7, "color":"8c5a4a"},
	"coffee_table": {"label":"Teatime coffee table", "category":"Decor", "price":150, "size":Vector2(1.15,.62), "height":.5, "color":"d7ae7e"},
	"floor_lamp": {"label":"Reading arc floor lamp", "category":"Decor", "price":110, "size":Vector2(.55,.55), "height":1.85, "color":"c8a562"},
	"rubbish_bin": {"label":"Pedal rubbish bin", "category":"Kitchen", "price":45, "size":Vector2(.45,.45), "height":.72, "color":"4a4f55"},
	# A counter-top espresso machine. It stands on the floor like every other
	# furnishing rather than on a worktop, so its declared box is the appliance's
	# own 42 x 55 cm footprint and its 86 cm column; the group head, portafilter
	# and cup shelf that face +z are inside that box. Beans cost a few ℒ at the
	# machine and the lift they give is the separate temporary-energy pool.
	"coffee_machine": {"label":"Counter-top espresso machine", "category":"Kitchen", "price":280, "size":Vector2(.42,.55), "height":.86, "color":"4a4f55"},
	"memorial": {"label":"Garden remembrance stone", "category":"Decor", "price":80, "size":Vector2(.72,.72), "height":.48, "color":"8c8a84"},
	"guitar": {"label":"Sit-and-strum guitar", "category":"Activities", "price":320, "size":Vector2(.5,.55), "height":1.05, "color":"d7ae7e"},
	"violin": {"label":"Evening violin", "category":"Activities", "price":380, "size":Vector2(.4,.5), "height":.65, "color":"624435"},
	"pet_bowl": {"label":"Food & water bowl", "category":"Pets", "price":60, "size":Vector2(.4,.32), "height":.12, "color":"c8a562"},
	"cat_tree": {"label":"Climbing cat tree", "category":"Pets", "price":240, "size":Vector2(.55,.55), "height":1.25, "color":"d7ae7e"},
	"kennel": {"label":"Garden dog kennel", "category":"Pets", "price":320, "size":Vector2(.95,1.1), "height":.85, "color":"8c5a4a"},
	"pet_bed_cat": {"label":"Cosy cat bed", "category":"Pets", "price":120, "size":Vector2(.62,.52), "height":.20, "color":"9aa7be"},
	"pet_bed_dog": {"label":"Cushioned dog bed", "category":"Pets", "price":160, "size":Vector2(.92,.68), "height":.32, "color":"9aa7be"},
	"pet_toy_cat": {"label":"Feather mouse toy", "category":"Pets", "price":25, "size":Vector2(.18,.18), "height":.18, "color":"c97c4e"},
	"pet_toy_dog": {"label":"Knotted rope bone", "category":"Pets", "price":30, "size":Vector2(.26,.16), "height":.12, "color":"c97c4e"},
	"cat_toy_box": {"label":"Cat Toy Box", "category":"Pets", "price":50, "size":Vector2(.56,.40), "height":.35, "color":"7fa8c6"},
	"dog_toy_box": {"label":"Dog Toy Box", "category":"Pets", "price":50, "size":Vector2(.56,.40), "height":.35, "color":"7fa8c6"},
	"urn": {"label":"Ceramic memorial urn", "category":"Decor", "price":120, "size":Vector2(.3,.3), "height":.42, "color":"3e6b65"},
	"tombstone": {"label":"Carved stone gravestone", "category":"Decor", "price":180, "size":Vector2(.56,.36), "height":.85, "color":"52555a"},
	# Vehicles. A garage is a building the household owns and a car is the thing
	# that parks in it, so both sit under Transport. They are deliberately the
	# dearest things in the catalogue — a car is saved for, and it costs about
	# what the parlour piano does while the building that shelters it costs more.
	# An entry that carries "paint" is bought in a colour of the player's own
	# choosing; the shade named here is the model's own authored Body tint.
	"garage": {"label":"The family garage", "category":"Transport", "price":1800, "size":Vector2(4.6,5.8), "height":2.59, "color":"417a71"},
	"electric_car": {"label":"Quiet miles electric car", "category":"Transport", "price":1250, "size":Vector2(1.79,4.19), "height":1.4775, "color":"c6d2da", "paint":"c6d2da"}
}

## The paints offered for a car, in the row's order, led by the shade the model
## already wears. Any six-digit shade is valid on a record — this is the palette
## a buy row offers, exactly as the coat and hair palettes are offered for a pet
## or a Lifelet rather than enforced on the save.
const CAR_PAINTS: Array[String] = [
	"c6d2da", "3f4a55", "1d2124", "8c1f28", "1f3b6b",
	"2f5f47", "8a6a2f", "b4553a", "6c4f8c", "e8e3d8",
]

## A piece whose volume is not one solid box lists the bands it really occupies,
## in its own local metres. The garage is the case: its solid back wall and both
## side walls (corner posts included) block, while the declared interior and the
## 4.28 m doorway stay clear, so a car — or two — parks inside. The rolled-up
## sectional door, its header and the roof are all overhead, which a floor-plan
## rectangle cannot express, so they are not bands. This is the staircase's own
## pattern — `stair_rect` plus `guard_footprints` rather than one solid volume —
## kept next to the size the ordinary box is derived from.
const BLOCKING_PANELS: Dictionary = {
	"garage": [
		{"x":0.0, "z":-2.835, "w":4.59, "d":0.12},
		{"x":-2.235, "z":0.0, "w":0.12, "d":5.79},
		{"x":2.235, "z":0.0, "w":0.12, "d":5.79}
	]
}

# Accessories for the household's pets. A cat tree is a cat's furnishing and a
# kennel is a dog's; the bowl suits either. LifePets owns that policy.
const PET_ACCESSORIES: Array[String] = ["pet_bowl", "cat_tree", "kennel"]

# The Build & buy filter row, in display order. Structure is the tool page.
const CATEGORIES: Array[String] = ["All", "Comfort", "Kitchen", "Bathroom", "Activities", "Decor", "Pets", "Transport", "Structure"]

# Instruments share one practice action; the authored model is the difference.
const INSTRUMENTS: Array[String] = ["guitar", "violin"]

# Floor coverings and wall decor: they never block routes, walls or other furnishings.
const PASSABLE: Array[String] = ["rug", "painting", "wall_clock", "shelf", "yoga_mat", "room_light", "memorial"]
const WALL_MOUNTED: Array[String] = ["painting", "wall_clock", "shelf"]

static func passable(kind: String) -> bool:
	return kind in PASSABLE

## The solid bands a kind occupies, in its own local metres: its authored ones
## when one box cannot describe it, otherwise the single box its declared size
## and depth describe. Only a kind the catalogue does not know returns nothing.
static func local_panels(kind: String) -> Array:
	var panels: Array = BLOCKING_PANELS.get(kind, [])
	if not panels.is_empty(): return panels
	var data: Dictionary = ITEMS.get(kind, {})
	if data.is_empty(): return []
	return [{"x":0.0, "z":0.0, "w":data.size.x, "d":data.size.y}]

## Whether a kind is bought in a colour of the player's own choosing.
static func paints(kind: String) -> bool:
	return ITEMS.get(kind, {}).has("paint")

## The paint a record carries: its own choice when it made one, the catalogue's
## authored tint otherwise. A record with no paint key keeps the model's finish.
static func paint_of(entry: Dictionary) -> String:
	var kind: String = str(entry.get("kind", ""))
	if not ITEMS.has(kind): return ""
	var value: String = str(entry.get("paint", ITEMS[kind].get("paint", ""))).trim_prefix("#").to_lower()
	return value if _shade(value) else ITEMS[kind].get("paint", "")

static func _shade(value: String) -> bool:
	if value.length() != 6: return false
	for index: int in range(6):
		if not "0123456789abcdef".contains(value[index]): return false
	return true

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
		["painting",-2.1,-4.91,0],["mirror",5.45,2.3,0],["rubbish_bin",.1,-4.45,0],
		["wardrobe",5.32,-0.35,-90]
	]
	if lot == 2:
		entries = [["fridge",-5.2,-4.3,0],["bed",3.5,2.1,0],["toilet",2.35,-4.1,0],["shower",4.9,-4.13,0],["stove",-3.1,-4.4,0],["wardrobe",5.32,0.85,-90]]
	elif lot == 1:
		entries = [
			["fridge",-5.28,-4.3,0],["sink",-4.18,-4.4,0],["counter",-3.10,-4.4,0],["stove",-2.02,-4.4,0],
			["rug",-3.65,2.0,90],["sofa",-4.85,2.0,90],["table",-2.85,2.0,90],["tv",0,2.0,-90],["lamp",-5.15,4.1,0],
			["dining",-3.7,-1.4,90],["chair",-4.85,-1.4,90],["chair",-2.6,-1.4,-90],
			["easel",-.1,-.05,-35],["bookshelf",-.05,-2.8,0],["plant",-1.6,4.3,180],
			["bed",4.65,1.6,-90],["nightstand",5.3,-.1,0],["plant",2,3.7,0],
			["desk",3.6,4.3,180],["chair",3.6,3.48,0],
			["shower",4.9,-4.13,0],["toilet",2.35,-4.1,0],["sink",5.15,-2.13,-90],
			["painting",-3.6,-4.91,0],["rubbish_bin",.1,-4.45,0],
			["wardrobe",5.32,3.35,-90]
		]
	for i in range(entries.size()):
		var e: Array = entries[i]
		a.append({"id":"item_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return a
