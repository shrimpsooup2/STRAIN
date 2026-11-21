extends CanvasLayer
## REST node, plus the shared pieces every run screen uses:
##   - a row picker overlay:
##       var i: int = await RestView.new().choose(parent, rows, opts)
##     rows: [{"label", "right", "detail", "desc", "disabled", "icon": [7 rows], "icon_color", "swatch", "color"}]
##     opts: title, footer, rect (Rect2), desc (bool, bottom description box), cancel (bool), cursor (int)
##     → chosen index, or -1 when backed out (only if cancel).
##   - static run helpers: heal / hurt / add_fray / band_pct / mend_amount,
##     place_gene / excise / enrich / upgrade_random / transform / arrange / add_junk.
## Rest screen: await RestView.open(parent)

signal done(result: int)

const GeneArt := preload("res://scripts/run/gene_art.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")
const SELF_PATH := "res://scripts/run/rest_view.gd"

const LIST := Rect2(6, 4, 372, 158)
const DESC := Rect2(6, 164, 372, 48)
const MEND_PCT := 30
const PROOFREAD_N := 3
const ARRANGE_MOVES := 3
const MIN_STRAND := 4

var rows: Array = []
var title := ""
var footer := ""
var rect := LIST
var show_desc := true
var allow_cancel := true
var cursor := 0
var _top := 0
var _row_h := 12
var _canvas: Control
var _desc: Label
var _closed := false
var _t := 0.0
var _flip := false


# ================================================================== picker

