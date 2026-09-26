extends RefCounted
class_name LifeCatalog

## Every garden game is offered at the same three garden sizes, so one list keeps
## the family consistent and the catalogue readable.
const GAMES_SIZES: Array[String] = ["small", "medium", "large"]

const ITEMS = {
	"bench": {"label":"Garden conversation bench", "category":"Comfort", "price":140, "size":Vector2(2,.72), "height":1.05, "color":"bb946c"},
	# A couch's places are its authored cushions: the sofa carries three seat
	# cushions at x = -0.70, 0 and 0.70 and the loveseat two at -0.37 and 0.37,
	# so `seat_count` states how many people each one really holds and
	# `seat_offsets` are those cushions' own local centres.
	"sofa": {"label":"Sunday sofa", "category":"Comfort", "price":620, "size":Vector2(2.6,1.0), "height":1.1, "color":"78a599", "seat_count":3, "seat_offsets":[-.70,0.0,.70]},
	"bed": {"label":"Double bed", "category":"Bedroom", "price":840, "size":Vector2(1.95,2.3), "height":1.4, "color":"c58a73",
		"sizes":["double","single"], "size_prices":{"double":840,"single":520}, "seats":{"double":2,"single":1},
		"size_labels":{"double":"Double","single":"Single"}},
	"fridge": {"label":"Fresh start fridge", "category":"Kitchen", "price":520, "size":Vector2(.9,.85), "height":1.9, "color":"86ada0"},
	"stove": {"label":"Home chef range", "category":"Kitchen", "price":480, "size":Vector2(1.05,.85), "height":1.2, "color":"e6dec9"},
	"counter": {"label":"Sage cabinet", "category":"Kitchen", "price":150, "size":Vector2(1.05,.8), "height":1.0, "color":"417a71"},
	"sink": {"label":"Brass & stone sink", "category":"Kitchen", "price":230, "size":Vector2(1.05,.8), "height":1.3, "color":"c8a562"},
	"dining": {"label":"Gathering table", "category":"Kitchen", "price":280, "size":Vector2(1.6,1.12), "height":1.0, "color":"d7ae7e"},
	"chair": {"label":"Everyday chair", "category":"Comfort", "price":85, "size":Vector2(.6,.6), "height":1.0, "color":"d7ae7e"},
	"toilet": {"label":"Porcelain toilet", "category":"Bathroom", "price":240, "size":Vector2(.7,.9), "height":1.1, "color":"eee8d9"},
	"shower": {"label":"Rainfall shower", "category":"Bathroom", "price":410, "size":Vector2(1.3,1.25), "height":2.3, "color":"8aada3"},
	"desk": {"label":"A little ambition", "category":"Activities", "price":540, "size":Vector2(1.65,.8), "height":1.3, "color":"ab7951"},
	"bookshelf": {"label":"Bookcase", "category":"Bedroom", "price":220, "size":Vector2(1.4,.5), "height":1.9, "color":"ab7951"},
	"easel": {"label":"Daydream easel", "category":"Activities", "price":180, "size":Vector2(.95,.85), "height":1.85, "color":"c97c66"},
	"tv": {"label":"Evening television", "category":"Activities", "price":650, "size":Vector2(2,.6), "height":1.5, "color":"406c72"},
	"table": {"label":"Chapter coffee table", "category":"Decor", "price":160, "size":Vector2(1.85,.9), "height":.8, "color":"d7ae7e"},
	"lamp": {"label":"Warm glow floor lamp", "category":"Decor", "price":95, "size":Vector2(.75,.75), "height":1.8, "color":"c8a562"},
	"nightstand": {"label":"Bedside table", "category":"Bedroom", "price":130, "size":Vector2(.6,.55), "height":1, "color":"d7ae7e"},
	"bedside_lamp": {"label":"Bedside lamp", "category":"Bedroom", "price":45, "size":Vector2(.28,.28), "height":.48, "color":"c8a562", "model":"lamp", "model_scale":0.32},
	"study_desk": {"label":"Study desk with laptop", "category":"Bedroom", "price":480, "size":Vector2(1.2,.7), "height":.78, "color":"ab7951", "model":"desk", "model_scale":0.82},
	"office_desk": {"label":"Home office desk", "category":"Bedroom", "price":900, "size":Vector2(1.45,.75), "height":1.4, "color":"ab7951", "model":"computer"},
	"desk_chair": {"label":"Desk chair", "category":"Bedroom", "price":85, "size":Vector2(.6,.6), "height":1.0, "color":"d7ae7e", "model":"chair"},
	"bath_mat": {"label":"Bath mat", "category":"Bathroom", "price":15, "size":Vector2(.7,1.15), "height":.04, "color":"f4f1ea",
		"styles":["plush","oval","grid"],
		"style_labels":{"plush":"Plush rectangular","oval":"Oval woven","grid":"Memory foam grid"},
		"colors":["f7f4ee","3a3d42","e6d8c5","1f3b6b","f4b6c8","8faf9f","c8d7e0","e0b15a","e07a5f","2a9d8f"]},
	"framed_picture": {"label":"Framed picture", "category":"Decor", "price":35, "size":Vector2(.72,.08), "height":.62, "color":"5c3a24",
		"wall_mounted":true, "hang":1.5,
		"styles":["animals","scenic","people"],
		"style_labels":{"animals":"Animals","scenic":"Scenic","people":"People"},
		"colors":["5c3a24","d7ae7e","f4f1ea","1d2124"]},
	"plant": {"label":"A breath of green", "category":"Decor", "price":45, "size":Vector2(.8,.8), "height":1.5, "color":"749752"},
	"rug": {"label":"Sunwoven rug", "category":"Decor", "price":110, "size":Vector2(3.4,2.2), "height":.04, "color":"decfaf"},
	"painting": {"label":"Hills at dusk", "category":"Decor", "price":75, "size":Vector2(1.2,.1), "height":1.5, "color":"c97c66", "hang":1.45},
	"armchair": {"label":"Reading nook armchair", "category":"Comfort", "price":260, "size":Vector2(1.0,.92), "height":1.0, "color":"d2a24b"},
	"loveseat": {"label":"Two-together loveseat", "category":"Comfort", "price":440, "size":Vector2(1.9,1.0), "height":1.1, "color":"6e5470", "seat_count":2, "seat_offsets":[-.37,.37]},
	"stool": {"label":"Kitchen stool", "category":"Comfort", "price":60, "size":Vector2(.5,.5), "height":.78, "color":"417a71"},
	"wardrobe": {"label":"Wardrobe", "category":"Bedroom", "price":380, "size":Vector2(1.25,.62), "height":2.05, "color":"ab7951"},
	"bathtub": {"label":"Long soak bathtub", "category":"Bathroom", "price":560, "size":Vector2(1.75,.9), "height":.62, "color":"faf6ea"},
	# ---------------------------------------------------------------- Baby & Kids
	# The nursery and a child's own room. A cot is where a baby sleeps, a child
	# bed is the next size up, and the changing table, potty and feeding set are
	# the pieces a caregiver works with. Every one is a real furnishing, so the
	# household can place, move, save and click it like anything else.
	"cot": {"label":"Nursery cot", "category":"Baby & Kids", "price":30, "size":Vector2(1.24,.64), "height":.74, "color":"ab7951",
		"seat_count":1, "shared_beds":true},
	"child_bed": {"label":"Child's own bed", "category":"Baby & Kids", "price":50, "size":Vector2(1.02,1.94), "height":.96, "color":"624435",
		"seat_count":1},
	"changing_table": {"label":"Changing table", "category":"Baby & Kids", "price":50, "size":Vector2(1.10,.56), "height":1.02, "color":"efe9da"},
	"potty": {"label":"Toddler potty", "category":"Baby & Kids", "price":10, "size":Vector2(.42,.36), "height":.26, "color":"9ec1cf"},
	"baby_bottle": {"label":"Baby bottle", "category":"Baby & Kids", "price":5, "size":Vector2(.10,.10), "height":.27, "color":"f2f7fa"},
	"baby_food": {"label":"Jar of baby food", "category":"Baby & Kids", "price":5, "size":Vector2(.12,.12), "height":.15, "color":"c9a05a"},
	"baby_toys": {"label":"Baby toys", "category":"Baby & Kids", "price":5, "size":Vector2(.90,.90), "height":.22, "color":"d2a24b"},
	"baby_mobile": {"label":"Nursery mobile", "category":"Baby & Kids", "price":25, "size":Vector2(.42,.42), "height":.85, "color":"c97c66",
		"styles":["stars","cloud"]},
	"baby_rattle": {"label":"Baby rattle", "category":"Baby & Kids", "price":8, "size":Vector2(.18,.18), "height":.22, "color":"c97c66"},
	"rocking_chair": {"label":"Nursery rocking chair", "category":"Baby & Kids", "price":80, "size":Vector2(.78,.90), "height":1.05, "color":"ab7951"},
	"baby_mat": {"label":"Baby play mat", "category":"Baby & Kids", "price":20, "size":Vector2(1.20,1.20), "height":.06, "color":"d2a24b"},
	"children_picture": {"label":"Children's picture", "category":"Baby & Kids", "price":15, "size":Vector2(.72,.08), "height":.72, "color":"c97c66",
		"styles":["01","02","03","04","05"], "wall_mounted":true, "hang":1.35},
	"dollhouse": {"label":"Dollhouse", "category":"Baby & Kids", "price":60, "size":Vector2(.95,.55), "height":1.05, "color":"d7ae7e",
		"styles":["classic","cottage"]},
	"train_set": {"label":"Wooden train set", "category":"Baby & Kids", "price":40, "size":Vector2(1.10,.70), "height":.18, "color":"ab7951",
		"styles":["oval","figure8"]},
	"child_rug": {"label":"Child rug", "category":"Baby & Kids", "price":30, "size":Vector2(1.6,1.2), "height":.04, "color":"decfaf",
		"sizes":["small","medium","large"], "size_prices":{"small":30,"medium":50,"large":80}},
	"child_desk": {"label":"Child desk", "category":"Baby & Kids", "price":55, "size":Vector2(.95,.55), "height":.72, "color":"ab7951",
		"styles":["plain","shelf"]},
	"child_chair": {"label":"Child chair", "category":"Baby & Kids", "price":20, "size":Vector2(.42,.42), "height":.55, "color":"d7ae7e",
		"styles":["plain","arms"]},
	# Structure → Paint wall offers the same five patterns and ten colours at
	# ℒ5/m²; the Baby & Kids catalogue panel keeps the authored meshes for
	# placement when a household wants a freestanding sample board.
	"nursery_paint": {"label":"Nursery wall paint", "category":"Baby & Kids", "rate_per_square_metre":5, "size":Vector2(2.0,.04), "height":2.2, "color":"8faf9f", "tint":true,
		"styles":["stars","clouds","animals","dots","stripes"],
		"colors":["8faf9f","d9a0a0","9ec1cf","efeadb","c97c66","6e5470","c9a05a","7195b3","decfaf","4a6b5c"],
		"wall_mounted":true},
	"toy_chest": {"label":"Toy chest", "category":"Baby & Kids", "price":40, "size":Vector2(.9,.55), "height":.7, "color":"ab7951", "tint":true,
		"colors":["ab7951","c97c66","6f8fa8","417a71","c9a05a"]},
	"nursery_room_pack": {"label":"Nursery room pack", "category":"Baby & Kids", "price":2000, "size":Vector2(4.5,4.0), "height":2.2, "color":"8faf9f", "room_pack":true,
		"description":"Builds a carpeted 4.5 × 4 m nursery with its own doorway, sharing any wall it meets, then furnishes it: cot, mobile, changing table, rocking chair, play mat, pictures and curtains. ℒ2000 all in."},
	"child_bedroom_pack": {"label":"Child bedroom pack", "category":"Baby & Kids", "price":2000, "size":Vector2(4.5,4.0), "height":2.2, "color":"d7ae7e", "room_pack":true,
		"description":"Builds a carpeted 4.5 × 4 m child's bedroom with its own doorway, sharing any wall it meets, then furnishes it: bed, bedside table, floor lamp, rug, painting, and a desk with a home computer and chair. ℒ2000 all in."},
	"computer": {"label":"Home office computer", "category":"Activities", "price":900, "size":Vector2(1.45,.75), "height":1.4, "color":"ab7951"},
	"piano": {"label":"Parlour upright piano", "category":"Activities", "price":1200, "size":Vector2(1.55,1.3), "height":1.36, "color":"624435"},
	"chess": {"label":"Quiet strategy games table", "category":"Activities", "price":240, "size":Vector2(.85,2.0), "height":.85, "color":"ab7951"},
	"treadmill": {"label":"Morning miles treadmill", "category":"Activities", "price":780, "size":Vector2(.85,1.95), "height":1.45, "color":"4a4f55"},
	"yoga_mat": {"label":"Sunrise yoga mat", "category":"Activities", "price":60, "size":Vector2(.7,1.85), "height":.05, "color":"6e5470"},
	"stereo": {"label":"Record night stereo", "category":"Activities", "price":300, "size":Vector2(.95,.45), "height":1.0, "color":"624435"},
	"toybox": {"label":"Toy chest of wonders", "category":"Activities", "price":90, "size":Vector2(.85,.55), "height":.65, "color":"9ec1cf"},
	"mirror": {"label":"Full-length mirror", "category":"Decor", "price":120, "size":Vector2(.75,.45), "height":1.75, "color":"c8a562"},
	"dressing_table": {"label":"Dressing table", "category":"Bedroom", "price":320, "size":Vector2(1.10,.72), "height":1.50, "color":"d7ae7e"},
	"garden_bed": {"label":"Kitchen garden bed", "category":"Decor", "price":140, "size":Vector2(1.65,.9), "height":.7, "color":"42352d"},
	"fireplace": {"label":"Hearth & home fireplace", "category":"Decor", "price":620, "size":Vector2(1.5,.55), "height":1.6, "color":"8c5a4a"},
	"side_table": {"label":"Corner side table", "category":"Decor", "price":70, "size":Vector2(.55,.55), "height":.95, "color":"d7ae7e"},
	"shelf": {"label":"Little things shelf", "category":"Decor", "price":85, "size":Vector2(.92,.26), "height":1.7, "color":"ab7951", "hang":1.55},
	"wall_clock": {"label":"Steady hours wall clock", "category":"Decor", "price":40, "size":Vector2(.45,.1), "height":1.9, "color":"624435", "hang":1.7},
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
	"litter_tray": {"label":"Litter tray", "category":"Pets", "price":80, "size":Vector2(.56,.40), "height":.14, "color":"c9c3a8", "tint":true,
		"colors":["c9c3a8","8faf9f","6f8fa8","d9a0a0","4a4f55"]},
	"urn": {"label":"Ceramic memorial urn", "category":"Decor", "price":120, "size":Vector2(.3,.3), "height":.42, "color":"3e6b65"},
	"tombstone": {"label":"Carved stone gravestone", "category":"Decor", "price":180, "size":Vector2(.56,.36), "height":.85, "color":"52555a"},

	# ---------------------------------------------------------------- garden
	# Every garden family below names its axes explicitly: `styles` are separate
	# authored meshes, `tint` offers the shared ten-tone palette on the model's
	# `Tint` surface, and `sizes` scale the authored mesh and price it apart.
	# `size_prices` and `seats` therefore read per size rather than being fixed.
	"post_box": {"label":"Garden post box", "category":"Garden", "price":45, "size":Vector2(.45,.45), "height":1.15, "color":"4a6b5c", "tint":true},
	# A fence is sold by the square metre of panel face, so a taller or longer
	# run costs proportionally more from the one rate rather than a second table.
	"fence": {"label":"Garden fence", "category":"Garden", "rate_per_square_metre":10, "size":Vector2(2.0,.12), "height":1.2, "color":"c9c3a8", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10"],
		"sizes":["small","medium","large"]},
	"garden_gate": {"label":"Garden gate", "category":"Garden", "price":40, "size":Vector2(1.0,.12), "height":1.2, "color":"c9c3a8"},
	"garden_gate_double": {"label":"Wide double gate", "category":"Garden", "price":70, "size":Vector2(2.0,.12), "height":1.2, "color":"c9c3a8"},
	"garden_light": {"label":"Garden path light", "category":"Garden", "price":35, "size":Vector2(.22,.22), "height":.9, "color":"4a4f55", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10"]},
	"garden_light_wall": {"label":"Garden wall light", "category":"Garden", "price":30, "size":Vector2(.22,.30), "height":.42, "color":"4a4f55", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10"], "wall_mounted":true, "hang":1.6},
	"garden_table": {"label":"Garden table & chairs", "category":"Garden", "price":50, "size":Vector2(2.0,2.0), "height":2.3, "color":"d7ae7e", "tint":true,
		"sizes":["small","medium","large"], "size_prices":{"small":50,"medium":70,"large":90}, "seats":{"small":4,"medium":8,"large":10}},
	"bbq": {"label":"Barbecue", "category":"Garden", "price":100, "size":Vector2(.9,.7), "height":1.05, "color":"52555a", "tint":true,
		"styles":["round","barrel","brick"], "sizes":["small","medium","large"], "size_prices":{"small":100,"medium":300,"large":500}},
	"hot_tub": {"label":"Hot tub", "category":"Pool", "price":300, "size":Vector2(1.8,1.7), "height":.85, "color":"8faf9f", "tint":true,
		"styles":["round","square","oval"]},
	"outdoor_tv": {"label":"Outdoor television", "category":"Outdoor", "price":100, "size":Vector2(1.4,.6), "height":1.5, "color":"4a4f55", "tint":true,
		"styles":["classic","console","stand"], "sizes":["small","medium","large"], "size_prices":{"small":100,"medium":200,"large":300}},
	"outdoor_swing": {"label":"Garden swing", "category":"Outdoor", "price":100, "size":Vector2(2.2,1.4), "height":2.1, "color":"d7ae7e", "tint":true,
		"styles":["a","b","c"], "sizes":["small","medium","large"], "size_prices":{"small":100,"medium":400,"large":500},
		"seats":{"small":4,"medium":5,"large":8}},
	"tree_garden": {"label":"Garden tree", "category":"Garden", "price":100, "size":Vector2(1.8,1.8), "height":2.4, "color":"749752", "tint":true,
		"styles":["a","b","c","d","e","f","g","h","i","j"], "sizes":["small","medium","large"], "size_prices":{"small":100,"medium":200,"large":1000}},
	"shrub": {"label":"Garden shrub", "category":"Garden", "price":10, "size":Vector2(.8,.8), "height":.7, "color":"48794b", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20"],
		"sizes":["small","medium","large"], "size_prices":{"small":10,"medium":15,"large":30}},
	"flowers": {"label":"Garden flowers", "category":"Garden", "price":10, "size":Vector2(.5,.5), "height":.45, "color":"d9a0a0", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20"],
		"sizes":["small","medium","large"], "size_prices":{"small":10,"medium":15,"large":30}},
	"garden_ready": {"label":"Ready-made garden", "category":"Garden", "price":400, "size":Vector2(4.0,3.0), "height":2.2, "color":"6b7d5a", "tint":true,
		"styles":["plain","tree","rocks","tree_rocks"], "sizes":["small","medium","large"],
		"size_prices":{"small":400,"medium":900,"large":1800}},

	# ------------------------------------------------------------------ pool
	# The authored footprint is the small pool, and it fits the free ring the
	# starter home leaves in the garden; a medium or large pool needs the wider
	# ground a bigger garden or a cleared lot gives it.
	"pool": {"label":"Swimming pool", "category":"Pool", "price":400, "size":Vector2(4.0,3.0), "height":.35, "color":"7fb8c6", "tint":true,
		"styles":["classic","roman","lagoon"], "sizes":["small","medium","large"], "size_prices":{"small":400,"medium":600,"large":800}},
	"pool_ladder": {"label":"Pool ladder", "category":"Pool", "price":20, "size":Vector2(.6,.6), "height":1.1, "color":"b9bec2", "tint":true},
	"pool_slide": {"label":"Pool slide", "category":"Pool", "price":20, "size":Vector2(1.2,2.4), "height":1.6, "color":"c9a05a", "tint":true,
		"styles":["curved","straight","spiral"]},
	"pool_ring": {"label":"Rubber ring", "category":"Pool", "price":5, "size":Vector2(.9,.9), "height":.15, "color":"c97c4e", "tint":true},
	"pool_noodle": {"label":"Swimming pool noodle float", "category":"Pool", "price":5, "size":Vector2(1.5,.16), "height":.16, "color":"d9a0a0", "tint":true},
	"pool_light": {"label":"Pool light", "category":"Pool", "price":20, "size":Vector2(.24,.24), "height":.10, "color":"e6d8c5", "tint":true},

	# ------------------------------------------------------------------ kids
	"kids_swing": {"label":"Kids swing set", "category":"Kids", "price":100, "size":Vector2(2.6,1.6), "height":2.0, "color":"c9a05a", "tint":true,
		"styles":["a","b","c"]},
	"sand_pit": {"label":"Kids sand pit", "category":"Kids", "price":100, "size":Vector2(1.8,1.8), "height":.3, "color":"d7ae7e", "tint":true, "colors":["c9a05a","6f8fa8","d9a0a0","8faf9f","a8674f"],
		"sizes":["small","medium","large"], "size_prices":{"small":100,"medium":300,"large":500},
		"seats":{"small":2,"medium":3,"large":5}},
	"kids_slide": {"label":"Kids slide", "category":"Kids", "price":100, "size":Vector2(.9,1.8), "height":1.2, "color":"c97c4e", "tint":true, "colors":["c97c4e","6f8fa8","c9a05a","d9a0a0","8faf9f"]},
	"adult_slide": {"label":"Adult slide", "category":"Kids", "price":180, "size":Vector2(1.2,2.6), "height":2.0, "color":"6f8fa8", "tint":true, "colors":["6f8fa8","c97c4e","c9a05a","d9a0a0","8faf9f","4a6b5c"]},
	"climbing_frame": {"label":"Kids climbing frame", "category":"Kids", "price":100, "size":Vector2(2.8,2.2), "height":2.2, "color":"c9a05a", "tint":true, "colors":["c9a05a","6f8fa8","c97c4e","8faf9f","7d6b93"],
		"styles":["a","b","c","d"]},
	# Baby and child transport for neighbourhood walks and car journeys.
	"baby_pram": {"label":"Baby pram", "category":"Kids", "price":50, "size":Vector2(1.0,.6), "height":1.0, "color":"d9a0a0", "tint":true,
		"styles":[""], "colors":["d9a0a0","c97c66","6f8fa8","417a71","c9a05a","efeadb","4a4f55","7d6b93","8faf9f","a8674f"]},
	"pushchair": {"label":"Pushchair", "category":"Kids", "price":50, "size":Vector2(.9,.55), "height":1.05, "color":"6f8fa8", "tint":true,
		"styles":[""], "colors":["6f8fa8","c97c66","d9a0a0","417a71","c9a05a","efeadb","4a4f55","7d6b93","8faf9f","a8674f"]},
	"baby_car_seat": {"label":"Baby car seat", "category":"Vehicles", "price":50, "size":Vector2(.55,.55), "height":.65, "color":"c97c66", "tint":true,
		"styles":[""], "colors":["c97c66","6f8fa8","d9a0a0","417a71","c9a05a","efeadb","4a4f55","7d6b93","8faf9f","a8674f"]},
	"child_car_seat": {"label":"Child car seat", "category":"Vehicles", "price":50, "size":Vector2(.6,.55), "height":.75, "color":"417a71", "tint":true,
		"styles":[""], "colors":["417a71","c97c66","6f8fa8","d9a0a0","c9a05a","efeadb","4a4f55","7d6b93","8faf9f","a8674f"]},
	# Curtain packs: two panels that snap over a window. Ten authored styles
	# (tools/create_curtains.py) × ten colours on the fabric's Tint surface.
	"curtains": {"label":"Curtain set", "category":"Decor", "price":100, "size":Vector2(2.6,.14), "height":2.4, "color":"c97c66", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10"],
		"style_labels":{"01":"Pinch pleat","02":"Tab top","03":"Tied back","04":"Café","05":"Box pelmet","06":"Swag and tails","07":"Layered sheer","08":"Eyelet","09":"Shaped pelmet","10":"Nursery scallop"},
		"colors":["c97c66","417a71","efeadb","7195b3","bd9b68","3d4145","d9a0a0","6e5470","8faf9f","a8674f"],
		"wall_mounted":true, "window_snap":true},
	# Structure openings: five authored silhouettes × ten Tint colours
	# (tools/create_doors_windows.py). Doors hang in a cut doorway; windows
	# carry an aperture so curtains can centre on them.
	"house_door": {"label":"Door", "category":"Decor", "price":120, "size":Vector2(.96,.08), "height":2.1, "color":"8faf9f", "tint":true,
		"styles":["a","b","c","d","e"],
		"style_labels":{"a":"Panel","b":"Half-lite","c":"Arched","d":"Cottage","e":"French"},
		"colors":["8faf9f","6f8fa8","c9a05a","a8674f","7d6b93","c9c3a8","5b7c6a","d9a0a0","4a4f55","e6d8c5"],
		"wall_mounted":true, "cuts_doorway":true},
	"archway": {"label":"Archway", "category":"Structure", "price":90, "size":Vector2(1.24,.14), "height":2.4, "color":"eae7d7", "tint":true,
		"styles":["round","roman","tudor"],
		"style_labels":{"round":"Round","roman":"Roman","tudor":"Tudor"},
		"colors":["eae7d7","8faf9f","6f8fa8","c9a05a","a8674f","7d6b93","c9c3a8","d9a0a0","4a4f55","5b7c6a"],
		"wall_mounted":true, "cuts_doorway":true},
	"house_window": {"label":"Window", "category":"Decor", "price":90, "size":Vector2(1.9,.1), "height":1.5, "color":"efeadb", "tint":true,
		"styles":["a","b","c","d","e"],
		"style_labels":{"a":"Cross","b":"Two-lite","c":"Six-pane","d":"Arch bar","e":"Picture"},
		"colors":["efeadb","8faf9f","6f8fa8","c9a05a","a8674f","7d6b93","c9c3a8","d9a0a0","4a4f55","7195b3"],
		"wall_mounted":true, "window_aperture":true},
	# A bike is ridden: riding needs a helmet, and `ride_from` names the youngest
	# life stage that may ride each one, so a child takes the small bike.
	"bike_adult": {"label":"Adult bicycle", "category":"Vehicles", "price":120, "size":Vector2(1.7,.5), "height":1.1, "color":"4a6b5c", "tint":true,
		"styles":["a","b","c","d"], "colors":["4a6b5c","6f8fa8","c9a05a","a8674f","4a4f55"], "ride_from":"teen"},
	"bike_kids": {"label":"Kids bicycle", "category":"Kids", "price":60, "size":Vector2(1.1,.4), "height":.75, "color":"c97c4e", "tint":true,
		"styles":["a","b","c","d"], "colors":["c97c4e","6f8fa8","c9a05a","d9a0a0","4a4f55"], "ride_from":"child", "ride_until":"teen"},
	"helmet": {"label":"Bicycle helmet", "category":"Vehicles", "price":20, "size":Vector2(.26,.32), "height":.20, "color":"c9a05a", "tint":true,
		"styles":["a","b","c"]},

	# -------------------------------------------------------------- vehicles
	"car": {"label":"Car", "category":"Vehicles", "price":200, "size":Vector2(4.2,1.8), "height":1.5, "color":"4a6b5c", "tint":true,
		"styles":["saloon_a","saloon_b","hatchback","estate","coupe","van","minibus","suv","offroader","pickup"],
		"sizes":["small","medium","large"], "size_prices":{"small":200,"medium":400,"large":1500},
		"seats":{"small":5,"medium":8,"large":5}},
	"garage": {"label":"Garage", "category":"Vehicles", "price":100, "size":Vector2(3.2,3.0), "height":2.4, "color":"8c5a4a", "tint":true,
		"styles":["brick","timber","lean_to","double","carport"],
		"sizes":["small","medium","large"], "size_prices":{"small":100,"medium":200,"large":500},
		"seats":{"small":2,"medium":4,"large":8}},
	# An electric car is charged rather than filled, and the charger is what
	# makes it usable: it is bought for the wall of a garage or a driveway and
	# the car plugs into it at home.
	"car_electric": {"label":"Electric car", "category":"Vehicles", "price":900, "size":Vector2(4.2,1.8), "height":1.5, "color":"6f8fa8", "tint":true,
		"styles":[""],
		"sizes":["small","medium","large"], "size_prices":{"small":900,"medium":1800,"large":4200},
		"seats":{"small":5,"medium":5,"large":5}},
	"electric_charger": {"label":"Wall charger", "category":"Vehicles", "price":650, "size":Vector2(.34,.22), "height":1.1, "color":"4a6b5c", "tint":true,
		"styles":[""],
		"sizes":["small","medium","large"], "size_prices":{"small":650,"medium":650,"large":650},
		"wall_mounted":true, "charges":"car_electric"},

	# --------------------------------------------------------- garden games
	# Fifty garden activities. Each is its own family with its own authored model
	# and the shared ten-tone tint, and each offers the three garden sizes so a
	# small yard and a large one can both hold the same game at their own scale.
	# What each one teaches lives in LifeGardenGames, beside the action table.
	"game_trampoline": {"label":"Trampoline", "category":"Kids", "price":180, "size":Vector2(1.5,1.5), "height":.6, "color":"4a4f55", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":180,"medium":320,"large":520}},
	"game_hopscotch": {"label":"Hopscotch", "category":"Kids", "price":30, "size":Vector2(1.0,1.8), "height":.04, "color":"e6d8c5", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":30,"medium":55,"large":90}},
	"game_hoop": {"label":"Garden hoop", "category":"Garden", "price":25, "size":Vector2(.7,.7), "height":1.1, "color":"c97c4e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":25,"medium":45,"large":75}},
	"game_skipping_rope": {"label":"Skipping rope", "category":"Kids", "price":12, "size":Vector2(.5,.5), "height":.12, "color":"c9a05a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":12,"medium":22,"large":36}},
	"game_dartboard": {"label":"Dartboard", "category":"Activities", "price":60, "size":Vector2(.6,.4), "height":1.5, "color":"c9c3a8", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":60,"medium":105,"large":170}},
	"game_croquet": {"label":"Croquet set", "category":"Garden", "price":75, "size":Vector2(2.0,1.2), "height":.4, "color":"6b7d5a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":75,"medium":130,"large":210}},
	"game_ring_toss": {"label":"Ring toss", "category":"Garden", "price":30, "size":Vector2(.9,.9), "height":.5, "color":"8faf9f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":30,"medium":55,"large":90}},
	"game_mini_golf": {"label":"Mini golf", "category":"Garden", "price":90, "size":Vector2(1.8,.9), "height":.3, "color":"749752", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":90,"medium":160,"large":260}},
	"game_bowling": {"label":"Garden bowling", "category":"Garden", "price":55, "size":Vector2(.8,1.4), "height":.4, "color":"d7ae7e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":55,"medium":95,"large":155}},
	"game_table_tennis": {"label":"Table tennis", "category":"Activities", "price":200, "size":Vector2(2.4,1.2), "height":.9, "color":"6f8fa8", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":200,"medium":350,"large":560}},
	"game_badminton": {"label":"Badminton", "category":"Activities", "price":85, "size":Vector2(1.6,1.0), "height":1.6, "color":"8faf9f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":85,"medium":150,"large":240}},
	"game_football_goal": {"label":"Football goal", "category":"Activities", "price":95, "size":Vector2(2.0,.9), "height":1.4, "color":"c9c3a8", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":95,"medium":165,"large":265}},
	"game_basketball": {"label":"Basketball hoop", "category":"Activities", "price":140, "size":Vector2(.9,.9), "height":2.4, "color":"4a4f55", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":140,"medium":245,"large":390}},
	"game_bean_bags": {"label":"Bean bag toss", "category":"Garden", "price":40, "size":Vector2(.8,.8), "height":.5, "color":"a8674f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":40,"medium":70,"large":115}},
	"game_horseshoes": {"label":"Horseshoes", "category":"Garden", "price":45, "size":Vector2(1.2,1.0), "height":.4, "color":"7d6b93", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":45,"medium":80,"large":130}},
	"game_boules": {"label":"Boules", "category":"Garden", "price":50, "size":Vector2(.8,.8), "height":.2, "color":"8faf9f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":50,"medium":90,"large":145}},
	"game_skittles": {"label":"Skittles", "category":"Garden", "price":40, "size":Vector2(1.0,.6), "height":.4, "color":"c9a05a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":40,"medium":70,"large":115}},
	"game_quotis": {"label":"Quoits", "category":"Garden", "price":35, "size":Vector2(.9,.9), "height":.4, "color":"d9a0a0", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":35,"medium":60,"large":100}},
	"game_shuffleboard": {"label":"Shuffleboard", "category":"Activities", "price":110, "size":Vector2(2.2,.7), "height":.4, "color":"d7ae7e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":110,"medium":190,"large":305}},
	"game_connect_four": {"label":"Giant connect four", "category":"Garden", "price":80, "size":Vector2(.8,.6), "height":1.1, "color":"6f8fa8", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":80,"medium":140,"large":225}},
	"game_giant_chess": {"label":"Giant chess", "category":"Garden", "price":150, "size":Vector2(1.8,1.8), "height":.5, "color":"c9c3a8", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":150,"medium":260,"large":420}},
	"game_checkers": {"label":"Checkers", "category":"Garden", "price":45, "size":Vector2(.9,.9), "height":.5, "color":"52555a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":45,"medium":80,"large":130}},
	"game_dominoes": {"label":"Giant dominoes", "category":"Garden", "price":55, "size":Vector2(1.0,.7), "height":.3, "color":"e6d8c5", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":55,"medium":95,"large":155}},
	"game_jenga": {"label":"Giant jenga", "category":"Garden", "price":65, "size":Vector2(.6,.6), "height":1.0, "color":"d7ae7e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":65,"medium":115,"large":185}},
	"game_twister": {"label":"Twister mat", "category":"Kids", "price":35, "size":Vector2(1.6,1.2), "height":.04, "color":"d9a0a0", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":35,"medium":60,"large":100}},
	"game_obstacle_course": {"label":"Obstacle course", "category":"Activities", "price":220, "size":Vector2(2.6,2.0), "height":1.2, "color":"c97c4e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":220,"medium":385,"large":620}},
	"game_balance_beam": {"label":"Balance beam", "category":"Kids", "price":50, "size":Vector2(1.8,.4), "height":.4, "color":"6b7d5a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":50,"medium":90,"large":145}},
	"game_monkey_bars": {"label":"Monkey bars", "category":"Kids", "price":190, "size":Vector2(2.0,1.0), "height":1.9, "color":"8faf9f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":190,"medium":330,"large":535}},
	"game_parallel_bars": {"label":"Parallel bars", "category":"Activities", "price":160, "size":Vector2(.9,1.6), "height":1.2, "color":"4a4f55", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":160,"medium":280,"large":450}},
	"game_pull_up_bar": {"label":"Pull-up bar", "category":"Activities", "price":120, "size":Vector2(.9,.9), "height":2.2, "color":"4a4f55", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":120,"medium":210,"large":335}},
	"game_sandpit_toys": {"label":"Sandpit toys", "category":"Kids", "price":15, "size":Vector2(.7,.7), "height":.25, "color":"c9a05a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":15,"medium":25,"large":45}},
	"game_water_table": {"label":"Water play table", "category":"Kids", "price":70, "size":Vector2(1.0,.6), "height":.6, "color":"7fb8c6", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":70,"medium":120,"large":195}},
	"game_mud_kitchen": {"label":"Mud kitchen", "category":"Kids", "price":85, "size":Vector2(1.1,.7), "height":.9, "color":"a8674f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":85,"medium":150,"large":240}},
	"game_bubble_station": {"label":"Bubble station", "category":"Kids", "price":40, "size":Vector2(.7,.7), "height":.8, "color":"7fb8c6", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":40,"medium":70,"large":115}},
	"game_kite": {"label":"Kite", "category":"Kids", "price":20, "size":Vector2(.6,.6), "height":.5, "color":"d9a0a0", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":20,"medium":35,"large":60}},
	"game_skate_ramp": {"label":"Skate ramp", "category":"Activities", "price":240, "size":Vector2(1.6,1.2), "height":.9, "color":"52555a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":240,"medium":420,"large":680}},
	"game_roller_skates": {"label":"Roller skates", "category":"Activities", "price":45, "size":Vector2(.6,.5), "height":.3, "color":"c97c4e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":45,"medium":80,"large":130}},
	"game_space_hopper": {"label":"Space hopper", "category":"Kids", "price":25, "size":Vector2(.6,.6), "height":.6, "color":"c9a05a", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":25,"medium":45,"large":75}},
	"game_pogo_stick": {"label":"Pogo stick", "category":"Kids", "price":35, "size":Vector2(.5,.5), "height":1.1, "color":"4a4f55", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":35,"medium":60,"large":100}},
	"game_hula_hoop": {"label":"Hula hoops", "category":"Kids", "price":20, "size":Vector2(.8,.8), "height":.9, "color":"7d6b93", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":20,"medium":35,"large":60}},
	"game_stilts": {"label":"Stilts", "category":"Kids", "price":40, "size":Vector2(.6,.6), "height":1.2, "color":"d7ae7e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":40,"medium":70,"large":115}},
	"game_diy_den": {"label":"Den building set", "category":"Kids", "price":60, "size":Vector2(1.4,1.4), "height":1.2, "color":"8faf9f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":60,"medium":105,"large":170}},
	"game_playhouse": {"label":"Playhouse", "category":"Kids", "price":320, "size":Vector2(1.4,1.4), "height":1.6, "color":"c97c4e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":320,"medium":560,"large":900}},
	"game_wendy_house": {"label":"Wendy house", "category":"Kids", "price":260, "size":Vector2(1.2,1.2), "height":1.5, "color":"d7ae7e", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":260,"medium":455,"large":735}},
	"game_climbing_net": {"label":"Climbing net", "category":"Kids", "price":130, "size":Vector2(1.6,.8), "height":1.6, "color":"6f8fa8", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":130,"medium":230,"large":370}},
	"game_slackline": {"label":"Slackline", "category":"Activities", "price":70, "size":Vector2(2.2,.5), "height":.5, "color":"4a4f55", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":70,"medium":120,"large":195}},
	"game_stilts_race": {"label":"Stilts race set", "category":"Kids", "price":45, "size":Vector2(.8,.6), "height":.5, "color":"a8674f", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":45,"medium":80,"large":130}},
	"game_parachute": {"label":"Play parachute", "category":"Kids", "price":55, "size":Vector2(2.0,2.0), "height":.1, "color":"d9a0a0", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":55,"medium":95,"large":155}},
	"game_beanbag_chairs": {"label":"Beanbag seats", "category":"Comfort", "price":90, "size":Vector2(.9,.9), "height":.7, "color":"7d6b93", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":90,"medium":160,"large":260}, "seats":{"small":1,"medium":2,"large":2}},
	"game_hook_a_duck": {"label":"Hook a duck", "category":"Kids", "price":45, "size":Vector2(1.0,.7), "height":.9, "color":"7fb8c6", "tint":true, "sizes":GAMES_SIZES, "size_prices":{"small":45,"medium":80,"large":130}},
	# A two-car building whose own interior is walkable: its walls, posts and
	# roof block but its bays do not, so cars park inside it. `BLOCKING_PANELS`
	# below carries the bands that really block. Remote already ships a `garage`
	# family of its own, so this building keeps a name of its own.
	# Four parking bays: two side-by-side rows. The hollow interior is what lets
	# cars snap onto the authored bay centres; the solid walls stay in BLOCKING_PANELS.
	"car_garage": {"label":"Four-car garage", "category":"Vehicles", "price":2400, "size":Vector2(9.2,5.8), "height":2.59, "color":"417a71",
		"vehicle_snaps":4},
	"electric_car": {"label":"Quiet miles electric car", "category":"Vehicles", "price":1250, "size":Vector2(1.79,4.19), "height":1.4775, "color":"c6d2da", "paint":"c6d2da"}
}

# Accessories for the household's pets. A cat tree is a cat's furnishing and a
# kennel is a dog's; the bowl suits either. LifePets owns that policy.
const PET_ACCESSORIES: Array[String] = ["pet_bowl", "cat_tree", "kennel"]

# The Build & buy filter row, in display order. Structure is the tool page.
const CATEGORIES: Array[String] = ["All", "Comfort", "Bedroom", "Baby & Kids", "Kitchen", "Bathroom", "Activities", "Decor", "Pets", "Garden", "Pool", "Kids", "Outdoor", "Vehicles", "Structure"]

# Instruments share one practice action; the authored model is the difference.
const INSTRUMENTS: Array[String] = ["guitar", "violin"]

# Floor coverings and wall decor: they never block routes, walls or other furnishings.
const PASSABLE: Array[String] = ["rug", "child_rug", "bath_mat", "painting", "framed_picture", "wall_clock", "shelf", "yoga_mat", "room_light", "memorial", "curtains", "house_door", "house_window", "pet_toy_cat", "pet_toy_dog", "garden_gate", "garden_gate_double"]

## Fence runs and gates share one edge. Their footprints may touch; a gap is
## only the overlap of the panels themselves.
const FLUSH: Array[String] = ["fence", "garden_gate", "garden_gate_double"]

static func runs_flush(kind: String) -> bool:
	return kind in FLUSH

## True when the incoming footprint may not stand next to one that is already there.
static func blocks_neighbor(incoming: Rect2, existing: Rect2, incoming_kind: String, existing_kind: String) -> bool:
	if runs_flush(incoming_kind) and runs_flush(existing_kind):
		return incoming.grow(-0.01).intersects(existing.grow(-0.01))
	return incoming.grow(0.05).intersects(existing)
## Decor that hangs flat against a wall, kept as a list for the pieces that have
## always been authored that way. A catalogue entry may also declare
## `"wall_mounted": true` for itself, and `wall_mounted(kind)` is the one
## authority every placement rule reads — so a new wall-mounted furnishing says so
## in its own entry rather than needing a second edit in a list here.
const WALL_MOUNTED: Array[String] = ["painting", "wall_clock", "shelf"]

## Whether this furnishing must be placed against a wall. The entry's own flag
## wins, and the authored list covers the pieces that predate it.
static func wall_mounted(kind: String) -> bool:
	if bool(ITEMS.get(kind, {}).get("wall_mounted", false)):
		return true
	return kind in WALL_MOUNTED

static func passable(kind: String) -> bool:
	return kind in PASSABLE

## The paints offered for a car, in the row's order, led by the shade the model
## already wears. Any six-digit shade is valid on a record — this is the palette
## a buy row offers, exactly as the coat and hair palettes are offered for a pet
## or a Lifelet rather than enforced on the save.
const CAR_PAINTS: Array[String] = [
	"c6d2da", "3f4a55", "1d2124", "8c1f28", "1f3b6b",
	"2f5f47", "8a6a2f", "b4553a", "6c4f8c", "e8e3d8",
]

## A piece whose volume is not one solid box lists the bands it really occupies,
## in its own local metres. The two-car garage is the case: its solid back wall
## and both side walls (corner posts included) block, while the declared interior
## and the 4.28 m doorway stay clear, so a car — or two — parks inside. The
## rolled-up sectional door, its header and the roof are all overhead, which a
## floor-plan rectangle cannot express, so they are not bands. This is the
## staircase's own pattern — `stair_rect` plus `guard_footprints` rather than one
## solid volume — kept next to the size the ordinary box is derived from.
const BLOCKING_PANELS: Dictionary = {
	"archway": [
		{"x":-0.54, "z":0.0, "w":0.16, "d":0.14},
		{"x":0.54, "z":0.0, "w":0.16, "d":0.14}
	],
	"car_garage": [
		{"x":0.0, "z":-2.835, "w":9.08, "d":0.12},
		{"x":-4.54, "z":0.0, "w":0.12, "d":5.79},
		{"x":4.54, "z":0.0, "w":0.12, "d":5.79},
		{"x":0.0, "z":0.0, "w":0.12, "d":5.79}
	]
}

## Local-space parking centres inside a garage. Four bays: left pair then right
## pair, facing the open doorway (+z). An empty garage returns four snaps; a
## kind without vehicle_snaps returns nothing.
static func vehicle_snap_locals(kind: String) -> Array[Vector3]:
	var data: Dictionary = ITEMS.get(kind, {})
	var count: int = int(data.get("vehicle_snaps", 0))
	if count <= 0:
		return []
	var snaps: Array[Vector3] = []
	# Two columns of two bays across the four-car width.
	var xs: Array[float] = [-3.2, -1.1, 1.1, 3.2]
	for i: int in mini(count, xs.size()):
		snaps.append(Vector3(xs[i], 0.0, 0.35))
	return snaps

## The solid bands a kind occupies, in its own local metres: its authored ones
## when one box cannot describe it, otherwise the single box its declared size
## and depth describe. `size` is the buy-catalogue size id; a sized pool or
## hot tub blocks the footprint it really occupies so walkers path around the
## water rather than across it. Only a kind the catalogue does not know returns
## nothing. Authored multi-band kinds keep their authored metres.
static func local_panels(kind: String, size: String = "") -> Array:
	var panels: Array = BLOCKING_PANELS.get(kind, [])
	if not panels.is_empty(): return panels
	var data: Dictionary = ITEMS.get(kind, {})
	if data.is_empty(): return []
	var span: Vector2 = (data.size as Vector2) * LifeCatalogVariants.size_scale(size)
	return [{"x":0.0, "z":0.0, "w":span.x, "d":span.y}]

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

## The furniture of the two larger houses. They are laid out inside the same
## 12 m by 10 m shell as the starter homes — the shell is what Build mode lets a
## player reshape — but every room is a separate one, so a growing household has
## real bedrooms rather than one shared room.
##
## Rowan Villa uses the middle partition as its bedroom wall, Juniper House uses
## the two side rooms as separate bedrooms and the middle as a hallway.
static func _rowan_entries() -> Array:
	return [
		# Kitchen along the back-left, with a second counter run for a big household.
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["counter",-3.1,-4.4,0],["stove",-2.02,-4.4,0],["sink",-.94,-4.4,0],
		["dining",-2.6,-2.0,0],["chair",-2.6,-2.95,0],["chair",-2.6,-1.05,180],["chair",-3.6,-2.0,90],["chair",-1.6,-2.0,-90],
		# Living room.
		["rug",-4.0,2.2,0],["sofa",-4.5,3.6,180],["loveseat",-1.9,3.6,180],["table",-3.2,2.1,0],
		["tv",-5.1,.6,90],["lamp",-5.15,4.2,0],["floor_lamp",-.2,4.3,0],
		# Study corner.
		["desk",-.2,-2.9,0],["chair",-.2,-2.0,180],["bookshelf",-.2,-4.3,0],["bookshelf",2.2,-4.3,0],
		# Two real bedrooms behind the side partition.
		["bed",2.6,-2.4,0],["nightstand",1.6,-2.4,0],["wardrobe",3.7,-4.2,180],
		["bed",4.8,1.4,90],["nightstand",4.8,2.6,0],["wardrobe",2.4,4.3,180],["mirror",2.4,-.5,0],
		# Bathroom in the far corner.
		["shower",5.2,-3.9,0],["toilet",2.2,-.6,-90],["sink",4.0,-.6,-90],
		["plant",1.5,3.4,0],["plant",-5.0,-.6,0],["painting",-2.1,-4.91,0],["painting",2.6,4.91,180],
		["rubbish_bin",-.6,-4.45,0],["piano",3.6,2.6,0],
	]


static func _juniper_entries() -> Array:
	return [
		# A wide kitchen along the whole back wall.
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["counter",-3.1,-4.4,0],["stove",-2.02,-4.4,0],
		["sink",-.94,-4.4,0],["counter",.14,-4.4,0],["counter",1.22,-4.4,0],
		# Formal dining room on the left, seating six.
		["dining",-4.2,-.6,0],["chair",-4.2,-1.6,0],["chair",-4.2,.4,180],["chair",-5.3,-.6,90],["chair",-3.1,-.6,-90],
		["painting",-5.9,-.6,90],["plant",-5.0,1.6,0],
		# Two reception rooms: a lounge and a snug.
		["rug",-3.5,3.1,0],["sofa",-4.4,4.0,180],["loveseat",-1.5,4.0,180],["table",-3.0,3.0,0],
		["tv",-5.15,2.2,90],["lamp",-5.15,4.4,0],
		["armchair",-1.0,2.0,0],["book_nook",-.4,3.9,180],["floor_lamp",-1.9,1.4,0],
		# Four bedrooms: two off the hallway on the right, two beyond it.
		["bed",2.4,-3.3,0],["nightstand",1.4,-3.3,0],["wardrobe",3.7,-4.2,180],
		["bed",4.9,-1.2,90],["nightstand",4.9,-2.4,0],["wardrobe",2.4,-1.2,-90],
		["bed",2.4,1.5,0],["nightstand",1.4,1.5,0],["wardrobe",3.7,3.6,180],
		["bed",4.9,3.4,90],["nightstand",4.9,4.5,0],["mirror",3.0,4.6,180],
		# Two bathrooms: the family bathroom and an en-suite.
		["shower",5.2,-4.2,0],["bathtub",3.0,4.5,0],["toilet",.2,.6,0],["sink",.2,1.6,180],
		["toilet",1.4,-.2,0],["sink",1.4,-1.2,180],
		# Study and study corner.
		["desk",-.2,-2.2,180],["chair",-.2,-1.3,0],["computer",1.4,-2.2,180],
		["bookshelf",-.2,-4.3,0],["bookshelf",-.2,.9,0],
		["plant",.6,4.5,0],["plant",-5.0,-2.6,0],["painting",-2.1,-4.91,0],["painting",1.0,4.91,180],
		["rubbish_bin",.9,-4.45,0],["piano",3.9,2.9,0],["stereo",4.9,.4,90],
	]


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
	elif lot == 3:
		entries = _rowan_entries()
	elif lot == 4:
		entries = _juniper_entries()
	elif lot == 5:
		entries = nursery_room_preset()
	elif lot == 6:
		entries = _medium_entries()
	elif lot == 7:
		entries = _large_entries()
	elif lot == 8:
		entries = _ultramodern_entries()
	elif lot == 9:
		entries = _traditional_entries()
	elif lot == 10:
		entries = _lumen_entries()
	elif lot == 11:
		entries = _haven_entries()
	for i in range(entries.size()):
		var e: Array = entries[i]
		a.append({"id":"item_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return a

## Lumen House: modern two bedrooms, two bathrooms, and a pool.
static func _lumen_entries() -> Array:
	return [
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["stove",-3.1,-4.4,0],["sink",-2.02,-4.4,0],
		["dining",-3.5,-1.6,0],["sofa",-3.4,3.4,180],["table",-3.0,2.2,0],
		["bed",4.6,1.6,0],["nightstand",3.4,1.6,0],["wardrobe",5.3,3.2,-90],
		["child_bed",2.2,-2.6,0],["child_desk",3.4,-3.8,180],["child_chair",3.4,-3.0,0],["toy_chest",1.4,-3.6,0],
		["shower",5.1,-4.1,0],["toilet",3.6,-4.1,0],["sink",5.15,-2.4,-90],
		["bathtub",1.2,-4.2,90],["toilet",-.2,-4.1,0],["sink",-.2,-2.8,0],
		["pool",-8.4,1.6,0],["plant",-.2,4.2,0],
	]

## Haven: two bedrooms with a nursery and a child room already furnished.
static func _haven_entries() -> Array:
	return [
		["fridge",-5.0,-4.2,0],["stove",-3.4,-4.2,0],["sink",-2.2,-4.2,0],
		["bed",4.6,1.4,0],["nightstand",3.4,1.4,0],
		["child_bed",2.0,-1.6,0],["child_desk",3.2,-3.2,180],["toy_chest",1.2,-3.2,0],["dollhouse",1.2,-1.2,0],
		["cot",4.4,-2.6,0],["changing_table",5.2,-3.8,0],["rocking_chair",3.2,-4.0,0],["baby_mat",4.2,-4.2,0],
		["shower",5.1,4.0,0],["toilet",3.4,4.0,0],["bathtub",1.0,4.1,90],["toilet",-.4,4.0,0],
		["sofa",-3.2,2.8,180],
	]

## Medium Garden Home: two bedrooms, pool, outdoor table and barbecue.
static func _medium_entries() -> Array:
	return [
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["stove",-3.1,-4.4,0],["sink",-2.02,-4.4,0],
		["dining",-3.5,-1.85,0],["chair",-3.5,-2.8,0],["chair",-3.5,-.92,180],
		["rug",-2.9,2.43,0],["sofa",-3.4,3.75,180],["table",-3.1,2.17,0],["tv",-4.95,.65,90],
		["bed",3.5,1.5,0],["nightstand",2.03,.65,0],["wardrobe",5.32,-0.35,-90],
		["bed",4.8,-2.4,90],["nightstand",4.8,-1.2,0],["wardrobe",2.4,-4.2,180],
		["shower",4.9,-4.13,0],["toilet",2.35,-4.1,0],["sink",5.15,-2.13,-90],
		["pool",-8.5,2.0,0],["garden_table",-8.2,-2.4,0],["bbq",-10.2,-1.0,90],
		["plant",-.05,4.15,0],["rubbish_bin",.1,-4.45,0],
	]

## Large Estate: four bedrooms, three baths, pool, hot tub, four-car garage.
static func _large_entries() -> Array:
	return [
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["counter",-3.1,-4.4,0],["stove",-2.02,-4.4,0],
		["sink",-.94,-4.4,0],["dining",-4.2,-.6,0],["chair",-4.2,-1.6,0],["chair",-4.2,.4,180],
		["rug",-3.5,3.1,0],["sofa",-4.4,4.0,180],["table",-3.0,3.0,0],["tv",-5.15,2.2,90],
		["bed",2.4,-3.3,0],["nightstand",1.4,-3.3,0],["wardrobe",3.7,-4.2,180],
		["bed",4.9,-1.2,90],["nightstand",4.9,-2.4,0],["wardrobe",2.4,-1.2,-90],
		["bed",2.4,1.5,0],["nightstand",1.4,1.5,0],["wardrobe",3.7,3.6,180],
		["bed",4.9,3.4,90],["nightstand",4.9,4.5,0],
		["shower",5.2,-4.2,0],["bathtub",3.0,4.5,0],["toilet",.2,.6,0],["sink",.2,1.6,180],
		["toilet",1.4,-.2,0],["sink",1.4,-1.2,180],["shower",5.2,1.8,0],
		["pool",-9.5,1.5,0],["hot_tub",-9.5,-2.2,0],["garden_table",-7.0,-3.5,0],["bbq",-11.0,-3.0,90],
		["car_garage",-9.0,8.5,180],["plant",.6,4.5,0],["rubbish_bin",.9,-4.45,0],
	]

## Ultra-Modern Residence: open living, garden seating, barbecue.
static func _ultramodern_entries() -> Array:
	return [
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["stove",-3.1,-4.4,0],["sink",-2.02,-4.4,0],
		["dining",-3.2,-1.5,0],["chair",-3.2,-2.4,0],["chair",-3.2,-.6,180],
		["sofa",-3.4,3.4,180],["table",-2.8,2.2,0],["tv",-5.0,.8,90],["lamp",-5.1,3.9,0],
		["bed",3.6,1.6,0],["wardrobe",5.32,-0.2,-90],["bed",4.6,-2.6,90],["bed",2.2,3.6,0],
		["shower",4.9,-4.13,0],["toilet",2.35,-4.1,0],["sink",5.15,-2.13,-90],
		["toilet",.4,1.2,0],["sink",.4,2.2,180],
		["garden_table",-8.0,-2.0,0],["bbq",-9.8,-.8,90],["outdoor_swing",-7.5,2.5,0],
		["shrub",-10.5,2.0,0],["flowers",-10.2,-2.8,0],["tree_garden",-11.5,3.5,0],
		["plant",-.05,4.15,0],["rubbish_bin",.1,-4.45,0],
	]

## Traditional Family House: classic rooms with a garden table and barbecue.
static func _traditional_entries() -> Array:
	return [
		["fridge",-5.28,-4.3,0],["counter",-4.18,-4.4,0],["stove",-3.1,-4.4,0],["sink",-2.02,-4.4,0],
		["dining",-3.5,-1.85,0],["chair",-3.5,-2.8,0],["chair",-3.5,-.92,180],["chair",-4.5,-1.85,90],
		["rug",-2.9,2.43,0],["sofa",-3.4,3.75,180],["table",-3.1,2.17,0],["tv",-4.95,.65,90],
		["bookshelf",-.05,-2.8,0],["piano",1.2,3.6,0],
		["bed",3.5,1.5,0],["nightstand",2.03,.65,0],["wardrobe",5.32,-0.35,-90],
		["bed",4.8,-2.4,90],["nightstand",4.8,-1.2,0],["bed",2.2,3.8,0],
		["shower",4.9,-4.13,0],["toilet",2.35,-4.1,0],["sink",5.15,-2.13,-90],
		["toilet",.2,.8,0],["sink",.2,1.8,180],
		["garden_table",-8.0,-2.2,0],["bbq",-9.8,-1.0,90],["flowers",-10.5,1.5,0],
		["shrub",-7.5,3.0,0],["tree_garden",-11.0,2.8,0],["plant",5.2,4.2,180],
		["painting",-2.1,-4.91,0],["rubbish_bin",.1,-4.45,0],
	]

## A ready nursery: cot, changing table, mobile, mat, rocking chair and paint
## accents. Offered as starter_layout(5) and as Build & buy's nursery preset pack
## (ℒ2000: furnished, carpet, themed pictures).
static func nursery_room_preset() -> Array:
	return [
		["cot",3.4,1.6,0],["changing_table",5.0,1.2,-90],["baby_mobile",3.4,2.35,0],
		["baby_mat",2.2,2.8,0],["rocking_chair",1.4,1.4,90],["baby_rattle",2.5,2.6,0],
		["children_picture",3.4,4.91,180],["children_picture",1.2,4.91,180],
		["child_rug",3.2,2.4,0],["lamp",5.1,3.6,0],["curtains",3.4,4.85,180],
	]

## Child bedroom preset pack (ℒ2000). There is no bedside-lamp or laptop item, so
## the pack uses the floor lamp beside the nightstand and a desk with the home
## office computer and a chair.
static func child_bedroom_preset() -> Array:
	return [
		["child_bed",3.6,1.5,0],["nightstand",2.5,1.5,0],["floor_lamp",2.5,2.4,0],
		["child_desk",5.0,3.2,-90],["child_chair",4.4,3.2,0],["computer",5.0,1.6,-90],
		["child_rug",3.0,2.6,0],["painting",5.0,4.91,180],["curtains",3.4,4.85,180],
	]

## How a room pack furnishes the room it builds, relative to that room rather
## than to the lot. `x` runs from the left wall (−1) to the right wall (1) and
## `z` from the doorway wall (−1) to the back wall (1), as seen walking in; ±1
## means flush against that wall. `facing` is the wall the piece's front turns
## toward ("door", "back", "left", "right"). `wall` pieces hang on the named
## wall; curtains then centre on a window in any of the room's walls.
static func room_pack_layout(kind: String) -> Array:
	if kind == "nursery_room_pack":
		return [
			{"kind":"cot","x":-.15,"z":1.0,"facing":"door"},
			{"kind":"baby_mobile","x":.42,"z":1.0,"facing":"door"},
			{"kind":"changing_table","x":1.0,"z":.15,"facing":"left"},
			{"kind":"rocking_chair","x":-1.0,"z":-.45,"facing":"right"},
			{"kind":"child_rug","x":-.05,"z":-.05,"facing":"door","size":"medium"},
			{"kind":"baby_mat","x":-.15,"z":-.05,"facing":"door"},
			{"kind":"baby_rattle","x":.35,"z":-.1,"facing":"door"},
			{"kind":"lamp","x":-1.0,"z":1.0,"facing":"door"},
			{"kind":"children_picture","wall":"left","along":.55,"style":"01"},
			{"kind":"children_picture","wall":"right","along":-.6,"style":"03"},
			{"kind":"curtains","wall":"back","along":0.0,"style":"10","color":"d9a0a0"},
		]
	if kind == "child_bedroom_pack":
		return [
			{"kind":"child_bed","x":-.35,"z":1.0,"facing":"door"},
			{"kind":"nightstand","x":-1.0,"z":1.0,"facing":"door"},
			{"kind":"floor_lamp","x":-1.0,"z":.5,"facing":"door"},
			{"kind":"child_desk","x":1.0,"z":.45,"facing":"left"},
			{"kind":"child_chair","x":.52,"z":.45,"facing":"right"},
			{"kind":"computer","x":1.0,"z":-.72,"facing":"left"},
			{"kind":"child_rug","x":.1,"z":-.05,"facing":"door","size":"medium"},
			{"kind":"painting","wall":"left","along":-.35},
			{"kind":"curtains","wall":"back","along":0.0,"style":"03","color":"7195b3"},
		]
	return []

## The carpet each room pack lays on its floor.
static func room_pack_carpet(kind: String) -> String:
	return "c9d8cf" if kind == "nursery_room_pack" else "b9c7d9"

static func nursery_preset_price() -> int:
	return 2000

static func child_bedroom_preset_price() -> int:
	return 2000