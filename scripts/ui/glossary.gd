extends CanvasLayer
## Glossary overlay (lab reference card). Scrollable term list, drawn in 8px text.
## Usage: const Glossary := preload("res://scripts/ui/glossary.gd")
##        await Glossary.new().run(self)
## Up/Down or wheel scroll; X / H / F1 / Z / Esc / right-click close.

signal done

const GeneArt := preload("res://scripts/run/gene_art.gd")

const BOX := Rect2(6, 4, 372, 208)
const LINE_H := 10
const ROWS := 18
const WRAP := 42            ## chars per definition line (indented 2 chars; 8px per char)
const C_TERM := Color("f8d878")
const C_TEXT := Color("d8e0e8")
const C_HEAD := Color("88d070")
const C_DIM := Color("788088")

const TERMS := [
	["COLONY", "Your culture's health. At 0 it dies and the run ends."],
	["FILM", "Blocks damage. Clears at the start of its owner's turn."],
	["CHARGE", "Energy. 3 per turn, plus modifiers."],
	["STRAND", "Your genes: a fixed loop, read in order. Rearranged between fights."],
	["WINDOW", "The next 5 genes. Slots 1-3 are READ, slots 4-5 are NEXT."],
	["READ", "At END the READ zone leaves. Genes there you did not express are SKIPPED. NEXT slides left. Expressed genes always leave."],
	["LINK / CHAIN", "Express the gene right of your last one: LINK. Keep going: CHAIN. +1 to all numbers per step past the first. Fires the gene's LINK text."],
	["CLEAN", "Stop the read bar in its bright band: x1.5, rounded up. No penalty for missing. Fray shrinks the band. Green genes are always CLEAN."],
	["SPLICE", "Swap the selected gene with its right neighbour. 1 free per turn. Spent slots can't be spliced."],
	["MUTATE", "1 Charge, +1 Fray. Spin the reel, press to stop. Lasts this fight. Clears junk."],
	["CHORUS", "Shared meter, 0-10. Both sides push it. Decays 1 per turn."],
	["QUIET / HUM / LOUD", "Chorus 0-3 / 4-6 / 7-10. Genes with a LOUD or QUIET mode replace their effect in that band."],
	["RESONANCE", "Whoever pushes Chorus to 10: their next gene or intent fires twice. Then Chorus drops to 5."],
	["ENDING LOUD", "Win with Chorus 7+ : +1 UPTAKE."],
	["UPTAKE", "Advances the infection clock at day end. Green genes add +1 each."],
	["FRAY", "Run instability. Narrows CLEAN. At 5+, two genes overgrow at fight start."],
	["ROT", "Damage over time."],
	["MARKED", "Express this gene this turn or lose it."],
	["BREAK n", "Deal n or more this turn to cancel the wind-up. The host is STAGGERED and loses its turn."],
	["KNOTTED", "Costs +1 until expressed or read."],
	["MEDIUM", "Each region's fluid bends the rules:"],
	["  WOUND", "CLOTTING. Film only half-clears."],
	["  RIVERS", "CURRENT. Turns alternate EBB / SURGE. SURGE: READ +1, Chorus +2. EBB: Chorus -2."],
	["  HOLLOW", "BREATH. INHALE: Film x1.5. EXHALE: damage x1.5. Chorus does not decay."],
	["  ARCHIVE", "FADING. NEXT is hidden until read."],
	["  ROOT", "THE HEART. No decay. Resonance never drops."],
	["FADED", "Hidden NEXT genes in the archive. They can still be spliced."],
	["BOOSTER", "Syringe made in the culture room. Press F in a fight. 0 Charge, 1 per turn. Uses the read bar."],
	["TISSUE", "Clot, plasma, alveoli, myelin. Dropped on wins. Banked after the run; half if the culture dies."],
	["ADAPTATION", "A lasting mutation for this run. Triggers on events. Shown as icons in the HUD."],
]

var _lines: Array = []      ## [text: String, color: Color, x: int]
var _scroll := 0
var _closed := false
var _canvas: Control


func run(parent: Node) -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(self)
	_build()
	Sfx.play("blip")
	await done
	queue_free()


func _build() -> void:
	_lines.clear()
	for t in TERMS:
		var term: String = t[0]
		var body: String = t[1]
		var sub := term.begins_with("  ")
		_lines.append([term.strip_edges(), C_TERM if not sub else C_HEAD, 2 if sub else 0])
		for ln in _wrap(body, WRAP - (2 if sub else 0)):
			_lines.append([ln, C_TEXT, 4 if sub else 2])
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(384, 216)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_canvas = Control.new()
	_canvas.size = Vector2(384, 216)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_list)
	add_child(_canvas)
	dim.gui_input.connect(_on_gui)


func _wrap(s: String, cols: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for word in s.split(" ", false):
		if cur == "":
			cur = word
		elif cur.length() + 1 + word.length() <= cols:
			cur += " " + word
		else:
			out.append(cur)
			cur = word
	if cur != "":
		out.append(cur)
	return out


func _max_scroll() -> int:
	return maxi(0, _lines.size() - ROWS)


func _draw_list() -> void:
	var ci := _canvas
	GeneArt.box(ci, BOX, true, C_DIM)
	var o := BOX.position + Vector2(8, 5)
	GeneArt.text(ci, o, "GLOSSARY", C_HEAD)
	var hint := "UP/DN SCROLL  X CLOSE"
	GeneArt.text(ci, Vector2(BOX.end.x - 8 - GeneArt.text_w(hint), o.y), hint, C_DIM)
	ci.draw_rect(Rect2(BOX.position.x + 4, BOX.position.y + 16, BOX.size.x - 8, 1), C_DIM)
	var y := BOX.position.y + 20
	for i in ROWS:
		var idx := _scroll + i
		if idx >= _lines.size():
			break
		var l: Array = _lines[idx]
		var txt: String = l[0]
		var col: Color = l[1]
		var ind: int = l[2]
		GeneArt.text(ci, Vector2(o.x + ind * 8, y + i * LINE_H), txt, col)
	var ax := BOX.end.x - 16
	if _scroll > 0:
		GeneArt.text(ci, Vector2(ax, BOX.position.y + 20), "^", C_TERM)
	if _scroll < _max_scroll():
		GeneArt.text(ci, Vector2(ax, BOX.position.y + 20 + (ROWS - 1) * LINE_H), "v", C_TERM)


func _move(d: int) -> void:
	var n := clampi(_scroll + d, 0, _max_scroll())
	if n != _scroll:
		_scroll = n
		Sfx.play("blip", 1.1, -6.0)
		_canvas.queue_redraw()


func _close() -> void:
	if _closed:
		return
	_closed = true
	Sfx.play("cancel")
	done.emit()


func _input(e: InputEvent) -> void:
	if _closed or UI.busy:
		return
	if e is InputEventMouseButton:
		_on_gui(e)
		return
	if not (e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion or e is InputEventAction):
		return
	if e.is_action_pressed("move_up", true):
		_move(-1)
	elif e.is_action_pressed("move_down", true):
		_move(1)
	elif e.is_action_pressed("back") or e.is_action_pressed("help") \
			or e.is_action_pressed("interact") or e.is_action_pressed("menu"):
		_close()
	# The glossary is modal: nothing underneath sees keys while it is open.
	get_viewport().set_input_as_handled()


func _on_gui(e: InputEvent) -> void:
	if _closed or UI.busy:
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)
		MOUSE_BUTTON_RIGHT:
			_close()
	get_viewport().set_input_as_handled()
