extends Node
## Everything the lab can show you. No voices, no letters addressed to you:
## only what a real lab would have (labels, logs, signatures) plus your own
## internal lines ("think"), which are collected in the notebook.
##
## Entry fields:
##   title   notebook heading
##   see     lines shown in the white box (what you observe)
##   think   one internal line shown in the dark box ("" = silence)
##   hand    true = written in your own handwriting → scrambles as the infection reaches memory
##   depth   "surface" | "mid" | "deep" | "deepest" (for pacing / notebook grouping)
##   page    leash page id granted on reading ("1".."4"), optional

const ENTRIES := {
	"badge": {"title": "BADGE", "depth": "surface",
		"see": ["A lanyard badge. STATION FALLOW. LEAD - ACCESS 0001.",
			"The photo is a blistered green smear. Whatever was on your hand got on it."],
		"think": "Was that me?"},
	"vial": {"title": "BROKEN VIAL", "depth": "surface",
		"see": ["Broken glass. One label survives: S-7 / SOWER.",
			"The floor around it is tacky, and faintly green."],
		"think": "My hand."},
	"whiteboard": {"title": "WHITEBOARD", "depth": "surface", "hand": true,
		"see": ["A whiteboard dense with diagrams. Arrows in a loop:",
			"SOIL > TAKE > ADAPT > SPREAD",
			"Circled twice: FASTER THAN THE GREY."],
		"think": "That's my handwriting. All of it."},
	"binder": {"title": "PROTOCOL 12-L", "depth": "mid",
		"see": ["Binder: PROTOCOL 12-L. SAFEGUARD (\"LEASH\") REMOVAL.",
			"LEAD AUTHORIZATION: 0001. Signed.",
			"SECOND AUTHORIZATION: ________",
			"A vial is clipped to the page. LEASH - REMOVED."],
		"think": "Only one signature."},
	"coats": {"title": "COAT HOOKS", "depth": "mid",
		"see": ["Seven hooks.", "Six are empty."], "think": ""},
	"mugs": {"title": "MUGS", "depth": "mid",
		"see": ["Seven mugs on the counter.", "Six have a skin of dust. One is still half full."],
		"think": ""},
	"cctv": {"title": "CCTV 03:12", "depth": "mid",
		"see": ["LOCKDOWN 03:12. Six figures cross the airlock.",
			"One stays behind the glass, palm flat against it."],
		"think": "I let them go."},
	"doorlog": {"title": "AIRLOCK LOG", "depth": "mid",
		"see": ["AIRLOCK LOG  03:12  LOCKDOWN - MANUAL",
			"TRIGGERED FROM INSIDE. BADGE 0001.",
			"RELEASE CONDITION: OCCUPANT SCANS CLEAN."],
		"think": "From the inside."},
	"freezer": {"title": "FREEZER", "depth": "deep",
		"see": ["Every rack is empty. Frost outlines where the vials stood.",
			"A printout on the door: STERILIZE ALL STOCKS - COMPLETE - 03:14."],
		"think": "There's no other copy."},
	"pots": {"title": "TRIAL POTS", "depth": "deep",
		"see": ["Forty-one pots in rows. Grey dirt in every one.",
			"Tags: TRIAL 1 to TRIAL 41. Every tag says LEASHED."],
		"think": ""},
	"palm_pot": {"title": "THE PALM PRINT", "depth": "deep", "page": "4",
		"see": ["The pot you leaned on, the first night.",
			"A handprint of green moss has spread across the grey.",
			"It's the only living thing in the room."],
		"think": "It's alive."},
	"comms": {"title": "SATELLITE", "depth": "deep",
		"see": ["SATELLITE COMPOSITE - 14 MONTHS.",
			"Grey spreads outward from one point. The station sits at its center."],
		"think": "It isn't stopping."},
	"photo": {"title": "PHOTO", "depth": "deep",
		"see": ["A photo pinned above the desk: a farmhouse, a green field,",
			"a small figure sitting on a fence. Coordinates on the back."],
		"think": ""},
	"drawing": {"title": "DRAWING", "depth": "deep",
		"see": ["A child's drawing. A green sun over a brown field."], "think": ""},
	"coords": {"title": "COORDINATES", "depth": "deep",
		"see": ["You find the photo's coordinates on the composite.", "Grey."], "think": ""},
	"plaque": {"title": "PLAQUE", "depth": "deepest",
		"see": ["STATION FALLOW", "A HALDEN AGRITECH FACILITY",
			"Under the words, a wheat-sheaf logo."], "think": ""},
	"tillwell": {"title": "OLD ADVERT", "depth": "deepest",
		"see": ["A faded advert in the archive drawer: TILLWELL by HALDEN.",
			"WAKE UP YOUR SOIL!  The same wheat-sheaf logo."],
		"think": "Same logo."},
	"page_1": {"title": "NOTEBOOK PAGE I", "depth": "deepest", "hand": true, "page": "1",
		"see": ["A torn page, back in your memory:",
			"The lab feed dies in grey soil. So the leash dies. So the trial dies."],
		"think": ""},
	"page_2": {"title": "NOTEBOOK PAGE II", "depth": "deepest", "hand": true, "page": "2",
		"see": ["Another page:", "Don't tie it to us. Tie it to something only living ground makes."],
		"think": ""},
	"page_3": {"title": "NOTEBOOK PAGE III", "depth": "deepest", "hand": true, "page": "3",
		"see": ["The last page:", "Living soil is loud. A body is quiet.",
			"If it can only live where the Chorus is loud..."],
		"think": "Then it can't live in me."},
}

