extends Node3D
## INJECTION (design §13). A pale low-poly body turns on a scanner pad; pick a
## region, then a site on a close-up, draw a dose, find the vein, push.
## Every injection leaves a track mark on the body.

const GeneArt := preload("res://scripts/run/gene_art.gd")
const Injection := preload("res://scripts/run/injection.gd")
const JUICE_PATH := "res://scripts/fx/juice.gd"

enum Step { REGION, SITE, DOSE, STAKES, SWEEP, STRUCK, PUSH }

const ROWS := ["wound", "rivers", "hollow", "archive", "root", "back"]
const SKIN := Color("e4d8cc")
const GREEN_DEEP := Color("2e7a2a")
const GROWTH_WORD := ["CLEARED", "THIN", "SPREADING", "OVERGROWN"]
const MENU := Rect2(198, 4, 182, 128)
const INFO := Rect2(4, 136, 376, 78)
const ROW_H := 16

# Close-up palette: dim, clinical.
const ART_OFS := Vector2(2, 14)
const PANEL := Rect2(200, 4, 180, 208)
const BG := Color("06080b")
const SKIN_D := Color("7c6e64")
const SKIN_S := Color("4a3f38")
const SKIN_H := Color("9c8c7e")
const VEIN := Color("3a4868")
const STEEL := Color("b8c4cc")
const HAIR := Color("1a1612")
const TIP_Y := 118.0
const SWEEP_C := 192.0
const SWEEP_A := 120.0
const VIEW_CORE := {
	"hand": Rect2(60, 112, 80, 66), "arm": Rect2(56, 96, 136, 30),
	"neck": Rect2(74, 40, 48, 94), "chest": Rect2(34, 20, 128, 170),
	"head": Rect2(50, 44, 100, 120)}

var sel := 0
var _t := 0.0
var _busy := false
var _body: Node3D
var _parts: Dictionary = {}     ## region -> Array[ShaderMaterial]
var _markers: Dictionary = {}   ## region -> MeshInstance3D
var _marker_base: Dictionary = {}
var _scan: Node3D
var _buttons: Array = []
var _info: RichTextLabel
var _page := 0
var _focus_style: StyleBoxFlat
var _row_style: StyleBoxEmpty
var _menu_layer: CanvasLayer

# Injection state.
var _step: int = Step.REGION
var _st := 0.0                  ## seconds in the current step
var _region := "wound"
var _site_i := 0
var _dose_i := 1
var _fill := 0.0                ## culture units drawn into the barrel
var _close_layer: CanvasLayer
var _close: Control
var _desc: Label
var _cover: ColorRect
var _cover_tw: Tween
var _tip := 0.0
var _phase := 0.0
var _vein_x := 200.0
var _vein_w := 16.0
var _vein_ph := 0.0
var _blown := false
var _hit_p := Vector2.ZERO
var _push := 0.0
var _inj_played := false
var _diving := false
var _shake := 0.0
var _hb := 0.0


func _ready() -> void:
	UI.apply_stage_post()
	Sfx.drone("lab")
	_build_world()
	_build_marks()
	_build_ui()
	_build_close()
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


## Every past injection, quietly: fresh red, older yellow-brown, blown ones bruised.
func _build_marks() -> void:
	var ms := Injection.marks()
	for i in ms.size():
		var mk: Variant = ms[i]
		if not (mk is Dictionary):
			continue
		var d: Dictionary = mk
		var p := Injection.mark_spot(d, i)
		var col := Injection.mark_color(d)
		if bool(d.get("blown", false)):
			_body.add_child(Retro.box(Vector3(0.05, 0.04, 0.006), col, p, {"unlit": true}))
			_body.add_child(Retro.box(Vector3(0.012, 0.012, 0.008), Color("6a1818"), p + Vector3(0, 0, 0.002), {"unlit": true}))
		else:
			_body.add_child(Retro.box(Vector3(0.014, 0.014, 0.012), col, p, {"unlit": true}))


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
	if _step != Step.REGION:
		_tick_close(dt)


# ------------------------------------------------------------------ region pick UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_menu_layer = layer
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
		b.text = "BACK TO BENCH" if r == "back" else String(Game.REGION_NAMES[r])
		var idx := i
		b.mouse_entered.connect(func(): if not _busy and not UI.busy and _step == Step.REGION: _select(idx))
		b.pressed.connect(func(): if _step == Step.REGION: _activate(idx))
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
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.scroll_active = false
	_info.fit_content = false
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(INFO.size.x - 14, INFO.size.y - 10)
	_info.add_theme_font_override("normal_font", UI.font)
	_info.add_theme_font_size_override("normal_font_size", 8)
	_info.add_theme_color_override("default_color", UI.C_INK)
	_info.add_theme_constant_override("line_separation", 1)
	info.add_child(_info)


func _select(i: int) -> void:
	sel = posmod(i, ROWS.size())
	for k in _buttons.size():
		var b: Button = _buttons[k]
		var st: StyleBox = _focus_style if k == sel else _row_style
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("disabled", st)
	_info.text = _info_text(ROWS[sel])


func _c(col: Color, s: String) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), s]


func _elites(re: Dictionary) -> Array:
	var el: Variant = re.get("elite", [])
	if el is String:
		return [el] if String(el) != "" else []
	if el is Array:
		return el
	return []