func choose(parent: Node, p_rows: Array, opts: Dictionary = {}) -> int:
	rows = p_rows
	title = String(opts.get("title", ""))
	footer = String(opts.get("footer", ""))
	show_desc = bool(opts.get("desc", true))
	var default_rect := LIST if show_desc else Rect2(6, 4, 372, 208)
	rect = opts.get("rect", default_rect)
	allow_cancel = bool(opts.get("cancel", true))
	_flip = bool(opts.get("flip", false))
	_row_h = 12
	for r in rows:
		var rd: Dictionary = r
		if rd.has("detail") or rd.has("icon"):
			_row_h = 20
	cursor = clampi(int(opts.get("cursor", 0)), 0, maxi(0, rows.size() - 1))
	for k in rows.size():
		var probe: Dictionary = rows[(cursor + k) % rows.size()]
		if not bool(probe.get("disabled", false)):
			cursor = (cursor + k) % rows.size()
			break
	layer = 55
	parent.add_child(self)
	_build()
	var res: int = await done
	queue_free()
	return res


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_rows)
	_canvas.gui_input.connect(_on_gui)
	add_child(_canvas)
	if show_desc:
		var dp := UI.panel(DESC, true)
		dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dp)
		_desc = UI.label("", UI.C_THINK_FG)
		_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_desc.custom_minimum_size = Vector2(DESC.size.x - 14, 36)
		_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		dp.add_child(_desc)
	_refresh()
	if _flip:
		_canvas.pivot_offset = rect.get_center()
		_canvas.scale = Vector2(1, 0.05)
		var tw := create_tween()
		tw.tween_property(_canvas, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _visible_rows() -> int:
	var head := 20 if title != "" else 6
	var foot := 12 if footer != "" else 4
	return maxi(1, int((rect.size.y - head - foot) / _row_h))


func _refresh() -> void:
	var vis := _visible_rows()
	if cursor < _top:
		_top = cursor
	elif cursor >= _top + vis:
		_top = cursor - vis + 1
	_top = clampi(_top, 0, maxi(0, rows.size() - vis))
	if _desc and rows.size() > 0:
		var r: Dictionary = rows[cursor]
		_desc.text = String(r.get("desc", r.get("detail", "")))
	_canvas.queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	if _canvas:
		_canvas.queue_redraw()


func _draw_rows() -> void:
	var ci := _canvas
	GeneArt.box(ci, rect, false)
	var y0 := rect.position.y + 6
	if title != "":
		GeneArt.text(ci, rect.position + Vector2(8, 5), title, UI.C_INK)
		ci.draw_rect(Rect2(rect.position.x + 6, rect.position.y + 16, rect.size.x - 12, 1), UI.C_BORDER)
		y0 = rect.position.y + 20
	var vis := _visible_rows()
	for k in mini(vis, rows.size() - _top):
		var i := _top + k
		var r: Dictionary = rows[i]
		var y := y0 + k * _row_h
		var x := rect.position.x + 8
		var off := bool(r.get("disabled", false))
		if i == cursor:
			ci.draw_rect(Rect2(x - 2, y - 1, rect.size.x - 12, _row_h - 1), UI.C_FOCUS)
			ci.draw_rect(Rect2(x - 2, y - 1, 3, _row_h - 1), UI.C_WARN if off else UI.C_ACCENT)
		var tx := x + 4
		if r.has("icon"):
			var ic: Color = r.get("icon_color", UI.C_ACCENT.darkened(0.3))
			GeneArt.bitmap(ci, Vector2(x + 3, y + 2), r["icon"], ic.darkened(0.5) if off else ic, 2)
			tx = x + 22
		elif r.has("swatch"):
			var sw: Color = r["swatch"]
			ci.draw_rect(Rect2(x + 3, y + 1, 6, 6), sw)
			tx = x + 14
		var ink: Color = r.get("color", UI.C_INK)
		if off:
			ink = UI.C_DIM
		GeneArt.text(ci, Vector2(tx, y), String(r.get("label", "")), ink)
		var right := String(r.get("right", ""))
		if right != "":
			GeneArt.text(ci, Vector2(rect.end.x - 10 - GeneArt.text_w(right), y), right,
				UI.C_DIM if off else UI.C_BORDER)
		if r.has("detail"):
			GeneArt.text(ci, Vector2(tx, y + 9), String(r["detail"]), UI.C_DIM if off else UI.C_BORDER)
	if _top > 0:
		GeneArt.text(ci, Vector2(rect.end.x - 16, y0), "^", UI.C_BORDER)
	if _top + vis < rows.size():
		GeneArt.text(ci, Vector2(rect.end.x - 16, rect.end.y - 12), "v", UI.C_BORDER)
	if footer != "":
		GeneArt.text(ci, Vector2(rect.position.x + 8, rect.end.y - 11), footer, UI.C_BORDER)


func _row_at(p: Vector2) -> int:
	if not rect.has_point(p):
		return -1
	var y0 := rect.position.y + (20 if title != "" else 6)
	var k := int(floor((p.y - y0) / _row_h))
	if k < 0 or k >= _visible_rows():
		return -1
	var i := _top + k
	return i if i < rows.size() else -1


func _on_gui(e: InputEvent) -> void:
	if _closed or UI.busy:
		return
	if e is InputEventMouseMotion:
		var i := _row_at(e.position)
		if i >= 0 and i != cursor:
			cursor = i
			Sfx.play("blip")
			_refresh()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_move(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_move(1)
			MOUSE_BUTTON_LEFT:
				var i := _row_at(e.position)
				if i >= 0:
					cursor = i
					_pick()
			MOUSE_BUTTON_RIGHT:
				_cancel()


func _move(d: int) -> void:
	if rows.is_empty():
		return
	cursor = posmod(cursor + d, rows.size())
	Sfx.play("blip")
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if _closed or UI.busy:
		return
	if e.is_action_pressed("move_up"):
		_move(-1)
	elif e.is_action_pressed("move_down"):
		_move(1)
	elif e.is_action_pressed("interact"):
		_pick()
	elif e.is_action_pressed("back"):
		_cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _pick() -> void:
	if rows.is_empty():
		_cancel()
		return
	var r: Dictionary = rows[cursor]
	if bool(r.get("disabled", false)):
		Sfx.play("error")
		return
	Sfx.play("select")
	_closed = true
	done.emit(cursor)


func _cancel() -> void:
	if not allow_cancel:
		return
	Sfx.play("cancel")
	_closed = true
	done.emit(-1)


# ================================================================== stats

static func strand() -> Array:
	if not Game.run.has("strand"):
		Game.run["strand"] = []
	return Game.run["strand"]


static func heal(n: int) -> int:
	var col: int = int(Game.run.get("colony", 0))
	var mx: int = int(Game.run.get("max_colony", 1))
	var now := clampi(col + n, 1, mx)
	Game.run["colony"] = now
	if now > col:
		Sfx.play("heal")
	return now - col


## Out-of-battle damage never kills: Colony stops at 1.
static func hurt(n: int) -> int:
	var col: int = int(Game.run.get("colony", 1))
	var now := maxi(1, col - n)
	Game.run["colony"] = now
	UI.flash(Color(0.8, 0.2, 0.2), 0.2)
	Sfx.play("hurt")
	return col - now


static func add_max(n: int) -> void:
	var mx: int = maxi(1, int(Game.run.get("max_colony", 1)) + n)
	Game.run["max_colony"] = mx
	var col: int = int(Game.run.get("colony", 1))
	if n > 0:
		col += n
	Game.run["colony"] = clampi(col, 1, mx)


static func add_fray(n: int) -> void:
	Game.run["fray"] = maxi(0, int(Game.run.get("fray", 0)) + n)


static func add_reagent(n: int) -> void:
	Game.run["reagent"] = maxi(0, int(Game.run.get("reagent", 0)) + n)


static func region_mat() -> String:
	return String(Cards.REGION_TISSUE.get(String(Game.run.get("region", "")), ""))


static func tissue(mat: String) -> int:
	var t: Dictionary = Game.run.get("tissue", {})
	return int(t.get(mat, 0))


static func add_tissue(mat: String, n: int) -> int:
	if mat == "":
		return 0
	if not Game.run.has("tissue"):
		Game.run["tissue"] = {}
	var t: Dictionary = Game.run["tissue"]
	var before: int = int(t.get(mat, 0))
	var now := maxi(0, before + n)
	t[mat] = now
	return now - before


## CLEAN read band width in percent at this Fray (30, -4 per Fray, min 10, + band mods).
static func band_pct(fray: int) -> int:
	return maxi(5, maxi(10, 30 - 4 * fray) + Adapt.mod("band"))


static func mend_amount() -> int:
	var mx: int = int(Game.run.get("max_colony", 1))
	return int(ceil(mx * (MEND_PCT + Adapt.mod("rest_heal")) / 100.0))


# ================================================================== genes

static func gene_line(id: String) -> String:
	var c: Dictionary = Cards.card(id)
	if c.get("kind", "") == "passive":
		return "%s (PASSIVE): %s" % [StrandView.gene_name(id), String(c.get("desc", ""))]
	return "%s COST %d: %s" % [StrandView.gene_name(id), int(c.get("cost", 0)), String(c.get("desc", ""))]


## Slide a new gene into the run strand. Returns the insertion index.
static func place_gene(parent: Node, id: String, head := "") -> int:
	var s := strand()
	var t := head if head != "" else "INSERT %s WHERE?" % StrandView.gene_name(id)
	var at: int = await StrandView.new().run(parent, s, "place", {"moving": id, "cancel": false, "title": t})
	at = clampi(at, 0, s.size())
	s.insert(at, id)
	Sfx.play("splice")
	UI.toast("%s SPLICED IN" % StrandView.gene_name(id))
	return at


static func excise(parent: Node, head := "EXCISE WHICH GENE?") -> bool:
	var s := strand()
	if s.size() <= MIN_STRAND:
		UI.toast("THE STRAND CANNOT LOSE MORE.", UI.C_BAD)
		return false
	var idx: int = await StrandView.new().run(parent, s, "pick", {"title": head})
	if idx < 0:
		return false
	var id: String = s[idx]
	var c: Dictionary = Cards.card(id)
	if c.has("pact"):
		if not await UI.confirm("PACT. Cutting %s costs %d Colony." % [StrandView.gene_name(id), int(c["pact"])]):
			return false
		hurt(int(c["pact"]))
	s.remove_at(idx)
	Sfx.play("skip")
	UI.toast("%s EXCISED" % StrandView.gene_name(id))
	return true


static func upgradable() -> Array:
	var out: Array = []
	var s := strand()
	for i in s.size():
		if Cards.can_upgrade(String(s[i])):
			out.append(i)
	return out


## Player picks a gene and sees before → after. Returns true if a gene was enriched.
static func enrich(parent: Node) -> bool:
	if upgradable().is_empty():
		UI.toast("NOTHING LEFT TO ENRICH.", UI.C_BAD)
		return false
	var s := strand()
	var cur := 0
	while true:
		var idx: int = await StrandView.new().run(parent, s, "pick", {"title": "ENRICH WHICH GENE?", "cursor": cur})
		if idx < 0:
			return false
		cur = idx
		var id: String = s[idx]
		if not Cards.can_upgrade(id):
			Sfx.play("error")
			UI.toast("%s CANNOT BE ENRICHED." % StrandView.gene_name(id), UI.C_BAD)
			continue
		var up: String = Cards.upgraded(id)
		var compare := "NOW   %s\nAFTER %s" % [gene_line(id), gene_line(up)]
		var picker = load(SELF_PATH).new()
		var i: int = await picker.choose(parent, [
			{"label": "ENRICH", "right": StrandView.gene_name(id) + " > " + StrandView.gene_name(up), "desc": compare},
			{"label": "PICK ANOTHER", "desc": compare},
		], {"title": "ENRICH %s?" % StrandView.gene_name(id)})
		if i == 0:
			s[idx] = up
			Sfx.play("mutate")
			UI.toast("%s ENRICHED" % StrandView.gene_name(up), UI.C_INK)
			return true
		if i < 0:
			return false
	return false


static func upgrade_random() -> String:
	var opts := upgradable()
	if opts.is_empty():
		return ""
	var s := strand()
	var idx: int = opts[randi() % opts.size()]
	var up: String = Cards.upgraded(String(s[idx]))
	s[idx] = up
	Sfx.play("mutate")
	return up


## Player picks a gene; it becomes a random gene from the pool.
static func transform(parent: Node) -> bool:
	var s := strand()
	if s.is_empty():
		return false
	var idx: int = await StrandView.new().run(parent, s, "pick",
		{"title": "TRANSFORM WHICH GENE?", "cancel": false})
	if idx < 0:
		return false
	var old: String = s[idx]
	var pool: Array = Game.unlocked if not Game.unlocked.is_empty() else Cards.STARTING_POOL
	var nid := old
	for k in 12:
		nid = String(pool[randi() % pool.size()])
		if nid != Cards.base_id(old):
			break
	s[idx] = nid
	Sfx.play("mutate")
	UI.toast("%s BECAME %s" % [StrandView.gene_name(old), StrandView.gene_name(nid)])
	return true


## Up to `moves` gene moves. Returns true if anything changed.
static func arrange(parent: Node, moves := ARRANGE_MOVES) -> bool:
	var moved := false
	var left := moves
	while left > 0:
		var s := strand()
		var idx: int = await StrandView.new().run(parent, s, "pick",
			{"title": "ARRANGE (%d LEFT): MOVE WHICH?" % left})
		if idx < 0:
			break
		var id: String = s[idx]
		s.remove_at(idx)
		var to: int = await StrandView.new().run(parent, s, "place",
			{"moving": id, "cursor": idx, "title": "MOVE %s TO?" % StrandView.gene_name(id)})
		if to < 0:
			to = idx
		s.insert(clampi(to, 0, s.size()), id)
		if to != idx:
			moved = true
			left -= 1
			Sfx.play("splice")
	return moved


## OVERGROWTH junk at random places in the run strand.
static func add_junk(n: int) -> void:
	var s := strand()
	for k in n:
		s.insert(randi() % (s.size() + 1), "overgrowth")
	if n > 0:
		Sfx.play("rot")


# ================================================================== rest

static func open(parent: Node) -> void:
	Sfx.play("rest")
	await UI.say(["A still pocket in the tissue. Nothing presses here."], "see")
	while true:
		var col: int = int(Game.run.get("colony", 0))
		var mx: int = int(Game.run.get("max_colony", 1))
		var mend := mend_amount()
		var fray: int = int(Game.run.get("fray", 0))
		var fray_to := maxi(0, fray - PROOFREAD_N)
		var size := strand().size()
		var pct := MEND_PCT + Adapt.mod("rest_heal")
		var menu: Array = [
			{"label": "MEND", "right": "+%d COLONY" % mend,
				"desc": "Heal %d (%d%% of max %d). Colony %d > %d." % [mend, pct, mx, col, mini(mx, col + mend)],
				"disabled": col >= mx},
			{"label": "ENRICH", "right": "UPGRADE 1 GENE",
				"desc": "Upgrade one gene for the rest of the run. You see it before and after.",
				"disabled": upgradable().is_empty()},
			{"label": "EXCISE", "right": "CUT 1 GENE",
				"desc": ("Remove one gene. PACT genes cost Colony when cut." if size > MIN_STRAND
					else "The strand is at %d genes. It cannot lose more." % MIN_STRAND),
				"disabled": size <= MIN_STRAND},
			{"label": "ARRANGE", "right": "MOVE UP TO %d" % ARRANGE_MOVES,
				"desc": "Move up to %d genes to new slots. Order decides what links." % ARRANGE_MOVES},
			{"label": "PROOFREAD", "right": "FRAY -%d" % PROOFREAD_N,
				"desc": "Fray %d > %d. CLEAN band %d%% > %d%%." % [fray, fray_to, band_pct(fray), band_pct(fray_to)],
				"disabled": fray == 0},
		]
		if col >= mx:
			menu[0]["desc"] = "Colony is full (%d/%d)." % [col, mx]
		var picker = load(SELF_PATH).new()
		var i: int = await picker.choose(parent, menu, {"title": "REST. ONE THING, THEN ON.", "cancel": false})
		match i:
			0:
				var got := heal(mend)
				UI.toast("COLONY +%d" % got, Color("287818"))
				return
			1:
				if await enrich(parent):
					return
			2:
				if await excise(parent):
					return
			3:
				if await arrange(parent):
					return
			4:
				add_fray(-PROOFREAD_N)
				Sfx.play("clean")
				UI.toast("FRAY %d. THE STRAND READS CLEANER." % int(Game.run.get("fray", 0)))
				return
