extends SceneTree
## Rendered frame-time probe without audit instrumentation: starts the default
## household at very fast speed and records every process delta for one wall
## minute, then reports percentiles.
##     godot --path . --audio-driver Dummy --script res://tests/probe_frames.gd
##
## The sample runs with vsync disabled. With vsync on, process delta is the
## presentation interval (16.7 ms at 60 Hz), so the percentile tail measures
## how the compositor quantised a missed interval rather than how long the game
## took to build the frame; that reading made earlier iterations chase draw
## calls for a cost the game did not have. An uncapped run reports the actual
## frame work, and the capped line reports what the player sees once a 60 fps
## cap is the only limit.

var samples: Array[float] = []
var seconds: float = 60.0
var cap_samples: Array[float] = []

func _initialize() -> void:run.call_deferred()

func _percentiles(label:String,values:Array[float])->void:
	var sorted:Array=values.duplicate()
	sorted.sort()
	var n:int=sorted.size()
	if n==0:return
	var pct:=func(t:float)->float: return sorted[mini(n-1,int(float(n)*t))]
	print("%s frames=%d p50=%.1f p90=%.1f p95=%.1f p99=%.1f max=%.1f"%[label,n,pct.call(0.50),pct.call(0.90),pct.call(0.95),pct.call(0.99),sorted[n-1]])

func _sample_window() -> void:
	var start:float=Time.get_ticks_msec()/1000.0
	while Time.get_ticks_msec()/1000.0-start<seconds:
		await process_frame
		samples.append(root.get_process_delta_time()*1000.0)

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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame;await process_frame
	await _sample_window()
	_percentiles("FRAME_PROBE",samples)
	# The player-facing reading: a 60 fps cap is the only limit, so a frame
	# that takes 7 ms is presented at 16.7 ms and only real overruns show.
	Engine.max_fps=60
	await process_frame;await process_frame
	start=Time.get_ticks_msec()/1000.0
	while Time.get_ticks_msec()/1000.0-start<minf(seconds,10.0):
		await process_frame
		cap_samples.append(root.get_process_delta_time()*1000.0)
	Engine.max_fps=0
	_percentiles("FRAME_PROBE_CAP60",cap_samples)
	app.queue_free()
	await process_frame;await process_frame
	quit(0)
