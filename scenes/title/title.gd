extends Node3D
## Title: a cracked vial on a bench in the dark, something green inside it.

var _cam: Camera3D
var _vial: Node3D
var _glow: OmniLight3D
var _menu: VBoxContainer
var _t := 0.0


func _ready() -> void:
	UI.set_post(0.0, 0.0)
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

	_cam = Camera3D.new()
	_cam.fov = 38
	add_child(_cam)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := UI.label("STRAIN", UI.C_PAPER, 24)
	title.position = Vector2(20, 26)
	layer.add_child(title)
	var sub := UI.label("STATION FALLOW  -  WING B", UI.C_THINK_FG)
	sub.position = Vector2(22, 58)
	layer.add_child(sub)

	var p := UI.panel(Rect2(16, 128, 120, 72))
	layer.add_child(p)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 0)
	p.add_child(_menu)
	var can_continue := Game.has_save()
	if can_continue:
		_add_button("CONTINUE", _on_continue)
	_add_button("NEW GAME", _on_new)
	_add_button("QUIT", func(): get_tree().quit())
	var hint := UI.label("Z/ENTER: SELECT   X: BACK", UI.C_DIM)
	hint.position = Vector2(150, 202)
	layer.add_child(hint)
	await get_tree().process_frame
	if is_inside_tree():
		(_menu.get_child(0) as Button).grab_focus()


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(104, 0)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.grab_focus())
	_menu.add_child(b)


func _process(dt: float) -> void:
	_t += dt
	var a := _t * 0.12
	_cam.position = Vector3(sin(a) * 3.0, 2.3, cos(a) * 3.0)
	_cam.look_at(Vector3(0.2, 1.1, 0.1))
	_glow.light_energy = 1.4 + sin(_t * 2.1) * 0.25 + (0.3 if fmod(_t, 4.7) < 0.08 else 0.0)


func _on_continue() -> void:
	if UI.busy:
		return
	if not Game.load_game():
		UI.toast("SAVE UNREADABLE", UI.C_BAD)
		return
	Game.resolve_abandoned_run()
	Game.goto("ending" if Game.ending != "" else "lab")


func _on_new() -> void:
	if UI.busy:
		return
	if Game.has_save() and not await UI.confirm("Start over? The current save will be erased."):
		(_menu.get_child(0) as Button).grab_focus()
		return
	Game.wipe_save()
	Game.new_game()
	Game.goto("lab")
