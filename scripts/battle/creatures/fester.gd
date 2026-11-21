extends "res://scripts/battle/creatures/creature_base.gd"
## FESTER: a swollen pus sac on six stubby legs, veined and throbbing,
## crowned with yellow pustules and bone spines. Pustules burst first.

var _sac: Node3D
var _legs: Array = []   ## [pivot, phase]
var _veins: Array = []  ## MeshInstance3D
var _gulp := 0.0


func _build() -> void:
	_rng.seed = 303
	_native_elite = true
	_height = 1.95
	var skin := _m(c_flesh.lerp(c_sick, 0.25))
	var under := _m(c_dark)
	var vein := _m(c_accent.darkened(0.25))
	var pus := _m(c_sick.lightened(0.15))
	var pus_hi := _m(Color("f0e8a0"), {"unlit": true})
	var bone := _m(c_bone)
	var void_m := _m(c_void, {"unlit": true})
	_sac = _pivot(_root, Vector3(0, 1.0, 0))
	var body := _ball(0.78, skin, _sac, Vector3.ZERO, 8, 6)
	body.scale = Vector3(1.0, 0.92, 0.95)
	var belly := _ball(0.6, under, _sac, Vector3(0, -0.32, 0.05), 7, 4)
	belly.scale = Vector3(1.1, 0.5, 1.05)
	# drooling front orifice
	var mouth := _torus(0.1, 0.19, vein, _sac, Vector3(0, -0.1, 0.72), 8, 4)
	mouth.rotation.x = PI * 0.5
	var hole := _cyl(0.11, 0.11, 0.06, void_m, _sac, Vector3(0, -0.1, 0.71), 6)
	hole.rotation.x = PI * 0.5
	_cyl(0.025, 0.05, 0.4, pus, _sac, Vector3(0, -0.36, 0.73), 4)
	# veins: thin stretched boxes hugging the sac
	for i in 7:
		var d := _rand_dir(-0.3)
		var v := _box(Vector3(0.04, 0.6, 0.03), vein, _sac, d * 0.74)
		_align_up(v, d.cross(Vector3(_rng.randf_range(-1, 1), 1, 0)).normalized())
		_veins.append(v)
	# six legs
	for i in 6:
		var ang := TAU * (float(i) + 0.5) / 6.0
		var lp := _pivot(_root, Vector3(cos(ang) * 0.5, 0.55, sin(ang) * 0.5))
		var out := Vector3(cos(ang), 0, sin(ang))
		var leg := _cyl(0.07, 0.13, 0.6, under, lp, Vector3.ZERO, 5)
		_align_up(leg, (out * 0.55 + Vector3.UP).normalized())
		leg.position = -(out * 0.55 + Vector3.UP).normalized() * 0.28 + out * 0.02
		_ball(0.1, skin, lp, leg.position - (out * 0.55 + Vector3.UP).normalized() * 0.3, 5, 3)
		_legs.append([lp, float(i) * 1.1])
	# spines (lost after the pustules)
	for i in 7:
		var d := _rand_dir(0.35)
		var sp := _cyl(0.0, 0.06, 0.4, bone, _sac, d * 0.72, 4)
		_align_up(sp, d)
		sp.position = d * 0.86
		_part(sp, FALL)
	# pustules: lost first
	for i in 12:
		var d := _rand_dir(-0.1)
		if d.z < -0.6:
			d.z = -d.z
		var r := _rng.randf_range(0.1, 0.2)
		var p := _ball(r, pus, _sac, d * 0.76, 6, 4)
		_ball(r * 0.35, pus_hi, p, Vector3(0, r * 0.55, r * 0.5), 4, 3)
		_part(p, POP)


func _idle(t: float, _dt: float) -> void:
	var th := sin(t * 2.6)
	var throb := 1.0 + maxf(th, 0.0) * 0.05 + _gulp * 0.12
	_sac.scale = Vector3(throb, 1.0 + (throb - 1.0) * 0.6, throb)
	_sac.position.y = 1.0 + sin(t * 1.3) * 0.03 - _gulp * 0.05
	_sac.rotation.z = sin(t * 0.9) * 0.04
	for e in _legs:
		var lp: Node3D = e[0]
		var ph: float = e[1]
		lp.rotation.x = sin(t * 2.0 + ph) * 0.06
	for i in _veins.size():
		var v: MeshInstance3D = _veins[i]
		var s := 1.0 + maxf(sin(t * 2.6 - float(i) * 0.4), 0.0) * 0.6
		v.scale = Vector3(s, 1.0, s)


func _attack(kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_gulp", 1.0, 0.12 if kind != "buff" else 0.3)
	tw.tween_property(self, "_gulp", -0.3, 0.1)
	tw.tween_property(self, "_gulp", 0.0, 0.2)
	if kind != "buff":
		_spit()
