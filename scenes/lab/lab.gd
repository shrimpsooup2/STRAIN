extends Node3D
## The hub between runs: Station Fallow's sealed wing. Grid-walk the rooms,
## read what's left, restore power, and inject the day's Strand at the bench.

const LabMap := preload("res://scripts/lab/lab_map.gd")
const LabPlayer := preload("res://scripts/lab/lab_player.gd")
const LabMenus := preload("res://scripts/lab/lab_menus.gd")
const Monitor := preload("res://scripts/ui/monitor.gd")

const CAM_DIST := 9.0
const CAM_PITCH := 50.0
const TURN_DELAY := 0.1    ## tap = turn in place; hold longer = walk
const IDLE_TURN := 4.0     ## stage 5: seconds idle before you turn toward the garden
const GARDEN_TILE := Vector2i(19, 3)
const INTRO_TILE := Vector2i(4, 15)
const COT_TILE := Vector2i(23, 16)
const STAGE_LINES := {
	1: "The lines reached my wrist.",
	2: "My hands won't stop shaking.",
	3: "Every breath is work.",
	4: "The grey isn't in the room. It's in my eyes.",
	5: "We are so tired.",
}
const BREAKER_NAMES := {
	"medbay": "MEDBAY", "freezer": "FREEZER", "cctv": "CCTV", "comms": "COMMS",
	"archive": "ARCHIVE", "incubator": "INCUBATOR", "garden": "GARDEN",
}
const LORE_OBJECTS := ["vial", "whiteboard", "mugs", "doorlog", "freezer", "pots",
	"photo", "drawing", "plaque", "chair", "n_chair", "n_soil", "n_tally", "n_pot", "n_headset"]
## Sheets in rooms that need their own breaker before you can read them.
const SHEET_POWER := {"invert": "freezer", "lance": "cctv", "mirror": "incubator"}
const CABINET_CODE := "0611"
## Waking up somewhere you didn't lie down. One line, first time that day.
const WAKE_LINES := {
	3: "Grit in the blanket.",
	5: "My knees are grey.",
	8: "My voice is gone.",
	11: "Soil under my nails.",
	15: "The blanket is outside.",
}
## What each room is for, shown in the bottom strip while you stand in it.
const ROOM_PURPOSE := {
	"lab": "Bench: grow a culture, inject.",
	"corridor": "Signed doors. Breakers inside.",
	"medbay": "Scan the hand. Treat the spread.",
	"break": "Cot: sleep to end the day.",
	"freezer": "Deep store. Cold samples.",
	"security": "Camera files. Garden breaker.",
	"comms": "Messages. Station records.",
	"garden": "Trial beds. Keep out.",
	"generator": "Powers the whole wing.",
	"airlock": "The way out. Needs a clean scan.",
	"hatch": "One supply drop a day.",
	"incubator": "Culture lines on file.",
}
## What Z does to the thing you face. Lore objects fall back to LOOK + their title.
const OBJ_VERB := {
	"bench": "CULTURE BENCH: grow, inject",
	"scanner": "SCANNER: scan, treat",
	"cabinet": "CABINET: keypad",
	"cot": "COT: sleep, end the day",
	"generator": "GENERATOR: power the wing",
	"hatch": "SUPPLY HATCH: today's drop",
	"incubator": "INCUBATOR: culture lines",
	"cctv": "CCTV: camera files",
	"comms": "COMMS: messages",
	"testbed": "TEST BED",
	"airlock": "AIRLOCK: scan out",
	"decon": "DECON TRAY",
	"fridge": "FRIDGE: search",
	"toolbox": "TOOLBOX: search",
	"locker": "LOCKER: search",
	"coldbox": "COLD BOX: search",
	"deep": "DEEP FREEZE: search",
	"desk2": "DESK 2: drawer",
	"coats": "COAT HOOKS: search",
	"badge": "BADGE: pick up",
	"n_dish": "DISH: take",
}

