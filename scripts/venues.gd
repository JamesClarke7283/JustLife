extends RefCounted
class_name LifeVenues
## The working parts of Juniper Bay: the places a household travels to when a
## home cannot give it what it needs — fuel, the weekly shop, a haircut, a
## coffee, a workout, a classroom, a degree, and the visiting room at the prison.
##
## A venue is shaped exactly like a `LifeNeighborhood.PLACES` entry, so the
## travel picker, the public-venue builder and a save can treat all of them the
## same way. What each one *offers* is stated beside it as data, so the service
## list a player reads and the venue the game lays out come from one place
## rather than being described again in every panel.
##
## Every furnishing is an existing catalogue kind, and a layout is the same
## `["kind", x, z, rotation]` rows the neighborhood uses, so a venue is built
## from what the game already sells and nothing here invents a model. A kind the
## catalogue does not know would be dropped silently by the world builder, which
## is exactly what `validate` exists to catch.
##
## Pure static policy — no Nodes, no clock, no wallet.

const PLACES: Dictionary = {
	"cafe":{"name":"Bay Window Café","tag":"A table by the window","description":"A corner café with a long counter, an early cake stand and a reading nook by the shelves. Good for a quiet hour, a light lunch, or meeting somebody you have been meaning to see.","color":"b08055"},
	"hairdresser":{"name":"The Cutting Room","tag":"A fresh look for the week ahead","description":"A small salon with two styling chairs, a backwash basin and mirrors along the wall. Book a cut or a colour and leave with something you did not have before.","color":"c08ea0"},
	"shopping_centre":{"name":"Harbourgate Shopping Centre","tag":"One trip, one list","description":"A covered arcade of shops under one roof, with a food court in the middle and trolleys by the door. Most of the household's weekly shop is done here in a single outing.","color":"c2a06a"},
	"gymnasium":{"name":"The Movement Rooms","tag":"Work up a proper sweat","description":"A gymnasium of treadmills, mats and a small weights corner, with a shower and changing space along the back wall. Fitness is built here in the time a session takes.","color":"5f8f9a"},
	"petrol_station":{"name":"Bayview Filling Station","tag":"Tank up and go","description":"The last stop before the bypass: a lit forecourt, an air line and a kiosk that stays open later than anything else on the lane. Fill the car here, or plug an electric one into the fast charger.","color":"6f8f8b"},
	"school":{"name":"Juniper Bay School","tag":"Class is in session","description":"The town's school gates. Willow School takes the youngest pupils and Morrow Secondary the teenagers; the office here enrols both and keeps the term's records.","color":"8a9ab5"},
	"university":{"name":"Juniper Bay University","tag":"Study for something more","description":"A city campus of lecture rooms around a wide library, open to adults who want a degree. A qualification raises what the jobs that ask for one will pay, and a PHD is a doctor whatever the job.","color":"5a6f9a"},
	"prison":{"name":"Blackmoor Prison","tag":"Visiting hours twice a week","description":"A remand and resettlement prison on the road out of town, where a Lifelet who was caught serves their sentence. The visiting room has tables for families and a desk at the door.","color":"7a7b76"},
}