## Lines for objects that are not lore (shown, never collected).
const FLAVOR := {
	"palm_pot_early": ["A grey pot on the bench edge. A smeared handprint on the rim."],
	"airlock_scan": ["OCCUPANT SCAN . . .", "CONTAMINATED. RELEASE DENIED."],
	"airlock_clean": ["OCCUPANT SCAN . . .", "CLEAN."],
	"cot": ["A fold-out cot. The blanket still holds the shape of someone smaller."],
	"dark_room": ["The breaker for this room is dead."],
	"generator_dead": ["The generator is cold. The fuel gauge says otherwise."],
}

const SCRAMBLE := "#~%&@*"


func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})


func has(id: String) -> bool:
	return Game.lore.has(id)


## How unreadable your own handwriting is right now (0..0.55).
func blur() -> float:
	return clampf((Game.stage - 1) * 0.12 - Game.memories * 0.1, 0.0, 0.55)


## Deterministic per-day scramble so text doesn't flicker while you read it.
func legible(text: String) -> String:
	var b := blur()
	if b <= 0.0:
		return text
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text) + Game.day
	var out := ""
	for ch in text:
		if ch != " " and ch != "." and rng.randf() < b:
			out += SCRAMBLE[rng.randi() % SCRAMBLE.length()]
		else:
			out += ch
	return out


## Lines to show for an entry (scrambled if it's your handwriting).
func lines(id: String) -> Array:
	var e := entry(id)
	var out: Array = []
	for l in e.get("see", []):
		out.append(legible(l) if e.get("hand", false) else l)
	return out


## Show an entry through the textbox, record it, grant leash pages. Awaitable.
func show(id: String) -> void:
	var e := entry(id)
	if e.is_empty():
		return
	await UI.say(lines(id), "see")
	var first := not Game.lore.has(id)
	if first:
		Game.lore[id] = Game.day
		if e.has("page"):
			Game.leash_pages[e["page"]] = true
	var t: String = e.get("think", "")
	if t != "":
		await UI.say([t], "think")
		Game.add_thought(t)
	if first:
		Game.save_game()


func flavor(key: String) -> void:
	await UI.say(FLAVOR.get(key, ["..."]), "see")


## Found entries in notebook order.
func found() -> Array:
	var out: Array = []
	for id in ENTRIES.keys():
		if Game.lore.has(id):
			out.append(id)
	return out
