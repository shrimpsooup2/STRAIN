extends Node3D
## A colony drawn as a mound of low-poly cells. The number of living cells
## follows the colony value; outer cells pop first so the mound shrinks inward.

var cells: Array = []        ## MeshInstance3D, sorted inner → outer
var _base_scale: Array = []  ## float per cell
var _offs: Array = []        ## float phase per cell
var _base_pos: Array = []    ## Vector3 per cell
var _tendrils: Array = []    ## [MeshInstance3D pivot, base rotation, phase]
var alive := 0
var home := Vector3.ZERO
var _mat: ShaderMaterial
var _base_col: Color
var _t := 0.0
var _flash_tw: Tween
var _move_tw: Tween


## color: cell colour. count: max cells. r: cell radius. tendrils: number of tendril arms.
func setup(color: Color, count: int, r: float, tendrils := 0, seed_value := 1, tendril_col := Color("2c6a24")) -> void:
	home = position
	_base_col = color
	_mat = Retro.mat_unique(color)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var big := r * pow(float(count), 1.0 / 3.0) * 1.15
	var core := Vector3(0, big * 0.75, 0)
	var pts: Array = []
	while pts.size() < count:
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if p.length() > 1.0:
			continue
		p = core + p * big
		if p.y < r * 0.7:
			continue
		pts.append(p)
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(core) < b.distance_to(core))
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 6
	sm.rings = 4
	for p in pts:
		var c := MeshInstance3D.new()
		c.mesh = sm
		c.material_override = _mat
		c.position = p
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		var s := rng.randf_range(0.75, 1.2)
		c.scale = Vector3.ONE * s
		add_child(c)
		cells.append(c)
		_base_scale.append(s)
		_offs.append(rng.randf() * TAU)
		_base_pos.append(p)
	alive = count
	for i in tendrils:
		var pivot := Node3D.new()
		var ang := TAU * float(i) / float(tendrils) + rng.randf_range(-0.3, 0.3)
		pivot.position = core + Vector3(cos(ang), 0.2, sin(ang)) * big * 0.5
		var tlen := rng.randf_range(0.6, 1.1) * big * 1.3
		var segs := 3
		var parent: Node3D = pivot
		for sgi in segs:
			var seg_len := tlen / segs
			var seg := Retro.box(Vector3(0.07, seg_len, 0.07) * (1.0 - sgi * 0.22),
				tendril_col.lightened(sgi * 0.12), Vector3(0, seg_len * 0.5, 0))
			var joint := Node3D.new()
			joint.position = Vector3(0, seg_len, 0)
			joint.rotation = Vector3(0, 0, 0.35)
			parent.add_child(seg)
			parent.add_child(joint)
			parent = joint
		var base_rot := Vector3(sin(ang) * 0.9, 0, -cos(ang) * 0.9)
		pivot.rotation = base_rot
		add_child(pivot)
		_tendrils.append([pivot, base_rot, rng.randf() * TAU])


func set_count(n: int, animate := true) -> void:
	n = clampi(n, 0, cells.size())
	if n == alive:
		return
	for i in cells.size():
		var c: MeshInstance3D = cells[i]
		var full := Vector3.ONE * float(_base_scale[i])
		var was_alive := i < alive
		var now_alive := i < n
		if was_alive == now_alive:
			continue
		if not animate:
			c.scale = full if now_alive else Vector3.ZERO
			continue
		var delay := 0.03 * absf(float(i - mini(n, alive)))
		var tw := c.create_tween()
		if now_alive:
			c.scale = Vector3.ZERO
			tw.tween_property(c, "scale", full * 1.25, 0.12).set_delay(delay)
			tw.tween_property(c, "scale", full, 0.08)
		else:
			tw.tween_property(c, "scale", full * 1.3, 0.06).set_delay(delay)
			tw.tween_property(c, "scale", Vector3.ZERO, 0.12)
	alive = n


func flash(color := Color.WHITE, t := 0.22) -> void:
	if _flash_tw:
		_flash_tw.kill()
	_mat.set_shader_parameter("albedo", color)
	_flash_tw = create_tween()
	_flash_tw.tween_method(func(v: float): _mat.set_shader_parameter("albedo", color.lerp(_base_col, v)), 0.0, 1.0, t)


## Lunge toward a world-space point and back.
func lunge(target: Vector3, dist := 0.8) -> void:
	if _move_tw:
		_move_tw.kill()
	var dir := (target - home)
	dir.y = 0.0
	dir = dir.normalized() * dist
	_move_tw = create_tween()
	_move_tw.tween_property(self, "position", home + dir, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tw.tween_property(self, "position", home, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _move_tw.finished


## Recoil: a quick shove away from the attacker.
func recoil(from: Vector3) -> void:
	if _move_tw:
		_move_tw.kill()
	var dir := (home - from)
	dir.y = 0.0
	dir = dir.normalized() * 0.25
	_move_tw = create_tween()
	_move_tw.tween_property(self, "position", home + dir, 0.05)
	_move_tw.tween_property(self, "position", home - dir * 0.4, 0.06)
	_move_tw.tween_property(self, "position", home, 0.08)


func top() -> Vector3:
	var hi := 0.0
	for i in alive:
		hi = maxf(hi, (cells[i] as MeshInstance3D).position.y)
	return global_position + Vector3(0, hi + 0.4, 0)


func _process(dt: float) -> void:
	_t += dt
	var k := 1.0 + sin(_t * 2.0) * 0.03
	scale = Vector3(k, 1.0 / k, k)
	for i in alive:
		var c: MeshInstance3D = cells[i]
		c.rotation.y += dt * 0.3
		c.position = _base_pos[i] + Vector3(0, sin(_t * 1.7 + float(_offs[i])) * 0.03, 0)
	for e in _tendrils:
		var p: Node3D = e[0]
		var base: Vector3 = e[1]
		var ph: float = e[2]
		p.rotation = base + Vector3(sin(_t * 1.3 + ph) * 0.25, sin(_t * 0.7 + ph) * 0.4, cos(_t * 1.1 + ph) * 0.2)
