extends Node3D
## Region-themed inner-body backdrop: fogged inverted sphere, fleshy cellular
## blobs, hanging strands and drifting motes. Add as a child, then `setup(region)`.

var _motes: Array = []       ## [MeshInstance3D, base Vector3, speed float, phase float]
var _blobs: Array = []       ## [MeshInstance3D, base scale float, phase float]
var _t := 0.0
var _extent := Vector3(14, 6, 14)
var _center := Vector3.ZERO


## opts: fog (density), center (Vector3 mote volume centre), extent (Vector3 half-size),
## floor_y (float), motes (int), seed (int)
func setup(region: String, opts: Dictionary = {}) -> void:
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	var bg: Color = pal["bg"]
	var fog: Color = pal["fog"]
	var floor_c: Color = pal["floor"]
	var accent: Color = pal["accent"]
	_center = opts.get("center", Vector3.ZERO)
	_extent = opts.get("extent", Vector3(14, 6, 14))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", hash(region)))

	add_child(Retro.environment(bg, fog.lightened(0.35), 0.9, fog, float(opts.get("fog", 0.035))))
	add_child(Retro.sun(Vector3(-50, -30, 0), accent.lerp(Color.WHITE, 0.6), 0.9))

	# Inner wall: an inverted low-poly sphere with a speckled flesh texture.
	var sky := SphereMesh.new()
	sky.radius = 42.0
	sky.height = 84.0
	sky.radial_segments = 12
	sky.rings = 8
	sky.flip_faces = true
	add_child(Retro.mesh(sky, Color.WHITE, _center, {"unlit": true, "uv": 8.0,
		"tex": Retro.tex_noise(bg, fog, 16, rng.randi(), 0.3)}))

	# Floor membrane.
	var floor_y: float = opts.get("floor_y", -0.6)
	add_child(Retro.plane(Vector2(90, 90), Color.WHITE, Vector3(_center.x, floor_y, _center.z),
		{"uv": 14.0, "tex": Retro.tex_noise(floor_c.darkened(0.45), floor_c.darkened(0.25), 16, rng.randi(), 0.4)}))

	# Cellular blobs around the edge of the space.
	for i in 18:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(9.0, 24.0)
		var r := rng.randf_range(1.2, 3.8)
		var pos := _center + Vector3(cos(ang) * dist, floor_y + r * rng.randf_range(0.2, 0.8), sin(ang) * dist)
		var col := floor_c.lerp(fog, rng.randf_range(0.0, 0.6)).darkened(rng.randf_range(0.0, 0.3))
		var b := Retro.ball(r, col, 7, 5, pos)
		b.scale = Vector3(1.0, rng.randf_range(0.6, 1.1), 1.0)
		add_child(b)
		_blobs.append([b, b.scale, rng.randf() * TAU])
		# A nucleus: a smaller, brighter ball nested half out of the blob.
		if rng.randf() < 0.5:
			var n := Retro.ball(r * 0.35, accent.darkened(0.35), 5, 3, pos + Vector3(0, r * 0.55, 0))
			add_child(n)

	# Hanging strands from above.
	for i in 10:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(7.0, 18.0)
		var h := rng.randf_range(6.0, 14.0)
		var s := Retro.box(Vector3(0.18, h, 0.18), fog.lerp(accent, 0.25).darkened(0.2),
			_center + Vector3(cos(ang) * dist, floor_y + 14.0 - h * 0.5, sin(ang) * dist))
		s.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		add_child(s)

	# Drifting motes.
	var mote_mat_opts := {"unlit": true}
	for i in int(opts.get("motes", 46)):
		var size := rng.randf_range(0.04, 0.11)
		var col := accent.lerp(Color.WHITE, rng.randf_range(0.0, 0.5))
		if rng.randf() < 0.3:
			col = fog.lightened(0.5)
		var m := Retro.box(Vector3(size, size, size), col, Vector3.ZERO, mote_mat_opts)
		var base := _center + Vector3(rng.randf_range(-_extent.x, _extent.x),
			rng.randf_range(-_extent.y * 0.3, _extent.y), rng.randf_range(-_extent.z, _extent.z))
		m.position = base
		m.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		add_child(m)
		_motes.append([m, base, rng.randf_range(0.12, 0.35), rng.randf() * TAU])


func _process(dt: float) -> void:
	_t += dt
	for e in _motes:
		var m: MeshInstance3D = e[0]
		var base: Vector3 = e[1]
		var spd: float = e[2]
		var ph: float = e[3]
		var y := fposmod(base.y - _center.y + _extent.y * 0.3 + _t * spd, _extent.y * 1.3) - _extent.y * 0.3
		m.position = Vector3(base.x + sin(_t * 0.4 + ph) * 0.4, _center.y + y, base.z + cos(_t * 0.3 + ph) * 0.4)
		m.rotation.y += dt * spd
	for e in _blobs:
		var b: MeshInstance3D = e[0]
		var s: Vector3 = e[1]
		var k := 1.0 + sin(_t * 0.6 + float(e[2])) * 0.04
		b.scale = Vector3(s.x * k, s.y / k, s.z * k)