var cam_dist := CAM_DIST

var _map: LabMap
var _player: LabPlayer
var _menus: LabMenus
var _cam: Camera3D
var _cam_target := Vector3.ZERO
var _acting := false
var _leaving := false
var _turn_wait := 0.0
var _chain := false
var _idle := 0.0
var _room := ""
var _hud_day: Label
var _hud_reagent: Label
var _hud_pips: HBoxContainer
var _hud_sig := ""
var _hud_note: Label
var _strip: PanelContainer
var _strip_name: Label
var _strip_room: Label
var _strip_hint: Label
var _strip_sig := ""


func _ready() -> void:
	if Game.unlocked.is_empty():
		Game.new_game()
	UI.apply_stage_post()
	Sfx.drone("lab")
	add_child(Retro.environment(Color("05070a"), Color(0.4, 0.46, 0.58), 0.32, Color("080c10"), 0.03))
	add_child(Retro.sun(Vector3(-60, 20, 0), Color(0.75, 0.82, 0.95), 0.12))
	_map = LabMap.new()
	add_child(_map)
	_map.build()
	_player = LabPlayer.new()
	add_child(_player)
	_player.walkable = _map.walkable
	_player.step_time = 0.28 if Game.stage >= 3 else 0.2
	_player.stepped.connect(_on_stepped)
	_menus = LabMenus.new()
	add_child(_menus)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.near = 0.3
	_cam.far = 60.0
	_cam.rotation_degrees.x = -CAM_PITCH
	add_child(_cam)
	_cam.current = true
	_build_hud()
	Game.save_game()
	_day_start()


# ------------------------------------------------------------ day start

func _day_start() -> void:
	# Debug: `--at=x,y` skips the wake-up and stands you on that tile.
	var at: String = Game._user_args().get("at", "")
	if at != "":
		var xy := at.split(",")
		_player.place(Vector2i(int(xy[0]), int(xy[1])), Vector2i(0, -1))
		_snap_camera()
		_room = _map.room_at(_player.tile)
		return
	# Back from the culture bench: stand where you left, no wake-up.
	if Game.flags.has("from_culture"):
		Game.flags.erase("from_culture")
		_player.place(Vector2i(2, 13), Vector2i(0, -1))
		_snap_camera()
		_room = _map.room_at(_player.tile)
		return
	_acting = true
	var intro := Game.day == 1 and not Game.flags.has("intro")
	if intro:
		# Woken on the floor beside the broken vial, alarm pulsing.
		_player.lie(Vector3(INTRO_TILE.x, 0, INTRO_TILE.y), Vector2i(1, 0))
	else:
		# Woken on the cot.
		_player.lie(Vector3(24.55, 0.26, 16.0), Vector2i(1, 0))
	_snap_camera()
	await get_tree().create_timer(1.4 if intro else 0.8).timeout
	if intro:
		await _player.stand_up(INTRO_TILE, Vector2i(1, 0))
		await get_tree().create_timer(0.4).timeout
		await UI.say(["My hand."], "think")
		Game.add_thought("My hand.")
		Game.flags["intro"] = true
		Game.flags["seen_stage"] = Game.stage
	else:
		await _player.stand_up(COT_TILE, Vector2i(0, 1))
		var seen := int(Game.flags.get("seen_stage", 0))
		if Game.stage > seen:
			await _stage_beat()
		Game.flags["seen_stage"] = Game.stage
		var woke := int(Game.flags.get("woke", 0))
		if WAKE_LINES.has(Game.day) and woke < Game.day:
			var wl: String = WAKE_LINES[Game.day]
			await UI.say([wl], "think")
			Game.add_thought(wl)
		Game.flags["woke"] = Game.day
	Game.save_game()
	_room = _map.room_at(_player.tile)
	UI.toast(_map.room_name(_room))
	_acting = false


