extends Node3D
## The path through one region: rows of nodes, bottom to top, ending at the heart.
## `Game.run.row`/`col` hold the node last entered (row -1 = not started);
## `Game.run.path` (added here) keeps the column taken on every row.

const GeneArt := preload("res://scripts/run/gene_art.gd")
const PixelBar := preload("res://scripts/run/pixel_bar.gd")
const Backdrop := preload("res://scripts/run/region_backdrop.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")

const MAP := Rect2(4, 4, 248, 196)
const HUD := Rect2(256, 4, 124, 120)
const INFO := Rect2(256, 128, 124, 84)
const COL_GAP := 66
const NODE := 18

const ICONS := {
	"fight": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"],
	"elite": [".#####.", "#######", "#.##.##", "#######", ".#####.", ".#.#.#.", "......."],
	"rest": ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."],
	"event": ["..###..", ".#...#.", ".....#.", "...##..", "...#...", ".......", "...#..."],
	"boss": ["#.#.#.#", ".#####.", "##.#.##", ".#####.", "##...##", ".#####.", "#.#.#.#"],
}
const NAMES := {"fight": "FIGHT", "elite": "ELITE", "rest": "REST", "event": "EVENT", "boss": "HEART"}
const COLORS := {"fight": Color("d86048"), "elite": Color("e8a040"), "rest": Color("58d0a8"),
	"event": Color("e8c840"), "boss": Color("70d850")}
const ENTRY_THOUGHT := {
	"wound": "The cut. Where it got in.",
	"rivers": "Into the blood. It moves fast here.",
	"hollow": "The lungs. Every breath feeds it.",
	"archive": "Behind the eyes. What it is eating.",
	"root": "The centre. No more going around it.",
}

var region := "wound"
var nodes: Array = []
var path: Array = []
var row := -1
var sel := 0
var _busy := true
var _t := 0.0
var _map: Control
var _hud: Control
var _bar: Control
var _info: Label
var _cam: Camera3D
var _cells: Array = []


func _ready() -> void:
	UI.apply_stage_post()
	if Game.run.is_empty():
		Game.start_run(Game.args_region())
	region = String(Game.run.get("region", "wound"))
	nodes = Game.run.get("nodes", [])
	row = int(Game.run.get("row", -1))
	path = Game.run.get("path", [])
	# Debug entry points may set row/col without a path: fill it in.
	while path.size() < row + 1:
		path.append(int(Game.run.get("col", 0)))
	Game.run["path"] = path
	_build_world()
	_build_ui()
	sel = 0
	_refresh()
	_begin()


func _begin() -> void:
	await get_tree().create_timer(0.4).timeout
	if row < 0:
		await UI.say([ENTRY_THOUGHT.get(region, "In.")], "think")
	_busy = false
	_refresh()


# ------------------------------------------------------------------ 3D

func _build_world() -> void:
	var bd := Backdrop.new()
	add_child(bd)
	bd.setup(region, {"center": Vector3(0, 0.5, -3), "extent": Vector3(10, 5, 10), "floor_y": -1.5,
		"fog": 0.045, "motes": 60})
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region) + 7
	# Nearby floating cells, each with a nucleus.
	for i in 9:
		var p := Vector3(rng.randf_range(-3.5, 5.0), rng.randf_range(-0.6, 2.6), rng.randf_range(-7.0, -1.5))
		var r := rng.randf_range(0.35, 0.9)
		var cell := Node3D.new()
		cell.position = p
		var shell_col := (pal["floor"] as Color).lerp(pal["accent"], rng.randf_range(0.1, 0.4))
		var shell := Retro.ball(r, shell_col, 8, 5)
		cell.add_child(shell)
		cell.add_child(Retro.ball(r * 0.4, (pal["accent"] as Color).lerp(Color.WHITE, 0.2), 5, 3,
			Vector3(r * 0.3, r * 0.35, r * 0.55)))
		add_child(cell)
		_cells.append([cell, p, rng.randf() * TAU])
	add_child(Retro.omni(pal["accent"], 9.0, 0.9, Vector3(2, 3, -2)))
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.position = Vector3(0.5, 1.2, 3.5)
	add_child(_cam)
	_cam.look_at(Vector3(1.5, 0.8, -4))
	_cam.current = true


