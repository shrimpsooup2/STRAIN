extends RefCounted
## Post-fight reward, shown by run_map when it finds Game.run["pending_reward"].
##   await RewardView.open(parent, {"kind": "fight"|"elite"|"event", "enemy": id})
## Elite and event fights first offer an ADAPTATION (1 of 3), then every kind offers a
## gene (1 of 3 + reward_choices) placed through StrandView "place". SKIP = +1 run reagent.
## Shared pickers (used by the shop, events and the needle):
##   await RewardView.pick_gene(parent, offers, title, skip_reward) -> id or ""
##   await RewardView.pick_adapt(parent, ids, title, allow_skip) -> id or ""

const RestView := preload("res://scripts/run/rest_view.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")
const GeneArt := preload("res://scripts/run/gene_art.gd")

const SKIP_REAGENT := 1


static func open(parent: Node, pending: Dictionary) -> void:
	var kind: String = String(pending.get("kind", "fight"))
	var enemy: String = String(pending.get("enemy", ""))
	var foe := ""
	if Cards.ENEMIES.has(enemy):
		var e: Dictionary = Cards.enemy(enemy)
		foe = String(e.get("name", enemy.to_upper()))
	Sfx.play("reward")
	if foe != "":
		UI.toast("%s DISSOLVED" % foe, UI.C_INK)
	if kind == "elite" or kind == "event" or bool(pending.get("event", false)):
		var ids: Array = Adapt.offers(3 + Adapt.mod("reward_choices"), "common", Adapt.owned())
		if randf() < 0.25:
			var rare: Array = Adapt.offers(1, "rare", Adapt.owned())
			if not rare.is_empty() and not ids.has(rare[0]):
				ids[ids.size() - 1] = rare[0]
		var got := await pick_adapt(parent, ids, "IT LEFT SOMETHING. TAKE ONE ADAPTATION.", true)
		if got != "":
			gain_adapt(got)
	var offers := gene_offers(3 + Adapt.mod("reward_choices"))
	var id := await pick_gene(parent, offers, "TAKE ONE GENE. OR SKIP: +%d REAGENT." % SKIP_REAGENT, SKIP_REAGENT)
	if id != "":
		await RestView.place_gene(parent, id)


static func gain_adapt(id: String) -> void:
	Adapt.gain(id)
	var info: Dictionary = Adapt.info(id)
	Sfx.play("adapt")
	UI.toast("ADAPTED: %s" % String(info.get("name", id.to_upper())), UI.C_ACCENT)


## n distinct reward genes. Cards.reward_offers gives 3 per call; extra calls fill the rest.
static func gene_offers(n: int) -> Array:
	var out: Array = []
	for k in 6:
		var batch: Array = Cards.reward_offers(Game.unlocked, Game.stage)
		for v in batch:
			var id := String(v)
			if not out.has(id) and out.size() < n:
				out.append(id)
		if out.size() >= n:
			break
	return out


## "LINK: ..." segment of a gene's desc (up to the next mode keyword), or "".
static func link_text(id: String) -> String:
	var desc := String(Cards.card(id).get("desc", ""))
	var at := desc.find("LINK:")
	if at < 0:
		return ""
	var seg := desc.substr(at)
	for kw in [" LOUD:", " QUIET:", " FIRST:", " DORMANT:"]:
		var cut := seg.find(kw)
		if cut > 0:
			seg = seg.left(cut)
	return seg.strip_edges()


## Where the gene links best in the current strand: after the cheapest active gene
## (the one you can always express first).
static func link_hint(id: String) -> String:
	var lt := link_text(id)
	if lt == "":
		return "No LINK bonus. Order matters less."
	var s: Array = Game.run.get("strand", [])
	var best := ""
	var best_cost := 99
	for v in s:
		var gid := String(v)
		var c: Dictionary = Cards.card(gid)
		if String(c.get("kind", "gene")) != "gene":
			continue
		var cost: int = int(c.get("cost", 0))
		if cost < best_cost:
			best_cost = cost
			best = gid
	if best == "":
		return lt
	return "%s LINKS BEST AFTER %s (COST %d)." % [lt, StrandView.gene_name(best), best_cost]


static func gene_row(id: String, price := -1) -> Dictionary:
	var c: Dictionary = Cards.card(id)
	var right := "PASSIVE" if String(c.get("kind", "")) == "passive" else "COST %d" % int(c.get("cost", 0))
	if price >= 0:
		right = "%d REAGENT" % price
	var tag := String(c.get("rarity", "common")).to_upper()
	if Cards.is_green(id):
		tag = "GREEN. +1 UPTAKE EACH USE"
	var row := {
		"label": StrandView.gene_name(id),
		"right": right,
		"detail": "%s  %s" % [String(c.get("short", "")), tag],
		"desc": RestView.gene_line(id) + "\n" + link_hint(id),
		"swatch": GeneArt.gene_color(id),
	}
	if Cards.is_green(id):
		row["color"] = UI.C_GREEN
	return row


static func adapt_row(id: String, price := -1) -> Dictionary:
	var info: Dictionary = Adapt.info(id)
	var rarity := String(info.get("rarity", "common"))
	var col := UI.C_ACCENT
	if rarity == "rare":
		col = UI.C_WARN
	elif rarity == "cursed":
		col = UI.C_BAD
	return {
		"label": String(info.get("name", id.to_upper())),
		"right": ("%d REAGENT" % price) if price >= 0 else rarity.to_upper(),
		"detail": rarity.to_upper() + (". KEPT ALL RUN" if rarity != "cursed" else ". CANNOT BE REMOVED"),
		"desc": String(info.get("desc", "")),
		"icon": Adapt.icon(id),
		"icon_color": col,
	}


static func pick_gene(parent: Node, offers: Array, head: String, skip_reward := 0) -> String:
	if offers.is_empty():
		return ""
	var rows: Array = []
	for v in offers:
		rows.append(gene_row(String(v)))
	if skip_reward > 0:
		rows.append({"label": "SKIP", "right": "+%d REAGENT" % skip_reward,
			"desc": "Leave the genes. Run reagent +%d (now %d)." % [skip_reward, int(Game.run.get("reagent", 0))]})
	else:
		rows.append({"label": "SKIP", "right": "NOTHING", "desc": "Take nothing."})
	var i: int = await RestView.new().choose(parent, rows, {"title": head, "flip": true, "cancel": false})
	if i < 0 or i >= offers.size():
		if skip_reward > 0:
			RestView.add_reagent(skip_reward)
			UI.toast("+%d REAGENT" % skip_reward)
		return ""
	Sfx.play("pickup")
	return String(offers[i])


static func pick_adapt(parent: Node, ids: Array, head: String, allow_skip := true) -> String:
	if ids.is_empty():
		return ""
	var rows: Array = []
	for v in ids:
		rows.append(adapt_row(String(v)))
	if allow_skip:
		rows.append({"label": "LEAVE IT", "right": "NOTHING", "desc": "Take no adaptation."})
	var i: int = await RestView.new().choose(parent, rows, {"title": head, "flip": true, "cancel": false})
	if i < 0 or i >= ids.size():
		return ""
	return String(ids[i])