## "NAME (TRAIT): trait desc" or "NAME: blurb".
func _host_line(id: String, with_trait: bool) -> String:
	var e: Dictionary = Cards.enemy(id)
	var nm := String(e.get("name", id.to_upper()))
	var trt: Variant = e.get("trait", null)
	if with_trait and trt is Dictionary:
		var td: Dictionary = trt
		return "%s (%s): %s" % [_c(Color("a03030"), nm), String(td.get("name", "")), String(td.get("desc", ""))]
	var blurb := String(e.get("blurb", ""))
	return nm if blurb == "" else "%s: %s" % [_c(Color("305868"), nm), blurb]


func _medium_line(r: String) -> String:
	var md: Dictionary = Cards.REGION_MEDIUM.get(r, {})
	if md.is_empty():
		return ""
	return "%s %s" % [_c(Color("306878"), String(md.get("name", "")) + ":"), String(md.get("desc", ""))]


func _info_text(r: String) -> String:
	if r == "back":
		return "Seal the port. Back to the culture.\nThe day does not end until you inject."
	var re: Dictionary = Cards.REGION_ENEMIES.get(r, {})
	var boss_id := String(re.get("boss", ""))
	var boss := String(Cards.enemy(boss_id).get("name", "?"))
	if r == "root":
		if not Game.purge_available():
			return "THE ROOT\nToo deep now. It has gone past reaching."
		if not Game.root_unlocked():
			return "THE ROOT: SEALED\nClear all four regions to reach the centre."
		var t := "THE ROOT. HEART: %s\nKill it: PURGE. Everything it touched dies.\n" % boss
		if Game.graft_ready():
			t += "BIND READY: core at 40% or less, CHAIN x4."
		else:
			t += "BIND: not ready."
		var ml := _medium_line(r)
		if ml != "":
			t += "\n" + ml
		return t
	var lines: Array = []
	if _page == 0:
		var g := _growth(r)
		var ml := _medium_line(r)
		if ml != "":
			lines.append(ml)
		var gl := "GROWTH: %s (%d/3)" % [GROWTH_WORD[g], g]
		var tis := String(Cards.REGION_TISSUE.get(r, ""))
		if tis != "":
			gl += "  YIELDS: " + _c(Color("8a3030"), tis.to_upper())
		lines.append(gl)
		lines.append("CLEAR: " + Game.region_reward_text(r))
		lines.append(_c(UI.C_DIM, "< > HOSTS AND HEART"))
	else:
		for id in re.get("normal", []):
			lines.append(_host_line(String(id), false))
		var els := _elites(re)
		if not els.is_empty():
			lines.append("ELITE " + _host_line(String(els[0]), true))
		lines.append("HEART " + _host_line(boss_id, true))
	return "\n".join(lines)


func _activate(i: int) -> void:
	if _busy or UI.busy:
		return
	_select(i)
	var r: String = ROWS[sel]
	if r == "back":
		_busy = true
		Sfx.play("cancel")
		Game.goto("culture")
		return
	if r == "root" and not Game.root_unlocked():
		Sfx.play("error")
		UI.toast("SEALED", UI.C_BAD)
		return
	Sfx.play("select")
	_region = r
	_site_i = 0
	_enter(Step.SITE)


func _unhandled_input(e: InputEvent) -> void:
	if _busy or UI.busy or _diving:
		return
	var handled := true
	match _step:
		Step.REGION:
			if e.is_action_pressed("move_up"):
				Sfx.play("blip")
				_select(sel - 1)
			elif e.is_action_pressed("move_down"):
				Sfx.play("blip")
				_select(sel + 1)
			elif e.is_action_pressed("move_left") or e.is_action_pressed("move_right"):
				Sfx.play("blip")
				_page = 1 - _page
				_select(sel)
			elif e.is_action_pressed("interact"):
				_activate(sel)
			elif e.is_action_pressed("back"):
				_busy = true
				Sfx.play("cancel")
				Game.goto("culture")
			else:
				handled = false
		Step.SITE:
			if e.is_action_pressed("move_up") or e.is_action_pressed("move_left"):
				_pick_site(_site_i - 1)
			elif e.is_action_pressed("move_down") or e.is_action_pressed("move_right"):
				_pick_site(_site_i + 1)
			elif e.is_action_pressed("interact"):
				Sfx.play("select")
				_enter(Step.DOSE)
			elif e.is_action_pressed("back"):
				Sfx.play("cancel")
				_enter(Step.REGION)
			else:
				handled = false
		Step.DOSE:
			if e.is_action_pressed("move_left") or e.is_action_pressed("move_up"):
				_pick_dose(_dose_i - 1)
			elif e.is_action_pressed("move_right") or e.is_action_pressed("move_down"):
				_pick_dose(_dose_i + 1)
			elif e.is_action_pressed("interact"):
				Sfx.play("confirm")
				_enter(Step.STAKES)
			elif e.is_action_pressed("back"):
				Sfx.play("cancel")
				_enter(Step.SITE)
			else:
				handled = false
		Step.STAKES:
			if e.is_action_pressed("interact"):
				Sfx.play("needle")
				_enter(Step.SWEEP)
			elif e.is_action_pressed("back"):
				Sfx.play("cancel")
				_enter(Step.DOSE)
			else:
				handled = false
		Step.SWEEP:
			if e.is_action_pressed("interact"):
				_strike()
			elif e.is_action_pressed("back"):
				Sfx.play("cancel")
				_enter(Step.DOSE)
			else:
				handled = false
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ injection steps

func _sites() -> Array:
	return Injection.sites(_region)


func _site() -> Dictionary:
	var a := _sites()
	var d: Dictionary = a[clampi(_site_i, 0, a.size() - 1)]
	return d


