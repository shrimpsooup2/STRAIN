extends Node3D
## Shared rig for procedural enemy creatures (see creatures.gd for the factory).
## Same interface as ColonyCluster: set_count / flash / lunge / recoil / top /
## home / alive, plus windup / stagger / die / attack_anim.
##
## Hierarchy: self (position = home, moved by lunge/recoil)
##   └ _face (yaw toward the player and camera)
##       └ _rig (windup swell, tremble, lean, stagger wobble, death squash)
##           └ _root (spawn scale; subclasses build everything in here)
##
## Damage: subclasses register "parts" with _part(). The visible part count
## follows alive/cap; parts at the END of the list are lost first. Idle code
## must not touch a part's scale (POP) or position/rotation (FALL, FLING);
## animate a parent pivot instead.

const FACE := -0.9   ## yaw (rad): local +Z points between the player and the camera
const POP := 0       ## part swells and vanishes
const FALL := 1      ## part drops to the platform, lingers, then vanishes
const FLING := 2     ## part is thrown outward and vanishes

var home := Vector3.ZERO
var alive := 0
var cap := 1
var elite := false
var boss := false
var region := "wound"

## Palette, derived from Cards.REGION_COLORS in setup().
var c_floor := Color("6a2028")
var c_accent := Color("e06060")
var c_fog := Color("4a1418")
var c_flesh := Color.WHITE
var c_dark := Color.BLACK
var c_pale := Color.WHITE
var c_bone := Color("e8dcc4")
var c_void := Color("080406")
var c_sick := Color("c8b850")
var c_glow := Color(1.0, 0.3, 0.15)

var _face: Node3D
var _rig: Node3D
var _root: Node3D
var _height := 2.0          ## model height at scale 1 (for top())
var _base_k := 1.0          ## spawn scale of _root
var _native_elite := false  ## model is already a swollen/mutated form
var _native_boss := false   ## model is already boss-sized
var _rng := RandomNumberGenerator.new()

var _mats: Array = []       ## ShaderMaterial
var _mat_base: Array = []   ## Color
var _mat_emit: Array = []   ## bool: has an emission uniform
var _parts: Array = []      ## Node3D
var _part_info: Array = []  ## Dictionary {s, p, r, m}
var _part_tw: Array = []    ## Tween or null
var _shown := 0

var _t := 0.0
var _wind := 0.0
var _wind_on := false
var _stag := 0.0
var _lean := 0.0
var _swell := 0.0
var _emit_live := false
var _dead := false
var _flash_tw: Tween
var _move_tw: Tween
var _wind_tw: Tween
var _lean_tw: Tween
var _swell_tw: Tween
var _spawn_tw: Tween


func setup(p_region: String, p_cap: int, p_elite: bool, p_boss: bool) -> void:
	region = p_region
	cap = maxi(p_cap, 1)
	elite = p_elite
	boss = p_boss
	home = position
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	c_floor = pal["floor"]
	c_accent = pal["accent"]
	c_fog = pal["fog"]
	c_flesh = c_floor.lightened(0.3)
	c_dark = c_floor.darkened(0.45)
	c_pale = c_accent.lightened(0.45)
	c_bone = Color("e8dcc4").lerp(c_accent, 0.12)
	c_sick = Color("c8b850").lerp(c_accent, 0.25)
	c_glow = Color(1.0, 0.3, 0.15).lerp(c_accent, 0.25)
	_face = Node3D.new()
	_face.rotation.y = FACE
	add_child(_face)
	_rig = Node3D.new()
	_face.add_child(_rig)
	_root = Node3D.new()
	_rig.add_child(_root)
	_build()
	var k := 1.0
	if elite and not _native_elite:
		k *= 1.12
		_elite_growths()
	if boss and not _native_boss:
		k *= 1.4
	_base_k = k
	_root.scale = Vector3.ONE * k
	alive = cap
	_shown = _parts.size()


func _ready() -> void:
	home = position


# ------------------------------------------------------------ virtuals

## Build the model under _root. Set _height.
func _build() -> void:
	pass


