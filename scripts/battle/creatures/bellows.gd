extends "res://scripts/battle/creatures/creature_base.gd"
## BELLOWS: a ringed windpipe rooted in a fleshy base, carrying a lobed lung
## sac that heaves in and out. Windup and buffs inflate it. Alveoli bubbles
## burst with damage.

var _stalk: Node3D
var _sac: Node3D
var _lobes: Array = []  ## [mesh, phase, base scale]
var _rings: Array = []  ## MeshInstance3D
var _puff := 0.0


func _build() -> void:
	_rng.seed = 1010
	_height = 2.05
	var flesh := _m(c_flesh)
	var cart := _m(c_bone.lerp(c_flesh, 0.35))
	var lung := _m(c_accent.lerp(Color("e08090"), 0.35))
	var lung_d := _m(c_accent.darkened(0.25))
	var dark := _m(c_dark)
	var bub := _m(c_pale.lerp(Color("ffc0c8"), 0.4))
	# base mound with roots
	var base := _ball(0.5, dark, _root, Vector3(0, 0.08, 0), 8, 4)
	base.scale = Vector3(1.2, 0.45, 1.2)
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		var r := _cyl(0.03, 0.08, 0.6, dark, _root, Vector3(cos(a) * 0.55, 0.06, sin(a) * 0.55), 4)
		r.rotation = Vector3(0, -a, PI * 0.5 - 0.2)
	# windpipe stalk
	_stalk = _pivot(_root, Vector3(0, 0.25, 0))
	_cyl(0.13, 0.16, 0.85, flesh, _stalk, Vector3(0, 0.42, 0), 6)
	for i in 6:
		var rg := _torus(0.12, 0.2, cart, _stalk, Vector3(0, 0.1 + 0.14 * float(i), 0), 8, 3)
		_rings.append(rg)
	# lung sac: two big lobes and smaller sub-lobes
	_sac = _pivot(_stalk, Vector3(0, 1.15, 0))
	var specs := [
		[Vector3(-0.32, 0.05, 0.0), Vector3(0.48, 0.62, 0.42), lung],
		[Vector3(0.32, 0.05, 0.0), Vector3(0.48, 0.62, 0.42), lung],
		[Vector3(-0.25, -0.3, 0.15), Vector3(0.3, 0.3, 0.3), lung_d],
		[Vector3(0.27, -0.28, 0.15), Vector3(0.3, 0.3, 0.3), lung_d],
		[Vector3(0.0, 0.32, -0.1), Vector3(0.3, 0.32, 0.3), lung_d],
	]
	for i in specs.size():
		var sp: Array = specs[i]
		var p: Vector3 = sp[0]
		var s: Vector3 = sp[1]
		var mm: Material = sp[2]
		var lb := _ball(1.0, mm, _sac, p, 8, 5)
		lb.scale = s
		_lobes.append([lb, float(i) * 0.7, s])
	# bronchi split
	for sd in [-1.0, 1.0]:
		var sdf: float = sd
		var br := _cyl(0.06, 0.09, 0.4, cart, _sac, Vector3(0.12 * sdf, -0.38, 0.05), 5)
		br.rotation.z = -0.6 * sdf
	# alveoli clusters (parts)
	for i in 16:
		var d := _rand_dir(-0.4)
		var side := -1.0 if d.x < 0.0 else 1.0
		var c := Vector3(0.32 * side, 0.05, 0)
		var p := c + Vector3(d.x * 0.48, d.y * 0.62, d.z * 0.42) * 0.98
		var b := _ball(_rng.randf_range(0.06, 0.11), bub, _sac, p, 5, 3)
		_part(b, POP)


func _idle(t: float, _dt: float) -> void:
	var br := sin(t * 1.6)
	var infl := 1.0 + br * 0.08 + _wind * 0.22 + _puff * 0.3
	_sac.scale = Vector3(infl, 1.0 + (infl - 1.0) * 0.7, infl)
	_sac.rotation = Vector3(sin(t * 0.7) * 0.05, sin(t * 0.4) * 0.1, sin(t * 0.9) * 0.05)
	_stalk.rotation = Vector3(sin(t * 0.8) * 0.04 - _puff * 0.1, 0, sin(t * 0.6) * 0.05)
	for e in _lobes:
		var lb: MeshInstance3D = e[0]
		var ph: float = e[1]
		var s: Vector3 = e[2]
		lb.scale = s * (1.0 + sin(t * 1.6 + ph) * 0.04)
	for i in _rings.size():
		var rg: MeshInstance3D = _rings[i]
		var w := 1.0 + maxf(sin(t * 3.2 - float(i) * 0.8), 0.0) * (0.12 + _puff * 0.3)
		rg.scale = Vector3(w, 1.0, w)


func _attack(kind: String) -> void:
	var tw := create_tween()
	if kind == "buff":
		tw.tween_property(self, "_puff", 1.0, 0.35)
		tw.tween_property(self, "_puff", 0.0, 0.5)
	else:
		tw.tween_property(self, "_puff", 0.7, 0.2)
		tw.tween_property(self, "_puff", -0.4, 0.1)
		tw.tween_property(self, "_puff", 0.0, 0.3)
