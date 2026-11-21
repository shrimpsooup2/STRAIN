extends RefCounted
## EVENT node runner (data in events.gd, doc §16).
##   var fought: bool = await EventView.open(parent, event_id)
## Returns true when the chosen option started a fight: run.battle is set, the game is
## saved and Game.goto("battle") was called; the caller must stop.

const RestView := preload("res://scripts/run/rest_view.gd")
const RewardView := preload("res://scripts/run/reward_view.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")
const Boosters := preload("res://scripts/culture/boosters.gd")


static func _events() -> GDScript:
	return load("res://scripts/run/events.gd")


## Short reason an option is locked, or "" when it can be taken.
static func req_fail(opt: Dictionary) -> String:
	var req: Dictionary = opt.get("req", {})
	for k in req:
		var need: int = int(req[k])
		var key := String(k)
		match key:
			"reagent":
				var have: int = int(Game.run.get("reagent", 0))
				if have < need:
					return "NEEDS %d REAGENT (HAVE %d)" % [need, have]
			"colony":
				var col: int = int(Game.run.get("colony", 0))
				if col <= need:
					return "NEEDS MORE THAN %d COLONY" % need
			"fray_max":
				var fr: int = int(Game.run.get("fray", 0))
				if fr > need:
					return "FRAY MUST BE %d OR LESS" % need
			_:
				var mat := RestView.region_mat() if key == "tissue" else key
				var t: int = RestView.tissue(mat)
				if t < need:
					return "NEEDS %d %s (HAVE %d)" % [need, mat.to_upper(), t]
	# Implicit: a lab-reagent cost needs that much banked reagent.
	for v in opt.get("out", []):
		var o: Dictionary = v
		if String(o.get("t", "")) == "lab_reagent" and int(o.get("n", 0)) < 0:
			if Game.reagent < -int(o["n"]):
				return "NEEDS %d LAB REAGENT (HAVE %d)" % [-int(o["n"]), Game.reagent]
	return ""


static func open(parent: Node, eid: String) -> bool:
	var ev: Dictionary = _events().get_event(eid)
	if ev.is_empty():
		return false
	Sfx.play("event")
	var see: Array = []
	for v in ev.get("see", []):
		var line := String(v)
		if bool(ev.get("hand", false)):
			line = Lore.legible(line)
		see.append(line)
	if not see.is_empty():
		await UI.say(see, "see")
	var think := String(ev.get("think", ""))
	if think != "":
		await UI.say([think], "think")
	var opts: Array = ev.get("options", [])
	if opts.is_empty():
		return false
	var rows: Array = []
	for v in opts:
		var o: Dictionary = v
		var why := req_fail(o)
		var row := {"label": String(o.get("label", "")), "right": "",
			"desc": String(o.get("detail", ""))}
		if why != "":
			row["disabled"] = true
			row["desc"] = String(row["desc"]) + "\n" + why
		rows.append(row)
	var i: int = await RestView.new().choose(parent, rows,
		{"title": String(ev.get("title", "")), "cancel": false})
	if i < 0 or i >= opts.size():
		i = opts.size() - 1
	var pick: Dictionary = opts[i]
	var outs: Array = pick.get("out", [])
	var after := String(pick.get("after", ""))
	if pick.has("chance") and randf() >= float(pick["chance"]):
		outs = pick.get("else", [])
		after = String(pick.get("else_after", after))
	var fight := ""
	for v in outs:
		var o: Dictionary = v
		if String(o.get("t", "")) == "fight":
			fight = String(o.get("enemy", "elite"))
	if after != "":
		await UI.say([after], "see")
	for v in outs:
		var o: Dictionary = v
		if String(o.get("t", "")) != "fight":
			await apply(parent, o)
	Game.save_game()
	if fight != "":
		start_fight(fight)
		return true
	return false


static func start_fight(enemy: String) -> void:
	var id := enemy
	if not Cards.ENEMIES.has(id):
		var region := String(Game.run.get("region", "wound"))
		var pool: Dictionary = Cards.REGION_ENEMIES.get(region, Cards.REGION_ENEMIES["wound"])
		var el = pool.get("elite", [])
		if el is Array:
			var arr: Array = el
			id = String(arr.pick_random()) if not arr.is_empty() else "fester"
		else:
			id = String(el)
	Game.run["battle"] = {"kind": "elite", "enemy": id, "event": true}
	Game.save_game()
	Game.goto("battle")


