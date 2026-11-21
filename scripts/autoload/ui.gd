extends Node
## Global UI: pixel theme, Pokemon-style textbox + choice box, fades, toast,
## the retro post-process pass, and debug screenshot/input hooks.
##
## While a textbox/choice is open `UI.busy` is true; scenes must ignore
## gameplay input then (check `if UI.busy: return`).

const W := 384
const H := 216
const TYPE_SPEED := 70.0  ## characters per second

const C_INK := Color("101820")
const C_PAPER := Color("f8f8f0")
const C_BORDER := Color("405868")
const C_ACCENT := Color("58d0a8")
const C_FOCUS := Color("d0f0e0")
const C_WARN := Color("e8a040")
const C_BAD := Color("d84848")
const C_GREEN := Color("70d850")
const C_DIM := Color("8890a0")
const C_THINK_BG := Color("141c24")
const C_THINK_FG := Color("a8e0c8")

signal _confirm
signal _chosen(index: int)

var font: FontFile
var theme: Theme
var busy: bool:
	get:
		return _open > 0

var _open := 0
var _typing := false
var _skip := false
var _choice_cancel := -2   ## -2 = no choice open; else value emitted on cancel
var _dialog_layer: CanvasLayer
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _post_layer: CanvasLayer
var _post_mat: ShaderMaterial
var _toast_layer: CanvasLayer
var _frame := 0
var _args := {}
var _choice_sfx := false      ## true once the choice box has its first focus (move blips on)
var _choice_cancelled := false
var _pulse_tw: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = 8
	theme = _build_theme()
	# Controls under a CanvasLayer don't inherit the root window's theme, so merge
	# ours into the engine default theme: every Control everywhere gets it.
	var dt := ThemeDB.get_default_theme()
	dt.merge_with(theme)
	dt.default_font = font
	dt.default_font_size = 8
	get_tree().root.theme = theme

	_dialog_layer = _layer(60)
	_toast_layer = _layer(70)
	_fade_layer = _layer(90)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)

	_post_layer = _layer(120)
	var post := ColorRect.new()
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/post.gdshader")
	post.material = _post_mat
	_post_layer.add_child(post)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _layer(n: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.layer = n
	add_child(l)
	return l


# ------------------------------------------------------------------ theme

func box_style(bg: Color, border: Color, width := 2, radius := 3, margin := Vector4(6, 4, 6, 4)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = false
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	return s


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 8

	var paper := box_style(C_PAPER, C_BORDER)
	t.set_stylebox("panel", "PanelContainer", paper)
	t.set_stylebox("panel", "Panel", paper)
	# Dark variation: think box, HUD over 3D.
	t.add_type("DarkPanel")
	t.set_type_variation("DarkPanel", "PanelContainer")
	t.set_stylebox("panel", "DarkPanel", box_style(C_THINK_BG, C_ACCENT.darkened(0.3)))

	t.set_color("font_color", "Label", C_INK)
	t.set_constant("line_spacing", "Label", 3)
	t.add_type("LightLabel")
	t.set_type_variation("LightLabel", "Label")
	t.set_color("font_color", "LightLabel", C_PAPER)

	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 10
	flat.content_margin_right = 4
	flat.content_margin_top = 3
	flat.content_margin_bottom = 3
	var focus := box_style(C_FOCUS, C_ACCENT, 0, 0, Vector4(10, 3, 4, 3))
	focus.border_width_left = 3
	t.set_stylebox("normal", "Button", flat)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("pressed", "Button", focus)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", flat)
	t.set_color("font_color", "Button", C_INK)
	t.set_color("font_hover_color", "Button", C_INK)
	t.set_color("font_focus_color", "Button", C_INK)
	t.set_color("font_pressed_color", "Button", C_INK)
	t.set_color("font_disabled_color", "Button", C_DIM)
	t.set_constant("h_separation", "Button", 4)

	var bar_bg := box_style(C_INK, C_INK, 1, 0, Vector4.ZERO)
	var bar_fg := box_style(C_GREEN, C_GREEN, 0, 0, Vector4.ZERO)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	t.set_color("font_color", "ProgressBar", C_PAPER)

	t.set_constant("separation", "VBoxContainer", 2)
	t.set_constant("separation", "HBoxContainer", 4)
	return t


# ------------------------------------------------------------------ helpers

func label(text: String, color := C_INK, size := 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size != 8:
		l.add_theme_font_size_override("font_size", size)
	return l


func panel(rect: Rect2, dark := false) -> PanelContainer:
	var p := PanelContainer.new()
	if dark:
		p.theme_type_variation = "DarkPanel"
	p.position = rect.position
	p.size = rect.size
	p.custom_minimum_size = rect.size
	return p


## A Pokemon-style colony bar: green > yellow > red by fraction.
func bar_color(frac: float) -> Color:
	if frac > 0.5:
		return C_GREEN
	if frac > 0.2:
		return Color("e8c840")
	return C_BAD


# ------------------------------------------------------------------ input routing

func _input(e: InputEvent) -> void:
	if _open <= 0:
		return
	var confirm: bool = e.is_action_pressed("interact") or \
		(e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if _choice_cancel != -2:
		# Choice open: buttons handle accept; we only handle cancel.
		if e.is_action_pressed("back") and _choice_cancel != -1000:
			get_viewport().set_input_as_handled()
			_choice_cancelled = true
			Sfx.play("cancel")
			_chosen.emit(_choice_cancel)
		return
	if confirm:
		get_viewport().set_input_as_handled()
		if _typing:
			_skip = true
		else:
			Sfx.play("blip", 0.8, -4.0)
			_confirm.emit()
	elif e.is_action_pressed("back") or e.is_action_pressed("move_up") or e.is_action_pressed("move_down") \
			or e.is_action_pressed("move_left") or e.is_action_pressed("move_right"):
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ textbox

func _make_box(style: String) -> Dictionary:
	var dark := style == "think"
	var p := panel(Rect2(4, H - 50, W - 8, 46), dark)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(W - 22, 34)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.add_theme_color_override("font_color", C_THINK_FG if dark else C_INK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	var arrow := label("v", C_THINK_FG if dark else C_BORDER)
	arrow.position = Vector2(W - 18, H - 14)
	arrow.visible = false
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_layer.add_child(p)
	_dialog_layer.add_child(arrow)
	return {"panel": p, "label": lbl, "arrow": arrow}


## Show lines one by one. style: "see" (white, what you observe) or "think" (dark, internal).
func say(lines, style := "see") -> void:
	if lines is String:
		lines = [lines]
	_open += 1
	var box := _make_box(style)
	var tw: Tween = null
	for line in lines:
		var lbl: Label = box["label"]
		lbl.text = str(line)
		lbl.visible_characters = 0
		var total := lbl.text.length()
		var t := 0.0
		var last_blip := 0
		var blip_pitch := 0.8 if style == "think" else 1.0
		_typing = true
		_skip = false
		while lbl.visible_characters < total:
			await get_tree().process_frame
			if _skip:
				break
			t += get_process_delta_time() * TYPE_SPEED
			lbl.visible_characters = mini(total, int(t))
			if lbl.visible_characters - last_blip >= 2:
				last_blip = lbl.visible_characters
				Sfx.play("type", blip_pitch * randf_range(0.88, 1.12), -6.0)
		lbl.visible_characters = -1
		_typing = false
		_skip = false
		var arrow: Label = box["arrow"]
		arrow.visible = true
		tw = create_tween().set_loops()
		tw.tween_property(arrow, "position:y", H - 12.0, 0.25)
		tw.tween_property(arrow, "position:y", H - 14.0, 0.25)
		await _confirm
		tw.kill()
		arrow.visible = false
	box["panel"].queue_free()
	box["arrow"].queue_free()
	await get_tree().process_frame
	_open -= 1


## Pokemon-style choice box. options: Array of String or {"text":..,"disabled":bool}.
## Returns the chosen index, or `cancel_value` if backed out (cancel disabled when allow_cancel=false).
func choose(options: Array, prompt := "", allow_cancel := true, cancel_value := -1) -> int:
	_open += 1
	_choice_cancel = cancel_value if allow_cancel else -1000
	_choice_sfx = false
	_choice_cancelled = false
	var prompt_box := {}
	if prompt != "":
		prompt_box = _make_box("see")
		prompt_box["label"].text = prompt
	var widest := 0
	for o in options:
		var txt: String = o if o is String else o.get("text", "")
		widest = maxi(widest, txt.length())
	var w := clampi(widest * 8 + 28, 64, W - 8)
	var max_h := (H - 54) if prompt != "" else (H - 8)
	var h := mini(options.size() * 14 + 12, max_h)
	var y := (H - 52 - h) if prompt != "" else (H - 4 - h)
	var p := panel(Rect2(W - 4 - w, y, w, h))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(w - 12, h - 8)
	p.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	var first: Button = null
	for i in options.size():
		var o = options[i]
		var b := Button.new()
		b.text = o if o is String else o.get("text", "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = (o is Dictionary) and o.get("disabled", false)
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func(): _chosen.emit(idx))
		b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
		b.focus_entered.connect(func(): if _choice_sfx: Sfx.play("blip"))
		vb.add_child(b)
		if first == null and not b.disabled:
			first = b
	_dialog_layer.add_child(p)
	await get_tree().process_frame
	if first:
		first.grab_focus()
	_choice_sfx = true
	var result: int = await _chosen
	_choice_sfx = false
	if not _choice_cancelled:
		Sfx.play("confirm")
	p.queue_free()
	if not prompt_box.is_empty():
		prompt_box["panel"].queue_free()
		prompt_box["arrow"].queue_free()
	_choice_cancel = -2
	await get_tree().process_frame
	_open -= 1
	return result


func confirm(prompt: String) -> bool:
	return await choose(["YES", "NO"], prompt, true, 1) == 0


## Small transient message at the top of the screen.
func toast(text: String, color := C_INK) -> void:
	var p := panel(Rect2(0, 4, 0, 0))
	var l := label(text, color)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(p)
	await get_tree().process_frame
	p.position.x = (W - p.size.x) / 2.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ fades / post

func fade_out(t := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, t)
	await tw.finished


func fade_in(t := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, t)
	await tw.finished


func flash(color: Color, t := 0.15) -> void:
	_fade.color = Color(color, 0.8)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, t)


## grey: 0..1 drain non-green colour. tremor: 0..1 screen shake chance.
func set_post(grey := 0.0, tremor := 0.0) -> void:
	_post_mat.set_shader_parameter("grey", grey)
	_post_mat.set_shader_parameter("tremor", tremor)


## Hurt pulse: tints the screen rim with `color`, then fades. strength ~0.3 graze .. 1.0 heavy.
func pulse(color := C_BAD, strength := 0.6) -> void:
	if _pulse_tw != null and _pulse_tw.is_valid():
		_pulse_tw.kill()
	var s := clampf(strength, 0.0, 1.5)
	_post_mat.set_shader_parameter("pulse_color", color)
	_pulse_tw = create_tween()
	_pulse_tw.set_ignore_time_scale(true)
	_pulse_tw.tween_method(_set_pulse, 0.0, s, 0.05)
	_pulse_tw.tween_method(_set_pulse, s, 0.0, 0.25 + 0.4 * s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_pulse(v: float) -> void:
	_post_mat.set_shader_parameter("pulse", v)


## Corner darkening, 0..1 (default 0.22). Dream/lab scenes may want more.
func set_vignette(v: float) -> void:
	_post_mat.set_shader_parameter("vignette", clampf(v, 0.0, 1.0))


## The body's current effect on what you see, by infection stage.
func apply_stage_post() -> void:
	var s := Game.stage
	var grey := 0.0
	if s >= 4:
		grey = 0.85
	elif s == 3:
		grey = 0.3
	set_post(grey, 0.35 if s >= 2 else 0.0)


# ------------------------------------------------------------------ debug hooks
## --shot=path.png --frames=N : save a screenshot after N frames, then quit.
## --input=F:action,F:action  : press `action` on frame F (for scripted smoke tests).
## --quit=N                   : quit after N frames.

func _process(_dt: float) -> void:
	_frame += 1
	if _args.has("input"):
		for pair in String(_args["input"]).split(","):
			var kv := pair.split(":")
			if kv.size() == 2 and int(kv[0]) == _frame:
				_press(kv[1])
	if _args.has("shot") and _frame == int(_args.get("frames", "60")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args["shot"])
		print("SHOT ", _args["shot"])
		if not _args.has("quit"):
			get_tree().quit()
	if _args.has("quit") and _frame >= int(_args["quit"]):
		get_tree().quit()


func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