func _site_id() -> String:
	return String(_site().get("id", ""))


func _dose() -> Dictionary:
	var d: Dictionary = Injection.DOSES[clampi(_dose_i, 0, Injection.DOSES.size() - 1)]
	return d


func _dose_id() -> String:
	return String(_dose().get("id", "dose"))


func _strain_color() -> Color:
	var sd: Dictionary = Cards.STRAINS.get(Game.strain, {})
	var c: Color = sd.get("color", UI.C_GREEN)
	return c


func _pick_site(i: int) -> void:
	var n := _sites().size()
	if n <= 1:
		return
	_site_i = posmod(i, n)
	Sfx.play("blip")
	_refresh_desc()


func _pick_dose(i: int) -> void:
	var n := Injection.DOSES.size()
	var ni := clampi(i, 0, n - 1)
	if ni == _dose_i:
		Sfx.play("error", 1.0, -8.0)
		return
	Sfx.play("plunger", 1.25 if ni > _dose_i else 0.85, -4.0)
	_dose_i = ni


func _build_close() -> void:
	_close_layer = CanvasLayer.new()
	_close_layer.layer = 11
	_close_layer.visible = false
	add_child(_close_layer)
	_close = Control.new()
	_close.position = Vector2.ZERO
	_close.size = Vector2(384, 216)
	_close.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close.draw.connect(_draw_close)
	_close_layer.add_child(_close)
	_desc = UI.label("", UI.C_THINK_FG)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.position = PANEL.position + Vector2(8, 98)
	_desc.custom_minimum_size = Vector2(PANEL.size.x - 16, 56)
	_desc.size = Vector2(PANEL.size.x - 16, 56)
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_close.add_child(_desc)
	_cover = ColorRect.new()
	_cover.size = Vector2(384, 216)
	_cover.color = Color(0, 0, 0, 0)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_layer.add_child(_cover)


func _refresh_desc() -> void:
	_desc.visible = _step == Step.SITE
	_desc.text = String(_site().get("desc", ""))


## A quick black blink between steps.
func _blink() -> void:
	if _cover_tw:
		_cover_tw.kill()
	_cover.color = Color(0, 0, 0, 1)
	_cover_tw = create_tween()
	_cover_tw.tween_property(_cover, "color", Color(0, 0, 0, 0), 0.2)


func _set_hb(rate: float) -> void:
	if absf(rate - _hb) < 0.1 and not (rate == 0.0 and _hb != 0.0):
		return
	_hb = rate
	Sfx.heartbeat(rate)


func _enter(s: int) -> void:
	_step = s
	_st = 0.0
	_menu_layer.visible = s == Step.REGION
	_close_layer.visible = s != Step.REGION
	_close.scale = Vector2.ONE
	if s != Step.PUSH:
		_blink()
	match s:
		Step.REGION:
			_set_hb(0.0)
			_select(sel)
		Step.SITE:
			_set_hb(0.0)
		Step.DOSE:
			_set_hb(0.0)
		Step.STAKES:
			_vein_x = randf_range(160.0, 250.0)
			_vein_ph = randf() * TAU
			_phase = -PI * 0.5
			_tip = SWEEP_C - SWEEP_A
			_blown = false
			_push = 0.0
			_inj_played = false
			_set_hb(0.9)
		Step.SWEEP:
			_phase = -PI * 0.5
			# No blink: the needle must not jump.
			if _cover_tw:
				_cover_tw.kill()
			_cover.color = Color(0, 0, 0, 0)
		Step.PUSH:
			Sfx.play("plunger")
	_refresh_desc()


func _vein_at(y: float) -> float:
	return _vein_x + sin(y * 0.035 + _vein_ph) * 8.0


func _tick_close(dt: float) -> void:
	_st += dt
	_shake = maxf(0.0, _shake - dt * 18.0)
	match _step:
		Step.DOSE, Step.SITE:
			var target: float = float(Injection.build_opts(_region, _site_id(), _dose_id(), false).get("max_colony", 30))
			if _step == Step.SITE:
				target = 0.0
			_fill = move_toward(_fill, target, dt * 40.0)
		Step.SWEEP:
			var w := minf(1.4 + _st * 0.15, 2.6)
			_phase += dt * w
			_tip = SWEEP_C + sin(_phase) * SWEEP_A
			_set_hb(1.0 + minf(_st, 8.0) * 0.18)
			if _st > 10.0:
				_strike()
		Step.STRUCK:
			if _st >= (1.1 if _blown else 0.7):
				_enter(Step.PUSH)
		Step.PUSH:
			_push = clampf(_st / 1.3, 0.0, 1.0)
			if not _inj_played and _st > 0.35:
				_inj_played = true
				Sfx.play("inject")
			if _st > 1.5 and not _diving:
				_dive()
	_close.queue_redraw()


func _strike() -> void:
	var d := absf(_tip - _vein_at(TIP_Y))
	_blown = d > _vein_w * 0.5 + 4.0
	_hit_p = Vector2(_tip, TIP_Y)
	_step = Step.STRUCK
	_st = 0.0
	if _blown:
		Sfx.play("hurt")
		Sfx.play("vein", 0.6, -4.0)
		UI.flash(Color(0.6, 0.08, 0.12, 0.6), 0.15)
		if not _juice("shake", [_close, 6.0, 0.3]):
			_shake = 6.0
		_set_hb(2.2)
	else:
		Sfx.play("vein")
		_juice("punch", [_close, 0.04])
		_set_hb(1.6)


