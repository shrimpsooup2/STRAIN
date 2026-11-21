extends Node
## Everything the lab can show you. No voices, no letters addressed to you:
## only what a real lab would have (labels, logs, tape, signatures) plus your
## own internal lines ("think"), which are collected in the notebook.
##
## Entry fields:
##   title     notebook heading
##   see       lines shown in the white box (what you observe)
##   think     one internal line, shown once, the first time ("" = silence)
##   hand      true = your handwriting -> scrambles as the infection reaches memory
##   depth     "surface" | "mid" | "deep" | "deepest" (pacing / notebook grouping)
##   page      leash page id granted on reading ("1".."4"), optional
##   min_day / min_stage / needs   GATE. Conditions are OR'ed: time, infection or
##             progress can each open it. needs = {cond: value} (see _cond()).
##   requires  {cond: value}, AND'ed on top of the gate (ordering, e.g. vm_2 needs vm_1).
##   more      addenda [{gate fields, see, think, hand, replace}]. An addendum joins
##             the entry the next time it is read with its gate open, and stays.
##             replace = true drops everything before it.
## Text tokens: {days} -> nights spent here (Game.day - 1).

const ENTRIES := {
	# --- Day 1. Mundane, slightly wrong. -------------------------------------
	"vial": {"title": "BROKEN VIAL", "depth": "surface",
		"see": ["Broken glass where you woke. A green film dried on the tiles.",
			"Half a label, cramped capitals: S-7 / ~~~~~~~"],
		"think": "That's what cut me.",
		"more": [{"min_stage": 2, "needs": {"pages": 3},
			"see": ["In better light the label reads: S-7 SOWER. LEASH: NONE.",
				"The capitals lean the way yours do."],
			"think": "Everyone writes like that."}]},
	"chair": {"title": "STOOL", "depth": "surface",
		"see": ["A lab stool on its side. One castor snapped off.",
			"A smear of green on the seat, the size of a palm."], "think": ""},
	"badge": {"title": "BADGE", "depth": "surface",
		"see": ["A lanyard badge, face down by the stool.",
			"STATION FALLOW. Name and number gouged out. Hard, with something sharp.",
			"The photo is a blistered green smear."],
		"think": "Someone didn't want this read.",
		"more": [{"min_stage": 4, "needs": {"pages": 4, "lore": "decon"}, "replace": true,
			"see": ["Your badge, tilted to the lamp. The gouges are shallow at the edges.",
				"STATION FALLOW.   LEAD - ACCESS 0001."],
			"think": "Mine."}]},
	"whiteboard": {"title": "WHITEBOARD", "depth": "surface", "hand": true,
		"see": ["Diagrams to the edges. Arrows in a loop:",
			"SOIL > TAKE > ADAPT > SPREAD",
			"Circled twice: FASTER THAN THE GREY."],
		"think": "Somebody was having a good week.",
		"more": [
			{"min_day": 3, "see": ["Bottom corner, fresh marker. The cap is off:", "COUNT THE HOOKS."],
				"think": "That wasn't there yesterday."},
			{"min_day": 6, "see": ["Smaller, under it:", "IT ONLY LIVES WHERE IT'S LOUD."],
				"think": "Loud?"},
			{"min_day": 9, "see": ["Along the frame:", "SHE CAN'T HEAR YOU. STOP CALLING."],
				"think": "I haven't called anyone."},
			{"min_day": 12, "requires": {"lore": "protocol"},
				"see": ["Across everything, pressed hard enough to squeak:", "YOU SIGNED IT. ONE LINE."],
				"think": ""},
		]},
	"binder": {"title": "PROTOCOL 12-L", "depth": "surface",
		"see": ["Binder: PROTOCOL 12-L. SAFEGUARD REMOVAL.",
			"The rings are open. Every page torn out at the holes."], "think": ""},
	"coats": {"title": "COAT HOOKS", "depth": "surface",
		"see": ["Seven hooks by the door. Six empty.",
			"On the last, a lab coat. Your size. Green on the right cuff."], "think": ""},
	"mugs": {"title": "MUGS", "depth": "surface",
		"see": ["Seven mugs. Six with a skin of dust. Initials in marker:",
			"R.O.   T.K.   M.A.   D.V.   S.B.   P.N.",
			"The seventh has none. Half full. Not old."], "think": ""},
	"doorlog": {"title": "AIRLOCK LOG", "depth": "surface",
		"see": ["AIRLOCK: SEALED. LOCKDOWN ACTIVE.", "RELEASE CONDITION: OCCUPANT SCANS CLEAN."],
		"think": "",
		"more": [
			{"min_day": 4, "min_stage": 2,
				"see": ["ACCESS, LAST 30 NIGHTS:",
					"0001 02:47 GARDEN.  0001 03:05 FREEZER.  0001 01:58 GARDEN.",
					"0001, every night. No other badge after 22:00."],
				"think": "Who works nights?"},
			{"min_stage": 3, "needs": {"cleared": "archive"},
				"see": ["03:12  LOCKDOWN - MANUAL - INTERNAL PANEL - BADGE 0001."],
				"think": "From the inside."},
			{"min_stage": 4, "needs": {"pages": 4},
				"see": ["03:12  DECON CYCLE. OCCUPANTS: 6. STANDARD: 4 MIN.",
					"OVERRIDE 0001. CYCLE END 03:51. OUTER DOOR: NOT OPENED."],
				"think": "Thirty-nine minutes."},
		]},
	"freezer": {"title": "FREEZER", "depth": "mid",
		"see": ["Every rack empty. Frost rings where the tubes stood.",
			"Someone counted them. Grease pencil on the door: 212."], "think": "",
		"more": [{"min_stage": 4, "needs": {"pages": 4},
			"see": ["A printout frozen to the inside of the door:",
				"STERILIZE ALL STOCKS. S-7 LINES: 212. COMPLETE 03:14. OPERATOR 0001.",
				"NON-S7 (PHAGE): EXEMPT."],
			"think": "There's no other copy."}]},
	"lytic": {"title": "DEEP STORE", "depth": "mid",
		"see": ["DEEP STORE, -80. One rack the cycle skipped. A frosted box:",
			"PHAGE LINE L-2 \"LYTIC\". NOT S-7. EXEMPT.  - R.O."],
		"think": "Something it didn't burn."},
	"pots": {"title": "TRIAL POTS", "depth": "mid",
		"see": ["Forty-one pots. Grey dirt in every one.",
			"Tags: TRIAL 01 to TRIAL 41. LEASHED. FAIL. FAIL. FAIL."], "think": ""},
	"palm_pot": {"title": "THE PALM PRINT", "depth": "deep", "page": "4",
		"see": ["The pot on its own stand. Your handprint on the rim.",
			"Green moss has spread out of the print, across the grey.",
			"The only living thing in the room."],
		"think": "It's alive."},
	"protocol": {"title": "12-L, TORN PAGES", "depth": "mid", "min_day": 4, "min_stage": 2,
		"see": ["Torn pages, squared into a pile. PROTOCOL 12-L.",
			"REMOVAL OF SAFEGUARD S-7/L (\"LEASH\"). TWO AUTHORIZATIONS REQUIRED.",
			"AUTH 1: a signature. The name beside it torn off with the corner.",
			"AUTH 2: ______________________"],
		"think": "Only one line signed."},
	"photo": {"title": "PHOTO", "depth": "mid",
		"see": ["A photo above the desk. A farmhouse, a green field.",
			"A kid on the fence, squinting. On the back, pencil: 52.41N 1.93W."], "think": "",
		"more": [{"min_day": 11, "see": ["This morning it's turned to face the wall."],
			"think": "I wouldn't do that."}]},
	"drawing": {"title": "DRAWING", "depth": "mid",
		"see": ["Wax crayon. A green sun over a brown field. Two stick people.",
			"The tall one wears a white coat. Signed JUNO. Dated 06.11."], "think": ""},
	# --- Comms. Opens on the first clear or day 3. ---------------------------
	"comms": {"title": "SATELLITE", "depth": "mid",
		"see": ["SATELLITE COMPOSITE, 14 MONTHS.",
			"Grey spreads from one point. The point doesn't move. It's this station."],
		"think": "It isn't stopping."},
	"coords": {"title": "COORDINATES", "depth": "deep",
		"see": ["52.41N 1.93W, on the composite.", "Grey since month nine."], "think": ""},
	"vm_1": {"title": "MESSAGE 1", "depth": "mid", "min_day": 3, "needs": {"cleared": "any"},
		"see": ["MSG 1. RECEIVED 18:02. 0:31.",
			"\"Hi, it's me. Gran says you're too busy, so I'm ringing anyway.\"",
			"\"The north field's gone grey. Like your pictures. Gran says it's the weather.\"",
			"\"Ring me back? Love you. Bye. Bye.\""],
		"think": "Juno."},
	"vm_2": {"title": "MESSAGE 2", "depth": "mid", "min_day": 6, "min_stage": 2,
		"requires": {"lore": "vm_1"},
		"see": ["MSG 2. RECEIVED 04:12. 0:48.",
			"\"It's me. It's over the fence now. The dog won't go out.\"",
			"\"The radio keeps saying Halden. That's your work. Isn't it?\"",
			"\"Gran's not well. Please ring. Please.\""],
		"think": "There's no line out."},
	"vm_3": {"title": "MESSAGE 3", "depth": "deep", "min_day": 10, "min_stage": 3,
		"requires": {"lore": "vm_2"},
		"see": ["MSG 3. RECEIVED 02:55. 2:10. MOSTLY WIND.",
			"\"...can't see the road... [WIND] ...it's soft, the ground, it gives when you...\"",
			"[STATIC, 1:40]",
			"\"...are you there...\""],
		"think": ""},
	"vm_4": {"title": "MESSAGE 4", "depth": "deepest", "min_day": 15, "min_stage": 4,
		"needs": {"pages": 4}, "requires": {"lore": "vm_3"},
		"see": ["MSG 4. RECEIVED 03:20. 0:58.",
			"\"Hi, it's me.\"  [4 SECONDS]  \"Hi, it's me.\"",
			"\"It's warm here. The ground's warm. We're all lying down in the north field.\"",
			"\"It's so loud here. You'd like it. Come home and lie down.\""],
		"think": "That's not her."},
	# --- CCTV. The lockdown file opens at stage 3 or an archive clear. -------
	"cctv": {"title": "CCTV 03:12", "depth": "deep", "min_stage": 3, "needs": {"cleared": "archive"},
		"see": ["CAM 04. DECON CORRIDOR. 03:12.",
			"A figure in a lab coat at the wall panel, back to the lens. The lights go red.",
			"Six people file into decon. The door shuts behind them. The figure doesn't turn."],
		"think": "That's my coat."},
	"cctv_palm": {"title": "CCTV 03:20", "depth": "deepest", "min_stage": 4, "needs": {"pages": 4},
		"see": ["CAM 02. SPLICE LAB. 03:20.",
			"The coat at the bench. One dish under the lamp. A blade drawn across the right palm.",
			"The hand held over the dish. Held there. Eleven seconds."],
		"think": "My hand didn't shake."},
	"decon": {"title": "DECON TRAY", "depth": "deepest", "min_stage": 4, "needs": {"pages": 4},
		"see": ["DECON - RETURN OF EFFECTS. The shutter is up.",
			"Six badges in the tray. Lanyards cut, not unclipped.",
			"R. OKAFOR. T. KOVAC. M. ADEYEMI. D. VOSS. S. BRANDT. P. NAIR."],
		"think": "Six. Not seven."},
	# --- Night changes. You don't remember any of these. ---------------------
	"n_chair": {"title": "CHAIR", "depth": "surface", "min_day": 2,
		"see": ["A desk chair from security, set square to the airlock door.",
			"Castor tracks through the dust, all the way from the corridor."],
		"think": "Someone sat watching the door."},
	"n_soil": {"title": "FOOTPRINTS", "depth": "surface", "min_day": 3,
		"see": ["Grey soil on the floor. Bare footprints, from the door to the cot."],
		"think": "My feet are clean."},
	"n_dish": {"title": "DISH", "depth": "mid", "min_day": 5,
		"see": ["A petri dish on the table, lid off, set out for someone.",
			"Masking tape, block capitals: CHAIN ENZYME. FOR LATER."],
		"think": "For later?"},
	"n_tally": {"title": "TALLY", "depth": "mid", "min_day": 6,
		"see": ["Tally marks scratched into the paint at knee height.", "{days} of them."],
		"think": "One a night."},
	"n_pot": {"title": "POT 17", "depth": "mid", "min_day": 7,
		"see": ["Trial pot 17, carried from the garden. Set by the scanner.",
			"A finger-hole in the grey. Something pushed in. Nothing there now."],
		"think": "Was I planting something?"},
	"n_headset": {"title": "HEADSET", "depth": "mid", "min_day": 8,
		"see": ["A stool by the console. The headset coiled on it, still warm.",
			"REDIAL 52.41N 1.93W. NO CARRIER. NO CARRIER. NO CARRIER."],
		"think": "Who was I calling?"},
	# --- Old Halden. ---------------------------------------------------------
	"plaque": {"title": "PLAQUE", "depth": "deepest",
		"see": ["STATION FALLOW. A HALDEN AGRITECH FACILITY.", "Under the words, a wheat-sheaf logo."],
		"think": ""},
	"tillwell": {"title": "OLD ADVERT", "depth": "deepest",
		"see": ["Archive drawer 2. A faded advert: TILLWELL by HALDEN.",
			"WAKE UP YOUR SOIL!  The same wheat-sheaf."],
		"think": "Same logo."},
	# --- Leash pages (archive clears + the palm pot). -------------------------
	"page_1": {"title": "NOTEBOOK PAGE I", "depth": "deepest", "hand": true, "page": "1",
		"see": ["A torn page, in your hand:",
			"Leashed, it starves when the lab feed stops. Grey soil has no feed. Trial 41: FAIL."],
		"think": ""},
	"page_2": {"title": "NOTEBOOK PAGE II", "depth": "deepest", "hand": true, "page": "2",
		"see": ["Another:", "Don't tie it to us. Tie it to something only living ground makes."],
		"think": ""},
	"page_3": {"title": "NOTEBOOK PAGE III", "depth": "deepest", "hand": true, "page": "3",
		"see": ["The last:", "Living soil is loud. A body is quiet.",
			"If it can only live where the Chorus is loud..."],
		"think": "Then it can't live in me."},
	# --- Stated once, in your own hand. Shown at the test bed (or by an ending).
	"truth": {"title": "IN YOUR HAND", "depth": "deepest",
		"see": ["Pencil, on the underside of the test bed. Your hand, steady:",
			"03:12 I locked us in. 03:14 I burned the stocks. 03:20 I cut my hand.",
			"I sent them through decon and held the door. Thirty-nine minutes.",
			"Nobody signed the second line. It would have lost. I didn't want it to lose."],
		"think": ""},
}