func _process(dt: float) -> void:
	_t += dt
	for e in _cells:
		var c: Node3D = e[0]
		var p: Vector3 = e[1]
		var ph: float = e[2]
		c.position = p + Vector3(sin(_t * 0.4 + ph) * 0.2, sin(_t * 0.6 + ph) * 0.25, 0)
		c.rotation.y += dt * 0.2
	if _cam:
		_cam.position = Vector3(0.5 + sin(_t * 0.15) * 0.4, 1.2 + sin(_t * 0.21) * 0.15, 3.5)
		_cam.look_at(Vector3(1.5, 0.8, -4))
	if _map:
		_map.queue_redraw()


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_PASS
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	layer.add_child(_map)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_bar = PixelBar.new()
	_bar.position = HUD.position + Vector2(8, 30)
	_bar.size = Vector2(HUD.size.x - 16, 6)
	_hud.add_child(_bar)
	_bar.set_values(int(Game.run.get("colony", 1)), int(Game.run.get("max_colony", 1)), true)
	for i in 2:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = "STRAND" if i == 0 else "LEAVE"
		b.position = Vector2(HUD.position.x + 4 + i * 60, HUD.end.y - 16)
		b.size = Vector2(56, 13)
		b.add_theme_color_override("font_color", UI.C_THINK_FG)
		b.add_theme_stylebox_override("normal", UI.box_style(Color("1c2a32"), UI.C_ACCENT.darkened(0.4), 1, 2, Vector4(4, 2, 4, 2)))
		b.add_theme_stylebox_override("hover", UI.box_style(UI.C_FOCUS, UI.C_ACCENT, 1, 2, Vector4(4, 2, 4, 2)))
		b.add_theme_stylebox_override("pressed", UI.box_style(UI.C_FOCUS, UI.C_ACCENT, 1, 2, Vector4(4, 2, 4, 2)))
		if i == 0:
			b.pressed.connect(func(): if not _busy and not UI.busy: _view_strand())
		else:
			b.pressed.connect(func(): if not _busy and not UI.busy: _withdraw())
		layer.add_child(b)
	var ip := UI.panel(INFO, true)
	ip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ip)
	_info = UI.label("", UI.C_THINK_FG)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(INFO.size.x - 14, INFO.size.y - 10)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ip.add_child(_info)


func _node_pos(r: int, c: int) -> Vector2:
	var n := nodes.size()
	var top := MAP.position.y + 20.0
	var bottom := MAP.end.y - 36.0
	var y := bottom - (bottom - top) * float(r) / float(maxi(1, n - 1))
	var k: int = (nodes[r] as Array).size()
	var x := MAP.position.x + MAP.size.x / 2.0 + (float(c) - float(k - 1) / 2.0) * COL_GAP
	return Vector2(roundf(x), roundf(y))


func _entry_pos() -> Vector2:
	return Vector2(MAP.position.x + MAP.size.x / 2.0, MAP.end.y - 10)


func _reachable() -> Array:
	if row + 1 >= nodes.size():
		return []
	var out: Array = []
	for c in (nodes[row + 1] as Array).size():
		out.append(c)
	return out