static func apply(parent: Node, o: Dictionary) -> void:
	var t := String(o.get("t", ""))
	var n: int = int(o.get("n", 0))
	match t:
		"colony":
			if n >= 0:
				var got := RestView.heal(n)
				UI.toast("COLONY +%d" % got, UI.C_GREEN)
			else:
				var lost := RestView.hurt(-n)
				UI.toast("COLONY -%d" % lost, UI.C_BAD)
				Sfx.play("hurt")
		"max_colony":
			RestView.add_max(n)
			UI.toast("MAX COLONY %+d" % n, UI.C_GREEN if n > 0 else UI.C_BAD)
		"fray":
			RestView.add_fray(n)
			UI.toast("FRAY %+d" % n, UI.C_WARN if n > 0 else UI.C_GREEN)
		"reagent":
			RestView.add_reagent(n)
			UI.toast("REAGENT %+d" % n)
		"uptake":
			Game.run["uptake"] = maxi(0, int(Game.run.get("uptake", 0)) + n)
			UI.toast("UPTAKE %+d" % n, UI.C_WARN if n > 0 else UI.C_GREEN)
		"tissue":
			var mat := String(o.get("mat", RestView.region_mat()))
			if mat == "":
				return
			var got := RestView.add_tissue(mat, n)
			UI.toast("%s %+d" % [mat.to_upper(), got])
		"booster":
			var bid := String(o.get("id", ""))
			if not Game.run.has("boosters"):
				Game.run["boosters"] = []
			var bl: Array = Game.run["boosters"]
			bl.append(bid)
			var binfo: Dictionary = Boosters.info(bid)
			UI.toast("BOOSTER: %s" % String(binfo.get("name", bid.to_upper())), binfo.get("color", UI.C_ACCENT))
		"pitch":
			Game.run["pitch"] = int(Game.run.get("pitch", 0)) + n
			UI.toast("PITCH %+d THIS RUN" % n)
		"lab_reagent":
			Game.reagent = maxi(0, Game.reagent + n)
			UI.toast("LAB REAGENT %+d" % n)
		"breath":
			# Negative is allowed (a short day), but tomorrow keeps at least 1 breath.
			Game.extra_breath = maxi(1 - Game.breath_max(), Game.extra_breath + n)
			UI.toast("BREATH %+d TOMORROW" % n)
		"clock":
			Game.push_back(float(n))
			UI.toast("CLOCK -%d%%" % n, UI.C_GREEN)
		"clock_fwd":
			Game.stage_progress += float(n)
			UI.toast("INFECTION +%d%%" % n, UI.C_BAD)
		"adapt":
			if o.has("id"):
				RewardView.gain_adapt(String(o["id"]))
			else:
				var rarity := String(o.get("rarity", "common"))
				var count := 1 if not bool(o.get("pick", true)) else 3
				var ids: Array = Adapt.offers(count, rarity, Adapt.owned())
				if ids.is_empty():
					return
				var got := String(ids[0])
				if count > 1:
					got = await RewardView.pick_adapt(parent, ids, "TAKE ONE. %s." % rarity.to_upper(),
						rarity != "cursed")
				if got != "":
					RewardView.gain_adapt(got)
		"gene":
			var gid := ""
			if o.has("id"):
				gid = String(o["id"])
			else:
				var pool := String(o.get("pool", "any"))
				var offers: Array = []
				if pool == "green":
					var g: Array = Cards.GREEN_POOL.duplicate()
					g.shuffle()
					offers = g.slice(0, 3)
				else:
					offers = RewardView.gene_offers(3)
				gid = await RewardView.pick_gene(parent, offers, "TAKE ONE GENE.", 0)
			if gid != "":
				await RestView.place_gene(parent, gid)
		"upgrade":
			await RestView.enrich(parent)
		"upgrade_random":
			var up := RestView.upgrade_random()
			if up != "":
				UI.toast("ENRICHED: %s" % StrandView.gene_name(up), UI.C_ACCENT)
		"excise":
			await RestView.excise(parent)
		"transform":
			await RestView.transform(parent)
		"junk":
			RestView.add_junk(maxi(1, n))
			UI.toast("+%d JUNK GENE%s" % [maxi(1, n), "S" if n > 1 else ""], UI.C_BAD)
			Sfx.play("rot")
		"text":
			var lines: Array = []
			if o.has("lines"):
				lines = o["lines"]
			else:
				lines = [String(o.get("text", ""))]
			await UI.say(lines, String(o.get("style", "see")))
		"lore":
			await Lore.show(String(o.get("id", "")))