## Calls a static Juice func if scripts/fx/juice.gd exists. False if not.
func _juice(fn: String, args: Array) -> bool:
	if not ResourceLoader.exists(JUICE_PATH):
		return false
	var j := load(JUICE_PATH) as Script
	if j == null:
		return false
	j.callv(fn, args)
	return true


func _dive() -> void:
	_diving = true
	_busy = true
	_set_hb(2.6)
	if _cover_tw:
		_cover_tw.kill()
	_close.pivot_offset = _hit_p
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_close, "scale", Vector2.ONE * 5.0, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_cover, "color", Color(0.42, 0.02, 0.04, 1.0), 0.6)
	await tw.finished
	_commit()


func _commit() -> void:
	var opts := Injection.build_opts(_region, _site_id(), _dose_id(), _blown)
	Injection.add_mark(_region, _site_id(), _blown)
	Game.start_run(_region, opts)
	Sfx.heartbeat(0.0)
	Game.goto("run_map")


# ------------------------------------------------------------------ close-up drawing

func _poly(pts: Array, col: Color) -> void:
	_close.draw_colored_polygon(PackedVector2Array(pts), col)


func _line(pts: Array, col: Color, w := 1.0) -> void:
	_close.draw_polyline(PackedVector2Array(pts), col, w)


func _shake_off() -> Vector2:
	if _shake <= 0.0:
		return Vector2.ZERO
	return Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))


func _draw_close() -> void:
	var sh := _shake_off()
	_close.draw_set_transform(sh)
	_close.draw_rect(Rect2(0, 0, 384, 216), BG)
	match _step:
		Step.SITE:
			_draw_site(sh)
		Step.DOSE:
			_draw_dose()
		Step.STAKES, Step.SWEEP, Step.STRUCK, Step.PUSH:
			_draw_insert()
	_close.draw_set_transform(Vector2.ZERO)
	# Scanlines + a hard vignette.
	for y in range(0, 216, 2):
		_close.draw_line(Vector2(0, y), Vector2(384, y), Color(0, 0, 0, 0.14), 1.0)
	for k in 4:
		_close.draw_rect(Rect2(k, k, 384 - k * 2, 216 - k * 2), Color(0, 0, 0, 0.5 - k * 0.1), false, 1.0)


func _header(s: String) -> void:
	GeneArt.text(_close, Vector2(6, 4), s, UI.C_DIM)


# ---- SITE

func _draw_site(sh: Vector2) -> void:
	var s := _site()
	var view := String(s.get("view", "hand"))
	_close.draw_set_transform(ART_OFS + sh)
	# Overhead lamp falloff.
	for k in 5:
		_close.draw_circle(Vector2(98, 90), 110.0 - k * 18.0, Color(0.5, 0.55, 0.6, 0.025))
	match view:
		"hand":
			_view_hand()
		"arm":
			_view_arm()
		"neck":
			_view_neck()
		"chest":
			_view_chest()
		"head":
			_view_head()
	var core: Rect2 = VIEW_CORE.get(view, Rect2(60, 60, 80, 80))
	_threads(core, _growth(_region) * 5 + Game.stage * 2, hash(view))
	_draw_site_marks(view)
	# Crosshairs for every site on this view.
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	for i in _sites().size():
		var o: Dictionary = _sites()[i]
		if String(o.get("view", "")) != view:
			continue
		var at: Vector2 = o.get("at", Vector2(98, 100))
		if i == _site_i:
			var r := 7.0 + pulse * 2.0
			_close.draw_arc(at, r, 0, TAU, 20, UI.C_ACCENT, 1.0)
			for q in 4:
				var a := q * PI * 0.5 + PI * 0.25
				var dv := Vector2(cos(a), sin(a))
				_close.draw_line(at + dv * (r + 3), at + dv * (r + 8), UI.C_ACCENT, 1.0)
			_close.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), UI.C_FOCUS)
		else:
			var c := Color(UI.C_ACCENT, 0.45)
			_close.draw_line(at - Vector2(4, 0), at + Vector2(4, 0), c, 1.0)
			_close.draw_line(at - Vector2(0, 4), at + Vector2(0, 4), c, 1.0)
	_close.draw_set_transform(sh)
	_header("SITE // " + String(Game.REGION_NAMES.get(_region, _region.to_upper())))

	# Panel: site list, plain-words effect, history.
	GeneArt.box(_close, PANEL, true)
	var p := PANEL.position
	GeneArt.text(_close, p + Vector2(8, 8), "INJECTION SITE", UI.C_DIM)
	for i in _sites().size():
		var o: Dictionary = _sites()[i]
		var y := 26.0 + i * 16.0
		var on := i == _site_i
		if on:
			_close.draw_rect(Rect2(p + Vector2(4, y - 3), Vector2(PANEL.size.x - 8, 14)), Color(UI.C_ACCENT, 0.16))
			_close.draw_rect(Rect2(p + Vector2(4, y - 3), Vector2(2, 14)), UI.C_ACCENT)
		GeneArt.text(_close, p + Vector2(10, y), String(o.get("name", "")), UI.C_PAPER if on else UI.C_DIM)
	_close.draw_line(p + Vector2(8, 88), p + Vector2(PANEL.size.x - 8, 88), Color(UI.C_ACCENT, 0.3), 1.0)
	var n := _marks_at(_region, _site_id()).size()
	var hist := "NO PRIOR MARKS" if n == 0 else ("%d PRIOR MARK" % n + ("" if n == 1 else "S"))
	GeneArt.text(_close, p + Vector2(8, 160), hist, Color("a85a50") if n > 0 else UI.C_DIM)
	GeneArt.text(_close, p + Vector2(8, 184), "NEXT: DOSE", UI.C_ACCENT.darkened(0.2 * pulse))
	GeneArt.text(_close, p + Vector2(8, 196), "BACK: REGION", UI.C_DIM)