func _draw_map() -> void:
	var ci := _map
	ci.draw_rect(Rect2(MAP.position, MAP.size + Vector2(0, 12)), Color(0.02, 0.03, 0.04, 0.45))
	var reach := _reachable()
	var blink := fmod(_t, 0.8) < 0.5
	# Connections.
	for r in nodes.size():
		var cur_row: Array = nodes[r]
		for c in cur_row.size():
			var b := _node_pos(r, c)
			if r == 0:
				var on0 := path.size() > 0 and int(path[0]) == c
				_link(ci, _entry_pos(), b, on0, row == -1 and not _busy and c == sel)
			if r + 1 < nodes.size():
				for c2 in (nodes[r + 1] as Array).size():
					var on := path.size() > r + 1 and int(path[r]) == c and int(path[r + 1]) == c2
					var next := r == row and path.size() > r and int(path[r]) == c and c2 == sel and not _busy
					_link(ci, b, _node_pos(r + 1, c2), on, next)
	# Entry marker.
	var ep := _entry_pos()
	ci.draw_rect(Rect2(ep.x - 3, ep.y - 3, 6, 4), UI.C_PAPER if row == -1 else UI.C_DIM)
	# Nodes.
	for r in nodes.size():
		var cur_row: Array = nodes[r]
		for c in cur_row.size():
			var type: String = cur_row[c]
			var p := _node_pos(r, c)
			var sz := 24 if type == "boss" else NODE
			var rect := Rect2(p - Vector2(sz, sz) / 2.0, Vector2(sz, sz))
			var col: Color = COLORS.get(type, UI.C_PAPER)
			var taken := r <= row and path.size() > r and int(path[r]) == c
			var skipped := r <= row and not taken
			var is_reach := reach.has(c) and r == row + 1
			var is_sel := is_reach and c == sel and not _busy
			var bg := Color("141c24")
			var bd := col.darkened(0.3)
			var ic := col
			if skipped:
				bd = Color("303840")
				ic = Color("404850")
				bg = Color("0c1014")
			elif taken:
				bg = col.darkened(0.6)
				bd = col.darkened(0.2)
				ic = col.darkened(0.15)
			elif is_reach:
				bd = col if not blink or is_sel else col.darkened(0.2)
			elif r > row + 1:
				ic = col.darkened(0.35)
				bd = col.darkened(0.55)
			if is_sel:
				ci.draw_rect(rect.grow(3), UI.C_PAPER)
				ci.draw_rect(rect.grow(2), UI.C_INK)
			ci.draw_rect(rect, bd)
			ci.draw_rect(rect.grow(-1), bg)
			var px := 3 if type == "boss" else 2
			GeneArt.bitmap(ci, rect.position + (rect.size - Vector2(7 * px, 7 * px)) / 2.0, ICONS[type], ic, px)
			# Label.
			var nm: String = NAMES[type]
			var lc := UI.C_PAPER if (is_reach or r > row) and not skipped else UI.C_DIM
			if is_sel:
				lc = UI.C_WARN
			if r > row + 1:
				lc = Color("8890a0")
			var lp := Vector2(roundf(p.x - nm.length() * 4), rect.end.y + 2)
			GeneArt.text(ci, lp + Vector2(1, 1), nm, Color(0, 0, 0, 0.8))
			GeneArt.text(ci, lp, nm, lc)
			# You-are-here marker.
			if r == row and taken:
				var my := rect.position.y - 7 + (1 if blink else 0)
				ci.draw_rect(Rect2(p.x - 3, my, 7, 2), UI.C_PAPER)
				ci.draw_rect(Rect2(p.x - 2, my + 2, 5, 1), UI.C_PAPER)
				ci.draw_rect(Rect2(p.x - 1, my + 3, 3, 1), UI.C_PAPER)
	var hint := "Z GO  TAB STRAND  X LEAVE"
	GeneArt.text(ci, Vector2(MAP.position.x + 6, MAP.end.y + 2), hint, UI.C_DIM)


func _link(ci: Control, a: Vector2, b: Vector2, taken: bool, next: bool) -> void:
	var col := Color(0.55, 0.6, 0.65, 0.35)
	var w := 1.0
	if taken:
		col = UI.C_ACCENT
		w = 2.0
	elif next:
		col = UI.C_PAPER
		w = 1.0
	# Pixel-stepped line: draw small squares along it.
	var d := b - a
	var steps := int(maxf(absf(d.x), absf(d.y)) / 3.0)
	for i in steps + 1:
		if not taken and not next and i % 2 == 1:
			continue
		var p := a + d * (float(i) / float(maxi(1, steps)))
		ci.draw_rect(Rect2(roundf(p.x), roundf(p.y), w, w), col)


func _draw_hud() -> void:
	var ci := _hud
	GeneArt.box(ci, HUD, true)
	var x := HUD.position.x + 7
	var y := HUD.position.y + 5
	var pal: Dictionary = Cards.REGION_COLORS.get(region, Cards.REGION_COLORS["wound"])
	GeneArt.text(ci, Vector2(x, y), String(Game.REGION_NAMES.get(region, region)), (pal["accent"] as Color).lightened(0.2))
	var col: int = int(Game.run.get("colony", 0))
	var mx: int = int(Game.run.get("max_colony", 1))
	GeneArt.text(ci, Vector2(x, y + 12), "COLONY", UI.C_WARN)
	var num := "%d/%d" % [col, mx]
	GeneArt.text(ci, Vector2(HUD.end.x - 7 - GeneArt.text_w(num), y + 12), num, UI.C_PAPER)
	var fray: int = int(Game.run.get("fray", 0))
	var lines := [
		["FRAY", str(fray), UI.C_BAD if fray >= 5 else UI.C_THINK_FG],
		["STRAND", str((Game.run.get("strand", []) as Array).size()), UI.C_THINK_FG],
		["REAGENT", "+%d" % int(Game.run.get("reagent", 0)), UI.C_THINK_FG],
		["LEDGER", "%d/3" % (Game.run.get("ledger", []) as Array).size(), UI.C_THINK_FG],
		["UPTAKE", str(int(Game.run.get("uptake", 0))), UI.C_GREEN if int(Game.run.get("uptake", 0)) > 0 else UI.C_THINK_FG],
	]
	for i in lines.size():
		var ly := y + 36 + i * 10
		var l: Array = lines[i]
		GeneArt.text(ci, Vector2(x, ly), String(l[0]), UI.C_DIM)
		GeneArt.text(ci, Vector2(HUD.end.x - 7 - GeneArt.text_w(String(l[1])), ly), String(l[1]), l[2])


