extends RefCounted
class_name LifeMail
## The household's post box: what arrives, when, and what reading it does.
##
## Mail is a record of paper, not a second ledger. A bill is still issued,
## owned and paid exactly as it was — the post box is where that bill also shows
## up as something you can hold, alongside the letters a household's own days
## produce: a child's first school day, a new pet, an adoption, a birthday.
##
## A household with no post box lives exactly as it did before: bills arrive by
## notice and are paid from the phone. The box adds a place, not a rule.
##
## Pure static policy — no Nodes, no clock, no wallet.

const VERSION: int = 1
## A mail box holds what a real one does. Older post is taken in and thrown away
## rather than growing without bound in the save.
const MAX_MAIL: int = 24

## The kinds of post, and whether reading one asks the player for something.
const KINDS: Array[String] = ["bill", "letter", "invite"]
const KIND_LABELS: Dictionary = {"bill": "Bill", "letter": "Letter", "invite": "Invitation"}

## The letters a household's own milestones produce. Each is written once per
## event, and `subject` names the person the letter is about.
const LETTERS: Dictionary = {
	"arrival": {"title": "Welcome to the lane", "body": "The neighbours write to say hello and wish %s a happy first week at home."},
	"school": {"title": "First day at school", "body": "A note from the school office confirms %s is enrolled and starts on the next weekday."},
	"adoption": {"title": "A new arrival", "body": "Everyone at the agency is delighted that %s has joined the household."},
	"pet": {"title": "Pet registration", "body": "The veterinary practice has registered %s and enclosed a first appointment card."},
	"birthday": {"title": "Many happy returns", "body": "A card for %s' birthday, signed by the neighbours on the lane."},
	"utility": {"title": "Utilities notice", "body": "A reminder that %s pays for what the home uses, and that the account is in good standing."},
	"juniper": {"title": "News from Juniper Gardens", "body": "The gardens say a new season is starting and %s is welcome any afternoon."},
}


static func fresh() -> Dictionary:
	return {"version": VERSION, "next_serial": 1, "letters": []}


## One letter, in the shape the save keeps.
static func letter(serial: int, kind: String, title: String, body: String, day: int, subject: String = "", amount: int = 0, due_day: int = 0) -> Dictionary:
	return {
		"id": "mail_%d" % serial,
		"serial": serial,
		"kind": kind if KINDS.has(kind) else "letter",
		"title": str(title),
		"body": str(body),
		"subject": str(subject),
		"amount": int(amount),
		"due_day": int(due_day),
		"day": int(day),
		"read": false,
	}


## The letter a named milestone produces.
static func milestone(serial: int, reason: String, who: String, day: int) -> Dictionary:
	var entry: Dictionary = LETTERS.get(reason, {})
	if entry.is_empty(): return {}
	return letter(serial, "letter", str(entry.title), str(entry.body) % who, day, who)


## The letter a bill is posted as. It carries the amount and the due day, so the
## box can show what is owed and settle it without re-reading the ledger.
static func bill_letter(serial: int, amount: int, day: int, due_day: int) -> Dictionary:
	return letter(serial, "bill", "Household bill", "From Juniper Utilities. ℒ%d is due by day %d." % [amount, due_day], day, "", amount, due_day)


## Whether this letter asks the household for money.
static func is_bill(value: Dictionary) -> bool:
	return str(value.get("kind", "")) == "bill"


## A one-line summary for the box's own list.
static func summary(value: Dictionary) -> String:
	if is_bill(value):
		return "ℒ%d due by day %d" % [int(value.get("amount", 0)), int(value.get("due_day", 0))]
	var subject: String = str(value.get("subject", ""))
	return "About %s" % subject if not subject.is_empty() else "For the household"


## File one letter into the box, retiring the oldest once it is full. Returns the
## letter that was filed, so the caller can name it in a notice.
static func deliver(box: Dictionary, value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var letters: Array = box.get("letters", [])
	letters.append(value.duplicate(true))
	while letters.size() > MAX_MAIL:
		letters.pop_front()
	box["letters"] = letters
	box["next_serial"] = maxi(int(box.get("next_serial", 1)), int(value.get("serial", 0)) + 1)
	return value


## Mark one letter read. Reading is what a bill's own payment does, so the box
## shows at a glance what is still waiting.
static func mark_read(box: Dictionary, id: String) -> bool:
	for entry: Dictionary in box.get("letters", []):
		if str(entry.id) == id:
			entry["read"] = true
			return true
	return false


## Every letter still unread.
static func unread(box: Dictionary) -> Array:
	return (box.get("letters", []) as Array).filter(func(value: Dictionary) -> bool: return not bool(value.get("read", false)))


## The bill the box is holding, if any, as the ledger's own shape so paying it
## goes through the ordinary settlement path rather than a second one.
static func outstanding_bill(box: Dictionary) -> Dictionary:
	for entry: Dictionary in box.get("letters", []):
		if is_bill(entry) and not bool(entry.get("read", false)):
			return {"amount": int(entry.get("amount", 0)), "issued_day": int(entry.get("day", 0)), "due_day": int(entry.get("due_day", 0)), "late_fee": 0}
	return {}


## Validate a saved box. Absent is legal and means a household saved before it
## had a post box, which loads with an empty one.
static func validate(value: Variant) -> String:
	if value == null: return ""
	if not value is Dictionary: return "Save contains an invalid post box."
	var box: Dictionary = value
	if box.size() != 3: return "The saved post box has unexpected fields."
	if not integer(box.get("version", 0), VERSION, VERSION): return "The saved post box uses an unsupported version."
	if not box.get("letters") is Array or box.letters.size() > MAX_MAIL: return "The saved post box is invalid."
	if not integer(box.get("next_serial", 1), 1, 1000000): return "Save contains an invalid post serial."
	var seen: Dictionary = {}
	for entry: Variant in box.letters:
		if not entry is Dictionary: return "Save contains an invalid letter."
		var mail: Dictionary = entry
		var id: String = str(mail.get("id", ""))
		if id.is_empty() or seen.has(id): return "Save contains a duplicate letter identity."
		seen[id] = true
		if not KINDS.has(str(mail.get("kind", ""))): return "Save contains an unknown kind of post."
		if not integer(mail.get("serial", 0), 1, 1000000): return "Save contains an invalid letter serial."
		if not integer(mail.get("day", 0), 0, 1000000): return "Save contains an invalid letter date."
		if not integer(mail.get("amount", 0), 0, 1000000) or not integer(mail.get("due_day", 0), 0, 1000000):
			return "Save contains an invalid letter amount."
		if not mail.get("read") is bool: return "Save contains an invalid letter state."
	return ""


static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
