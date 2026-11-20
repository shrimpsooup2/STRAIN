extends Node3D
## Choose where to inject the culture. A pale low-poly body turns slowly on a
## scanner pad; each region is tinted by how far the Green has grown there.

const GeneArt := preload("res://scripts/run/gene_art.gd")

const ROWS := ["wound", "rivers", "hollow", "archive", "root", "back"]
const SKIN := Color("e4d8cc")
const GREEN_DEEP := Color("2e7a2a")
const GROWTH_WORD := ["CLEARED", "THIN", "SPREADING", "OVERGROWN"]
const MENU := Rect2(198, 4, 182, 128)
const INFO := Rect2(4, 152, 376, 60)
const ROW_H := 16

var sel := 0
var _t := 0.0
var _busy := false
var _body: Node3D
var _parts: Dictionary = {}     ## region -> Array[ShaderMaterial]
var _markers: Dictionary = {}   ## region -> MeshInstance3D
var _marker_base: Dictionary = {}
var _scan: Node3D
var _buttons: Array = []
var _info: Label
var _focus_style: StyleBoxFlat
var _row_style: StyleBoxEmpty


func _ready() -> void:
	UI.apply_stage_post()
	_build_world()
	_build_ui()
	_select(0)


# ------------------------------------------------------------------ 3D

func _growth(r: String) -> int:
	if r == "root":
		return 3
	return int(Game.regions.get(r, 0))


func _tint(r: String) -> Color:
	var k := float(_growth(r)) / 3.0 * 0.65
	if r == "root":
		k = clampf(float(Game.stage) / 6.0, 0.0, 0.8)
	return SKIN.lerp(GREEN_DEEP, k)