## What each venue offers a visitor, in the order a counter or an office would
## present it. A row is `[id, label, description]` so the table stays as compact
## as a layout row and the accessor turns it into the record the menus read.
##
## The services are described rather than priced: what a service costs, if
## anything, belongs to the trade that owns it (a degree's fee to the careers
## table, a fill of petrol to the household purse), so no second copy of a price
## can drift away from the one that charges it.
const _SERVICES: Dictionary = {
	"cafe":[
		["coffee_and_cake","Coffee and cake","A flat white and something from the counter, taken at a table by the window. Lifts a low mood for the rest of the afternoon."],
		["light_lunch","A light lunch","Soup, a sandwich or a salad between errands. A proper sit-down meal rather than something eaten standing up."],
		["takeaway_cup","A cup to take away","Tea or coffee in a paper cup for the walk home. Cheaper than sitting in, and just as warming."],
	],
	"hairdresser":[
		["haircut","Haircut","A wash, a cut and a tidy up at the chair. The quickest way to look like the week has started."],
		["colour_and_restyle","Colour and restyle","A new colour and a proper restyle, with the chair kept for as long as it takes. Books out the afternoon."],
		["wash_and_style","Wash and style","A wash and a blow-dry before an evening out. Nothing permanent — just the good version of the hair you have."],
	],
	"shopping_centre":[
		["weekly_shop","The weekly shop","One trolley, one trip: groceries and household things for the week ahead, gathered in a single outing."],
		["food_court","Food court","Something hot and a pot of tea between shops, taken at a table in the middle of the arcade."],
		["buy_clothes","Clothes shops","Try something on for the season and take it home. A wardrobe of new things for a Lifelet's next chapter."],
		["window_shopping","Window shopping","Wander the arcade and see what is in the windows. Free, sociable, and a pleasant way to spend an hour."],
	],
	"gymnasium":[
		["workout","Work out","Treadmills, mats and the weights corner, for as long as a session lasts. The fastest way to build Fitness."],
		["yoga_class","Yoga class","A taught class on the mats. Stretch, breathe, and put the day's tension down before going home."],
		["shower_and_change","Shower and change","Hot water and a changing room afterwards, so a Lifelet leaves clean and ready for whatever comes next."],
	],
	"petrol_station":[
		["fill_petrol","Fill up with petrol","Fill the household car's tank at the pump. A full tank is what makes the longer journeys out of town possible."],
		["charge_car","Charge an electric car","Plug in at the fast charger and wait while the battery fills. Slower than a fill-up, cheaper per mile, and quiet besides."],
		["air_and_water","Air, water and screen wash","Check the tyres and top up the washers before a long drive. A few minutes that saves a breakdown."],
		["forecourt_shop","Forecourt shop","Milk, bread and something for the journey, from a kiosk that opens later than anywhere else on the lane."],
	],
	"school":[
		["enrol_child","Enrol a child at Willow School","Bring a child to the school office. Lessons run on weekdays and every attended day builds their grade."],
		["enrol_teen","Enrol a teen at Morrow Secondary","Teenagers carry on at Morrow Secondary. The office confirms the first classroom day and the term's dates."],
		["parents_evening","Parents' evening","Meet the teacher and hear how the term is going, grade by grade, before the report is written."],
		["school_report","School report","Collect the term's record: days attended, homework prepared, and the grade that came out of them."],
	],
	"university":[
		["study_bachelors","Study for a Bachelors","The first rung of higher education. A Bachelors raises what every job that asks for one will pay."],
		["study_masters","Study for a Masters","A second degree for a Lifelet who already holds a Bachelors, and worth more again to the jobs that ask."],
		["study_phd","Study for a PHD","The highest qualification the game offers. A PHD is a doctor whatever job its holder goes on to do."],
		["university_library","The university library","Reading rooms and stacks open to anyone studying here, with a desk to work at for the afternoon."],
	],
	"prison":[
		["visit_family","Visit an incarcerated family member","Book a visiting slot and sit with your family member in the visiting room. Visiting hours are posted at the gate."],
		["hand_in_parcel","Hand in a parcel","Leave a small parcel of permitted items at the desk for a family member inside, to be collected at the next visit."],
		["release_day","Meet them at the gate","Be waiting when the sentence ends, and walk them home rather than letting them find their own way back."],
	],
}


## Every venue this file owns, in the order a household tends to meet them: the
## everyday errands first, then the places that change a life, then the one
## nobody plans to visit. Dictionary order is insertion order in Godot, so a
## single pass is already stable across runs and needs no sort.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in PLACES: out.append(id)
	return out


static func has(place: String) -> bool:
	return PLACES.has(place)


## One venue's row, or an empty dictionary for an id this file does not know.
## The row carries no `resident` key, so a venue here is never somebody's home
## and is always open to anybody who can reach it.
static func info(place: String) -> Dictionary:
	return PLACES.get(place, {})