## Per-frame idle animation.
func _idle(_time: float, _dt: float) -> void:
	pass


## Called after set_count with the health fraction 0..1.
func _on_count(_frac: float, _animate: bool) -> void:
	pass


func _on_windup(_on: bool) -> void:
	pass


func _on_stagger() -> void:
	pass


func _on_die() -> void:
	pass


## Creature-specific attack flourish (jaws, rings, whips).
func _attack(_kind: String) -> void:
	pass


## Default elite mutation for models that are not elite-native.
func _elite_growths() -> void:
	_tumours(_root, Vector3(0, _height * 0.55, 0), _height * 0.28, 5)


# ------------------------------------------------------------ build helpers

## A registered (flashable, glowable) unique material.
func _m(col: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var mm := Retro.mat_unique(col, opts)
	var alpha: float = opts.get("alpha", 1.0)
	_mats.append(mm)
	_mat_base.append(Color(col, alpha))
	_mat_emit.append(alpha >= 1.0)
	return mm


func _mi(m: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3, mat: Material, parent: Node3D, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, mat, parent, pos)


func _ball(r: float, mat: Material, parent: Node3D, pos := Vector3.ZERO, segs := 6, rings := 4) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return _mi(s, mat, parent, pos)


func _cyl(r_top: float, r_bottom: float, h: float, mat: Material, parent: Node3D, pos := Vector3.ZERO, segs := 6) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return _mi(c, mat, parent, pos)


## Torus lying in the local XZ plane (axis Y).
func _torus(inner: float, outer: float, mat: Material, parent: Node3D, pos := Vector3.ZERO, rings := 10, ring_segs := 4) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = ring_segs
	return _mi(t, mat, parent, pos)


func _pivot(parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	p.rotation = rot
	parent.add_child(p)
	return p


## Point a node's local +Y along dir (keeps its scale).
func _align_up(n: Node3D, dir: Vector3) -> void:
	var s := n.scale
	var d := dir.normalized()
	if d.dot(Vector3.UP) < -0.999:
		n.basis = Basis(Vector3.RIGHT, PI)
	else:
		n.basis = Basis(Quaternion(Vector3.UP, d))
	n.scale = s


## Random unit vector, biased to the upper hemisphere when min_y > -1.
func _rand_dir(min_y := -1.0) -> Vector3:
	for _i in 12:
		var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		if v.length() > 1.0 or v.length() < 0.1:
			continue
		v = v.normalized()
		if v.y >= min_y:
			return v
	return Vector3.UP


## Register a damage part. Parts added LAST are lost FIRST.
func _part(n: Node3D, mode := POP) -> Node3D:
	_parts.append(n)
	_part_info.append({"s": n.scale, "p": n.position, "r": n.rotation, "m": mode})
	_part_tw.append(null)
	return n


## Mutated lumps (elite). Registered as parts, so they burst first.
func _tumours(parent: Node3D, center: Vector3, radius: float, n: int) -> void:
	var mat := _m(c_sick)
	var vein := _m(c_sick.darkened(0.4))
	for i in n:
		var dir := _rand_dir(-0.2)
		var r := radius * _rng.randf_range(0.24, 0.4)
		var b := _ball(r, mat, parent, center + dir * radius * 0.9)
		b.scale = Vector3(1.0, _rng.randf_range(0.75, 1.2), 1.0)
		_ball(r * 0.35, vein, b, dir * r * 0.75, 4, 3)
		_part(b, POP)


# ------------------------------------------------------------ interface

func set_count(n: int, animate := true) -> void:
	if _dead:
		return
	n = clampi(n, 0, cap)
	var total := _parts.size()
	var want := 0
	if n > 0 and total > 0:
		want = clampi(int(ceil(float(n) * float(total) / float(cap))), 1, total)
	if n == alive and want == _shown:
		return
	var was := alive
	alive = n
	var k := 0
	if want < _shown:
		for i in range(_shown - 1, want - 1, -1):
			_lose_part(i, animate, 0.04 * k)
			k += 1
	elif want > _shown:
		for i in range(_shown, want):
			_regrow_part(i, animate, 0.03 * k + (0.18 if was == 0 else 0.0))
			k += 1
	_shown = want
	if n == 0 and was > 0:
		_show_root(false, animate)
	elif n > 0 and was == 0:
		_show_root(true, animate)
	_on_count(float(n) / float(cap), animate)


func flash(color := Color.WHITE, t := 0.22) -> void:
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_method(_flash_step.bind(color), 0.0, 1.0, t)


func _flash_step(v: float, color: Color) -> void:
	for i in _mats.size():
		var mm: ShaderMaterial = _mats[i]
		var base: Color = _mat_base[i]
		mm.set_shader_parameter("albedo", Color(color, base.a).lerp(base, v))


## Lunge toward a world-space point and back (awaitable, ~0.28 s).
func lunge(target: Vector3, dist := 0.8) -> void:
	if _move_tw:
		_move_tw.kill()
	var dir := target - home
	dir.y = 0.0
	dir = dir.normalized() * dist
	_move_tw = create_tween()
	_move_tw.tween_property(self, "position", home + dir, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tw.tween_property(self, "position", home, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_kick_lean(1.0, 0.1, 0.2)
	if is_inside_tree():
		await get_tree().create_timer(0.28).timeout


## A quick shove away from the attacker.
func recoil(from: Vector3) -> void:
	if _move_tw:
		_move_tw.kill()
	var dir := home - from
	dir.y = 0.0
	dir = dir.normalized() * 0.25
	_move_tw = create_tween()
	_move_tw.tween_property(self, "position", home + dir, 0.05)
	_move_tw.tween_property(self, "position", home - dir * 0.4, 0.06)
	_move_tw.tween_property(self, "position", home, 0.08)
	_kick_lean(-0.7, 0.05, 0.2)


func top() -> Vector3:
	var sy := 1.0
	if _rig:
		sy = _rig.scale.y
	var k := _base_k if (_root and _root.visible) else 0.3
	return global_position + Vector3(0, _height * k * sy + 0.35, 0)


## Swell, tremble and glow while a BREAK intent is pending.
func windup(on: bool) -> void:
	if _dead or on == _wind_on:
		return
	_wind_on = on
	if _wind_tw:
		_wind_tw.kill()
	_wind_tw = create_tween()
	_wind_tw.tween_property(self, "_wind", 1.0 if on else 0.0, 0.45 if on else 0.2)
	_on_windup(on)


func stagger() -> void:
	if _dead:
		return
	windup(false)
	_stag = 1.0
	flash(Color(0.75, 0.75, 0.8), 0.4)
	_on_stagger()


## Dramatic collapse. Awaitable (~1.1 s). Further set_count calls are ignored.
func die() -> void:
	if _dead:
		return
	if _wind_tw:
		_wind_tw.kill()
	_wind = 0.0
	_wind_on = false
	_set_emission(Color.BLACK)
	_on_die()
	_dead = true
	if _spawn_tw:
		_spawn_tw.kill()
	if not _root.visible:
		alive = 0
		return
	_root.scale = Vector3.ONE * _base_k
	flash(Color.WHITE, 0.45)
	for i in _shown:
		_lose_part(i, true, _rng.randf() * 0.35, FLING)
	_shown = 0
	alive = 0
	var r0 := _rig.rotation
	var tw := create_tween()
	tw.tween_property(_rig, "scale", Vector3(1.18, 1.22, 1.18), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rig, "rotation", r0 + Vector3(0.18, 0, 0.3), 0.16)
	tw.tween_property(_rig, "scale", Vector3(1.4, 0.22, 1.4), 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_rig, "position", Vector3(0, -0.05, 0), 0.4)
	tw.tween_interval(0.15)
	tw.tween_property(_rig, "scale", Vector3(0.001, 0.001, 0.001), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _root.visible = false)
	await tw.finished


## kind: "dmg" | "buff" | "plant" | "gnaw" | "drain"
func attack_anim(kind: String) -> void:
	if _dead:
		return
	match kind:
		"buff":
			_kick_swell(1.0, 0.18, 0.4)
			flash(c_pale, 0.35)
		"plant":
			_kick_lean(0.6, 0.12, 0.25)
			_spit()
		"gnaw":
			if _lean_tw:
				_lean_tw.kill()
			_lean_tw = create_tween()
			for _i in 3:
				_lean_tw.tween_property(self, "_lean", 0.8, 0.06)
				_lean_tw.tween_property(self, "_lean", 0.1, 0.07)
			_lean_tw.tween_property(self, "_lean", 0.0, 0.1)
		"drain":
			if _lean_tw:
				_lean_tw.kill()
			_lean_tw = create_tween()
			_lean_tw.tween_property(self, "_lean", 0.9, 0.15)
			_lean_tw.tween_interval(0.25)
			_lean_tw.tween_property(self, "_lean", -0.3, 0.2)
			_lean_tw.tween_property(self, "_lean", 0.0, 0.2)
			_kick_swell(0.8, 0.45, 0.4)
			flash(c_glow.darkened(0.3), 0.5)
		_:
			_kick_lean(1.0, 0.08, 0.25)
	_attack(kind)


# ------------------------------------------------------------ internals

func _kick_lean(peak: float, up: float, down: float) -> void:
	if _lean_tw:
		_lean_tw.kill()
	_lean_tw = create_tween()
	_lean_tw.tween_property(self, "_lean", peak, up).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lean_tw.tween_property(self, "_lean", 0.0, down).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _kick_swell(peak: float, up: float, down: float) -> void:
	if _swell_tw:
		_swell_tw.kill()
	_swell_tw = create_tween()
	_swell_tw.tween_property(self, "_swell", peak, up).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swell_tw.tween_property(self, "_swell", 0.0, down)


## A small blob arcs out of the creature toward the player and bursts.
func _spit() -> void:
	var mat := Retro.mat(c_sick.lerp(c_accent, 0.3))
	var b := Retro.ball(0.12, c_sick, 5, 3)
	b.material_override = mat
	add_child(b)
	var fwd := Vector3(sin(FACE), 0, cos(FACE))
	var start := Vector3(0, _height * _base_k * 0.6, 0) + fwd * 0.4
	b.position = start
	var arc := func(v: float) -> void:
		b.position = start + fwd * 2.4 * v + Vector3(0, sin(v * PI) * 0.8 - v * start.y * 0.8, 0)
	var tw := b.create_tween()
	tw.tween_method(arc, 0.0, 1.0, 0.45)
	tw.tween_property(b, "scale", Vector3(1.8, 0.2, 1.8), 0.08)
	tw.tween_callback(b.queue_free)


func _lose_part(i: int, animate: bool, delay: float, force_mode := -1) -> void:
	var p: Node3D = _parts[i]
	var info: Dictionary = _part_info[i]
	var s: Vector3 = info["s"]
	var mode: int = info["m"]
	if force_mode >= 0:
		mode = force_mode
	var old: Tween = _part_tw[i]
	if old:
		old.kill()
	if not animate or not p.is_inside_tree():
		p.scale = Vector3.ONE * 0.001
		p.visible = false
		_part_tw[i] = null
		return
	var tw := p.create_tween()
	_part_tw[i] = tw
	if delay > 0.0:
		tw.tween_interval(delay)
	match mode:
		FALL:
			var pos: Vector3 = info["p"]
			var par := p.get_parent() as Node3D
			var out := p.global_position - global_position
			out.y = 0.0
			out = out.normalized() * 0.35 if out.length() > 0.05 else Vector3(_rng.randf_range(-0.3, 0.3), 0, 0.3)
			var drop := maxf(p.global_position.y - global_position.y - 0.05, 0.0)
			var world := out + Vector3(0, -drop, 0)
			var local := par.global_transform.basis.inverse() * world
			var spin := Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.6, 1.6))
			tw.tween_property(p, "position", pos + local * 0.25, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(p, "position", pos + local, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(p, "rotation", p.rotation + spin, 0.38)
			tw.tween_interval(0.5)
			tw.tween_property(p, "scale", Vector3.ONE * 0.001, 0.2)
		FLING:
			var pos2: Vector3 = info["p"]
			var par2 := p.get_parent() as Node3D
			var out2 := p.global_position - global_position
			out2.y = 0.0
			out2 = out2.normalized() if out2.length() > 0.05 else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
			var world2 := out2 * _rng.randf_range(0.5, 1.1) + Vector3(0, _rng.randf_range(0.2, 0.7), 0)
			var local2 := par2.global_transform.basis.inverse() * world2
			tw.tween_property(p, "position", pos2 + local2, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(p, "rotation", p.rotation + Vector3(2.0, 1.0, 1.5), 0.3)
			tw.tween_property(p, "scale", Vector3.ONE * 0.001, 0.15)
		_:
			tw.tween_property(p, "scale", s * 1.35, 0.06)
			tw.tween_property(p, "scale", Vector3.ONE * 0.001, 0.12)
	tw.tween_callback(func() -> void: p.visible = false)


func _regrow_part(i: int, animate: bool, delay: float) -> void:
	var p: Node3D = _parts[i]
	var info: Dictionary = _part_info[i]
	var s: Vector3 = info["s"]
	var old: Tween = _part_tw[i]
	if old:
		old.kill()
	p.position = info["p"]
	p.rotation = info["r"]
	p.visible = true
	if not animate:
		p.scale = s
		_part_tw[i] = null
		return
	p.scale = Vector3.ONE * 0.001
	var tw := p.create_tween()
	_part_tw[i] = tw
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(p, "scale", s * 1.25, 0.12)
	tw.tween_property(p, "scale", s, 0.08)


func _show_root(on: bool, animate: bool) -> void:
	if _spawn_tw:
		_spawn_tw.kill()
	var full := Vector3.ONE * _base_k
	if not animate:
		_root.scale = full if on else Vector3.ONE * 0.001
		_root.visible = on
		return
	_spawn_tw = create_tween()
	if on:
		_root.visible = true
		_root.scale = Vector3(full.x * 1.2, 0.001, full.z * 1.2)
		_spawn_tw.tween_property(_root, "scale", full * 1.12, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_spawn_tw.tween_property(_root, "scale", full, 0.12)
	else:
		# Delay so a die() that follows can take over the collapse.
		_spawn_tw.tween_interval(0.45)
		_spawn_tw.tween_property(_root, "scale", Vector3(full.x * 1.25, full.y * 0.2, full.z * 1.25), 0.15)
		_spawn_tw.tween_property(_root, "scale", Vector3.ONE * 0.001, 0.12)
		_spawn_tw.tween_callback(func() -> void: _root.visible = false)


func _set_emission(col: Color) -> void:
	for i in _mats.size():
		if _mat_emit[i]:
			(_mats[i] as ShaderMaterial).set_shader_parameter("emission", col)


func _process(dt: float) -> void:
	_t += dt
	if _dead or _rig == null:
		return
	_idle(_t, dt)
	var tremble := Vector3.ZERO
	if _wind > 0.01:
		tremble = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * 0.03 * _wind
	var sw := 1.0 + 0.1 * _wind + sin(_t * 9.0) * 0.025 * _wind + _swell * 0.12
	_rig.scale = Vector3(sw, sw * (1.0 + 0.03 * _wind), sw)
	var wob := 0.0
	if _stag > 0.0:
		_stag = maxf(_stag - dt * 0.9, 0.0)
		wob = sin(_t * 21.0) * 0.26 * _stag
	_rig.rotation = Vector3(_lean * 0.32 + wob * 0.4, sin(_t * 13.0) * 0.2 * _stag, wob)
	_rig.position = tremble + Vector3(0, -_stag * 0.12, _lean * 0.25)
	if _wind > 0.005:
		_set_emission(c_glow * (0.3 + 0.22 * sin(_t * 8.0)) * _wind)
		_emit_live = true
	elif _emit_live:
		_set_emission(Color.BLACK)
		_emit_live = false
