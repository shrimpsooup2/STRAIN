extends Node
## Hub menus: the pause menu (notebook / hand / strand) and the medbay scan
## panel. All awaitable; built on UI.choose / UI.say. The splice bench lives in
## its own scene now (scenes/culture).

const HandView := preload("res://scripts/ui/hand_view.gd")

var _layer: CanvasLayer


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)


func _gene_name(id: String) -> String:
	return Cards.card(id).get("name", id.to_upper())


func _strain_name(id: String) -> String:
	return Cards.STRAINS[id]["name"]


# ------------------------------------------------------------ hand / scan panels

## Hand panel. With `scan`, adds the projection and purge warning. Closes with the textbox.
func hand_panel(scan: bool) -> void:
	var p := UI.panel(Rect2(104, 8, 240, 152), true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var hv: Control = HandView.new()
	hv.set("stage", Game.stage)
	hv.set("progress", Game.stage_progress)
	hb.add_child(hv)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	hb.add_child(vb)
	vb.add_child(UI.label("BIOSCAN" if scan else "LEFT HAND", UI.C_ACCENT))
	vb.add_child(UI.label("STAGE %d" % Game.stage, UI.C_PAPER))
	vb.add_child(UI.label("DAY %d" % Game.day, UI.C_DIM))
	if scan:
		var days := Game.days_to_next_stage()
		vb.add_child(UI.label("NEXT CHANGE:", UI.C_PAPER))
		vb.add_child(UI.label("~%d DAY%s" % [days, "" if days == 1 else "S"], UI.C_WARN))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110, 8)
		bar.max_value = 100.0
		bar.value = Game.stage_progress
		vb.add_child(bar)
		if Game.stage >= 4:
			var closed := Game.stage > Game.PURGE_LAST_STAGE
			var w := UI.label("PURGE WINDOW:\n%s" % ("CLOSED" if closed else "CLOSING"), UI.C_BAD)
			vb.add_child(w)
			var tw := w.create_tween().set_loops()
			tw.tween_property(w, "modulate:a", 0.35, 0.4)
			tw.tween_property(w, "modulate:a", 1.0, 0.4)
	_layer.add_child(p)
	var lines: Array = []
	if scan:
		lines.append("SCAN COMPLETE. SPREAD: STAGE %d, %d%%." % [Game.stage, int(Game.stage_progress)])
	else:
		lines.append(["The cut, and the lines around it.", "The lines reach my wrist.",
			"It won't stop shaking.", "It's past my elbow.", "I can't see the grey in it any more.",
			"It isn't only my hand."][clampi(Game.stage, 0, 5)])
	await UI.say(lines, "see" if scan else "think")
	p.queue_free()


# ------------------------------------------------------------ pause menu

## Returns "title" if the player left for the title screen.
func pause() -> String:
	while true:
		var i := await UI.choose(["NOTEBOOK", "HAND", "STRAND", "SAVE", "TITLE", "CLOSE"])
		match i:
			0:
				await _notebook()
			1:
				await hand_panel(false)
			2:
				await _strand_panel()
			3:
				Game.save_game()
				UI.toast("SAVED")
			4:
				Game.save_game()
				Game.goto("title")
				return "title"
			_:
				return ""
	return ""


func _notebook() -> void:
	while true:
		var ids := Lore.found()
		var opts: Array = []
		for id in ids:
			opts.append(Lore.entry(id).get("title", id.to_upper()))
		opts.append({"text": "THOUGHTS", "disabled": Game.thoughts.is_empty()})
		var i := await UI.choose(opts, "NOTEBOOK. %d ENTRIES." % ids.size())
		if i < 0:
			return
		if i == ids.size():
			await UI.say(Game.thoughts.duplicate(), "think")
		else:
			await UI.say(Lore.lines(ids[i]))


func _strand_panel() -> void:
	var strand := Game.starting_strand()
	var p := UI.panel(Rect2(104, 8, 240, 152), true)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	vb.add_child(UI.label("STRAND - %s" % _strain_name(Game.strain), UI.C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	vb.add_child(grid)
	var base_n := strand.size() - Game.gene_bank.size()
	for k in strand.size():
		var id: String = strand[k]
		var col := UI.C_PAPER
		if k >= base_n:
			col = UI.C_WARN
		elif Cards.is_green(id):
			col = UI.C_GREEN
		grid.add_child(UI.label("%2d %s" % [k + 1, _gene_name(id)], col))
	_layer.add_child(p)
	var line := "%d GENES. BANKED GENES IN ORANGE." % strand.size() if Game.gene_bank.size() > 0 \
		else "%d GENES." % strand.size()
	await UI.say([line])
	p.queue_free()
