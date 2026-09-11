extends SceneTree
## Rendered frame-time probe without audit instrumentation: starts the default
## household at very fast speed and records every process delta for one wall
## minute, then reports percentiles.
##     godot --path . --audio-driver Dummy --script res://tests/probe_frames.gd

var samples: Array[float] = []
var seconds: float = 60.0

func _initialize() -> void:run.call_deferred()

func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame;await process_frame
	app.start_household()
	await process_frame
	app.sim.set_speed(8)
	var start:float=Time.get_ticks_msec()/1000.0
	while Time.get_ticks_msec()/1000.0-start<15.0:
		await process_frame
	start=Time.get_ticks_msec()/1000.0
	while Time.get_ticks_msec()/1000.0-start<seconds:
		await process_frame
		samples.append(root.get_process_delta_time()*1000.0)
	app.queue_free()
	await process_frame;await process_frame
	var sorted:Array=samples.duplicate()
	sorted.sort()
	var n:int=sorted.size()
	var pct:=func(t:float)->float: return sorted[mini(n-1,int(float(n)*t))]
	print("FRAME_PROBE frames=%d p50=%.1f p90=%.1f p95=%.1f p99=%.1f max=%.1f"%[n,pct.call(0.50),pct.call(0.90),pct.call(0.95),pct.call(0.99),sorted[n-1]])
	quit(0)
