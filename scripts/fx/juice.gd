extends RefCounted
## Juice — static game-feel helpers. Usage: const Juice := preload("res://scripts/fx/juice.gd")
##   Juice.shake(target, strength, dur)      camera / Control / Node2D / Node3D jitter
##   Juice.hitstop(ctx, sec)                 brief near-freeze of Engine.time_scale
##   Juice.pop(parent, pos, text, color, sz) rising, fading number/word (sz 2 = big)
##   Juice.burst(parent3d, pos, color, n, speed)  cube debris with gravity
##   Juice.punch(ci, amount)                 scale punch
##   Juice.flash(ci, color, t)               modulate flash
## All tweens run in real time (ignore time_scale) so they keep moving through hitstop.

const META_SHAKE := "_juice_shake"
const META_ORIGIN := "_juice_origin"
const META_SCALE := "_juice_scale"
const META_PUNCH := "_juice_punch"
const META_MOD := "_juice_mod"
const META_FLASH := "_juice_flash"

static var _stop_until := 0
static var _base_time_scale := 1.0


## strength: pixels for Control/Node2D. For Camera3D/Node3D it is world units when < 1,
## and is read as pixels (x0.02 units) when >= 1, so one value can serve both.
static func shake(target: Node, strength: float, dur := 0.25) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or strength <= 0.0:
		return
	if target.has_meta(META_SHAKE):
		var prev: Tween = target.get_meta(META_SHAKE)
		if prev != null and prev.is_valid():
			prev.kill()
	var origin: Variant
	if target.has_meta(META_ORIGIN):
		origin = target.get_meta(META_ORIGIN)
	else:
		origin = _get_off(target)
		if origin == null:
			return
		target.set_meta(META_ORIGIN, origin)
	var amt := strength
	if target is Node3D and strength >= 1.0:
		amt = strength * 0.02
	var tw := target.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_shake_step.bind(target, origin, amt), 0.0, 1.0, maxf(dur, 0.02))
	tw.tween_callback(_shake_end.bind(target, origin))
	target.set_meta(META_SHAKE, tw)


static func _get_off(t: Node) -> Variant:
	if t is Camera3D:
		var cam := t as Camera3D
		return Vector2(cam.h_offset, cam.v_offset)
	if t is Control:
		return (t as Control).position
	if t is Node2D:
		return (t as Node2D).position
	if t is Node3D:
		return (t as Node3D).position
	return null


static func _shake_step(k: float, t: Node, origin: Variant, amt: float) -> void:
	if not is_instance_valid(t):
		return
	var a := amt * (1.0 - k) * (1.0 - k)
	if t is Camera3D:
		var cam := t as Camera3D
		var o: Vector2 = origin
		cam.h_offset = o.x + randf_range(-a, a)
		cam.v_offset = o.y + randf_range(-a, a)
	elif t is Control:
		var o2: Vector2 = origin
		(t as Control).position = o2 + Vector2(roundf(randf_range(-a, a)), roundf(randf_range(-a, a)))
	elif t is Node2D:
		var o3: Vector2 = origin
		(t as Node2D).position = o3 + Vector2(roundf(randf_range(-a, a)), roundf(randf_range(-a, a)))
	elif t is Node3D:
		var o4: Vector3 = origin
		(t as Node3D).position = o4 + Vector3(randf_range(-a, a), randf_range(-a, a), randf_range(-a, a) * 0.5)


static func _shake_end(t: Node, origin: Variant) -> void:
	if not is_instance_valid(t):
		return
	if t is Camera3D:
		var cam := t as Camera3D
		var o: Vector2 = origin
		cam.h_offset = o.x
		cam.v_offset = o.y
	elif t is Control:
		(t as Control).position = origin
	elif t is Node2D:
		(t as Node2D).position = origin
	elif t is Node3D:
		(t as Node3D).position = origin
	t.remove_meta(META_ORIGIN)
	t.remove_meta(META_SHAKE)


## Near-freeze for `sec` real seconds. Overlapping calls extend the stop; the
## pre-hitstop time scale is restored once the last one ends.
static func hitstop(ctx: Node, sec: float) -> void:
	if ctx == null or not is_instance_valid(ctx) or not ctx.is_inside_tree() or sec <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now >= _stop_until:
		_base_time_scale = Engine.time_scale if Engine.time_scale > 0.06 else 1.0
	_stop_until = maxi(_stop_until, now + int(sec * 1000.0))
	Engine.time_scale = 0.05
	var timer := ctx.get_tree().create_timer(sec, true, false, true)
	timer.timeout.connect(_hitstop_end)


static func _hitstop_end() -> void:
	if Time.get_ticks_msec() + 4 >= _stop_until:
		Engine.time_scale = _base_time_scale


