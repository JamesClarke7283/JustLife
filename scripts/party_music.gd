extends Node
class_name LifePartyMusic
## The one owner of every celebration sound that goes on for a while: the
## birthday tune and the party groove. They share the speakers with the game's
## own theme ("Summit Dawn"), so there is a fixed order of who is heard:
##
##   1. the birthday tune,
##   2. the party loop,
##   3. the theme.
##
## While either of the first two is on, the theme is turned down by volume (from
## its usual -8 dB to about -24 dB) and brought back up afterwards. It is never
## paused: the Music and Sound switches in the menu pause and restart it
## themselves, and a pause owned here would be undone the next time a switch is
## flipped. The tune follows the Sound switch, the loop follows Sound and Music,
## and both hold still while the household is paused (speed 0) and carry on from
## the same spot.
##
## A feature asks for music with `play_birthday_tune` and `set_party_loop` and
## ends it with `stop_birthday_tune`, `set_party_loop(false)` or `stop_all`.
##
## The party loop can come from a stereo: given the stereo's place, it plays from a
## speaker there (a 3D player that fades with distance from the camera), and
## without one it plays flat, as before. Either way it is the same loop under the
## same rules.

const DUCK_DB: float = -24.0
## How fast the theme's volume moves, in decibels a second.
const DUCK_RATE: float = 30.0
const TUNE_DB: float = -3.0
const LOOP_DB: float = -8.0
## A speaker is a little quieter at its own spot, because it also fades with distance.
const STEREO_DB: float = -4.0
const STEREO_UNIT: float = 12.0

var app: Node
var tune_player: AudioStreamPlayer
var loop_player: AudioStreamPlayer
## The speaker the loop plays from when it has a stereo to come from.
var stereo_player: AudioStreamPlayer3D
## Where that speaker stands, or INF when the loop plays flat.
var loop_at: Vector3 = Vector3.INF
var wants_tune: bool = false
var wants_loop: bool = false
var epoch: int = 0
## The theme's own level, noted before it is first turned down.
var theme_db: float = -8.0
var ducked: bool = false


func _init(owner: Node = null) -> void:
	app = owner
	if is_instance_valid(owner): epoch = int(owner.load_epoch)

func _ready() -> void:
	tune_player = AudioStreamPlayer.new()
	tune_player.name = "BirthdayTune"
	tune_player.volume_db = TUNE_DB
	add_child(tune_player)
	tune_player.finished.connect(_tune_finished)
	loop_player = AudioStreamPlayer.new()
	loop_player.name = "PartyLoop"
	loop_player.volume_db = LOOP_DB
	add_child(loop_player)
	stereo_player = AudioStreamPlayer3D.new()
	stereo_player.name = "PartyMusic"
	stereo_player.volume_db = STEREO_DB
	stereo_player.unit_size = STEREO_UNIT
	add_child(stereo_player)


## Start the birthday tune, from `from_seconds` into it (a load puts it back where
## it was). It plays again from the top if asked while already playing.
func play_birthday_tune(from_seconds: float = 0.0) -> void:
	_sync_epoch()
	wants_tune = true
	tune_player.stream = CelebrationAudio.birthday_tune()
	tune_player.play(clampf(from_seconds, 0.0, maxf(0.0, tune_player.stream.get_length() - 0.1)))
	refresh()

func stop_birthday_tune() -> void:
	wants_tune = false
	tune_player.stop()
	refresh()