func _marks_at(region: String, site_id: String) -> Array:
	var out: Array = []
	for m in Injection.marks():
		if m is Dictionary:
			var d: Dictionary = m
			if String(d.get("region", "")) == region and String(d.get("site", "")) == site_id:
				out.append(d)
	return out


## Old punctures around each site on the close-up.
func _draw_site_marks(view: String) -> void:
	for o in _sites():
		var od: Dictionary = o
		if String(od.get("view", "")) != view:
			continue
		var at: Vector2 = od.get("at", Vector2.ZERO)
		var ms := _marks_at(_region, String(od.get("id", "")))
		for i in ms.size():
			var d: Dictionary = ms[i]
			var h := hash("%d" % i + String(od.get("id", "")))
			var off := Vector2(float(h % 13) - 6.0, float((h / 13) % 13) - 6.0)
			var col := Injection.mark_color(d)
			if bool(d.get("blown", false)):
				_close.draw_circle(at + off, 5.0, Color(col, 0.55))
				_close.draw_circle(at + off, 2.5, Color(col.darkened(0.3), 0.8))
			else:
				_close.draw_rect(Rect2(at + off, Vector2(2, 2)), col)


func _threads(core: Rect2, n: int, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var c := Color(UI.C_GREEN.darkened(0.4), 0.7)
	for i in n:
		var p0 := core.position + Vector2(rng.randf() * core.size.x, rng.randf() * core.size.y)
		var a := rng.randf() * TAU
		var p1 := p0 + Vector2(cos(a), sin(a)) * rng.randf_range(5.0, 12.0)
		var a2 := a + rng.randf_range(-0.9, 0.9)
		var p2 := p1 + Vector2(cos(a2), sin(a2)) * rng.randf_range(4.0, 9.0)
		_line([p0, p1, p2], c)


func _view_hand() -> void:
	var sk := SKIN_D
	_close.draw_rect(Rect2(68, 178, 62, 22), sk.darkened(0.1))
	_poly([Vector2(56, 108), Vector2(142, 108), Vector2(148, 166), Vector2(132, 182),
		Vector2(66, 182), Vector2(52, 164)], sk)
	for f in [[58.0, 40.0, 18.0], [80.0, 24.0, 18.0], [102.0, 30.0, 18.0], [124.0, 46.0, 16.0]]:
		var x: float = f[0]
		var top: float = f[1]
		var w: float = f[2]
		_close.draw_rect(Rect2(x, top, w, 114.0 - top), sk)
		_close.draw_circle(Vector2(x + w * 0.5, top), w * 0.5, sk)
		for k in [0.36, 0.7]:
			var y: float = top + (112.0 - top) * float(k)
			_close.draw_line(Vector2(x + 3, y), Vector2(x + w - 3, y), SKIN_S, 1.0)
		_close.draw_rect(Rect2(x + 4, top - 5, w - 8, 10), SKIN_H)
		_close.draw_line(Vector2(x + w, top + 6), Vector2(x + w, 112), SKIN_S, 1.0)
	_poly([Vector2(54, 156), Vector2(26, 116), Vector2(22, 98), Vector2(34, 92),
		Vector2(52, 112), Vector2(64, 132)], sk.darkened(0.05))
	_line([Vector2(60, 128), Vector2(92, 124), Vector2(138, 132)], SKIN_S)
	_line([Vector2(64, 164), Vector2(84, 136), Vector2(96, 120)], SKIN_S)
	# The cut: a crusted seam across the palm.
	var cut := [Vector2(76, 152), Vector2(86, 146), Vector2(94, 151), Vector2(104, 145),
		Vector2(114, 150), Vector2(122, 146)]
	_line(cut, Color("4a1414"), 3.0)
	_line(cut, Color("9a2c2c"), 1.0)


func _view_arm() -> void:
	var sk := SKIN_D
	_poly([Vector2(0, 90), Vector2(34, 96), Vector2(36, 128), Vector2(0, 134)], sk.darkened(0.08))
	_close.draw_rect(Rect2(34, 98, 20, 28), sk)
	_poly([Vector2(52, 94), Vector2(196, 78), Vector2(196, 142), Vector2(52, 128)], sk)
	_close.draw_line(Vector2(40, 100), Vector2(40, 124), SKIN_S, 1.0)
	_close.draw_line(Vector2(47, 99), Vector2(47, 125), SKIN_S, 1.0)
	_line([Vector2(36, 112), Vector2(80, 110), Vector2(126, 104), Vector2(160, 99), Vector2(196, 95)], VEIN, 3.0)
	_line([Vector2(98, 108), Vector2(140, 120), Vector2(196, 128)], VEIN, 2.0)
	_line([Vector2(56, 118), Vector2(110, 123), Vector2(160, 126)], SKIN_H)
	_line([Vector2(60, 100), Vector2(120, 94)], SKIN_H)


func _view_neck() -> void:
	var sk := SKIN_D
	_poly([Vector2(0, 148), Vector2(60, 134), Vector2(136, 134), Vector2(196, 148),
		Vector2(196, 200), Vector2(0, 200)], sk)
	_poly([Vector2(72, 26), Vector2(124, 26), Vector2(132, 140), Vector2(64, 140)], sk)
	_poly([Vector2(40, 0), Vector2(156, 0), Vector2(150, 22), Vector2(98, 46), Vector2(46, 22)], SKIN_S)
	_poly([Vector2(46, 0), Vector2(150, 0), Vector2(146, 16), Vector2(98, 38), Vector2(50, 16)], sk.darkened(0.15))
	_close.draw_line(Vector2(80, 44), Vector2(94, 136), SKIN_S, 1.0)
	_close.draw_line(Vector2(116, 44), Vector2(102, 136), SKIN_S, 1.0)
	_line([Vector2(122, 36), Vector2(127, 88), Vector2(124, 138)], VEIN, 3.0)
	_close.draw_rect(Rect2(92, 98, 12, 9), SKIN_H)
	for i in 3:
		_close.draw_line(Vector2(92, 112 + i * 6), Vector2(104, 112 + i * 6), SKIN_S, 1.0)
	_line([Vector2(96, 140), Vector2(70, 148), Vector2(14, 144)], SKIN_H, 3.0)
	_line([Vector2(100, 140), Vector2(126, 148), Vector2(182, 144)], SKIN_H, 3.0)
	_close.draw_circle(Vector2(98, 138), 4.0, SKIN_S)


func _view_chest() -> void:
	var sk := SKIN_D
	_poly([Vector2(20, 0), Vector2(176, 0), Vector2(184, 200), Vector2(12, 200)], sk)
	_close.draw_rect(Rect2(93, 6, 10, 168), sk.lightened(0.08))
	for i in 6:
		var y := 22.0 + i * 26.0
		_line([Vector2(92, y), Vector2(64, y + 8), Vector2(30, y + 24)], SKIN_S, 2.0)
		_line([Vector2(104, y), Vector2(132, y + 8), Vector2(166, y + 24)], SKIN_S, 2.0)
	# The heart, faint behind the bone, beating.
	var beat := pow(maxf(0.0, sin(_t * 5.0)), 6.0)
	var hc := Color(0.45, 0.08, 0.1, 0.18 + 0.25 * beat)
	var hs := 1.0 + 0.08 * beat
	_close.draw_circle(Vector2(104, 98), 11.0 * hs, hc)
	_close.draw_circle(Vector2(120, 98), 11.0 * hs, hc)
	_poly([Vector2(93, 102), Vector2(131, 102), Vector2(112, 102 + 26.0 * hs)], hc)


func _view_head() -> void:
	var sk := SKIN_D
	_close.draw_rect(Rect2(78, 172, 40, 28), sk.darkened(0.1))
	_poly([Vector2(60, 18), Vector2(136, 18), Vector2(160, 56), Vector2(160, 130),
		Vector2(136, 178), Vector2(60, 178), Vector2(36, 130), Vector2(36, 56)], sk)
	_poly([Vector2(36, 58), Vector2(60, 14), Vector2(136, 14), Vector2(160, 58),
		Vector2(146, 40), Vector2(98, 30), Vector2(50, 40)], HAIR)
	_close.draw_rect(Rect2(160, 84, 8, 40), sk.darkened(0.15))
	_close.draw_rect(Rect2(66, 88, 22, 6), Color("1a1210"))
	_close.draw_rect(Rect2(108, 88, 22, 6), Color("1a1210"))
	_close.draw_line(Vector2(64, 84), Vector2(90, 84), SKIN_S, 1.0)
	_close.draw_line(Vector2(106, 84), Vector2(132, 84), SKIN_S, 1.0)
	_line([Vector2(98, 96), Vector2(94, 128), Vector2(103, 130)], SKIN_S)
	_close.draw_line(Vector2(82, 150), Vector2(114, 150), Color("5a3a34"), 2.0)
	_line([Vector2(50, 60), Vector2(46, 76), Vector2(52, 96)], VEIN, 2.0)
	_line([Vector2(144, 150), Vector2(154, 162), Vector2(166, 170)], HAIR, 2.0)


# ---- DOSE

const BARREL := Rect2(100, 70, 200, 28)
const UNIT_PX := 5.0


func _draw_dose() -> void:
	var sc := _strain_color()
	var sd: Dictionary = Cards.STRAINS.get(Game.strain, {})
	_header("DOSE // " + String(sd.get("name", "CULTURE")) + " // " + String(_site().get("name", "")))
	# Culture vial, lying on its side; the needle runs through the stopper.
	var vial := Rect2(10, 72, 42, 24)
	var left := clampf(1.0 - _fill / 46.0, 0.08, 1.0)
	_close.draw_rect(Rect2(vial.position + Vector2(1, 3), Vector2((vial.size.x - 2) * left, vial.size.y - 4)), sc.darkened(0.25))
	_close.draw_rect(vial, Color(0.7, 0.8, 0.85, 0.5), false, 1.0)
	_close.draw_rect(Rect2(52, 74, 6, 20), Color("2a2026"))
	# Needle, hub, barrel.
	_close.draw_line(Vector2(30, 84), Vector2(92, 84), STEEL, 1.0)
	_close.draw_rect(Rect2(90, 79, 10, 10), Color("8a949c"))
	_close.draw_rect(BARREL, Color(0.7, 0.8, 0.85, 0.07))
	var fw := _fill * UNIT_PX
	var liq := Rect2(BARREL.position + Vector2(1, 2), Vector2(maxf(0.0, fw - 1.0), BARREL.size.y - 4))
	_close.draw_rect(liq, sc.darkened(0.15))
	_close.draw_rect(Rect2(liq.position, Vector2(liq.size.x, 3)), sc.lightened(0.25))
	# Bubbles drifting in the culture.
	for i in 5:
		var bx := fmod(_t * (6.0 + i * 3.0) + i * 37.0, maxf(1.0, fw - 4.0))
		var by := 76.0 + float((i * 7) % 18)
		if fw > 8.0:
			_close.draw_rect(Rect2(BARREL.position.x + 2.0 + bx, by, 1, 1), sc.lightened(0.5))
	_close.draw_rect(BARREL, Color(STEEL, 0.6), false, 1.0)
	for u in range(0, 41, 2):
		var x := BARREL.position.x + u * UNIT_PX
		var hgt := 8.0 if u % 10 == 0 else 4.0
		_close.draw_line(Vector2(x, BARREL.position.y), Vector2(x, BARREL.position.y + hgt), Color(STEEL, 0.55), 1.0)
		if u % 10 == 0 and u > 0:
			GeneArt.text(_close, Vector2(x - 8, 58), str(u), UI.C_DIM)
	# Stopper, rod, thumb pad, finger flange.
	var sx := BARREL.position.x + fw
	_close.draw_rect(Rect2(sx, BARREL.position.y + 1, 6, BARREL.size.y - 2), Color("1c2024"))
	_close.draw_rect(Rect2(sx + 6, 82, 60, 4), Color("c8d0d4"))
	_close.draw_rect(Rect2(sx + 64, 68, 4, 32), Color("c8d0d4"))
	_close.draw_rect(Rect2(BARREL.end.x - 2, 62, 5, 44), Color("9aa4ac"))
	# Tier marks on the gauge.
	for i in Injection.DOSES.size():
		var dd: Dictionary = Injection.DOSES[i]
		var mx: int = int((dd["opts"] as Dictionary).get("max_colony", 30))
		var x := BARREL.position.x + mx * UNIT_PX
		var on := i == _dose_i
		var c := UI.C_ACCENT if on else UI.C_DIM
		_poly([Vector2(x, 100), Vector2(x - 3, 106), Vector2(x + 3, 106)], c)
		GeneArt.text(_close, Vector2(x - 8, 108), str(mx), c)
	# Tier boxes.
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	for i in Injection.DOSES.size():
		var dd: Dictionary = Injection.DOSES[i]
		var on := i == _dose_i
		var r := Rect2(12 + i * 124, 124, 112, 34)
		GeneArt.box(_close, r, true, UI.C_ACCENT if on else Color(0, 0, 0, 0))
		if on:
			_close.draw_rect(r.grow(2), Color(UI.C_ACCENT, 0.25 + 0.4 * pulse), false, 1.0)
		var nm := String(dd["name"])
		GeneArt.text(_close, r.position + Vector2((r.size.x - nm.length() * 8) * 0.5, 6), nm, UI.C_PAPER if on else UI.C_DIM)
		var sub := "MAX %d" % int((dd["opts"] as Dictionary).get("max_colony", 30))
		GeneArt.text(_close, r.position + Vector2((r.size.x - sub.length() * 8) * 0.5, 20), sub, sc if on else UI.C_DIM)
	var desc := String(_dose().get("desc", ""))
	GeneArt.text(_close, Vector2((384 - desc.length() * 8) * 0.5, 168), desc, UI.C_THINK_FG)
	var pv := _preview()
	GeneArt.text(_close, Vector2((384 - pv.length() * 8) * 0.5, 182), pv, UI.C_WARN)
	GeneArt.text(_close, Vector2(6, 200), "< > DRAW", UI.C_DIM)
	GeneArt.text(_close, Vector2(378 - 14 * 8, 200), "NEXT: THE VEIN", UI.C_ACCENT.darkened(0.2 * pulse))


func _preview() -> String:
	var o := Injection.build_opts(_region, _site_id(), _dose_id(), false)
	var s := "ENTER %d/%d COLONY" % [int(o.get("colony", 0)), int(o.get("max_colony", 0))]
	if int(o.get("fray", 0)) > 0:
		s += "  FRAY+%d" % int(o.get("fray", 0))
	if int(o.get("uptake", 0)) > 0:
		s += "  UPTAKE+%d" % int(o.get("uptake", 0))
	return s


# ---- INSERTION

func _draw_insert() -> void:
	var sc := _strain_color()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_site_id())
	_close.draw_rect(Rect2(0, 0, 384, 216), SKIN_D.darkened(0.3))
	for k in 5:
		_close.draw_circle(Vector2(200, 110), 170.0 - k * 30.0, Color(0.6, 0.55, 0.5, 0.035))
	for i in 90:
		var p := Vector2(rng.randf() * 384.0, rng.randf() * 216.0)
		_close.draw_rect(Rect2(p, Vector2(1, 1)), SKIN_S.darkened(0.2))
	# The vein: a soft blue rope under the skin.
	var pts: Array = []
	for y in range(-8, 232, 8):
		pts.append(Vector2(_vein_at(float(y)), float(y)))
	_line(pts, VEIN.darkened(0.3), _vein_w + 4.0)
	_line(pts, VEIN, _vein_w)
	_line(pts, VEIN.lightened(0.18), 3.0)
	_threads(Rect2(40, 20, 300, 170), _growth(_region) * 4 + Game.stage * 2, hash(_region))
	# Culture flowing into the vessel.
	if _step == Step.PUSH:
		var reach := _push * 140.0
		var flow: Array = []
		var y0 := TIP_Y - reach * 0.4
		var fy := y0
		while fy <= TIP_Y + reach:
			flow.append(Vector2(_vein_at(fy), fy))
			fy += 4.0
		if flow.size() >= 2:
			_line(flow, Color(sc, 0.85), _vein_w * 0.55)
	# Bruise from a blown vein.
	if _blown and (_step == Step.STRUCK or _step == Step.PUSH):
		var k := clampf(_st / 0.6, 0.0, 1.0) if _step == Step.STRUCK else 1.0
		_close.draw_circle(_hit_p, 6.0 + 16.0 * k, Color(0.36, 0.32, 0.12, 0.35))
		_close.draw_circle(_hit_p, 4.0 + 11.0 * k, Color(0.3, 0.1, 0.3, 0.6))
		_close.draw_circle(_hit_p, 2.0 + 4.0 * k, Color(0.45, 0.06, 0.08, 0.8))
	_draw_needle(sc)
	# Read bar.
	if _step == Step.STAKES or _step == Step.SWEEP or _step == Step.STRUCK:
		var bar := Rect2(32, 198, 320, 8)
		_close.draw_rect(bar.grow(1), Color(0, 0, 0, 0.8))
		var lo := SWEEP_C - SWEEP_A
		var span := SWEEP_A * 2.0
		var vx := _vein_at(TIP_Y)
		var band_w := (_vein_w + 8.0) / span * bar.size.x
		var bx := bar.position.x + (vx - lo) / span * bar.size.x - band_w * 0.5
		_close.draw_rect(Rect2(bx, bar.position.y, band_w, bar.size.y), Color(UI.C_ACCENT, 0.55))
		var cx := bar.position.x + clampf((_tip - lo) / span, 0.0, 1.0) * bar.size.x
		_close.draw_rect(Rect2(cx - 1, bar.position.y - 3, 2, bar.size.y + 6), UI.C_PAPER)
	_header("INSERTION // " + String(_site().get("name", "")))
	match _step:
		Step.STAKES:
			var box := Rect2(36, 26, 312, 52)
			GeneArt.box(_close, box, true)
			GeneArt.text(_close, box.position + Vector2(12, 8), "PRESS AS THE TIP CROSSES THE VEIN.", UI.C_PAPER)
			GeneArt.text(_close, box.position + Vector2(12, 22), "MISS: +1 FRAY, -3 COLONY.", UI.C_WARN)
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			GeneArt.text(_close, box.position + Vector2(12, 36), "STEADY. INTERACT TO BEGIN.", UI.C_DIM.lerp(UI.C_ACCENT, pulse))
		Step.STRUCK:
			var rise := minf(_st, 0.7) * 14.0
			var fade := clampf(1.4 - _st, 0.0, 1.0)
			if _blown:
				GeneArt.text(_close, Vector2(_hit_p.x - 40, _hit_p.y - 34 - rise), "BLOWN VEIN", Color(UI.C_BAD, fade))
				GeneArt.text(_close, Vector2(_hit_p.x - 72, _hit_p.y - 22 - rise), "+1 FRAY  -3 COLONY", Color(UI.C_WARN, fade))
			else:
				GeneArt.text(_close, Vector2(_hit_p.x - 44, _hit_p.y - 30 - rise), "CLEAN ENTRY", Color(UI.C_ACCENT, fade))
		Step.PUSH:
			var mx: float = float(Injection.build_opts(_region, _site_id(), _dose_id(), false).get("max_colony", 30))
			var left := int(round(mx * (1.0 - _push)))
			GeneArt.text(_close, Vector2(6, 200), "PUSHING  %d UNITS" % left, UI.C_DIM)


