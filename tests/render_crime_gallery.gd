extends SceneTree
const Crime = preload("res://scripts/crime_response.gd")
var world: LifeWorld
var crime: Node3D

func _initialize() -> void: _run.call_deferred()

func advance(phase: String, limit: int = 2400) -> bool:
	for i: int in limit:
		crime.tick(.1,.3)
		if crime.phase == phase: return true
	return false

func capture(name: String, center: Vector3, size: float, angle: Vector3 = Vector3(5,5,8)) -> void:
	world.camera.size = size
	world.camera.position = center+angle
	world.camera.look_at(center)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/justlife-crime-%s.png"%name)
	print("CRIME_RENDER ",name," phase=",crime.phase)

func _run() -> void:
	world = LifeWorld.new(); root.add_child(world)
	var home := LifeHousehold.new(); root.add_child(home); home.new_household([{"name":"Crime render"}])
	await process_frame
	world.create_home(LifeCatalog.starter_layout(0))
	crime = Crime.new(); world.add_child(crime); crime.setup(world,home); crime.set_sound(false)
	crime.begin_break_in()
	for i: int in 4: crime.tick(.1,.3)
	await capture("sneak",crime.burglar.position+Vector3(0,1,0),3.5)
	for i: int in 2400:
		crime.tick(.1,.3)
		if crime.stolen_items.size()==1: break
	crime.call_police("player")
	advance("officers_exiting")
	for i: int in 17: crime.tick(.1,.3)
	await capture("arrival",Crime.CURB+Vector3(0,.7,0),7)
	advance("scuffle")
	for i: int in 15: crime.tick(.1,.3)
	await capture("scuffle",crime.burglar.position+Vector3(0,1,0),4)
	advance("escorting")
	await capture("cuffed",crime.burglar.position+Vector3(0,1,0),2.7,-crime.burglar.basis.z*4+Vector3(1.6,2.0,0))
	advance("loading")
	for i: int in 20: crime.tick(.1,.3)
	await capture("loading",Crime.CURB+Vector3(0,.7,0),6)
	advance("jailed")
	await capture("jail",Crime.STATION+Vector3(0,1,0),8)
	world.queue_free(); home.queue_free()
	await process_frame
	quit()