## The furnishings a venue is built with, as the world builder reads them. The
## identity of every piece carries the venue's own prefix, so two venues can
## share a layout index without ever sharing a furnishing id.
static func layout(place: String) -> Array:
	var entries: Array = []
	match place:
		# Kiosk along the back wall, the car pulled up in front of it facing the
		# shop, and a bench where somebody waits for the tank to fill.
		"petrol_station": entries = [
			["counter",-3.4,-4.3,0],["fridge",-4.5,-4.3,0],
			["shelf",-2.0,-4.9,0],["shelf",-0.9,-4.9,0],["wall_clock",1.2,-4.9,0],
			["car",8.0,1.0,90],["bench",-4.9,1.4,90],
			["plant",-5.2,-1.2,0],["rubbish_bin",-4.8,3.6,0],
			["garden_light",5.3,4.2,0],["garden_light",-5.3,4.2,0],
		]
		# Shop fittings along the back wall, a food court in the middle of the
		# floor, and seating on the aisle side where shoppers rest their bags.
		"shopping_centre": entries = [
			["counter",-4.6,-4.3,0],["counter",-3.4,-4.3,0],["wardrobe",-1.6,-4.4,0],
			["shelf",0.0,-4.9,0],["shelf",1.1,-4.9,0],["shelf",2.2,-4.9,0],
			["bookshelf",4.2,-4.3,0],["wall_clock",-0.4,-4.9,0],
			["bench",5.5,-2.6,-90],["bench",5.5,-0.6,-90],["tv",5.6,1.0,-90],["mirror",5.6,3.9,180],
			["rug",-3.4,1.7,0],["dining",-3.4,1.7,0],["chair",-3.4,2.65,180],["chair",-3.4,0.75,0],
			["bench",-4.9,1.0,90],
			["plant",5.3,4.2,0],["plant",-5.2,-1.4,0],["plant",-5.2,-3.0,0],["rubbish_bin",4.6,4.5,0],
		]
		# Two styling chairs facing the mirrors, the basin at the end of that
		# wall, and the waiting bench turned away from the street.
		"hairdresser": entries = [
			["counter",-4.6,-4.3,0],["mirror",-2.6,-4.9,0],["mirror",-1.2,-4.9,0],
			["chair",-2.6,-3.0,180],["chair",-1.2,-3.0,180],
			["sink",1.0,-4.3,0],["chair",1.0,-3.2,180],
			["dressing_table",4.4,-4.3,0],["chair",4.4,-3.3,180],["wall_clock",3.4,-4.9,0],
			["bench",3.6,4.2,180],["floor_lamp",5.3,2.0,0],
			["plant",-5.2,1.4,0],["plant",5.3,-1.0,0],["rubbish_bin",-4.9,3.4,0],
		]
		# A servery along the back wall with stools at the counter, three tables
		# down the middle, and a sofa and reading nook at the far ends.
		"cafe": entries = [
			["counter",-4.6,-4.3,0],["counter",-3.5,-4.3,0],["sink",-2.4,-4.3,0],["fridge",-1.3,-4.3,0],
			["stool",-4.4,-3.35,180],["stool",-3.4,-3.35,180],
			["stereo",1.6,-4.5,0],["painting",3.0,-4.9,0],["wall_clock",0.6,-4.9,0],
			["book_nook",4.4,-4.4,0],["armchair",4.4,-3.4,180],
			["dining",-3.0,1.0,0],["chair",-3.0,1.95,180],["chair",-3.0,0.05,0],
			["dining",0.4,1.0,0],["chair",0.4,1.95,180],["chair",0.4,0.05,0],
			["dining",3.8,1.0,0],["chair",3.8,1.95,180],["chair",3.8,0.05,0],
			["rug",-3.6,3.3,0],["sofa",-3.6,4.2,180],["coffee_table",-3.6,2.8,0],
			["plant",5.3,-2.2,0],["plant",-5.3,-1.0,0],["plant",5.3,4.2,0],["rubbish_bin",5.3,3.6,0],
		]
		# Machines along the back wall, mats laid out in the middle of the floor,
		# the weights corner on the far side, and the changing room in the corner.
		"gymnasium": entries = [
			["treadmill",-4.4,-3.8,0],["treadmill",-3.2,-3.8,0],["treadmill",-2.0,-3.8,0],
			["shower",3.8,-4.2,0],["toilet",5.4,-4.2,0],["sink",5.5,-2.4,-90],
			["mirror",-5.65,-2.2,90],["mirror",-5.65,0.4,90],["wall_clock",-1.0,-4.9,0],
			["yoga_mat",0.2,0.8,0],["yoga_mat",1.6,0.8,0],["yoga_mat",3.0,0.8,0],["yoga_mat",4.4,0.8,0],
			["game_parallel_bars",4.5,3.6,0],["game_pull_up_bar",-3.0,3.6,0],
			["bench",-5.0,3.0,90],["stereo",1.4,4.4,180],
			["plant",-5.3,-0.8,0],["rubbish_bin",-4.9,4.4,0],
		]
		# The teacher's desk at the front facing the class, four pupils' desks in
		# two rows facing it, and the working corners down either side.
		"school": entries = [
			["bookshelf",-5.2,-4.3,0],["sink",1.0,-4.3,0],
			["desk",4.4,-3.6,0],["chair",4.4,-4.3,0],
			["desk",-3.4,-2.0,0],["chair",-3.4,-1.1,180],["desk",-1.6,-2.0,0],["chair",-1.6,-1.1,180],
			["desk",-3.4,0.6,0],["chair",-3.4,1.5,180],["desk",-1.6,0.6,0],["chair",-1.6,1.5,180],
			["computer",-5.2,1.6,90],["chair",-4.4,1.6,-90],["computer",-5.2,3.3,90],["chair",-4.4,3.3,-90],
			["piano",5.0,1.0,-90],["stool",4.0,1.0,90],["easel",3.6,3.4,180],
			["dining",1.2,3.6,0],["chair",1.2,4.5,180],["chair",1.2,2.7,0],
			["shelf",2.8,-4.9,0],["wall_clock",1.9,-4.9,0],["painting",-5.9,-2.6,90],
			["plant",5.4,-1.4,0],["plant",-5.4,-1.4,0],["rubbish_bin",5.4,4.4,0],
		]
		# Stacks along the back wall, reading desks and computer stations around
		# the edges, and a soft corner with a lamp at one end of the room.
		"university": entries = [
			["bookshelf",-5.1,-4.2,0],["bookshelf",-3.4,-4.2,0],["bookshelf",-1.7,-4.2,0],
			["bookshelf",1.4,-4.2,0],["bookshelf",3.1,-4.2,0],["bookshelf",4.8,-4.2,0],
			["wall_clock",0.0,-4.9,0],
			["rug",-2.6,0.6,0],["sofa",-2.6,-0.6,0],["table",-2.6,0.9,0],["armchair",-4.6,0.4,90],["lamp",-5.4,2.6,0],
			["desk",2.6,-1.0,0],["chair",2.6,-0.1,180],["desk",2.6,1.8,0],["chair",2.6,2.7,180],
			["computer",5.3,-1.2,90],["chair",4.4,-1.2,90],["computer",5.3,1.4,90],["chair",4.4,1.4,90],
			["dining",-2.6,3.4,0],["chair",-2.6,4.3,180],["chair",-2.6,2.5,0],
			["plant",5.4,3.8,0],["plant",-5.3,-1.6,0],["rubbish_bin",5.3,4.6,0],
		]
		# The visiting room: the officer's desk and the sign-in counter at the
		# door end, a waiting bench on each side, and family tables down the floor.
		"prison": entries = [
			["counter",-4.6,-4.3,0],["wall_clock",3.0,-4.9,0],
			["desk",-5.0,1.0,90],["chair",-4.1,1.0,-90],
			["dining",-2.2,-2.4,0],["chair",-2.2,-1.5,180],["chair",-2.2,-3.3,0],
			["dining",-2.2,2.6,0],["chair",-2.2,3.5,180],["chair",-2.2,1.7,0],
			["dining",1.2,2.6,0],["chair",1.2,3.5,180],["chair",1.2,1.7,0],
			["bench",5.4,-2.0,-90],["bench",5.4,1.2,-90],
			["toilet",5.3,3.8,180],["sink",3.6,4.3,180],
			["plant",-5.4,-2.6,0],["rubbish_bin",-5.0,4.4,0],
		]
	var result: Array = []
	for i in range(entries.size()):
		var e: Array = entries[i]
		result.append({"id":place + "_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return result


## The services this venue offers the player, each `{"id", "label",
## "description"}`. Unknown venues offer nothing rather than something invented.
static func offers(place: String) -> Array:
	var rows: Array = _SERVICES.get(place, [])
	var result: Array = []
	for row: Array in rows:
		result.append({"id":str(row[0]), "label":str(row[1]), "description":str(row[2])})
	return result


## Why this venue cannot be visited, as the player-readable reason. Empty means
## the doors are open. The travel picker and a venue being restored from a save
## read this one answer, so a venue the game cannot lay out is refused before
## the household is moved into a half-built room.
##
## The layout checks are the real work here: the world builder drops a
## furnishing whose kind the catalogue does not know without saying so, and a
## venue added to `PLACES` with no layout or no services is a forgotten `match`
## branch rather than a design choice. Both are silent in play and obvious here.
static func validate(place: String) -> String:
	if not has(place):
		return "That venue is not part of Juniper Bay."
	var row: Dictionary = info(place)
	for key: String in ["name", "tag", "description", "color"]:
		if str(row.get(key, "")).strip_edges().is_empty():
			return "The venue is missing its %s." % key
	var services: Array = offers(place)
	if services.is_empty():
		return "The venue has nothing to offer a visitor."
	var offered: Dictionary = {}
	for service: Dictionary in services:
		var id: String = str(service.id)
		if id.is_empty(): return "A service at this venue has no identity."
		if offered.has(id): return "Two services at this venue share an identity."
		offered[id] = true
	var furnishings: Array = layout(place)
	if furnishings.is_empty():
		return "The venue has no furnishings to lay out."
	var seen: Dictionary = {}
	for entry: Dictionary in furnishings:
		var kind: String = str(entry.kind)
		if not LifeCatalog.ITEMS.has(kind):
			return "The venue is furnished with an uncatalogued %s." % (kind if not kind.is_empty() else "kind")
		if not str(entry.id).begins_with(place + "_"):
			return "A furnishing is not identified with this venue."
		if seen.has(str(entry.id)): return "Two furnishings at this venue share an identity."
		seen[str(entry.id)] = true
	return ""
