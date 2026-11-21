extends "res://scripts/battle/creatures/creature_base.gd"
## POD: a hovering almond seed-case of two shell halves clamped around a
## glowing core, fringed with waving cilia. Cilia are shed with damage; below
## half strength the shell splits and gapes.

var _float: Node3D
var _halves: Array = []  ## [pivot, side]
var _cilia: Array = []   ## [pivot, base rot, phase]
var _core: MeshInstance3D
var _shadow: MeshInstance3D
var _split := 0.0
var _split_tw: Tween
var _gape := 0.0


func _build() -> void:
	_rng.seed = 505
	_height = 2.05
	var shell := _m(c_floor.lerp(Color("c8a080"), 0.3))
	var shell_in := _m(c_accent.darkened(0.3))
	var seam := _m(c_dark)
	var glow := _m(c_accent.lightened(0.3), {"unlit": true})
	var cil := _m(c_pale.lerp(c_flesh, 0.4))
	var shadow_m := Retro.mat(Color(0, 0, 0), {"alpha": 0.35})
	_shadow = _cyl(0.55, 0.55, 0.01, shadow_m, _root, Vector3(0, 0.02, 0), 10)
	_float = _pivot(_root, Vector3(0, 1.15, 0))
	_core = _ball(0.3, glow, _float, Vector3.ZERO, 6, 4)
	# two shell halves (squashed hemispheres) hinged at the base
	for side in [-1.0, 1.0]:
		var sd: float = side
		var hp := _pivot(_float, Vector3(0.0, -0.62, 0.0))
		var half := Node3D.new()
		half.position = Vector3(0, 0.62, 0)
		hp.add_child(half)
		var outer := _ball(0.6, shell, half, Vector3(0.06 * sd, 0, 0), 8, 6)
		outer.scale = Vector3(0.62, 1.4, 0.9)
		var inner := _ball(0.5, shell_in, half, Vector3(0.0, 0, 0), 7, 5)
		inner.scale = Vector3(0.5, 1.3, 0.8)
		var ridge := _box(Vector3(0.06, 1.5, 0.08), seam, half, Vector3(0.36 * sd, 0, 0))
		ridge.rotation.z = 0.0
		for k in 3:
			var bumps := _ball(0.08, seam, half, Vector3(0.33 * sd, -0.4 + 0.4 * float(k), 0.25), 4, 3)
			bumps.scale = Vector3(0.6, 1.0, 1.0)
		_halves.append([hp, sd])
	# tip spike and stem
	_cyl(0.0, 0.08, 0.35, seam, _float, Vector3(0, 0.95, 0), 4)
	_cyl(0.07, 0.03, 0.3, seam, _float, Vector3(0, -0.95, 0), 4)
	# cilia ring around the seam
	for i in 18:
		var k := float(i) / 18.0
		var a := TAU * k
		var y := sin(a) * 0.72
		var z := cos(a) * 0.5
		var base := Vector3(0, 0, 0)
		var piv := _pivot(_float, Vector3(0, y, z))
		var out := Vector3(0, y, z).normalized()
		var side_x := 0.35 if i % 2 == 0 else -0.35
		var dir := (out + Vector3(side_x, 0, 0)).normalized()
		_align_up(piv, dir)
		base = piv.rotation
		var c := _cyl(0.008, 0.025, 0.45, cil, piv, Vector3(0, 0.22, 0), 4)
		_ball(0.03, glow, c, Vector3(0, 0.23, 0), 4, 3)
		_cilia.append([piv, base, k * TAU * 2.0])
		_part(c, POP)


func _idle(t: float, _dt: float) -> void:
	var hover := sin(t * 1.6) * 0.08
	_float.position.y = 1.15 + hover
	_float.rotation = Vector3(sin(t * 0.7) * 0.06, t * 0.25, sin(t * 0.9) * 0.08)
	_shadow.scale = Vector3.ONE * (1.0 - hover * 0.8)
	var gp := sin(t * 2.4) * 0.03
	var open := _split * 0.38 + _gape * 0.25 + _wind * 0.12
	for e in _halves:
		var hp: Node3D = e[0]
		var sd: float = e[1]
		hp.rotation.z = -sd * (open + gp * _split)
	_core.scale = Vector3.ONE * (1.0 + sin(t * 3.0) * 0.08 + _wind * 0.3 + _gape * 0.2)
	for e in _cilia:
		var piv: Node3D = e[0]
		var base: Vector3 = e[1]
		var ph: float = e[2]
		piv.rotation = base + Vector3(sin(t * 4.0 + ph) * 0.3, 0, cos(t * 3.0 + ph) * 0.2)


func _on_count(frac: float, animate: bool) -> void:
	var want := 1.0 if (frac > 0.0 and frac < 0.5) else 0.0
	if is_equal_approx(want, _split):
		return
	if _split_tw:
		_split_tw.kill()
	if not animate:
		_split = want
		return
	_split_tw = create_tween()
	_split_tw.tween_property(self, "_split", want, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _attack(kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_gape", 1.0, 0.12)
	tw.tween_interval(0.12 if kind != "drain" else 0.4)
	tw.tween_property(self, "_gape", 0.0, 0.25)