func _refresh() -> void:
	var reach := _reachable()
	if not reach.is_empty():
		sel = clampi(sel, 0, reach.size() - 1)
	_bar.set_values(int(Game.run.get("colony", 1)), int(Game.run.get("max_colony", 1)))
	_hud.queue_redraw()
	_map.queue_redraw()
	if reach.is_empty():
		_info.text = ""
		return
	var type: String = nodes[row + 1][sel]
	_info.text = _node_text(type)


func _node_text(type: String) -> String:
	match type:
		"fight":
			return "FIGHT\nA colony blocks the way. Win: reagent and a gene."
		"elite":
			return "ELITE\nSwollen, hits harder. +5 reagent, two genes."
		"rest":
			return "REST\nA still pocket. Mend, proofread, excise or arrange."
		"event":
			return "EVENT\nSomething drifts in the current."
		"boss":
			var re: Dictionary = Cards.REGION_ENEMIES.get(region, {})
			var nm := String(Cards.enemy(re.get("boss", "scab"))["name"])
			return "HEART\n%s. Kill it to clear the region." % nm
	return ""


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if _busy or UI.busy:
		return
	var reach := _reachable()
	if e.is_action_pressed("move_left"):
		if not reach.is_empty():
			sel = posmod(sel - 1, reach.size())
			_refresh()
	elif e.is_action_pressed("move_right"):
		if not reach.is_empty():
			sel = posmod(sel + 1, reach.size())
			_refresh()
	elif e.is_action_pressed("interact"):
		if not reach.is_empty():
			_enter(sel)
	elif e.is_action_pressed("menu"):
		_view_strand()
	elif e.is_action_pressed("back"):
		_withdraw()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_map_input(e: InputEvent) -> void:
	if _busy or UI.busy:
		return
	if not (e is InputEventMouseMotion or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)):
		return
	var r := row + 1
	if r >= nodes.size():
		return
	for c in (nodes[r] as Array).size():
		var p := _node_pos(r, c)
		if Rect2(p - Vector2(14, 14), Vector2(28, 36)).has_point(e.position):
			if c != sel:
				sel = c
				_refresh()
			if e is InputEventMouseButton:
				_enter(c)
			return


func _view_strand() -> void:
	_busy = true
	await StrandView.new().run(self, Game.run.get("strand", []), "view", {"title": "STRAND  (READ TOP DOWN)"})
	_busy = false


func _withdraw() -> void:
	_busy = true
	if await UI.confirm("Withdraw the culture? The run ends here."):
		Game.finish_run(false)
		return
	_busy = false


# ------------------------------------------------------------------ nodes

func _enter(c: int) -> void:
	if _busy:
		return
	_busy = true
	row += 1
	path.append(c)
	Game.run["row"] = row
	Game.run["col"] = c
	Game.run["path"] = path
	var type: String = nodes[row][c]
	_map.queue_redraw()
	await get_tree().create_timer(0.3).timeout
	match type:
		"fight", "elite", "boss":
			Game.run["battle"] = {"kind": type}
			Game.goto("battle")
			return
		"rest":
			await _rest()
		"event":
			await _event()
	sel = 0
	_busy = false
	_refresh()


func _strand() -> Array:
	return Game.run.get("strand", [])


func _heal(n: int) -> int:
	var col: int = int(Game.run.get("colony", 0))
	var mx: int = int(Game.run.get("max_colony", 1))
	var now := mini(mx, col + n)
	Game.run["colony"] = now
	_refresh()
	return now - col


func _hurt(n: int) -> void:
	Game.run["colony"] = maxi(1, int(Game.run.get("colony", 1)) - n)
	UI.flash(Color(0.8, 0.2, 0.2), 0.2)
	_refresh()


func _add_fray(n: int) -> void:
	Game.run["fray"] = maxi(0, int(Game.run.get("fray", 0)) + n)
	_refresh()