## Wordless: the camera closes in, the left hand flares, one line.
func _stage_beat() -> void:
	await get_tree().create_timer(0.3).timeout
	var tw := create_tween()
	tw.tween_property(self, "cam_dist", 4.2, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	await _player.pulse_hand(3)
	var line: String = STAGE_LINES.get(Game.stage, "")
	if line != "":
		await UI.say([line], "think")
		Game.add_thought(line)
	tw = create_tween()
	tw.tween_property(self, "cam_dist", CAM_DIST, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


# ------------------------------------------------------------ frame / input

func _busy() -> bool:
	return UI.busy or _acting or _leaving


func _cam_offset() -> Vector3:
	var p := deg_to_rad(CAM_PITCH)
	return Vector3(0, sin(p), cos(p)) * cam_dist


func _snap_camera() -> void:
	_cam_target = _player.position + Vector3(0, 0.5, 0)
	_cam.position = _cam_target + _cam_offset()


func _process(dt: float) -> void:
	_cam_target = _cam_target.lerp(_player.position + Vector3(0, 0.5, 0), 1.0 - exp(-7.0 * dt))
	_cam.position = _cam_target + _cam_offset()
	_update_hud()
	_update_strip()
	if _busy():
		_idle = 0.0
		return
	var dir := _input_dir()
	if dir == Vector2i.ZERO:
		_turn_wait = 0.0
		_chain = false
		_idle += dt
		if Game.stage >= 5 and _idle > IDLE_TURN and not _player.moving:
			_face_garden()
		return
	_idle = 0.0
	if _player.moving:
		return
	if dir != _player.facing and not _chain:
		_player.face(dir)
		_turn_wait = TURN_DELAY
		return
	if _turn_wait > 0.0:
		_turn_wait -= dt
		return
	_chain = _player.try_step(dir)


func _input_dir() -> Vector2i:
	if Input.is_action_pressed("move_up"):
		return Vector2i(0, -1)
	if Input.is_action_pressed("move_down"):
		return Vector2i(0, 1)
	if Input.is_action_pressed("move_left"):
		return Vector2i(-1, 0)
	if Input.is_action_pressed("move_right"):
		return Vector2i(1, 0)
	return Vector2i.ZERO


func _face_garden() -> void:
	var d := GARDEN_TILE - _player.tile
	var dir := Vector2i(signi(d.x), 0) if absi(d.x) > absi(d.y) else Vector2i(0, signi(d.y))
	if dir != Vector2i.ZERO and dir != _player.facing:
		_player.face(dir)


func _unhandled_input(e: InputEvent) -> void:
	if _busy() or _player.moving:
		return
	if e.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_interact()
	elif e.is_action_pressed("menu") or e.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		_pause()


func _on_stepped(t: Vector2i) -> void:
	var r: String = _map.room_at(t)
	if r != _room and r != "":
		_room = r
		Sfx.play("door", 1.0, -8.0)
		UI.toast(_map.room_name(r))


# ------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var p := UI.panel(Rect2(4, 4, 0, 0), true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	p.add_child(vb)
	_hud_day = UI.label("", UI.C_PAPER)
	vb.add_child(_hud_day)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	vb.add_child(hb)
	hb.add_child(UI.label("BREATH", UI.C_THINK_FG))
	_hud_pips = HBoxContainer.new()
	_hud_pips.add_theme_constant_override("separation", 2)
	_hud_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(_hud_pips)
	_hud_reagent = UI.label("", UI.C_GREEN)
	vb.add_child(_hud_reagent)
	vb.add_child(UI.label("NOTE TO SELF", UI.C_DIM))
	_hud_note = UI.label("", UI.C_THINK_FG)
	vb.add_child(_hud_note)
	# Bottom strip: where you are, what the room is for, what Z does here.
	_strip = UI.panel(Rect2(4, 186, 376, 0), true)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_strip)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 2)
	_strip.add_child(sv)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 8)
	sv.add_child(rb)
	_strip_name = UI.label("", UI.C_ACCENT)
	rb.add_child(_strip_name)
	_strip_room = UI.label("", UI.C_DIM)
	rb.add_child(_strip_room)
	_strip_hint = UI.label("", UI.C_PAPER)
	sv.add_child(_strip_hint)
	_update_hud()


