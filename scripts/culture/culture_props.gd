extends RefCounted
## Low-poly builders for the Culture bench (scenes/culture). Every prop's
## origin sits on the bench top (y = 0). Animated parts are named children
## with their own (unique) materials.

const C_GLASS := Color("c8e0e8")
const C_STEEL := Color("707880")
const C_DARK := Color("1c2228")
const C_ENAMEL := Color("c8ccc8")
const C_AGAR := Color("a89058")


static func glass(a := 0.28) -> Dictionary:
	return {"alpha": a}


## A ring lying flat (petri rim, plasmid track).
static func torus(r_in: float, r_out: float, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = 16
	t.ring_segments = 4
	return Retro.mesh(t, color, pos, opts)


static func clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


# ------------------------------------------------------------ room

static func bench() -> Node3D:
	var root := Node3D.new()
	var top_tex := Retro.tex_noise(Color("c8ccc8"), Color("b8bcb8"), 16, 3, 0.3)
	root.add_child(Retro.box(Vector3(9.8, 0.3, 3.6), Color.WHITE, Vector3(0, -0.15, 0), {"tex": top_tex, "uv": 6.0}))
	root.add_child(Retro.box(Vector3(9.8, 0.06, 0.08), C_STEEL, Vector3(0, -0.02, 1.8)))
	root.add_child(Retro.box(Vector3(9.6, 1.6, 3.2), Color("2a3036"), Vector3(0, -1.1, -0.1)))
	# Back wall, a splash strip and a pipe run.
	var wall_tex := Retro.tex_panel(Color("4a545c"), Color("38424a"), 16)
	root.add_child(Retro.box(Vector3(10.6, 4.0, 0.2), Color.WHITE, Vector3(0, 1.8, -1.95), {"tex": wall_tex, "uv": 5.0}))
	root.add_child(Retro.box(Vector3(9.8, 0.3, 0.06), Color("dcdcd4"), Vector3(0, 0.15, -1.82),
		{"tex": Retro.tex_tiles(Color("dcdcd4"), Color("a0a4a0"), 8), "uv": 12.0}))
	var pipe := Retro.cyl(0.06, 0.06, 10.4, Color("5a6066"), 6, Vector3(0, 1.5, -1.8))
	pipe.rotation_degrees.z = 90
	root.add_child(pipe)
	# Floor in front, barely lit.
	root.add_child(Retro.plane(Vector2(16, 10), Color("101418"), Vector3(0, -1.9, 3.0),
		{"tex": Retro.tex_tiles(Color("181e22"), Color("0c1014"), 16), "uv": 8.0}))
	return root


## A hanging shade with a bulb; the light itself is added by the scene.
static func lamp() -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.cyl(0.015, 0.015, 1.2, C_DARK, 4, Vector3(0, 0.75, 0)))
	root.add_child(Retro.cyl(0.08, 0.42, 0.3, Color("2c3438"), 8, Vector3.ZERO))
	root.add_child(Retro.ball(0.1, Color("fff0c8"), 6, 4, Vector3(0, -0.14, 0), {"unlit": true}))
	return root


# ------------------------------------------------------------ dish + ring

static func dish(r: float) -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.cyl(r + 0.06, r + 0.06, 0.03, C_GLASS, 16, Vector3(0, 0.015, 0), glass(0.35)))
	root.add_child(Retro.cyl(r, r, 0.05, C_AGAR, 16, Vector3(0, 0.045, 0)))
	var rim := torus(r, r + 0.05, C_GLASS, Vector3(0, 0.08, 0), glass(0.45))
	rim.scale = Vector3(1, 2.0, 1)
	root.add_child(rim)
	return root


## One plasmid bead. Upgraded ("+") genes are larger and glow; banked genes are cubes.
static func bead(id: String, color: Color, banked: bool) -> MeshInstance3D:
	var up := id.ends_with("+")
	var r := 0.11 if up else 0.085
	var opts: Dictionary = {"emit": color * 0.6} if up else {}
	if banked:
		return Retro.box(Vector3.ONE * r * 1.6, color, Vector3.ZERO, opts)
	return Retro.ball(r, color, 6, 4, Vector3.ZERO, opts)


## Read-head: a downward arrow over 12 o'clock.
static func read_head(color: Color) -> Node3D:
	var root := Node3D.new()
	var tip := Retro.cyl(0.11, 0.0, 0.18, color, 4, Vector3(0, 0.0, 0), {"emit": color * 0.5})
	root.add_child(tip)
	root.add_child(Retro.box(Vector3(0.06, 0.16, 0.06), color, Vector3(0, 0.16, 0), {"emit": color * 0.5}))
	return root


# ------------------------------------------------------------ vials

