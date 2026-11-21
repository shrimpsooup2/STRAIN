extends "res://scripts/battle/creatures/creature_base.gd"
## THE CORE (boss): the colony's green heart, raised on arching roots. Atrium
## lobes and great vessels crown a glowing ventricle that beats lub-dub.
## Its skin is made of cells; they burst off as it weakens.

var _heart: Node3D
var _atria: Array = []    ## [mesh, phase, base scale]
var _vessels: Array = []  ## [pivot, base rot, phase]
var _glow: MeshInstance3D
var _roots: Array = []    ## [pivot, base rot, phase]
var _thump := 0.0


func _build() -> void:
	_rng.seed = 1818
	_native_boss = true
	_height = 2.95
	var g_a := Color("3c9a34")
	var heart_m := _m(g_a.lerp(c_floor, 0.15))
	var heart_d := _m(Color("1c4a18"))
	var vessel_m := _m(Color("2c6a24").lerp(c_accent, 0.15))
	var vessel_l := _m(Color("58b848"))
	var glow_m := _m(Color("a8ff80"), {"unlit": true})
	var cell_a := _m(Color("58b848"))
	var cell_b := _m(Color("78d060"))
	var cell_c := _m(Color("3c9a34"))
	var root_m := _m(Color("1c3a18").lerp(c_dark, 0.3))
	# arching roots holding the heart up
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		var rp := _pivot(_root, Vector3(cos(a) * 0.3, 1.0, sin(a) * 0.3), Vector3(0, -a, 0))
		var base := rp.rotation
		var parent: Node3D = rp
		var seg_l := 0.42
		var bend := Vector3(0, 0, -0.75)
		parent.rotation = base
		var j0 := _pivot(parent, Vector3.ZERO, Vector3(0, 0, -2.3))
		parent = j0
		for s in 3:
			var r := lerpf(0.12, 0.05, float(s) / 3.0)
			_cyl(r * 0.8, r, seg_l, root_m, parent, Vector3(0, seg_l * 0.5, 0), 5)
			var j := _pivot(parent, Vector3(0, seg_l, 0), bend * (0.5 + 0.35 * float(s)))
			parent = j
		_roots.append([rp, base, float(i) * 1.4])
	_heart = _pivot(_root, Vector3(0, 1.65, 0))
	var vent := _ball(0.75, heart_m, _heart, Vector3(0, -0.1, 0.05), 10, 7)
	vent.scale = Vector3(1.0, 1.15, 0.9)
	var apex := _ball(0.4, heart_d, _heart, Vector3(0.1, -0.78, 0.1), 7, 4)
	apex.scale = Vector3(0.9, 1.2, 0.9)
	# atria lobes on top
	for spec in [[Vector3(-0.38, 0.52, -0.05), 0.4], [Vector3(0.36, 0.48, -0.1), 0.36]]:
		var p: Vector3 = spec[0]
		var r: float = spec[1]
		var at := _ball(r, heart_d, _heart, p, 8, 5)
		var s0 := Vector3(1.0, 0.85, 1.0)
		at.scale = s0
		_atria.append([at, p.x * 3.0, s0])
	# great vessels: aorta arch and two side trunks
	var specs := [
		[Vector3(0.0, 0.6, -0.15), Vector3(-0.2, 0, 0.15), 0.18, 0.7],
		[Vector3(-0.22, 0.55, 0.1), Vector3(0.2, 0, 0.55), 0.12, 0.6],
		[Vector3(0.25, 0.55, 0.05), Vector3(0.1, 0, -0.6), 0.12, 0.55],
	]
	for sp in specs:
		var p: Vector3 = sp[0]
		var r0: Vector3 = sp[1]
		var rad: float = sp[2]
		var l: float = sp[3]
		var vp := _pivot(_heart, p, r0)
		_cyl(rad * 0.85, rad, l, vessel_m, vp, Vector3(0, l * 0.5, 0), 6)
		var tor := _torus(rad * 0.6, rad * 1.1, vessel_l, vp, Vector3(0, l, 0), 8, 3)
		tor.scale = Vector3(1.0, 1.4, 1.0)
		var void_c := _cyl(rad * 0.6, rad * 0.6, 0.02, _m(c_void, {"unlit": true}), vp, Vector3(0, l + 0.01, 0), 6)
		void_c.rotation.y = 0.0
		_vessels.append([vp, r0, p.x * 4.0])
	# glowing ventricle window on the front
	_glow = _ball(0.3, glow_m, _heart, Vector3(0, -0.05, 0.62), 7, 5)
	_glow.scale = Vector3(1.0, 1.25, 0.45)
	# coronary veins
	for i in 5:
		var d := _rand_dir(-0.4)
		var v := _box(Vector3(0.05, 0.55, 0.04), vessel_m, _heart, Vector3(d.x * 0.72, d.y * 0.8 - 0.1, d.z * 0.66 + 0.04))
		v.rotation = Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.6, 0.6))
	# surface cells (parts). Back-hemisphere first in list so front ones go first.
	var cells: Array = []
	var mats := [cell_a, cell_b, cell_c]
	for i in 30:
		var d := _rand_dir(-0.75)
		var p := Vector3(0, -0.1, 0.05) + Vector3(d.x * 0.75, d.y * 0.86, d.z * 0.68)
		if absf(p.x) < 0.25 and p.z > 0.4 and absf(p.y + 0.05) < 0.35:
			p.x += 0.32 * (1.0 if p.x >= 0.0 else -1.0)
		var c := _ball(_rng.randf_range(0.1, 0.17), mats[i % 3] as Material, _heart, p, 6, 4)
		c.scale = Vector3(1.0, 0.85, 1.0)
		cells.append([p.z, c])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for e in cells:
		_part(e[1] as Node3D, POP)