func _update_strip() -> void:
	_strip.visible = not _busy() and _room != ""
	if not _strip.visible:
		return
	var id: String = _map.objs.get(_player.target_tile(), "")
	var lit := _map.room_lit(_room)
	var sig := "%s|%s|%s|%s" % [_room, id, lit, Game.is_powered(id.substr(8)) if id.begins_with("breaker:") else false]
	if sig == _strip_sig:
		return
	_strip_sig = sig
	var purpose: String = ROOM_PURPOSE.get(_room, "")
	if not Game.is_powered("generator"):
		purpose = "NO POWER. Start the GENERATOR."
	elif not lit:
		purpose = "DARK. Breaker is in SECURITY." if _room == "garden" else "DARK. Breaker on the back wall."
	_strip_name.text = _map.room_name(_room)
	_strip_room.text = purpose
	_strip_room.add_theme_color_override("font_color", UI.C_DIM if lit else UI.C_WARN)
	_strip_hint.text = ("Z  " + _verb(id)) if id != "" else "TAB  menu"
	_strip_hint.add_theme_color_override("font_color", UI.C_PAPER if id != "" else UI.C_DIM)


func _verb(id: String) -> String:
	if id.begins_with("breaker:"):
		var room := id.substr(8)
		var label: String = BREAKER_NAMES.get(room, room.to_upper())
		if Game.is_powered(room):
			return "BREAKER: %s is on" % label
		return "BREAKER: power %s (%dR 1B)" % [label, int(Game.ROOM_POWER_COST.get(room, 3))]
	if id.begins_with("sheet:"):
		return "GENE SHEET: take"
	if OBJ_VERB.has(id):
		return OBJ_VERB[id]
	var e: Dictionary = Lore.entry(id)
	return "LOOK: " + str(e.get("title", id.to_upper()))


func _update_hud() -> void:
	var bmax := Game.breath_max()
	var note := Lore.objective()
	var sig := "%d|%d|%d|%d|%s" % [Game.day, Game.breath, bmax, Game.reagent, note]
	if sig == _hud_sig:
		return
	_hud_sig = sig
	_hud_day.text = "DAY %02d" % Game.day
	_hud_reagent.text = "REAGENT %d" % Game.reagent
	# Your own handwriting: it smudges as the infection reaches memory.
	_hud_note.text = "- " + Lore.legible(note)
	for c in _hud_pips.get_children():
		c.queue_free()
	for i in maxi(bmax, Game.breath):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(5, 7)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = UI.C_ACCENT if i < Game.breath else Color("2c3a40")
		_hud_pips.add_child(pip)


# ------------------------------------------------------------ interactions

func _interact() -> void:
	var id: String = _map.objs.get(_player.target_tile(), "")
	if id == "":
		return
	_acting = true
	await _use(id)
	_hud_sig = ""
	_acting = false


func _pause() -> void:
	_acting = true
	var r: String = await _menus.pause()
	if r == "title":
		_leaving = true
	_acting = false