## Lines for objects that are not lore (shown, never collected).
const FLAVOR := {
	"palm_pot_early": ["A grey pot on its own stand. A smeared handprint on the rim."],
	"airlock_scan": ["OCCUPANT SCAN . . .", "CONTAMINATED. RELEASE DENIED."],
	"airlock_clean": ["OCCUPANT SCAN . . .", "CLEAN."],
	"cot": ["A fold-out cot. The blanket is kicked to the floor. Again."],
	"dark_room": ["The breaker for this room is dead."],
	"generator_dead": ["The generator is cold. The fuel gauge says otherwise."],
	"comms_dead": ["UPLINK: NO CARRIER. RETRYING NIGHTLY.", "The message light is off."],
	"cctv_live": ["CAM 01-06, LIVE. Empty rooms. On CAM 03, your own back.",
		"ARCHIVE: 1 FILE. 03:12. INDEX DAMAGED."],
	"coat_key": ["Something in the coat pocket. A small key on a paper tag:", "DESK 2."],
	"drawer_locked": ["DESK 2. Top drawer, locked. A small keyhole."],
	"drawer_open": ["The key turns. A sample jar wrapped in a nitrile glove.",
		"Under it, a sealed reagent pouch."],
	"keypad": ["MEDICINE CABINET. FOUR-DIGIT KEYPAD.", "Tape on the frame, block capitals: J'S DRAWING."],
	"keypad_wrong": ["The keypad blinks red."],
	"keypad_open": ["The lock clunks. Gauze. Saline. A reagent pouch.", "Behind the saline, a sample jar."],
	"cabinet_empty": ["Gauze. Saline. Nothing you need."],
	"fridge": ["A fridge. A sandwich gone to fur.",
		"Behind it, a sample jar in a freezer bag. Labelled. Hidden."],
	"fridge_empty": ["A fridge. A sandwich gone to fur."],
	"toolbox": ["A toolbox behind the drums. Fuses, tape, a sealed reagent pouch."],
	"toolbox_empty": ["Fuses. Tape. Nothing else."],
	"deep_empty": ["DEEP STORE, -80. The rest is frost."],
	"tray": ["The lower rack slides out. A second culture tray, sealed, unused."],
	"decon_shut": ["DECON - RETURN OF EFFECTS. The shutter is down.", "Something small rattles behind it."],
	"testbed_hollow": ["A hollow pressed into the soil. About your length."],
	"sheet": ["A sequence sheet, taped up in a hurry. Cramped capitals."],
	"jar": ["A sample jar, sealed. Grown, labelled, put away."],
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


# ---------------------------------------------------------------------------
# Gates
# ---------------------------------------------------------------------------

## One condition. Values: cleared "<region>"|"any", pages N, lore "<id>",
## flag "<key>", found "<id>", power "<room>", root true.
func _cond(key: String, v) -> bool:
	match key:
		"cleared":
			var r := str(v)
			if r == "any":
				return not Game.cleared_once.is_empty()
			return Game.cleared_once.has(r)
		"pages":
			var n: int = int(v)
			return Game.leash_pages.size() >= n
		"lore":
			return Game.lore.has(str(v))
		"flag":
			return Game.flags.has(str(v))
		"found":
			return got(str(v))
		"power":
			return Game.is_powered(str(v))
		"root":
			return Game.root_unlocked()
	return false


## Gate check for an entry or an addendum (see the header).
func gate_ok(g: Dictionary) -> bool:
	var req: Dictionary = g.get("requires", {})
	for k in req.keys():
		if not _cond(str(k), req[k]):
			return false
	var gated := false
	var open := false
	if g.has("min_day"):
		gated = true
		var d: int = int(g["min_day"])
		if Game.day >= d:
			open = true
	if g.has("min_stage"):
		gated = true
		var s: int = int(g["min_stage"])
		if Game.stage >= s:
			open = true
	var needs: Dictionary = g.get("needs", {})
	for k in needs.keys():
		gated = true
		if _cond(str(k), needs[k]):
			open = true
	return open or not gated


## Is this entry in the world yet?
func available(id: String) -> bool:
	var e := entry(id)
	if e.is_empty():
		return false
	return gate_ok(e)


## True if reading `id` again would show something new (an unseen addendum is open).
func pending(id: String) -> bool:
	var e := entry(id)
	var more: Array = e.get("more", [])
	for i in more.size():
		var a: Dictionary = more[i]
		if not Game.lore.has("%s+%d" % [id, i]) and gate_ok(a):
			return true
	return false


# ---------------------------------------------------------------------------
# Finds (Game.flags["found"] = {id: true})
# ---------------------------------------------------------------------------

func got(id: String) -> bool:
	var f: Dictionary = Game.flags.get("found", {})
	return f.has(id)


func take(id: String) -> void:
	var f: Dictionary = Game.flags.get("found", {})
	f[id] = true
	Game.flags["found"] = f


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func _fmt(text: String, hand: bool) -> String:
	var t := text.replace("{days}", str(maxi(0, Game.day - 1)))
	return legible(t) if hand else t


## Lines to show for an entry: base + every addendum already seen (scrambled if
## it's your handwriting).
func lines(id: String) -> Array:
	var e := entry(id)
	var hand: bool = e.get("hand", false)
	var out: Array = []
	for l in e.get("see", []):
		out.append(_fmt(str(l), hand))
	var more: Array = e.get("more", [])
	for i in more.size():
		if not Game.lore.has("%s+%d" % [id, i]):
			continue
		var a: Dictionary = more[i]
		if a.get("replace", false):
			out.clear()
		var ah: bool = a.get("hand", hand)
		for l in a.get("see", []):
			out.append(_fmt(str(l), ah))
	return out


## Show an entry through the textbox, record it, grant leash pages. Awaitable.
## Think lines play only when something is new.
func show(id: String) -> void:
	var e := entry(id)
	if e.is_empty():
		return
	var first := not Game.lore.has(id)
	var thinks: Array = []
	var replaced := false
	if first:
		Game.lore[id] = Game.day
		if e.has("page"):
			var pg: String = str(e["page"])
			Game.leash_pages[pg] = true
	var more: Array = e.get("more", [])
	for i in more.size():
		var a: Dictionary = more[i]
		var key := "%s+%d" % [id, i]
		if Game.lore.has(key) or not gate_ok(a):
			continue
		Game.lore[key] = Game.day
		if a.get("replace", false):
			replaced = true
		var at: String = a.get("think", "")
		if at != "":
			thinks.append(at)
	if first and not replaced:
		var t: String = e.get("think", "")
		if t != "":
			thinks.push_front(t)
	await UI.say(lines(id), "see")
	for t in thinks:
		await UI.say([t], "think")
		Game.add_thought(t)
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


# ---------------------------------------------------------------------------
# Comms / voicemail
# ---------------------------------------------------------------------------

## Comms has a carrier once a region is cleared, or from day 3.
func comms_open() -> bool:
	return available("vm_1")


## Next voicemail waiting ("" if none).
func next_vm() -> String:
	for i in range(1, 5):
		var id := "vm_%d" % i
		if Game.lore.has(id):
			continue
		return id if available(id) else ""
	return ""


## Signal quality for a voicemail: 0 clean .. 3 not quite her.
func voicemail_level(id: String) -> int:
	return clampi(int(id.trim_prefix("vm_")) - 1, 0, 3)


## Voicemails heard so far, in order.
func heard_vms() -> Array:
	var out: Array = []
	for i in range(1, 5):
		if Game.lore.has("vm_%d" % i):
			out.append("vm_%d" % i)
	return out


# ---------------------------------------------------------------------------
# HUD: NOTE TO SELF
# ---------------------------------------------------------------------------

func objective() -> String:
	if Game.stage >= 5:
		return "Stay out of the garden."
	if not Game.is_powered("generator"):
		return "Power the generator."
	if Game.cleared_once.is_empty():
		return "Inject a culture. Bench."
	if Game.is_powered("freezer") and not got("lytic"):
		return "Something in the freezer."
	if got("key") and not got("drawer"):
		return "Find DESK 2."
	if comms_open() and Game.is_powered("comms") and next_vm() != "":
		return "Message on the comms."
	if Game.root_unlocked():
		return "THE ROOT is open."
	var names: Dictionary = Game.REGION_NAMES
	for r in Game.REGIONS:
		if not Game.cleared_once.has(r):
			return "Clear %s." % str(names.get(r, str(r).to_upper()))
	return "Hold on. Treat. Sleep."
