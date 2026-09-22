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
	"loveseat": {"label":"Two-together loveseat", "category":"Comfort", "price":440, "size":Vector2(1.9,1.0), "height":1.1, "color":"6e5470", "seat_count":2, "seat_offsets":[-.37,.37]},
	"stool": {"label":"Kitchen stool", "category":"Comfort", "price":60, "size":Vector2(.5,.5), "height":.78, "color":"417a71"},
	"wardrobe": {"label":"Everyday wardrobe", "category":"Comfort", "price":380, "size":Vector2(1.25,.62), "height":2.05, "color":"ab7951"},
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
	"garden_light": {"label":"Garden path light", "category":"Garden", "price":35, "size":Vector2(.22,.22), "height":.9, "color":"4a4f55", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10"]},
	"garden_light_wall": {"label":"Garden wall light", "category":"Garden", "price":30, "size":Vector2(.22,.30), "height":.42, "color":"4a4f55", "tint":true,
		"styles":["01","02","03","04","05","06","07","08","09","10"], "wall_mounted":true},
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
	"climbing_frame": {"label":"Kids climbing frame", "category":"Kids", "price":100, "size":Vector2(2.8,2.2), "height":2.2, "color":"c9a05a", "tint":true, "colors":["c9a05a","6f8fa8","c97c4e","8faf9f","7d6b93"],
		"styles":["a","b","c","d"]},
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
	"car_garage": {"label":"Two-car garage", "category":"Vehicles", "price":1800, "size":Vector2(4.6,5.8), "height":2.59, "color":"417a71"},
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
const PASSABLE: Array[String] = ["rug", "painting", "wall_clock", "shelf", "yoga_mat", "room_light", "memorial"]
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
	"car_garage": [
		{"x":0.0, "z":-2.835, "w":4.59, "d":0.12},
		{"x":-2.235, "z":0.0, "w":0.12, "d":5.79},
		{"x":2.235, "z":0.0, "w":0.12, "d":5.79}
	]
}

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
	for i in range(entries.size()):
		var e: Array = entries[i]
		a.append({"id":"item_%d" % i,"kind":e[0],"x":e[1],"z":e[2],"rotation":e[3]})
	return a