func _rest() -> void:
	await UI.say(["A still pocket in the tissue. Nothing presses here."], "see")
	while true:
		var mx: int = int(Game.run.get("max_colony", 1))
		var mend := int(ceil(mx * 0.3))
		var fray: int = int(Game.run.get("fray", 0))
		var opts := [
			"MEND      +%d COLONY" % mend,
			{"text": "PROOFREAD FRAY %d -> 0" % fray, "disabled": fray == 0},
			{"text": "EXCISE    CUT A GENE", "disabled": _strand().size() <= 4},
			"ARRANGE   REORDER",
		]
		var i := await UI.choose(opts, "Rest. One thing, then on.", false)
		match i:
			0:
				var got := _heal(mend)
				UI.toast("COLONY +%d" % got, Color("287818"))
				return
			1:
				_add_fray(-fray)
				UI.toast("FRAY 0. THE STRAND READS CLEAN.")
				return
			2:
				if await _excise():
					return
			3:
				if await _arrange():
					return


func _excise() -> bool:
	var strand := _strand()
	var idx: int = await StrandView.new().run(self, strand, "pick", {"title": "EXCISE WHICH GENE?"})
	if idx < 0:
		return false
	var id: String = strand[idx]
	var c: Dictionary = Cards.card(id)
	if c.has("pact"):
		if not await UI.confirm("PACT. Cutting %s costs %d colony." % [c["name"], int(c["pact"])]):
			return false
		_hurt(int(c["pact"]))
	strand.remove_at(idx)
	Game.run["strand"] = strand
	UI.toast("%s EXCISED" % c["name"])
	_refresh()
	return true


func _arrange() -> bool:
	var moved := false
	while true:
		var strand := _strand()
		var idx: int = await StrandView.new().run(self, strand, "pick", {"title": "ARRANGE: MOVE WHICH?"})
		if idx < 0:
			break
		var id: String = strand[idx]
		strand.remove_at(idx)
		var to: int = await StrandView.new().run(self, strand, "place",
			{"moving": id, "cursor": idx, "title": "MOVE %s TO?" % Cards.card(id)["name"]})
		if to < 0:
			to = idx
		strand.insert(clampi(to, 0, strand.size()), id)
		Game.run["strand"] = strand
		moved = moved or to != idx
	_refresh()
	return moved


func _place_new(id: String) -> void:
	var strand := _strand()
	var at: int = await StrandView.new().run(self, strand, "place",
		{"moving": id, "cancel": false, "title": "INSERT %s WHERE?" % Cards.card(id)["name"]})
	strand.insert(clampi(at, 0, strand.size()), id)
	Game.run["strand"] = strand
	_refresh()


func _event() -> void:
	match randi() % 4:
		0:
			await UI.say(["A loose gene cluster drifts past, unbound.",
				"It would take. It would not take cleanly."], "see")
			var i := await UI.choose(["TAKE IT    +2 FRAY", "LET IT PASS"], "", false)
			if i == 0:
				var pool: Array = Game.unlocked if not Game.unlocked.is_empty() else Cards.STARTING_POOL
				var id: String = pool[randi() % pool.size()]
				UI.toast("TAKEN: %s" % Cards.card(id)["name"])
				await _place_new(id)
				_add_fray(2)
		1:
			await UI.say(["The vessel walls clench. Pressure spikes.",
				"Something loosens in the surge: reagent, raw."], "see")
			var i := await UI.choose(["RIDE IT    -6 COLONY +4 REAGENT", "BRACE      +1 FRAY"], "", false)
			if i == 0:
				_hurt(6)
				Game.run["reagent"] = int(Game.run.get("reagent", 0)) + 4
				UI.toast("REAGENT +4")
			else:
				_add_fray(1)
				UI.toast("FRAY +1")
			_refresh()
		2:
			await UI.say(["A quiet pocket. Nothing grows here.", "The culture settles and divides."], "see")
			var got := _heal(6)
			UI.toast("COLONY +%d" % got, Color("287818"))
		_:
			await UI.say(["A Green bloom. Open. Waiting."], "see")
			await UI.say(["It is offering. It should not be able to."], "think")
			var i := await UI.choose(["TAKE A GREEN GENE", "BURN IT    +2 REAGENT"], "", false)
			if i == 0:
				var id: String = Cards.GREEN_POOL[randi() % Cards.GREEN_POOL.size()]
				UI.toast("TAKEN: %s" % Cards.card(id)["name"], Color("287818"))
				await _place_new(id)
			else:
				Game.run["reagent"] = int(Game.run.get("reagent", 0)) + 2
				UI.toast("REAGENT +2")
				_refresh()