func _use(id: String) -> void:
	if id in LORE_OBJECTS:
		await Lore.show(id)
		return
	if id.begins_with("breaker:"):
		await _breaker(id.substr(8))
		return
	if id.begins_with("sheet:"):
		await _sheet(id.substr(6))
		return
	match id:
		"badge":
			await Lore.show("badge")
			_map.remove_badge()
		"bench":
			_leaving = true
			Sfx.play("door", 1.3, -6.0)
			Game.goto("culture")
		"binder":
			await Lore.show("binder")
			if Lore.available("protocol"):
				await Lore.show("protocol")
		"coats":
			await Lore.show("coats")
			if not Lore.got("key"):
				await Lore.flavor("coat_key")
				Lore.take("key")
				Sfx.play("pickup")
				Game.save_game()
		"desk2":
			await _desk2()
		"cabinet":
			await _cabinet()
		"fridge":
			if Lore.got("steady_hand"):
				await Lore.flavor("fridge_empty")
			else:
				await Lore.flavor("fridge")
				await _specimen("steady_hand")
		"toolbox":
			if Lore.got("toolbox"):
				await Lore.flavor("toolbox_empty")
			else:
				await Lore.flavor("toolbox")
				Lore.take("toolbox")
				_gain_reagent(3)
		"locker":
			if await _needs_power("cctv"):
				if Lore.got("loose_splice"):
					await UI.say(["Steel shelves. A ring in the dust where a jar stood."])
				else:
					await Lore.flavor("jar")
					await _specimen("loose_splice")
					_map.remove_find("jar:loose_splice")
		"coldbox":
			if await _needs_power("archive"):
				if Lore.got("long_read"):
					await UI.say(["The cold box hums. Empty."])
				else:
					await UI.say(["ARCHIVE COLD BOX. 4C.", "One jar in the rack, frosted. A slip: KEEP. FOR READING."])
					await _specimen("long_read")
		"deep":
			if await _needs_power("freezer"):
				if Lore.got("lytic"):
					await Lore.flavor("deep_empty")
				else:
					await Lore.show("lytic")
					if not Game.strains.has("lytic"):
						Game.strains.append("lytic")
					Lore.take("lytic")
					Sfx.play("pickup")
					UI.toast("NEW STRAIN: LYTIC")
					Game.save_game()
		"decon":
			if Lore.available("decon"):
				await Lore.show("decon")
				await Lore.show("badge")
				_map.remove_badge()
			else:
				await Lore.flavor("decon_shut")
		"n_dish":
			await Lore.show("n_dish")
			if not Lore.got("chain_enzyme"):
				await _specimen("chain_enzyme")
			_map.remove_find("n_dish")
		"cctv":
			if await _needs_power("cctv"):
				await _cctv()
		"comms":
			if await _needs_power("comms"):
				await _comms()
		"tillwell":
			if await _needs_power("archive"):
				await Lore.show("tillwell")
		"palm_pot":
			if Game.day < 4:
				await Lore.flavor("palm_pot_early")
			else:
				await Lore.show("palm_pot")
		"airlock":
			await Lore.flavor("airlock_scan")
		"generator":
			await _generator()
		"scanner":
			await _scanner()
		"hatch":
			await _hatch()
		"cot":
			await _cot()
		"testbed":
			await _testbed()
		"incubator":
			if await _needs_power("incubator"):
				await _incubator()


func _gain_reagent(n: int) -> void:
	Game.reagent += n
	Sfx.play("pickup")
	UI.toast("REAGENT +%d" % n)
	Game.save_game()


## A sample jar: the adaptation joins the culture's grown list for the bench.
func _specimen(aid: String) -> void:
	var grown: Array = Game.culture.get("grown", [])
	if not grown.has(aid):
		grown.append(aid)
	Game.culture["grown"] = grown
	var specs: Array = Game.flags.get("specimens", [])
	if not specs.has(aid):
		specs.append(aid)
	Game.flags["specimens"] = specs
	Lore.take(aid)
	Sfx.play("pickup")
	var info := Adapt.info(aid)
	await UI.say(["SPECIMEN: %s" % str(info.get("name", aid)), str(info.get("desc", "")),
		"Grow it into the culture at the bench."])
	Game.save_game()