## A stoppered tube. The "Fluid" child is resized by set_fill().
static func vial(color: Color, h := 0.62) -> Node3D:
	var root := Node3D.new()
	root.set_meta("h", h)
	var fluid := Retro.cyl(0.062, 0.062, h - 0.1, color, 6, Vector3(0, 0.04 + (h - 0.1) * 0.5, 0),
		{"emit": color * 0.25})
	fluid.name = "Fluid"
	root.add_child(fluid)
	root.add_child(Retro.cyl(0.08, 0.08, h, C_GLASS, 6, Vector3(0, h * 0.5, 0), glass(0.3)))
	root.add_child(Retro.cyl(0.088, 0.08, 0.07, Color("6a4a38"), 6, Vector3(0, h + 0.02, 0)))
	return root


static func set_fill(v: Node3D, f: float) -> void:
	var fluid := v.get_node_or_null("Fluid") as Node3D
	if fluid == null:
		return
	var h: float = v.get_meta("h", 0.62)
	var full := h - 0.1
	f = clampf(f, 0.0, 1.0)
	fluid.visible = f > 0.01
	fluid.scale = Vector3(1, maxf(f, 0.02), 1)
	fluid.position.y = 0.04 + full * f * 0.5


static func rack(w: float) -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.box(Vector3(w, 0.06, 0.34), C_STEEL, Vector3(0, 0.03, 0)))
	root.add_child(Retro.box(Vector3(w, 0.05, 0.34), C_STEEL, Vector3(0, 0.36, 0)))
	root.add_child(Retro.box(Vector3(0.05, 0.36, 0.3), C_STEEL, Vector3(-w * 0.5, 0.2, 0)))
	root.add_child(Retro.box(Vector3(0.05, 0.36, 0.3), C_STEEL, Vector3(w * 0.5, 0.2, 0)))
	return root


# ------------------------------------------------------------ machines

## Sequencer: a grey block with a green screen ("Screen") and a sample slot.
static func sequencer() -> Node3D:
	var root := Node3D.new()
	var tex := Retro.tex_panel(Color("8a9298"), Color("707880"), 16)
	root.add_child(Retro.box(Vector3(1.3, 0.7, 0.8), Color.WHITE, Vector3(0, 0.35, 0), {"tex": tex}))
	root.add_child(Retro.box(Vector3(1.0, 0.04, 0.5), Color("5a6268"), Vector3(0, 0.72, -0.05)))
	root.add_child(Retro.box(Vector3(0.5, 0.03, 0.08), C_DARK, Vector3(0, 0.745, 0.05)))
	var scr := Retro.quad(Vector2(0.86, 0.34), Color("1a3a2a"), Vector3(-0.1, 0.4, 0.401))
	scr.material_override = Retro.mat_unique(Color("1a3a2a"), {"emit": Color("1a5a38")})
	scr.name = "Screen"
	root.add_child(scr)
	var led := Retro.ball(0.04, Color("58d0a8"), 4, 3, Vector3(0.5, 0.52, 0.41), {"unlit": true})
	led.name = "Led"
	root.add_child(led)
	return root


## Incubator: open glass-fronted cabinet. "Jars" holds grown traits; "Glow" pulses.
static func incubator() -> Node3D:
	var root := Node3D.new()
	var c := C_ENAMEL
	root.add_child(Retro.box(Vector3(1.4, 0.08, 0.8), c, Vector3(0, 0.04, 0)))
	root.add_child(Retro.box(Vector3(1.4, 0.1, 0.8), c, Vector3(0, 0.95, 0)))
	root.add_child(Retro.box(Vector3(0.08, 0.9, 0.8), c, Vector3(-0.66, 0.5, 0)))
	root.add_child(Retro.box(Vector3(0.08, 0.9, 0.8), c, Vector3(0.66, 0.5, 0)))
	root.add_child(Retro.box(Vector3(1.4, 0.9, 0.06), Color("9aa09a"), Vector3(0, 0.5, -0.37)))
	root.add_child(Retro.box(Vector3(1.24, 0.03, 0.66), C_STEEL, Vector3(0, 0.48, 0)))
	var glow := Retro.box(Vector3(1.0, 0.04, 0.1), Color("90f0b0"), Vector3(0, 0.88, -0.2))
	glow.material_override = Retro.mat_unique(Color("90f0b0"), {"unlit": true})
	glow.name = "Glow"
	root.add_child(glow)
	var jars := Node3D.new()
	jars.name = "Jars"
	root.add_child(jars)
	root.add_child(Retro.quad(Vector2(1.24, 0.82), C_GLASS, Vector3(0, 0.5, 0.4), glass(0.18)))
	root.add_child(Retro.box(Vector3(0.05, 0.3, 0.05), C_STEEL, Vector3(0.55, 0.5, 0.44)))
	return root