## A number or word that pops in, bounces, rises and fades, then frees itself.
## pos is the centre of the text in `parent`'s local coordinates. sz 2 = double size.
static func pop(parent: CanvasItem, pos: Vector2, text: String, color: Color, sz := 1) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var s := float(clampi(sz, 1, 4))
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.05, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 60
	var w := float(text.length() * 8)
	l.size = Vector2(w + 1, 9)
	l.pivot_offset = Vector2(w * 0.5, 4)
	l.position = (pos - l.pivot_offset).round()
	l.scale = Vector2(s, s) * 0.3
	parent.add_child(l)
	var rise := Vector2(randf_range(-5.0, 5.0), -14.0 - 6.0 * s)
	var tw := l.create_tween().set_parallel(true)
	tw.set_ignore_time_scale(true)
	tw.tween_property(l, "scale", Vector2(s, s) * 1.35, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2(s, s), 0.14).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 5.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position", l.position + rise, 0.7).set_delay(0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


## Cube debris flying out of `pos` (parent-local), falling under gravity, shrinking, freed.
static func burst(parent: Node3D, pos: Vector3, color: Color, n := 14, speed := 2.5) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var root := Node3D.new()
	parent.add_child(root)
	var parts: Array[MeshInstance3D] = []
	var vels: Array[Vector3] = []
	var spins: Array[Vector3] = []
	for i in maxi(n, 1):
		var e := randf_range(0.05, 0.11)
		# Three fixed shades only: Retro.mat caches by colour, so no per-particle randoms.
		var shade := randi() % 3
		var col := color if shade == 0 else (color.lightened(0.3) if shade == 1 else color.darkened(0.25))
		var m := Retro.box(Vector3(e, e, e), col, pos, {"unlit": true})
		m.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		root.add_child(m)
		parts.append(m)
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.3), randf_range(-1.0, 1.0)).normalized()
		vels.append(dir * speed * randf_range(0.45, 1.0))
		spins.append(Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), 0))
	var life := 0.75
	var tw := root.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_burst_step.bind(parts, vels, spins, pos, life), 0.0, life, life)
	tw.tween_callback(root.queue_free)


static func _burst_step(t: float, parts: Array[MeshInstance3D], vels: Array[Vector3],
		spins: Array[Vector3], origin: Vector3, life: float) -> void:
	var k := maxf(0.05, 1.0 - t / life)
	for i in parts.size():
		var m := parts[i]
		if not is_instance_valid(m):
			continue
		var v := vels[i]
		m.position = origin + v * t + Vector3(0, -4.9 * t * t, 0)
		m.rotation = spins[i] * t
		m.scale = Vector3(k, k, k)


## Quick scale punch around the item's centre (Controls get a centred pivot if unset).
static func punch(ci: CanvasItem, amount := 0.15) -> void:
	if ci == null or not is_instance_valid(ci) or not ci.is_inside_tree():
		return
	if ci.has_meta(META_PUNCH):
		var prev: Tween = ci.get_meta(META_PUNCH)
		if prev != null and prev.is_valid():
			prev.kill()
	var base := Vector2.ONE
	if ci.has_meta(META_SCALE):
		base = ci.get_meta(META_SCALE)
	elif ci is Control:
		base = (ci as Control).scale
	elif ci is Node2D:
		base = (ci as Node2D).scale
	ci.set_meta(META_SCALE, base)
	if ci is Control:
		var c := ci as Control
		if c.pivot_offset == Vector2.ZERO:
			c.pivot_offset = c.size * 0.5
	var tw := ci.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(ci, "scale", base * (1.0 + amount), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ci, "scale", base, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_meta_clear.bind(ci, [META_SCALE, META_PUNCH]))
	ci.set_meta(META_PUNCH, tw)


## Brief over-bright modulate in `color`, easing back to the item's own modulate.
static func flash(ci: CanvasItem, color := Color.WHITE, t := 0.12) -> void:
	if ci == null or not is_instance_valid(ci) or not ci.is_inside_tree():
		return
	if ci.has_meta(META_FLASH):
		var prev: Tween = ci.get_meta(META_FLASH)
		if prev != null and prev.is_valid():
			prev.kill()
	var base: Color = ci.get_meta(META_MOD) if ci.has_meta(META_MOD) else ci.modulate
	ci.set_meta(META_MOD, base)
	ci.modulate = Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, base.a)
	var tw := ci.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(ci, "modulate", base, maxf(t, 0.02)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_meta_clear.bind(ci, [META_MOD, META_FLASH]))
	ci.set_meta(META_FLASH, tw)


static func _meta_clear(o: Object, keys: Array) -> void:
	if not is_instance_valid(o):
		return
	for k in keys:
		var key: String = k
		if o.has_meta(key):
			o.remove_meta(key)
