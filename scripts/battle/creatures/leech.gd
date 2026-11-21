extends "res://scripts/battle/creatures/creature_base.gd"
## LEECH: an engorged ringed slug arching up into a round sucker mouth ringed
## with rotating teeth. Blood blisters and teeth pop off with damage and
## visibly regrow when it feeds.

const SEGS := 9

var _segs: Array = []    ## Node3D holders tail -> neck
var _mouth: Node3D
var _teeth: Node3D
var _gulp := 0.0
var _suck := 0.0


func _build() -> void:
	_rng.seed = 707
	_native_elite = true
	_height = 1.9
	var skin := _m(c_dark.lerp(Color("201018"), 0.3))
	var ring := _m(c_floor.lightened(0.05))
	var gorged := _m(c_accent.darkened(0.25))
	var lip := _m(c_accent)
	var bone := _m(c_bone)
	var void_m := _m(c_void, {"unlit": true})
	var blister := _m(c_accent.lightened(0.1).lerp(Color("ff2030"), 0.3))
	var blisters: Array = []
	for i in SEGS:
		var k := float(i) / float(SEGS - 1)
		var h := _pivot(_root)
		var r := 0.22 + sin(k * PI * 0.85) * 0.28
		var b := _ball(r, gorged if i % 2 == 0 else skin, h, Vector3.ZERO, 7, 5)
		b.scale = Vector3(1.0, 0.9, 0.75)
		var rg := _torus(r * 0.82, r * 1.02, ring, h, Vector3.ZERO, 10, 3)
		rg.rotation.x = PI * 0.5
		_segs.append(h)
		if i >= 1 and i < SEGS - 1:
			for j in 2:
				var a := _rng.randf_range(-1.2, 1.2) + (0.0 if j == 0 else PI)
				var bl := _ball(_rng.randf_range(0.06, 0.1), blister, h, Vector3(sin(a) * r * 0.95, cos(a) * r * 0.85, 0), 5, 3)
				blisters.append(bl)
	# mouth on the last holder: lip ring, void, rotating tooth ring
	_mouth = _pivot(_segs[SEGS - 1] as Node3D, Vector3(0, 0, 0.2))
	var lp := _torus(0.2, 0.34, lip, _mouth, Vector3.ZERO, 12, 4)
	lp.rotation.x = PI * 0.5
	var hole := _cyl(0.22, 0.22, 0.05, void_m, _mouth, Vector3(0, 0, -0.02), 8)
	hole.rotation.x = PI * 0.5
	_teeth = _pivot(_mouth, Vector3(0, 0, 0.02))
	var teeth: Array = []
	for i in 10:
		var a := TAU * float(i) / 10.0
		var tp := _pivot(_teeth, Vector3(cos(a) * 0.22, sin(a) * 0.22, 0))
		tp.rotation.z = a - PI * 0.5
		var t := _cyl(0.0, 0.035, 0.13, bone, tp, Vector3(0, -0.05, 0.02), 4)
		t.rotation.x = 0.0
		teeth.append(tp)
	# teeth go first, then blisters alternate with them
	var order: Array = []
	var n := maxi(teeth.size(), blisters.size())
	for i in n:
		if i < blisters.size():
			order.append(blisters[i])
		if i < teeth.size():
			order.append(teeth[i])
	for p in order:
		_part(p as Node3D, POP)


func _path(k: float, t: float) -> Vector3:
	# low body along -Z, arching up to the mouth at the front
	var arch := 1.0 + _wind * 0.2 - _gulp * 0.15
	var y := 0.3 + pow(k, 2.2) * 1.15 * arch + sin(k * 6.0 - t * 2.5) * 0.04 * (1.0 - k)
	var z := -0.9 + k * 1.35 + _suck * 0.35 * k * k
	var x := sin(k * 4.0 + t * 0.9) * 0.08
	return Vector3(x, y, z)


func _idle(t: float, dt: float) -> void:
	for i in SEGS:
		var k := float(i) / float(SEGS - 1)
		var h: Node3D = _segs[i]
		var p := _path(k, t)
		var q := _path(minf(k + 0.06, 1.0), t) if i < SEGS - 1 else p + Vector3(0, 0.05 - _suck * 0.2, 0.08)
		h.position = p
		var fwd := q - p
		if fwd.length() > 0.001:
			h.basis = Basis.looking_at(fwd, Vector3.UP if absf(fwd.normalized().y) < 0.98 else Vector3.BACK, true)
		# peristaltic swell travelling forward
		var w := 1.0 + maxf(sin(k * 7.0 - t * 3.0), 0.0) * 0.08 + maxf(sin(k * 5.0 - t * 6.0), 0.0) * _gulp * 0.35
		h.scale = Vector3(w, w, 1.0)
	_teeth.rotation.z += dt * (0.6 + _wind * 3.0 + _suck * 6.0)
	var o := 1.0 + sin(t * 2.0) * 0.06 + _suck * 0.25
	_mouth.scale = Vector3(o, o, 1.0)


func _attack(kind: String) -> void:
	var tw := create_tween()
	if kind == "drain" or kind == "gnaw" or kind == "dmg":
		tw.tween_property(self, "_suck", 1.0, 0.12)
		tw.tween_interval(0.2 if kind == "drain" else 0.05)
		tw.tween_property(self, "_suck", 0.0, 0.2)
		tw.tween_property(self, "_gulp", 1.0, 0.15)
		tw.tween_property(self, "_gulp", 0.0, 0.5)
	else:
		tw.tween_property(self, "_gulp", 1.0, 0.2)
		tw.tween_property(self, "_gulp", 0.0, 0.4)
