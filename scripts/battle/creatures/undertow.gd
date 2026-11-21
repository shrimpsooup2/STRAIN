extends "res://scripts/battle/creatures/creature_base.gd"
## UNDERTOW (boss): a standing whirlpool maw. A fleshy rim ring faces the
## player, three counter-rotating rings of teeth spiral into a black throat,
## set on a twisting spout of blood rings. Teeth are lost with damage.

var _maw: Node3D
var _rings: Array = []    ## [pivot, speed]
var _spout: Array = []    ## [pivot, phase]
var _swirl: Node3D
var _tails: Array = []    ## [pivot, base rot, phase]
var _pull := 0.0


func _build() -> void:
	_rng.seed = 808
	_native_boss = true
	_height = 2.9
	var flesh := _m(c_flesh)
	var rim := _m(c_accent.darkened(0.15))
	var dark := _m(c_dark)
	var bone := _m(c_bone)
	var bone_b := _m(c_bone.darkened(0.2))
	var void_m := _m(c_void, {"unlit": true})
	var gleam := _m(c_accent.lightened(0.3), {"unlit": true})
	var water := _m(c_floor.lerp(c_accent, 0.35))
	var streak := Retro.mat(c_pale, {"alpha": 0.45})
	# spout: stacked tori twisting up from the floor
	for i in 7:
		var k := float(i) / 6.0
		var sp := _pivot(_root, Vector3(0, 0.12 + k * 1.0, 0))
		var r := lerpf(0.75, 0.42, k)
		var tor := _torus(r * 0.6, r, water if i % 2 == 0 else dark, sp, Vector3.ZERO, 12, 4)
		tor.scale = Vector3(1.0, 1.6, 1.0)
		_spout.append([sp, k * 2.4])
	# maw disc standing vertically, facing +Z
	_maw = _pivot(_root, Vector3(0, 1.62, 0.15))
	var lip := _torus(0.86, 1.15, rim, _maw, Vector3.ZERO, 16, 5)
	lip.rotation.x = PI * 0.5
	var lip2 := _torus(1.05, 1.22, flesh, _maw, Vector3(0, 0, -0.12), 16, 4)
	lip2.rotation.x = PI * 0.5
	var throat := _cyl(0.9, 0.9, 0.08, void_m, _maw, Vector3(0, 0, -0.2), 12)
	throat.rotation.x = PI * 0.5
	var back := _ball(0.95, dark, _maw, Vector3(0, 0, -0.35), 10, 6)
	back.scale = Vector3(1.0, 1.0, 0.45)
	var glint := _ball(0.12, gleam, _maw, Vector3(0, 0, -0.12), 5, 3)
	glint.scale = Vector3(1.0, 1.0, 0.3)
	# tooth rings (outer ring teeth are lost last)
	var ring_teeth: Array = []
	var specs := [[0.82, 14, 0.4, 0.22], [0.58, 11, -0.7, 0.17], [0.34, 7, 1.1, 0.13]]
	for si in specs.size():
		var spec: Array = specs[si]
		var rr: float = spec[0]
		var cnt: int = spec[1]
		var spd: float = spec[2]
		var tl: float = spec[3]
		var rp := _pivot(_maw, Vector3(0, 0, -0.04 * float(si)))
		_rings.append([rp, spd])
		var list: Array = []
		for k in cnt:
			var a := TAU * float(k) / float(cnt)
			var tp := _pivot(rp, Vector3(cos(a) * rr, sin(a) * rr, 0))
			tp.rotation.z = a + PI * 0.5
			var tooth := _cyl(0.0, tl * 0.3, tl, bone if k % 2 == 0 else bone_b, tp, Vector3(0, 0, 0), 4)
			# tp's +Y points at the throat; tilt the fangs toward the viewer
			tooth.position = Vector3(0, tl * 0.4, 0.04)
			tooth.rotation = Vector3(0.35, 0, 0)
			list.append(tp)
		ring_teeth.append(list)
	for si in range(ring_teeth.size()):
		var list: Array = ring_teeth[si]
		for tp in list:
			_part(tp as Node3D, POP)
	# swirl streaks orbiting the maw
	_swirl = _pivot(_maw)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var s := _box(Vector3(0.45, 0.04, 0.04), streak, _swirl, Vector3(cos(a) * 0.7, sin(a) * 0.7, 0.18))
		s.rotation.z = a + PI * 0.5 + 0.45
	# trailing tendrils from the rim, hanging and swaying
	for i in 5:
		var a := PI + 0.35 + float(i) * 0.6
		var p := Vector3(cos(a) * 1.1, sin(a) * 0.9 + 1.62, 0.1)
		var tp := _pivot(_root, p)
		var base := Vector3(0, 0, (float(i) - 2.0) * 0.25)
		tp.rotation = base
		var parent: Node3D = tp
		for s in 3:
			var l := 0.3 - 0.05 * float(s)
			_cyl(0.04 - 0.01 * s, 0.06 - 0.012 * s, l, rim, parent, Vector3(0, -l * 0.5, 0), 4)
			parent = _pivot(parent, Vector3(0, -l, 0), Vector3(0.2, 0, 0.1))
		_tails.append([tp, base, float(i) * 1.3])


func _idle(t: float, dt: float) -> void:
	var spin := 1.0 + _wind * 3.5 + _pull * 4.0
	for e in _rings:
		var rp: Node3D = e[0]
		var spd: float = e[1]
		rp.rotation.z += spd * dt * spin
	_swirl.rotation.z -= dt * 1.4 * spin
	var pulse := 1.0 + sin(t * 1.8) * 0.03 + _pull * 0.08
	_maw.scale = Vector3(pulse, pulse, 1.0)
	_maw.position = Vector3(sin(t * 0.7) * 0.06, 1.62 + sin(t * 1.1) * 0.05, 0.15 + _pull * 0.25)
	_maw.rotation = Vector3(sin(t * 0.6) * 0.05 - _pull * 0.1, sin(t * 0.5) * 0.08, 0)
	for e in _spout:
		var sp: Node3D = e[0]
		var ph: float = e[1]
		sp.rotation.y += dt * (1.5 + ph * 0.3) * spin
		sp.position.x = sin(t * 1.5 + ph) * 0.06 * (1.0 + ph)
		sp.position.z = cos(t * 1.3 + ph) * 0.05 * (1.0 + ph)
	for e in _tails:
		var tp: Node3D = e[0]
		var base: Vector3 = e[1]
		var ph: float = e[2]
		tp.rotation = base + Vector3(sin(t * 1.4 + ph) * 0.25, 0, cos(t * 1.1 + ph) * 0.2)


func _attack(kind: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_pull", 1.0, 0.15)
	tw.tween_interval(0.15 if kind != "drain" else 0.45)
	tw.tween_property(self, "_pull", 0.0, 0.35)
