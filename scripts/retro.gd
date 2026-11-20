class_name Retro
extends RefCounted
## Low-poly building blocks: cached retro materials, primitive meshes, tiny
## procedural nearest-filtered textures, environments and lights.
##
## opts keys (all optional):
##   tex: Texture2D   uv: float (uv scale)   emit: Color   unlit: bool
##   alpha: float (<1 → transparent unlit)  vcol: bool   snap: Vector2

const SHADER_LIT := preload("res://shaders/retro.gdshader")
const SHADER_UNLIT := preload("res://shaders/retro_unlit.gdshader")
const SHADER_ALPHA := preload("res://shaders/retro_alpha.gdshader")

static var _mats: Dictionary = {}


static func mat(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "%s|%s" % [color.to_html(), str(opts)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	var alpha: float = opts.get("alpha", 1.0)
	if alpha < 1.0:
		m.shader = SHADER_ALPHA
		m.set_shader_parameter("albedo", Color(color, alpha))
	else:
		m.shader = SHADER_UNLIT if opts.get("unlit", false) else SHADER_LIT
		m.set_shader_parameter("albedo", color)
		m.set_shader_parameter("emission", opts.get("emit", Color.BLACK))
		m.set_shader_parameter("use_vcol", opts.get("vcol", false))
	if opts.has("tex"):
		m.set_shader_parameter("tex", opts["tex"])
		m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("uv_scale", opts.get("uv", 1.0))
	if opts.has("snap"):
		m.set_shader_parameter("snap", opts["snap"])
	_mats[key] = m
	return m


## A fresh (uncached) material, for things you animate (colour pulses, fades).
static func mat_unique(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	return mat(color, opts).duplicate() as ShaderMaterial


static func mesh(m: Mesh, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat(color, opts)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(b, color, pos, opts)


static func cyl(r_top: float, r_bottom: float, h: float, color: Color, segs := 8, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return mesh(c, color, pos, opts)


static func ball(r: float, color: Color, segs := 6, rings := 4, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return mesh(s, color, pos, opts)


static func plane(size: Vector2, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var p := PlaneMesh.new()
	p.size = size
	return mesh(p, color, pos, opts)


static func quad(size: Vector2, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	return mesh(q, color, pos, opts)


# ---------------------------------------------------------------- textures

static func _img_tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## Square floor/wall tiles with a 1px grout line and a highlight corner.
static func tex_tiles(base: Color, line: Color, px := 16) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for i in px:
		img.set_pixel(i, 0, line)
		img.set_pixel(0, i, line)
	img.set_pixel(1, 1, base.lightened(0.15))
	img.set_pixel(2, 1, base.lightened(0.08))
	img.set_pixel(1, 2, base.lightened(0.08))
	return _img_tex(img)


## Two-tone speckle noise (dirt, flesh, concrete).
static func tex_noise(a: Color, b: Color, px := 16, seed_value := 1, density := 0.35) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in px:
		for x in px:
			img.set_pixel(x, y, b if rng.randf() < density else a)
	return _img_tex(img)


## Diagonal hazard / vertical stripes.
static func tex_stripes(a: Color, b: Color, px := 16, diagonal := true) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var k := (x + y) if diagonal else x
			img.set_pixel(x, y, a if (k / 4) % 2 == 0 else b)
	return _img_tex(img)


## Wall panelling: horizontal seams every 8px, a darker skirting band.
static func tex_panel(base: Color, seam: Color, px := 16) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for x in px:
		img.set_pixel(x, 0, seam)
		img.set_pixel(x, px / 2, seam.lerp(base, 0.5))
	for y in px:
		img.set_pixel(px - 1, y, seam.lerp(base, 0.4))
	return _img_tex(img)


## Draw a small pixel image from rows of characters, e.g. ["..##..", ".#..#."], using a palette map.
static func tex_from_rows(rows: Array, palette: Dictionary) -> ImageTexture:
	var h := rows.size()
	var w: int = (rows[0] as String).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in w:
			var ch := row[x]
			if palette.has(ch):
				img.set_pixel(x, y, palette[ch])
	return _img_tex(img)


# ------------------------------------------------------------ environment

static func environment(bg: Color, ambient: Color, ambient_energy := 1.0, fog_color := Color.BLACK, fog_density := 0.0) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog_color
		env.fog_density = fog_density
		env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	return we


static func sun(rot_deg: Vector3, color: Color, energy := 1.0) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	l.shadow_enabled = false
	return l


static func omni(color: Color, light_range: float, energy: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = light_range
	l.light_energy = energy
	l.position = pos
	l.shadow_enabled = false
	return l
