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
const LORE_OBJECTS := ["vial", "whiteboard", "binder", "coats", "mugs", "doorlog",
	"freezer", "pots", "photo", "drawing", "plaque"]

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


func _ready() -> void:
	if Game.unlocked.is_empty():
		Game.new_game()
	UI.apply_stage_post()
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
	_update_hud()


func _update_hud() -> void:
	var bmax := Game.breath_max()
	var sig := "%d|%d|%d|%d" % [Game.day, Game.breath, bmax, Game.reagent]
	if sig == _hud_sig:
		return
	_hud_sig = sig
	_hud_day.text = "DAY %02d" % Game.day
	_hud_reagent.text = "REAGENT %d" % Game.reagent
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
	match id:
		"badge":
			await Lore.show("badge")
			_map.remove_badge()
		"bench":
			if await _menus.bench():
				_leaving = true
		"cctv":
			if await _needs_power("cctv"):
				await _monitor("cctv")
				await Lore.show("cctv")
		"comms":
			if await _needs_power("comms"):
				await _monitor("comms")
				await Lore.show("comms")
				if Game.lore.has("photo"):
					await Lore.show("coords")
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
				var names: Array = []
				for s in Game.strains:
					names.append(Cards.STRAINS[s]["name"])
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


func _monitor(kind: String) -> void:
	var mon: CanvasLayer = Monitor.new()
	mon.set("kind", kind)
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
	if not await UI.confirm("THE TEST BED. THE SOIL IS WARM.\nSTAY HERE?"):
		return
	if not await UI.confirm("LIE DOWN?"):
		return
	_leaving = true
	Game.ending = "root"
	Game.save_game()
	Game.goto("ending")
