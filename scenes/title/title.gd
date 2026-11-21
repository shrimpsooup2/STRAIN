extends Node3D
## Title: a cracked vial on a bench in the dark, something green inside it.
## The name glitches now and then. Sometimes it shows what's underneath.

const Juice := preload("res://scripts/fx/juice.gd")

const TITLE_POS := Vector2(20, 26)
const GLITCH_WORDS := ["SOWER", "S-7", "0001", "STRAIN"]

var _cam: Camera3D
var _vial: Node3D
var _glow: OmniLight3D
var _menu: VBoxContainer
var _t := 0.0
var _title: Label
var _ghost_g: Label
var _ghost_r: Label
var _sub: Label
var _scan: ColorRect
var _lock: Label
var _motes: Array = []  ## [{node, vel, phase}]
var _next_glitch := 4.0
var _glitch_end := 0.0
var _armed := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	UI.set_post(0.0, 0.0)
	_rng.randomize()
	Sfx.drone("title")
	_build_world()
	_build_ui()


func _build_world() -> void:
	add_child(Retro.environment(Color("06090c"), Color("1a2430"), 0.6, Color("06090c"), 0.08))
	add_child(Retro.sun(Vector3(-50, 30, 0), Color("8098b0"), 0.35))
	_glow = Retro.omni(Color("70d850"), 4.0, 1.6, Vector3(0, 1.3, 0))
	add_child(_glow)

	var floor_tex := Retro.tex_tiles(Color("2a3036"), Color("1a1e22"))
	add_child(Retro.plane(Vector2(20, 20), Color.WHITE, Vector3.ZERO, {"tex": floor_tex, "uv": 20.0}))
	# Bench.
	var bench_top := Retro.tex_noise(Color("c8ccc8"), Color("b8bcb8"), 16, 3, 0.3)
	add_child(Retro.box(Vector3(3.2, 0.12, 1.4), Color.WHITE, Vector3(0, 1.0, 0), {"tex": bench_top}))
	for x in [-1.45, 1.45]:
		for z in [-0.55, 0.55]:
			add_child(Retro.box(Vector3(0.1, 1.0, 0.1), Color("4a525a"), Vector3(x, 0.5, z)))
	# Clutter: rack, beakers, a dead lamp.
	add_child(Retro.box(Vector3(0.8, 0.2, 0.35), Color("586068"), Vector3(-0.9, 1.16, -0.3)))
	for i in 4:
		add_child(Retro.cyl(0.05, 0.05, 0.28, Color("a8c0c8"), 6, Vector3(-1.2 + i * 0.2, 1.3, -0.3)))
	add_child(Retro.cyl(0.14, 0.18, 0.3, Color("8890a0"), 6, Vector3(1.0, 1.21, 0.2)))
	add_child(Retro.box(Vector3(0.06, 0.6, 0.06), Color("3a4048"), Vector3(1.2, 1.36, -0.4)))
	add_child(Retro.box(Vector3(0.4, 0.12, 0.2), Color("3a4048"), Vector3(1.05, 1.66, -0.4)))

	# The vial: glass shell + glowing green core, tilted, a crack line.
	_vial = Node3D.new()
	_vial.position = Vector3(0.1, 1.06, 0.15)
	_vial.rotation_degrees = Vector3(0, 0, -78)
	_vial.add_child(Retro.cyl(0.09, 0.09, 0.5, Color("d0e8e0"), 8, Vector3(0, 0.25, 0), {"alpha": 0.45}))
	_vial.add_child(Retro.cyl(0.06, 0.06, 0.3, Color("70d850"), 6, Vector3(0, 0.17, 0), {"unlit": true}))
	_vial.add_child(Retro.cyl(0.1, 0.1, 0.06, Color("405060"), 8, Vector3(0, 0.52, 0)))
	add_child(_vial)
	# Spill.
	add_child(Retro.cyl(0.32, 0.32, 0.01, Color("3c8a30"), 7, Vector3(0.45, 1.065, 0.2), {"unlit": true}))
	add_child(Retro.box(Vector3(0.12, 0.02, 0.05), Color("d0e8e0"), Vector3(0.62, 1.07, 0.32), {"alpha": 0.6}))
	# Spores hanging in the air over the spill.
	for i in 24:
		var c := Color("70d850") if i % 3 == 0 else Color("6a7a70")
		var m := Retro.box(Vector3(0.015, 0.015, 0.015), c, Vector3(
			_rng.randf_range(-0.8, 1.2), _rng.randf_range(1.1, 2.2), _rng.randf_range(-0.6, 0.8)), {"unlit": true})
		add_child(m)
		_motes.append({"node": m, "vel": Vector3(_rng.randf_range(0.01, 0.04), _rng.randf_range(0.01, 0.05), 0.0),
			"phase": _rng.randf() * TAU})

	_cam = Camera3D.new()
	_cam.fov = 38
	add_child(_cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Chromatic ghosts behind the name; they split apart when it glitches.
	_ghost_g = UI.label("STRAIN", Color(UI.C_GREEN, 0.45), 24)
	_ghost_r = UI.label("STRAIN", Color(UI.C_BAD, 0.35), 24)
	_title = UI.label("STRAIN", UI.C_PAPER, 24)
	for l in [_ghost_g, _ghost_r, _title]:
		(l as Label).position = TITLE_POS
		layer.add_child(l)
	_scan = ColorRect.new()
	_scan.color = Color(0.8, 1.0, 0.9, 0.0)
	_scan.size = Vector2(150, 1)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_scan)
	_sub = UI.label("STATION FALLOW  -  WING B", UI.C_THINK_FG)
	_sub.position = Vector2(22, 58)
	layer.add_child(_sub)
	_lock = UI.label("LOCKDOWN", UI.C_BAD)
	_lock.position = Vector2(UI.W - 8 - 64, 8)
	layer.add_child(_lock)

	var p := UI.panel(Rect2(16, 128, 120, 72))
	layer.add_child(p)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 0)
	p.add_child(_menu)
	var can_continue := Game.has_save()
	if can_continue:
		_add_button("CONTINUE", _on_continue)
	_add_button("NEW GAME", _on_new)
	_add_button("QUIT", _on_quit)
	var hint := UI.label("Z/ENTER: SELECT   X: BACK", UI.C_DIM)
	hint.position = Vector2(150, 202)
	layer.add_child(hint)
	await get_tree().process_frame
	if is_inside_tree():
		(_menu.get_child(0) as Button).grab_focus()
		_armed = true


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(104, 0)
	b.pressed.connect(_on_pressed.bind(b, cb))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(_on_focus)
	_menu.add_child(b)