## A specimen jar for a grown trait; equipped ones get a lit cap.
static func trait_jar(color: Color, equipped: bool) -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.ball(0.07, color, 5, 3, Vector3(0, 0.08, 0), {"emit": color * 0.35}))
	root.add_child(Retro.cyl(0.09, 0.09, 0.2, C_GLASS, 6, Vector3(0, 0.1, 0), glass(0.3)))
	var cap_col := UI.C_ACCENT if equipped else Color("4a5258")
	root.add_child(Retro.cyl(0.095, 0.095, 0.04, cap_col, 6, Vector3(0, 0.22, 0),
		{"emit": cap_col * 0.6} if equipped else {}))
	return root


## Tuning fork on a block. "Prongs" wobbles; "Pips" shows the pitch.
static func fork() -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.box(Vector3(0.7, 0.12, 0.42), Color("3a4248"), Vector3(0, 0.06, 0)))
	root.add_child(Retro.cyl(0.035, 0.035, 0.36, Color("b8c0c8"), 6, Vector3(0, 0.3, -0.06)))
	var prongs := Node3D.new()
	prongs.name = "Prongs"
	prongs.position = Vector3(0, 0.48, -0.06)
	prongs.add_child(Retro.box(Vector3(0.3, 0.05, 0.05), Color("c8d0d8"), Vector3(0, 0.0, 0)))
	prongs.add_child(Retro.box(Vector3(0.05, 0.55, 0.05), Color("c8d0d8"), Vector3(-0.13, 0.28, 0)))
	prongs.add_child(Retro.box(Vector3(0.05, 0.55, 0.05), Color("c8d0d8"), Vector3(0.13, 0.28, 0)))
	root.add_child(prongs)
	var pips := Node3D.new()
	pips.name = "Pips"
	root.add_child(pips)
	return root


static func set_pips(f: Node3D, n: int, top: int) -> void:
	var pips := f.get_node_or_null("Pips") as Node3D
	if pips == null:
		return
	clear(pips)
	for i in top:
		var lit := i < n
		var col: Color = (UI.C_WARN if i >= 3 else UI.C_ACCENT) if lit else Color("1c2428")
		pips.add_child(Retro.box(Vector3(0.07, 0.03, 0.07), col,
			Vector3(-0.25 + i * 0.1, 0.135, 0.13), {"unlit": true} if lit else {}))


## Strain stock: a little shelf. "Jars" is rebuilt per owned strain.
static func shelf() -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.box(Vector3(1.5, 0.06, 0.5), Color("5a4a3c"), Vector3(0, 0.42, 0)))
	root.add_child(Retro.box(Vector3(0.06, 0.42, 0.44), Color("4a3c30"), Vector3(-0.7, 0.21, 0)))
	root.add_child(Retro.box(Vector3(0.06, 0.42, 0.44), Color("4a3c30"), Vector3(0.7, 0.21, 0)))
	var jars := Node3D.new()
	jars.name = "Jars"
	root.add_child(jars)
	return root


static func stock_jar(color: Color, active: bool) -> Node3D:
	var root := Node3D.new()
	var lift := 0.06 if active else 0.0
	root.add_child(Retro.cyl(0.1, 0.1, 0.12, color, 6, Vector3(0, 0.07 + lift, 0),
		{"emit": color * (0.5 if active else 0.1)}))
	root.add_child(Retro.cyl(0.13, 0.13, 0.32, C_GLASS, 6, Vector3(0, 0.16 + lift, 0), glass(0.3)))
	root.add_child(Retro.cyl(0.14, 0.14, 0.05, Color("2c3438") if not active else UI.C_ACCENT, 6,
		Vector3(0, 0.34 + lift, 0)))
	return root


# ------------------------------------------------------------ syringes

## A syringe lying along x. Empty ones are bare glass.
static func syringe(color: Color, filled: bool, length := 0.8) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.rotation_degrees.z = 90
	root.add_child(body)
	if filled:
		var fl := Retro.cyl(0.05, 0.05, length * 0.7, color, 6, Vector3(0, -length * 0.1, 0), {"emit": color * 0.35})
		fl.name = "Fluid"
		body.add_child(fl)
	body.add_child(Retro.cyl(0.065, 0.065, length, C_GLASS, 6, Vector3.ZERO, glass(0.3 if filled else 0.18)))
	body.add_child(Retro.cyl(0.015, 0.015, length * 0.35, Color("c0c8d0"), 4, Vector3(0, length * 0.55 + (0.0 if filled else 0.25), 0)))
	body.add_child(Retro.cyl(0.07, 0.07, 0.02, Color("c0c8d0"), 6, Vector3(0, length * 0.72 + (0.0 if filled else 0.25), 0)))
	body.add_child(Retro.cyl(0.006, 0.006, 0.28, Color("d8e0e8"), 3, Vector3(0, -length * 0.5 - 0.14, 0)))
	return root