## Turn the party groove on or off. `at` is where a stereo stands (a world point):
## given one, the groove plays from there; without one it plays flat.
func set_party_loop(enabled: bool, at: Vector3 = Vector3.INF) -> void:
	_sync_epoch()
	var was_on: bool = wants_loop
	var was_at: Vector3 = loop_at
	wants_loop = enabled
	loop_at = at if enabled and at.is_finite() else Vector3.INF
	if enabled:
		var heard: Variant = _loop_voice()
		if heard.stream == null: heard.stream = CelebrationAudio.party_loop()
		if is_instance_valid(stereo_player) and loop_at.is_finite(): stereo_player.global_position = loop_at
		# Moving between the flat player and the speaker hands the loop over.
		var moved: bool = was_on and loop_at.is_finite() != was_at.is_finite()
		if moved:
			(loop_player if heard == stereo_player else stereo_player).stop()
		# A paused stream reports that it is not playing, so only a loop that is
		# newly asked for starts from the top.
		if not was_on or moved or (not heard.playing and not heard.stream_paused): heard.play()
	else:
		loop_player.stop()
		stereo_player.stop()
	refresh()

## The player the loop is heard from right now.
func _loop_voice() -> Node:
	return stereo_player if loop_at.is_finite() and is_instance_valid(stereo_player) else loop_player

## End all party and birthday music at once and bring the theme back.
func stop_all() -> void:
	wants_tune = false
	wants_loop = false
	if is_instance_valid(tune_player): tune_player.stop()
	if is_instance_valid(loop_player): loop_player.stop()
	if is_instance_valid(stereo_player): stereo_player.stop()
	loop_at = Vector3.INF
	if ducked and is_instance_valid(app) and is_instance_valid(app.music_player): app.music_player.volume_db = theme_db
	ducked = false

## Whose turn it is to be heard: "birthday", "party" or "theme".
func current_voice() -> String:
	if tune_audible(): return "birthday"
	if loop_audible(): return "party"
	return "theme"

func tune_audible() -> bool: return wants_tune and _sound_on()

func loop_audible() -> bool: return wants_loop and _sound_on() and _music_on() and not tune_audible()

## Where the birthday tune has reached, in seconds, so a save can put it back.
func tune_position() -> float:
	return tune_player.get_playback_position() if wants_tune and is_instance_valid(tune_player) else 0.0

## The level the theme is heading for.
func theme_target_db() -> float:
	return DUCK_DB if (tune_audible() or loop_audible()) else theme_db

## Re-read the Sound and Music switches and the household's speed. The controller
## calls this when a switch changes; it is also done every frame.
func refresh() -> void:
	if not is_instance_valid(tune_player): return
	var moving: bool = _moving()
	tune_player.stream_paused = not (tune_audible() and moving)
	var loud: bool = loop_audible() and moving
	loop_player.stream_paused = not (loud and not loop_at.is_finite())
	stereo_player.stream_paused = not (loud and loop_at.is_finite())

## Called every frame by the controller: a new load or leaving for the main menu
## ends the music, the players follow the switches and the pause, and the theme
## slides to its level.
func tick(delta: float) -> void:
	if not is_instance_valid(app): return
	_sync_epoch()
	if str(app.mode) == "creator":
		if wants_tune or wants_loop or ducked: stop_all()
		return
	refresh()
	var music: AudioStreamPlayer = app.music_player if "music_player" in app else null
	if not is_instance_valid(music): return
	var target: float = theme_target_db()
	if not ducked and target < music.volume_db:
		theme_db = music.volume_db
		ducked = true
		target = theme_target_db()
	if not ducked: return
	music.volume_db = move_toward(music.volume_db, target, DUCK_RATE * delta)
	if not (tune_audible() or loop_audible()) and is_equal_approx(music.volume_db, theme_db): ducked = false


## A new game or a load ends the old music. Checked before music is asked for, so
## a tune started right after a load is kept.
func _sync_epoch() -> void:
	if not is_instance_valid(app) or int(app.load_epoch) == epoch: return
	epoch = int(app.load_epoch)
	stop_all()

func _tune_finished() -> void:
	wants_tune = false
	refresh()

func _sound_on() -> bool: return is_instance_valid(app) and bool(app.sound_enabled)

func _music_on() -> bool: return is_instance_valid(app) and bool(app.music_enabled)

## Whether the household's clock is running.
func _moving() -> bool:
	return is_instance_valid(app) and is_instance_valid(app.household) and int(app.household.speed) > 0