func _on_pressed(b: Button, cb: Callable) -> void:
	if UI.busy:
		return
	Sfx.play("confirm")
	Juice.punch(b, 0.12)
	cb.call()


func _on_focus() -> void:
	if _armed and not UI.busy:
		Sfx.play("blip")


func _process(dt: float) -> void:
	_t += dt
	var a := _t * 0.12
	_cam.position = Vector3(sin(a) * 3.0, 2.3 + sin(_t * 0.4) * 0.05, cos(a) * 3.0)
	_cam.look_at(Vector3(0.2, 1.1, 0.1))
	var glitching := _t < _glitch_end
	_glow.light_energy = 1.4 + sin(_t * 2.1) * 0.25 + (0.3 if fmod(_t, 4.7) < 0.08 else 0.0)
	if glitching:
		_glow.light_energy = 0.4 if _rng.randf() < 0.5 else 2.4
	for m in _motes:
		var node: Node3D = m["node"]
		var vel: Vector3 = m["vel"]
		var ph: float = m["phase"]
		node.position += vel * dt + Vector3(sin(_t * 0.7 + ph), 0.0, cos(_t * 0.5 + ph)) * 0.02 * dt
		if node.position.y > 2.4:
			node.position.y = 1.1
	_animate_title(glitching)


func _animate_title(glitching: bool) -> void:
	# Slow breath, a faint green shimmer, a scan line that passes every few seconds.
	var bob := roundf(sin(_t * 0.8) * 1.0)
	var shimmer := 0.5 + 0.5 * sin(_t * 1.6)
	_title.modulate = Color(1, 1, 1).lerp(Color(0.8, 1.0, 0.88), shimmer * 0.35)
	_sub.modulate.a = 0.75 + 0.25 * sin(_t * 0.9 + 1.0) - (0.4 if fmod(_t, 6.1) < 0.06 else 0.0)
	_lock.visible = fmod(_t, 1.4) < 0.9
	var sweep := fmod(_t, 5.0)
	_scan.position = Vector2(TITLE_POS.x - 4, TITLE_POS.y - 2 + sweep * 14.0)
	_scan.color.a = 0.35 if sweep < 2.2 else 0.0
	var off_g := Vector2(-1, 0) * shimmer
	var off_r := Vector2(1, 0) * shimmer
	if _t >= _next_glitch:
		_next_glitch = _t + _rng.randf_range(3.5, 8.0)
		_glitch_end = _t + _rng.randf_range(0.12, 0.25)
		glitching = true
		Sfx.play("glitch", _rng.randf_range(0.8, 1.2), -16.0)
		if _rng.randf() < 0.35:
			var w: String = GLITCH_WORDS[_rng.randi_range(0, GLITCH_WORDS.size() - 2)]
			_title.text = w
			_ghost_g.text = w
			_ghost_r.text = w
	if glitching:
		off_g = Vector2(_rng.randi_range(-4, 4), _rng.randi_range(-1, 1))
		off_r = Vector2(_rng.randi_range(-4, 4), _rng.randi_range(-1, 1))
		_title.position = TITLE_POS + Vector2(_rng.randi_range(-1, 1), bob)
	else:
		if _title.text != "STRAIN":
			_title.text = "STRAIN"
			_ghost_g.text = "STRAIN"
			_ghost_r.text = "STRAIN"
		_title.position = TITLE_POS + Vector2(0, bob)
	_ghost_g.position = _title.position + off_g
	_ghost_r.position = _title.position + off_r


func _on_continue() -> void:
	if UI.busy:
		return
	if not Game.load_game():
		Sfx.play("error")
		UI.toast("SAVE UNREADABLE", UI.C_BAD)
		return
	Game.resolve_abandoned_run()
	Game.goto("ending" if Game.ending != "" else "lab")


func _on_new() -> void:
	if UI.busy:
		return
	if Game.has_save() and not await UI.confirm("Start over? The current save will be erased."):
		Sfx.play("cancel")
		(_menu.get_child(0) as Button).grab_focus()
		return
	Juice.shake(_cam, 0.06, 0.3)
	Game.wipe_save()
	Game.new_game()
	Game.goto("lab")


func _on_quit() -> void:
	get_tree().quit()