func _beat(t: float) -> float:
	var ph := fposmod(t * (1.1 + _wind * 0.9), 1.0)
	var lub := exp(-pow((ph - 0.05) * 18.0, 2.0))
	var dub := exp(-pow((ph - 0.25) * 18.0, 2.0)) * 0.6
	return lub + dub


func _idle(t: float, _dt: float) -> void:
	var b := _beat(t) + _thump
	var k := 1.0 + b * 0.07
	_heart.scale = Vector3(k, 1.0 + b * 0.05, k)
	_heart.position.y = 1.65 + sin(t * 0.8) * 0.03
	_heart.rotation = Vector3(sin(t * 0.5) * 0.04, sin(t * 0.3) * 0.1, sin(t * 0.6) * 0.03)
	_glow.scale = Vector3(1.0 + b * 0.3, 1.25 + b * 0.3, 0.45)
	for e in _atria:
		var at: MeshInstance3D = e[0]
		var ph: float = e[1]
		var s0: Vector3 = e[2]
		var ab := _beat(t + 0.12 + ph * 0.01)
		at.scale = s0 * (1.0 + ab * 0.12)
	for e in _vessels:
		var vp: Node3D = e[0]
		var r0: Vector3 = e[1]
		var ph: float = e[2]
		vp.rotation = r0 + Vector3(sin(t * 1.1 + ph) * 0.05 + b * 0.06, 0, cos(t * 0.9 + ph) * 0.05)
	for e in _roots:
		var rp: Node3D = e[0]
		var r0: Vector3 = e[1]
		var ph: float = e[2]
		rp.rotation = r0 + Vector3(0, 0, sin(t * 0.7 + ph) * 0.03 - b * 0.02)


func _attack(kind: String) -> void:
	var tw := create_tween()
	var reps := 2 if kind == "drain" or kind == "gnaw" else 1
	for _i in reps:
		tw.tween_property(self, "_thump", 1.2, 0.08)
		tw.tween_property(self, "_thump", 0.0, 0.22)


func _elite_growths() -> void:
	pass