func _draw_needle(sc: Color) -> void:
	var dir := Vector2(1.0, -0.72).normalized()
	var tip := Vector2(_tip, TIP_Y)
	if _step == Step.STRUCK or _step == Step.PUSH:
		tip = _hit_p - dir * 5.0   # sunk in
	# Shadow on the skin, further off the closer the tip is to the surface.
	var so := Vector2(5, 7)
	_close.draw_line(tip + so + dir * 8.0, tip + so + dir * 220.0, Color(0, 0, 0, 0.25), 6.0)
	_close.draw_line(tip, tip + dir * 70.0, STEEL, 2.0)
	_poly([tip, tip + dir * 6.0 + dir.orthogonal() * 2.0, tip + dir * 6.0], Color.WHITE)
	_close.draw_line(tip + dir * 68.0, tip + dir * 80.0, Color("8a949c"), 7.0)
	# Flashback: a bead of blood in the hub on a clean entry.
	if not _blown and (_step == Step.STRUCK or _step == Step.PUSH):
		_close.draw_line(tip + dir * 70.0, tip + dir * 77.0, Color("8a1818"), 3.0)
	var b0 := tip + dir * 80.0
	var full := 120.0
	_close.draw_line(b0, b0 + dir * full, Color(0.75, 0.85, 0.9, 0.22), 17.0)
	var liq := full * (1.0 - _push)
	if liq > 1.0:
		_close.draw_line(b0, b0 + dir * liq, sc.darkened(0.15), 13.0)
	var stop := b0 + dir * maxf(liq, 1.0)
	_close.draw_line(stop, stop + dir * 5.0, Color("1c2024"), 15.0)
	_close.draw_line(stop + dir * 5.0, stop + dir * 70.0, Color("c8d0d4"), 4.0)
	_close.draw_line(b0 + dir * full, b0 + dir * (full + 3.0), Color("9aa4ac"), 30.0)