static func tray() -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.box(Vector3(1.3, 0.05, 0.7), C_STEEL, Vector3(0, 0.025, 0)))
	root.add_child(Retro.box(Vector3(1.3, 0.06, 0.04), C_STEEL, Vector3(0, 0.06, 0.33)))
	root.add_child(Retro.box(Vector3(1.3, 0.06, 0.04), C_STEEL, Vector3(0, 0.06, -0.33)))
	var held := Node3D.new()
	held.name = "Held"
	root.add_child(held)
	return root


## The day's injector, upright in a clamp. "Fluid" carries the culture colour.
static func injector(color: Color) -> Node3D:
	var root := Node3D.new()
	root.add_child(Retro.box(Vector3(0.5, 0.08, 0.5), Color("3a4248"), Vector3(0, 0.04, 0)))
	root.add_child(Retro.box(Vector3(0.06, 1.1, 0.06), C_STEEL, Vector3(-0.2, 0.6, -0.15)))
	root.add_child(Retro.box(Vector3(0.26, 0.05, 0.06), C_STEEL, Vector3(-0.1, 0.85, -0.15)))
	var fl := Retro.cyl(0.1, 0.1, 0.7, color, 6, Vector3(0, 0.72, 0))
	fl.material_override = Retro.mat_unique(color, {"emit": color * 0.4})
	fl.name = "Fluid"
	root.add_child(fl)
	root.add_child(Retro.cyl(0.13, 0.13, 0.9, C_GLASS, 6, Vector3(0, 0.75, 0), glass(0.3)))
	root.add_child(Retro.cyl(0.02, 0.02, 0.35, Color("c0c8d0"), 4, Vector3(0, 1.36, 0)))
	root.add_child(Retro.cyl(0.12, 0.12, 0.03, Color("c0c8d0"), 6, Vector3(0, 1.54, 0)))
	root.add_child(Retro.cyl(0.01, 0.01, 0.25, Color("d8e0e8"), 3, Vector3(0, 0.2, 0)))
	return root


# ------------------------------------------------------------ door + hand

## The way back to the lab, set into the wall. "Lamp" shows the lock state.
static func door() -> Node3D:
	var root := Node3D.new()
	var tex := Retro.tex_panel(Color("3a444c"), Color("2c343a"), 16)
	root.add_child(Retro.box(Vector3(1.0, 2.6, 0.12), Color.WHITE, Vector3(0, 1.0, 0), {"tex": tex, "uv": 2.0}))
	root.add_child(Retro.box(Vector3(1.12, 0.08, 0.16), C_STEEL, Vector3(0, 2.32, 0)))
	root.add_child(Retro.box(Vector3(0.08, 0.26, 0.1), Color("b8c0c8"), Vector3(-0.34, 0.9, 0.1)))
	var l := Retro.ball(0.06, UI.C_GREEN, 4, 3, Vector3(0, 2.15, 0.1), {"unlit": true})
	l.name = "Lamp"
	root.add_child(l)
	return root


## A gloved hand pointing down. Glove greens with the infection stage.
static func hand(stage: int) -> Node3D:
	var root := Node3D.new()
	var glove := Color("a8c0c8").lerp(UI.C_GREEN, clampf(stage / 5.0, 0.0, 1.0) * 0.55)
	var o := {"emit": glove * 0.15}
	root.add_child(Retro.box(Vector3(0.28, 0.1, 0.3), glove, Vector3(0, 0.34, 0.12), o))
	root.add_child(Retro.box(Vector3(0.26, 0.09, 0.1), glove.darkened(0.08), Vector3(0, 0.28, -0.06), o))
	root.add_child(Retro.box(Vector3(0.07, 0.3, 0.07), glove, Vector3(0.08, 0.14, -0.08), o))
	root.add_child(Retro.box(Vector3(0.07, 0.07, 0.16), glove.darkened(0.1), Vector3(-0.16, 0.3, 0.04), o))
	root.add_child(Retro.cyl(0.13, 0.13, 0.14, glove.darkened(0.2), 6, Vector3(0, 0.38, 0.32), o))
	if stage >= 2:
		var vein := UI.C_GREEN.darkened(0.3)
		root.add_child(Retro.box(Vector3(0.02, 0.01, 0.24), vein, Vector3(0.04, 0.395, 0.14), {"unlit": true}))
	if stage >= 3:
		root.add_child(Retro.box(Vector3(0.02, 0.01, 0.2), UI.C_GREEN.darkened(0.3), Vector3(-0.07, 0.395, 0.16), {"unlit": true}))
	return root
