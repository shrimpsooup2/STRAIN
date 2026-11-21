extends RefCounted
## Tissue banked from runs (Game.materials): names, vial colours, and
## {material: n} cost helpers shared by the Culture bench stations.

const MATS := ["clot", "plasma", "alveoli", "myelin"]
const NAMES := {"clot": "CLOT", "plasma": "PLASMA", "alveoli": "ALVEOLI", "myelin": "MYELIN"}
const SHORT := {"clot": "CLOT", "plasma": "PLAS", "alveoli": "ALVE", "myelin": "MYEL"}
const COLORS := {"clot": Color("b8303c"), "plasma": Color("e8c070"),
	"alveoli": Color("e8a0b8"), "myelin": Color("dcd8f0")}
const SOURCE := {"clot": "THE WOUND", "plasma": "THE RIVERS",
	"alveoli": "THE HOLLOW", "myelin": "THE ARCHIVE"}
const C_REAGENT := Color("58d0a8")


static func have(m: String) -> int:
	return int(Game.materials.get(m, 0))


static func color(m: String) -> Color:
	if COLORS.has(m):
		return COLORS[m]
	return Color("b0b8c8")


static func mat_name(m: String) -> String:
	return String(NAMES.get(m, m.to_upper()))


## {material: missing amount} for everything the cost needs but you don't have.
static func lacking(cost: Dictionary) -> Dictionary:
	var out := {}
	for m in cost:
		var need: int = int(cost[m])
		var miss := need - have(String(m))
		if miss > 0:
			out[m] = miss
	return out


static func can_pay(cost: Dictionary) -> bool:
	return lacking(cost).is_empty()


## Spends the cost. Returns false (and spends nothing) if anything is short.
static func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for m in cost:
		Game.materials[m] = have(String(m)) - int(cost[m])
	return true


## "2 CLOT + 1 PLASMA". Empty cost reads "FREE".
static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for m in MATS:
		if cost.has(m) and int(cost[m]) > 0:
			parts.append("%d %s" % [int(cost[m]), mat_name(m)])
	for m in cost:
		if not MATS.has(m) and int(cost[m]) > 0:
			parts.append("%d %s" % [int(cost[m]), mat_name(String(m))])
	return "FREE" if parts.is_empty() else " + ".join(PackedStringArray(parts))


## Compact cost for a menu row: "2C 1P".
static func cost_short(cost: Dictionary) -> String:
	var parts: Array = []
	for m in cost:
		if int(cost[m]) > 0:
			parts.append("%d%s" % [int(cost[m]), String(m).left(1).to_upper()])
	return " ".join(PackedStringArray(parts))


## "LACK 1 CLOT, 2 MYELIN", or "" when affordable.
static func lack_text(cost: Dictionary) -> String:
	var miss := lacking(cost)
	if miss.is_empty():
		return ""
	var parts: Array = []
	for m in miss:
		parts.append("%d %s" % [int(miss[m]), mat_name(String(m))])
	return "LACK " + ", ".join(PackedStringArray(parts))