func _part(region: String, size: Vector3, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var col := _tint(region) if region != "" else SKIN
	var m := Retro.box(size, col, pos)
	if region != "":
		var mat := Retro.mat_unique(col)
		m.material_override = mat
		if not _parts.has(region):
			_parts[region] = []
		(_parts[region] as Array).append(mat)
	parent.add_child(m)
	return m


func _build_world() -> void:
	add_child(Retro.environment(Color("06080c"), Color("8090a0"), 0.7, Color("06080c"), 0.04))
	add_child(Retro.sun(Vector3(-35, 30, 0), Color("e8f0f0"), 0.9))
	add_child(Retro.omni(UI.C_ACCENT, 5.0, 0.6, Vector3(1.2, 2.4, 1.6)))

	# Floor grid + scanner pad.
	add_child(Retro.plane(Vector2(30, 30), Color.WHITE, Vector3(0, 0, 0),
		{"uv": 30.0, "tex": Retro.tex_tiles(Color("0c1218"), Color("16303a"), 16)}))
	add_child(Retro.cyl(0.62, 0.66, 0.06, Color("2a3a44"), 10, Vector3(0, 0.03, 0)))
	add_child(Retro.cyl(0.5, 0.5, 0.01, UI.C_ACCENT.darkened(0.5), 10, Vector3(0, 0.065, 0), {"unlit": true}))

	_body = Node3D.new()
	_body.position = Vector3(0, 0.07, 0)
	add_child(_body)
	# Legs, pelvis/belly (root), chest (hollow), neck, head (archive).
	for side in [-1, 1]:
		_part("", Vector3(0.17, 0.82, 0.19), Vector3(0.11 * side, 0.41, 0), _body)
		_part("", Vector3(0.18, 0.06, 0.24), Vector3(0.11 * side, 0.03, 0.03), _body)
	_part("root", Vector3(0.42, 0.34, 0.25), Vector3(0, 0.98, 0), _body)
	_part("hollow", Vector3(0.5, 0.4, 0.28), Vector3(0, 1.35, 0), _body)
	_part("", Vector3(0.12, 0.1, 0.12), Vector3(0, 1.6, 0), _body)
	_part("archive", Vector3(0.28, 0.32, 0.28), Vector3(0, 1.81, 0), _body)
	# Arms (rivers) and hands; the left hand (+x, facing camera) is the wound.
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(0.33 * side, 1.5, 0)
		arm.rotation.z = 0.12 * side
		_body.add_child(arm)
		_part("rivers", Vector3(0.13, 0.36, 0.14), Vector3(0, -0.18, 0), arm)
		_part("rivers", Vector3(0.12, 0.34, 0.13), Vector3(0, -0.53, 0), arm)
		_part("wound" if side > 0 else "", Vector3(0.12, 0.14, 0.08), Vector3(0, -0.77, 0), arm)
	_build_veins()

	# Region markers: floating diamonds in front of each site.
	var spots := {
		"wound": Vector3(0.48, 0.73, 0.28), "rivers": Vector3(-0.46, 1.05, 0.26),
		"hollow": Vector3(0.12, 1.42, 0.3), "archive": Vector3(0, 2.08, 0.18),
		"root": Vector3(0, 1.0, 0.3)}
	for r in spots:
		var col := _marker_color(r)
		var m := Retro.ball(0.055, col, 4, 2, spots[r], {"unlit": true})
		m.material_override = Retro.mat_unique(col, {"unlit": true})
		_body.add_child(m)
		_markers[r] = m
		_marker_base[r] = spots[r]

	# A scanner ring sweeping up and down.
	_scan = Node3D.new()
	for i in 16:
		var a := TAU * i / 16.0
		var seg := Retro.box(Vector3(0.2, 0.012, 0.02), UI.C_ACCENT, Vector3(cos(a), 0, sin(a)) * 0.6, {"unlit": true})
		seg.rotation.y = -a + PI / 2.0
		_scan.add_child(seg)
	add_child(_scan)

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.position = Vector3(0, 1.2, 4.2)
	add_child(cam)
	cam.look_at(Vector3(1.4, 0.55, 0))
	cam.current = true


func _marker_color(r: String) -> Color:
	if r == "root":
		return UI.C_GREEN if Game.root_unlocked() else Color("405040")
	var g := _growth(r)
	if g == 0:
		return Color("d8f0f4")
	return Color("a0d890").lerp(UI.C_GREEN, float(g) / 3.0)


## Faint green vein strips across the skin, more with every stage.
func _build_veins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var vmat_opts := {"unlit": true}
	var vcol := UI.C_GREEN.darkened(0.25)
	var count := 3 + Game.stage * 6
	# Front faces: [centre, half size x/y, z]
	var faces := [
		[Vector3(0.36, 0.75, 0.045), Vector2(0.05, 0.06)],   # left hand
		[Vector3(0.36, 1.0, 0.07), Vector2(0.05, 0.16)],     # left forearm
		[Vector3(0.34, 1.32, 0.075), Vector2(0.05, 0.16)],   # left upper arm
		[Vector3(0, 1.35, 0.145), Vector2(0.22, 0.18)],      # chest
		[Vector3(0, 0.98, 0.13), Vector2(0.19, 0.15)],       # belly
		[Vector3(-0.36, 1.0, 0.07), Vector2(0.05, 0.16)],    # right forearm
		[Vector3(-0.34, 1.32, 0.075), Vector2(0.05, 0.16)],  # right upper arm
		[Vector3(0, 1.6, 0.065), Vector2(0.05, 0.04)],       # neck
		[Vector3(0, 1.8, 0.145), Vector2(0.12, 0.14)],       # face
		[Vector3(0.11, 0.5, 0.1), Vector2(0.07, 0.3)],       # left leg
		[Vector3(-0.11, 0.5, 0.1), Vector2(0.07, 0.3)],      # right leg
	]
	for i in count:
		# Spread outward from the hand as the stage climbs.
		var reach := mini(faces.size(), 2 + Game.stage * 2)
		var f: Array = faces[0] if i < 3 else faces[rng.randi() % reach]
		var c: Vector3 = f[0]
		var h: Vector2 = f[1]
		var p := c + Vector3(rng.randf_range(-h.x, h.x), rng.randf_range(-h.y, h.y), 0.0)
		var lenv := rng.randf_range(0.06, 0.16)
		var v := Retro.box(Vector3(0.016, lenv, 0.01), vcol, p, vmat_opts)
		v.rotation.z = rng.randf_range(-0.8, 0.8)
		_body.add_child(v)


func _process(dt: float) -> void:
	_t += dt
	if _body:
		_body.rotation.y = sin(_t * 0.35) * 0.55
	if _scan:
		_scan.position.y = 1.0 + sin(_t * 0.9) * 0.95
	var focus: String = ROWS[sel]
	for r in _markers:
		var m: MeshInstance3D = _markers[r]
		var base: Vector3 = _marker_base[r]
		var on: bool = r == focus
		m.position = base + Vector3(0, sin(_t * 2.0 + base.y * 3.0) * 0.03, 0)
		m.rotation.y += dt * (3.0 if on else 1.0)
		var s := 1.0
		if on:
			s = 1.6 + sin(_t * 8.0) * 0.25
		m.scale = Vector3.ONE * s
	for r in _parts:
		var glow := Color.BLACK
		if r == focus:
			glow = Color(0.1, 0.35, 0.3) * (0.5 + 0.5 * sin(_t * 5.0))
		for mat in _parts[r]:
			(mat as ShaderMaterial).set_shader_parameter("emission", glow)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_focus_style = UI.box_style(UI.C_FOCUS, UI.C_ACCENT, 0, 0, Vector4(10, 3, 4, 3))
	_focus_style.border_width_left = 3
	_row_style = StyleBoxEmpty.new()
	_row_style.content_margin_left = 10
	_row_style.content_margin_top = 3
	_row_style.content_margin_bottom = 3

	var menu := UI.panel(MENU)
	layer.add_child(menu)
	var title := UI.label("INJECT WHERE?", UI.C_BORDER)
	title.position = MENU.position + Vector2(8, 6)
	layer.add_child(title)
	var day := UI.label("DAY %d" % Game.day, UI.C_DIM)
	day.position = MENU.position + Vector2(8, MENU.size.y - 14)
	layer.add_child(day)
	var st := "STAGE %d" % Game.stage
	var stl := UI.label(st, UI.C_BAD if Game.stage >= 4 else UI.C_DIM)
	stl.position = MENU.end - Vector2(8 + st.length() * 8, 14)
	layer.add_child(stl)
	for i in ROWS.size():
		var r: String = ROWS[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.position = MENU.position + Vector2(4, 17 + i * ROW_H)
		b.size = Vector2(MENU.size.x - 8, ROW_H - 1)
		b.text = "BACK TO LAB" if r == "back" else String(Game.REGION_NAMES[r])
		var idx := i
		b.mouse_entered.connect(func(): if not _busy and not UI.busy: _select(idx))
		b.pressed.connect(func(): _activate(idx))
		layer.add_child(b)
		_buttons.append(b)
		if r == "root":
			if not Game.root_unlocked():
				b.disabled = true
			elif Game.graft_ready():
				var br := UI.label("BIND READY", Color("287818"))
				br.position = Vector2(b.size.x - 84, 3)
				br.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(br)
		elif r != "back":
			var g := _growth(r)
			for k in 3:
				var pip := ColorRect.new()
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pip.position = Vector2(b.size.x - 34 + k * 10, 4)
				pip.size = Vector2(8, 7)
				pip.color = UI.C_INK
				b.add_child(pip)
				var fill := ColorRect.new()
				fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
				fill.position = Vector2(1, 1)
				fill.size = Vector2(6, 5)
				fill.color = UI.C_GREEN if k < g else Color("c8d0c8")
				pip.add_child(fill)
			if g == 0:
				var cl := UI.label("CLR", Color("308878"))
				cl.position = Vector2(b.size.x - 64, 3)
				cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(cl)

	var info := UI.panel(INFO)
	layer.add_child(info)
	_info = UI.label("")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(INFO.size.x - 14, INFO.size.y - 10)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info.add_child(_info)


func _select(i: int) -> void:
	sel = posmod(i, ROWS.size())
	for k in _buttons.size():
		var b: Button = _buttons[k]
		var st: StyleBox = _focus_style if k == sel else _row_style
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("disabled", st)
	_info.text = _info_text(ROWS[sel])


func _enemy_names(r: String) -> String:
	var re: Dictionary = Cards.REGION_ENEMIES[r]
	var names: Array = []
	for id in re["normal"]:
		names.append(String(Cards.enemy(id)["name"]))
	return ", ".join(names)


func _info_text(r: String) -> String:
	if r == "back":
		return "Seal the port. Go back to the bench.\nThe day does not end until you inject."
	var boss := String(Cards.enemy(Cards.REGION_ENEMIES[r]["boss"])["name"])
	if r == "root":
		if not Game.purge_available():
			return "THE ROOT\nToo deep now. It has gone past reaching."
		if not Game.root_unlocked():
			return "THE ROOT: SEALED\nClear all four regions to reach the centre."
		var t := "THE ROOT. HEART: %s\nKill it: PURGE. Everything it touched dies.\n" % boss
		if Game.graft_ready():
			t += "BIND READY: core at 40% or less, Chorus 10."
		else:
			t += "BIND: not ready."
		return t
	var g := _growth(r)
	var lines: Array = []
	lines.append("GROWTH: %s (%d/3)" % [GROWTH_WORD[g], g])
	lines.append("CLEAR: " + Game.region_reward_text(r))
	lines.append("HOSTS: %s" % _enemy_names(r))
	lines.append("HEART: %s" % boss)
	return "\n".join(lines)


func _activate(i: int) -> void:
	if _busy or UI.busy:
		return
	_select(i)
	var r: String = ROWS[sel]
	if r == "back":
		_busy = true
		Game.goto("lab")
		return
	if r == "root" and not Game.root_unlocked():
		UI.toast("SEALED", UI.C_BAD)
		return
	_busy = true
	var ok := await UI.confirm("Inject the culture into %s?" % String(Game.REGION_NAMES[r]).to_lower())
	if not ok:
		_busy = false
		return
	Game.start_run(r)
	Game.goto("run_map")


func _unhandled_input(e: InputEvent) -> void:
	if _busy or UI.busy:
		return
	if e.is_action_pressed("move_up"):
		_select(sel - 1)
	elif e.is_action_pressed("move_down"):
		_select(sel + 1)
	elif e.is_action_pressed("interact"):
		_activate(sel)
	elif e.is_action_pressed("back"):
		_busy = true
		Game.goto("lab")
	else:
		return
	get_viewport().set_input_as_handled()