func _sheet(gene: String) -> void:
	var room: String = SHEET_POWER.get(gene, "")
	if room != "" and not await _needs_power(room):
		return
	await Lore.flavor("sheet")
	if not Game.unlocked.has(gene):
		Game.unlocked.append(gene)
	Lore.take("sheet:" + gene)
	_map.remove_find("sheet:" + gene)
	Sfx.play("page")
	var c: Dictionary = Cards.card(gene)
	await UI.say(["NEW GENE: %s" % str(c.get("name", gene.to_upper())), str(c.get("desc", "")),
		"It can turn up in your runs now."])
	Game.save_game()


func _desk2() -> void:
	if Lore.got("drawer"):
		await UI.say(["DESK 2. The drawer hangs open. Empty."])
		return
	if not Lore.got("key"):
		await Lore.flavor("drawer_locked")
		return
	Sfx.play("door", 1.6, -6.0)
	await Lore.flavor("drawer_open")
	Lore.take("drawer")
	_gain_reagent(2)
	await _specimen("pellicle")


func _cabinet() -> void:
	if not await _needs_power("medbay"):
		return
	if Lore.got("cabinet"):
		await Lore.flavor("cabinet_empty")
		return
	await Lore.flavor("keypad")
	var code := ""
	for i in 4:
		var digits: Array = []
		for d in 10:
			digits.append(str(d))
		var pick := await UI.choose(digits, "CODE: %s" % (code + "_".repeat(4 - code.length())))
		if pick < 0:
			return
		code += str(pick)
		Sfx.play("blip", 1.0 + i * 0.1)
	if code != CABINET_CODE:
		Sfx.play("error")
		await Lore.flavor("keypad_wrong")
		return
	Sfx.play("confirm")
	await Lore.flavor("keypad_open")
	Lore.take("cabinet")
	_gain_reagent(2)
	await _specimen("quorum_sense")


func _cctv() -> void:
	var files: Array = []
	if Lore.available("cctv"):
		files.append("cctv")
	if Lore.available("cctv_palm"):
		files.append("cctv_palm")
	if files.is_empty():
		await Lore.flavor("cctv_live")
		return
	var rows: Array = []
	for f in files:
		rows.append(("FILE 03:12" if f == "cctv" else "FILE 03:20") + ("" if Lore.has(f) else "  NEW"))
	rows.append("LEAVE")
	var i := await UI.choose(rows, "CCTV ARCHIVE.")
	if i < 0 or i >= files.size():
		return
	var f: String = files[i]
	await _monitor(f)
	await Lore.show(f)


func _comms() -> void:
	if not Lore.comms_open():
		await Lore.flavor("comms_dead")
		return
	await _monitor("comms")
	await Lore.show("comms")
	if Lore.has("photo"):
		await Lore.show("coords")
	var vm := Lore.next_vm()
	if vm == "":
		return
	await UI.say(["The message light is blinking."])
	await _monitor("voicemail", Lore.voicemail_level(vm), str(Lore.entry(vm).get("title", "")))
	await Lore.show(vm)


func _incubator() -> void:
	if not Lore.got("tray"):
		await Lore.flavor("tray")
		Lore.take("tray")
		Game.culture["trait_slots"] = maxi(int(Game.culture.get("trait_slots", 1)), 2)
		Sfx.play("pickup")
		UI.toast("CULTURE: 2 TRAIT SLOTS")
		Game.save_game()
		return
	var names: Array = []
	for s in Game.strains:
		var sd: Dictionary = Cards.STRAINS.get(s, {})
		names.append(str(sd.get("name", str(s).to_upper())))
	await UI.say(["INCUBATOR. CULTURE LINES ON FILE:", ", ".join(names) + "."])


func _needs_power(room: String) -> bool:
	if Game.is_powered("generator") and Game.is_powered(room):
		return true
	await Lore.flavor("dark_room")
	return false


## Machine actions cost breath. Returns true (after saying so) when there's none left.
func _tired() -> bool:
	if Game.breath > 0:
		return false
	await UI.say(["Too tired. Rest or inject."], "think")
	return true


