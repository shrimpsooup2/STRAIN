extends RefCounted
## LESION node: a shop paid in run reagent.
##   await ShopView.open(parent, key)    key = "row_col"; stock is kept in Game.run["shop"][key]
## Stock: 3 genes (3-5 by rarity), 2 adaptations (6 common / 9 rare), and three services,
## each once: EXCISE 4, ENRICH 4, MEND +10 Colony for 2. Adapt.mod("shop_discount") takes
## that much off every price (min 1). Unspent run reagent is banked when the run ends.

const RestView := preload("res://scripts/run/rest_view.gd")
const RewardView := preload("res://scripts/run/reward_view.gd")
const StrandView := preload("res://scripts/run/strand_view.gd")

const GENE_PRICE := {"common": 3, "uncommon": 4, "rare": 5}
const ADAPT_PRICE := {"common": 6, "rare": 9, "cursed": 4}
const EXCISE_PRICE := 4
const ENRICH_PRICE := 4
const MEND_PRICE := 2
const MEND_N := 10


static func price(base: int) -> int:
	return maxi(1, base - Adapt.mod("shop_discount"))


static func stock(key: String) -> Array:
	if not Game.run.has("shop"):
		Game.run["shop"] = {}
	var shops: Dictionary = Game.run["shop"]
	if shops.has(key):
		return shops[key]
	var items: Array = []
	for id in RewardView.gene_offers(3):
		var r := String(Cards.card(String(id)).get("rarity", "common"))
		items.append({"kind": "gene", "id": String(id), "price": int(GENE_PRICE.get(r, 3)), "sold": false})
	var ads: Array = Adapt.offers(1, "common", Adapt.owned())
	var rare: Array = Adapt.offers(1, "rare", Adapt.owned() + ads)
	if rare.is_empty():
		rare = Adapt.offers(1, "common", Adapt.owned() + ads)
	ads.append_array(rare)
	for id in ads:
		var rar := String(Adapt.info(String(id)).get("rarity", "common"))
		items.append({"kind": "adapt", "id": String(id), "price": int(ADAPT_PRICE.get(rar, 6)), "sold": false})
	items.append({"kind": "excise", "id": "", "price": EXCISE_PRICE, "sold": false})
	items.append({"kind": "enrich", "id": "", "price": ENRICH_PRICE, "sold": false})
	items.append({"kind": "mend", "id": "", "price": MEND_PRICE, "sold": false})
	shops[key] = items
	return items


static func _row(it: Dictionary, money: int) -> Dictionary:
	var kind := String(it["kind"])
	var cost := price(int(it["price"]))
	var row: Dictionary = {}
	match kind:
		"gene":
			row = RewardView.gene_row(String(it["id"]), cost)
		"adapt":
			row = RewardView.adapt_row(String(it["id"]), cost)
		"excise":
			var n: int = RestView.strand().size()
			row = {"label": "EXCISE", "right": "%d REAGENT" % cost, "detail": "CUT ONE GENE. ONCE.",
				"desc": "Remove one gene from the strand (%d genes now, min %d). PACT genes cost Colony." % [n, RestView.MIN_STRAND]}
			if n <= RestView.MIN_STRAND:
				row["disabled"] = true
		"enrich":
			row = {"label": "ENRICH", "right": "%d REAGENT" % cost, "detail": "UPGRADE ONE GENE. ONCE.",
				"desc": "Upgrade one gene. You see it before and after, then confirm."}
			if RestView.upgradable().is_empty():
				row["disabled"] = true
		"mend":
			var col: int = int(Game.run.get("colony", 0))
			var mx: int = int(Game.run.get("max_colony", 1))
			row = {"label": "MEND", "right": "%d REAGENT" % cost, "detail": "+%d COLONY. ONCE." % MEND_N,
				"desc": "Colony %d > %d (max %d)." % [col, mini(mx, col + MEND_N), mx]}
			if col >= mx:
				row["disabled"] = true
	if bool(it.get("sold", false)):
		row["right"] = "TAKEN"
		row["disabled"] = true
	elif cost > money:
		row["disabled"] = true
		row["desc"] = String(row.get("desc", "")) + "\nNEEDS %d REAGENT. YOU HAVE %d." % [cost, money]
	return row


static func open(parent: Node, key: String) -> void:
	Sfx.play("shop")
	await UI.say(["A lesion, open and soft. Things drift in it.",
		"Reagent buys what floats here."], "see")
	var items := stock(key)
	var cursor := 0
	while true:
		var money: int = int(Game.run.get("reagent", 0))
		var rows: Array = []
		for v in items:
			var it: Dictionary = v
			rows.append(_row(it, money))
		rows.append({"label": "LEAVE", "right": "", "desc": "Close the lesion behind you."})
		var head := "LESION. REAGENT %d. BANKED AFTER RUN: %d" % [money, money]
		var foot := "RUN LOST: HALF BANKS (%d)." % (money / 2)
		if Adapt.mod("shop_discount") > 0:
			foot += " DISCOUNT -%d EACH." % Adapt.mod("shop_discount")
		var i: int = await RestView.new().choose(parent, rows, {"title": head, "cursor": cursor, "footer": foot})
		if i < 0 or i >= items.size():
			Sfx.play("cancel")
			Game.save_game()
			return
		cursor = i
		var it: Dictionary = items[i]
		var cost := price(int(it["price"]))
		var bought := false
		match String(it["kind"]):
			"gene":
				await RestView.place_gene(parent, String(it["id"]))
				bought = true
			"adapt":
				RewardView.gain_adapt(String(it["id"]))
				bought = true
			"excise":
				bought = await RestView.excise(parent)
			"enrich":
				bought = await RestView.enrich(parent)
			"mend":
				RestView.heal(MEND_N)
				bought = true
		if bought:
			it["sold"] = true
			RestView.add_reagent(-cost)
			Sfx.play("shop")
			UI.toast("-%d REAGENT" % cost, UI.C_WARN)
			Game.save_game()
