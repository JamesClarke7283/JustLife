extends Node
class_name LifeAnnouncements
## What the player is told in the middle of the screen when a life moves on.
##
## A Lifelet's `milestone` signal reaches the household, which relays it as
## `member_milestone`; the controller connects that to `milestone` here. Each kind
## of milestone has its own wording and its own size of fuss (below). Celebrations
## wait their turn: one is on the screen at a time, and none starts while a menu
## has paused the game, while a save is loading or while the player is not in the
## house. A load throws away everything still waiting, so an old birthday never
## appears after a different save opens.
##
## Kinds the household already sends or will send:
##   birthday            big banner: "Kit is now a teenager!" (every stage change)
##   retired             big banner: "Ben Vale is now retired"
##   retirement_eligible corner notice and a letter
##   driving_introduced  card banner and a letter
##   driving_licensed    big banner
##   pension             corner notice
## `data` may carry `text` to replace the default corner notice or card detail.

## Celebrations that are waiting; the oldest are dropped past this many.
const MAX_WAITING: int = 6

var app: Node
var queue: Array = []
var current: Node = null
## The load this service has seen, so a new load clears what was waiting.
var epoch: int = 0


func _init(owner: Node = null) -> void:
	app = owner
	if is_instance_valid(owner): epoch = int(owner.load_epoch)


## Wait to show one celebration. `style` is "grand" or "card".
func announce(title: String, subtitle: String = "", style: String = "grand") -> void:
	if not is_instance_valid(app) or bool(app.loading_game): return
	_sync_epoch()
	queue.append({"title": title, "subtitle": subtitle, "style": style, "epoch": int(app.load_epoch)})
	while queue.size() > MAX_WAITING: queue.pop_front()

## Decide what a milestone looks like. Called for every `member_milestone`.
func milestone(member_id: String, kind: String, data: Dictionary = {}) -> void:
	if not is_instance_valid(app) or bool(app.loading_game): return
	var household: LifeHousehold = app.household
	var sim: LifeSim = household.member_sim(member_id) if is_instance_valid(household) else null
	var full: String = str(sim.character.name) if sim != null else str(data.get("name", "Someone"))
	var first: String = full.split(" ")[0]
	var text: String = str(data.get("text", ""))
	match kind:
		"birthday":
			var stage: String = str(data.get("current", sim.character.age_stage if sim != null else ""))
			announce(LifeLifecycle.milestone_text(first, stage), "Happy birthday, %s." % full)
		"retired":
			announce("%s is now retired" % full, text if not text.is_empty() else "Time to enjoy the golden years.")
		"retirement_eligible":
			app.show_notice(text if not text.is_empty() else "%s has been an elder long enough to retire." % first)
			_post_letter(first, "Time to put your feet up", "%s has been an elder long enough to retire. Retiring is a choice, made from the Career tab." % first)
		"driving_introduced":
			announce("%s can learn to drive" % first, text if not text.is_empty() else "Study for seven days, then book lessons.", "card")
			_post_letter(first, "Learning to drive", "%s is old enough to learn to drive. Study the Highway Code, then book lessons with an instructor." % first)
		"driving_licensed":
			announce("%s can now drive!" % first, text if not text.is_empty() else "%s passed the driving test." % full)
		"pension":
			app.show_notice(text if not text.is_empty() else "%s's pension of ℒ%s has arrived." % [first, _with_commas(int(data.get("amount", 0)))])

## Whether a celebration may start now.
func can_show() -> bool:
	if not is_instance_valid(app) or bool(app.loading_game): return false
	if str(app.mode) not in ["live", "build"]: return false
	if is_instance_valid(app.household) and bool(app.household.restoring): return false
	return not (bool(app.overlay_open) and bool(app.overlay_pauses_sim))

## Whether a celebration is on the screen.
func showing() -> bool:
	return is_instance_valid(current) and not current.is_queued_for_deletion()

## Called every frame by the controller.
func tick(_delta: float) -> void:
	if not is_instance_valid(app): return
	_sync_epoch()
	if str(app.mode) == "creator":
		clear()
		return
	if showing(): return
	current = null
	while not queue.is_empty() and can_show():
		var next: Dictionary = queue.pop_front()
		if int(next.epoch) != epoch: continue
		current = LifeMilestoneCelebration.present(app, str(next.title), str(next.subtitle), str(next.style), bool(app.sound_enabled))
		return

## Turning Sound off silences a fanfare that is still playing.
func sound_changed(enabled: bool) -> void:
	if enabled or not showing(): return
	for player: Node in current.find_children("*", "AudioStreamPlayer", true, false): (player as AudioStreamPlayer).stop()

## Drop everything waiting and take down what is showing.
func clear() -> void:
	queue.clear()
	if is_instance_valid(current): current.queue_free()
	current = null


## A new game or a load starts a new epoch, and everything still waiting from the
## old one is dropped. Checked before anything is queued, so a celebration that
## comes right after a load is kept.
func _sync_epoch() -> void:
	if int(app.load_epoch) == epoch: return
	epoch = int(app.load_epoch)
	clear()

## 1000 as "1,000".
func _with_commas(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out

## A letter written for a milestone, once per person, title and day.
func _post_letter(who: String, title: String, body: String) -> void:
	var household: LifeHousehold = app.household
	if not is_instance_valid(household) or not household.owns_post_box(): return
	for entry: Dictionary in household.mail.get("letters", []):
		if str(entry.get("subject", "")) == who and str(entry.get("title", "")) == title and int(entry.get("day", 0)) == household.day: return
	household.deliver_mail(LifeMail.letter(int(household.mail.get("next_serial", 1)), "letter", title, body, household.day, who))
