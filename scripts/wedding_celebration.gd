extends CanvasLayer
## A short burst of falling streamers and a major-chord celebration.
var sound:bool=true
var elapsed:float=0.0
var pieces:Array=[]
var canvas:Control
func _ready()->void:
	layer=60
	canvas=Control.new();canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(canvas)
	var rng:=RandomNumberGenerator.new();rng.randomize()
	var width:float=get_viewport().get_visible_rect().size.x
	for index:int in 100:
		var piece:=ColorRect.new();piece.mouse_filter=Control.MOUSE_FILTER_IGNORE
		piece.color=[Color("efaa54"),Color("ed739b"),Color("75bda8"),Color("9586d6"),Color("f7d969")][index%5]
		piece.size=Vector2(rng.randf_range(5,9),rng.randf_range(12,28));piece.position=Vector2(rng.randf_range(0,width),rng.randf_range(-250,-20))
		canvas.add_child(piece);pieces.append({"node":piece,"speed":rng.randf_range(100,180),"sway":rng.randf_range(-35,35),"spin":rng.randf_range(-3,3)})
	if sound:
		var player:=AudioStreamPlayer.new();player.stream=_fanfare();player.volume_db=-7;add_child(player);player.play()

func _process(delta:float)->void:
	elapsed+=delta
	for piece:Dictionary in pieces:
		piece.node.position+=Vector2(float(piece.sway)*sin(elapsed*2.0),float(piece.speed))*delta
		piece.node.rotation+=float(piece.spin)*delta
		piece.node.modulate.a=clampf(5.0-elapsed,0,1)
	if elapsed>=5.0:queue_free()

static func _fanfare()->AudioStreamWAV:
	var rate:int=22050;var seconds:float=1.8;var data:=PackedByteArray();data.resize(int(rate*seconds)*2)
	var notes:Array[float]=[261.63,329.63,392.0,523.25]
	for index:int in int(rate*seconds):
		var time:float=float(index)/rate;var value:float=0.0
		for n:int in notes.size():
			var age:float=time-float(n)*.14
			if age>=0:value+=sin(TAU*notes[n]*age)*exp(-age*2.5)*minf(age*35,1)*.19
		data.encode_s16(index*2,int(clampf(value,-1,1)*32767))
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.data=data
	return stream