func _monitor(kind: String, level := 0, label := "") -> void:
	var mon: CanvasLayer = Monitor.new()
	mon.set("kind", kind)
	mon.set("level", level)
	mon.set("label", label)
	add_child(mon)
	await mon.finished


func _generator() -> void:
	if Game.is_powered("generator"):
		await UI.say(["The generator hums. The needle holds."])
		return
	await Lore.flavor("generator_dead")
	if not await UI.confirm("RESTART GENERATOR? (1 BREATH)"):
		return
	if await _tired():
		return
	Game.spend_breath(1)
	Game.power_room("generator")
	_map.apply_power()
	Sfx.play("power_on")
	UI.flash(Color(0.9, 0.95, 1.0))
	UI.toast("MAINS: ON")
	Game.save_game()


func _breaker(room: String) -> void:
	var label: String = BREAKER_NAMES.get(room, room.to_upper())
	if Game.is_powered(room):
		await UI.say(["BREAKER: %s. ON." % label])
		return
	if not Game.is_powered("generator"):
		await UI.say(["BREAKER: %s. NO MAINS POWER." % label])
		return
	var cost: int = Game.ROOM_POWER_COST.get(room, 3)
	if not await UI.confirm("BREAKER: %s. OFF.\nRESTORE? %d REAGENT, 1 BREATH." % [label, cost]):
		return
	if await _tired():
		return
	if Game.reagent < cost:
		await UI.say(["NOT ENOUGH REAGENT. (%d/%d)" % [Game.reagent, cost]])
		return
	Game.spend_breath(1)
	if Game.power_room(room):
		_map.apply_power()
		Sfx.play("power_on")
		UI.toast("%s: POWER ON" % label)
		Game.save_game()


func _scanner() -> void:
	if not await _needs_power("medbay"):
		return
	var treat := "TREAT  3R 1B" if not Game.treated_today else "TREATED TODAY"
	var i := await UI.choose(["SCAN", {"text": treat, "disabled": Game.treated_today}, "LEAVE"], "MEDBAY SCANNER.")
	match i:
		0:
			await _menus.hand_panel(true)
		1:
			if await _tired():
				return
			if Game.reagent < 3:
				await UI.say(["NOT ENOUGH REAGENT. (%d/3)" % Game.reagent])
				return
			if Game.treat():
				UI.flash(UI.C_GREEN)
				Game.save_game()
				await UI.say(["TREATMENT CYCLE COMPLETE. SPREAD SLOWED."])
				await UI.say(["It burns. Then it's quiet."], "think")


func _hatch() -> void:
	var n := Game.take_supply()
	if n < 0:
		await UI.say(["Nothing else today."])
		return
	Game.save_game()
	if n == 0:
		await UI.say(["The hatch is empty. Nothing came today."])
		return
	await UI.say(["SUPPLY DROP #%d. RATIONS: %d. REAGENT +%d." % [200 + Game.day, maxi(1, n - 1), n]])


func _cot() -> void:
	await Lore.flavor("cot")
	if not await UI.confirm("SLEEP? THE DAY ENDS WITHOUT AN INJECTION."):
		return
	_leaving = true
	Game.end_day(0)
	if Game.ending != "":
		Game.goto("ending")
	elif Game.pending_dream > 0:
		Game.goto("dream")
	else:
		Game.goto("lab")


func _testbed() -> void:
	if not (Game.is_powered("garden") or Game.stage >= 5):
		await Lore.flavor("dark_room")
		return
	await Lore.flavor("testbed_hollow")
	if Game.root_unlocked() and not Lore.has("truth"):
		await Lore.show("truth")
	if not await UI.confirm("THE TEST BED. THE SOIL IS WARM.\nSTAY HERE?"):
		return
	if not await UI.confirm("LIE DOWN?"):
		return
	_leaving = true
	Game.ending = "root"
	Game.save_game()
	Game.goto("ending")
