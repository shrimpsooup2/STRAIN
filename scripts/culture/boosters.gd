extends RefCounted
## Boosters: single-use mid-fight injections drawn up at the Culture bench.
## Carried in Game.culture.boosters (max 2) until a run starts, then in
## Game.run["boosters"]. Fx use the player FX schema (cards.gd, design §1/§9).
##
## Fields: name (≤8 chars), desc, fx (player fx), cost ({material: n}), color.

const MAX_CARRIED := 2

const BOOSTERS := {
	"saline": {"name": "SALINE", "desc": "Regain 10 Colony.",
		"fx": [{"t": "heal", "n": 10}], "cost": {"plasma": 1}, "color": Color("e888b0")},
	"clotter": {"name": "CLOTTER", "desc": "Gain 12 Film.",
		"fx": [{"t": "film", "n": 12}], "cost": {"clot": 1}, "color": Color("58a8e8")},
	"ligase": {"name": "LIGASE", "desc": "CHAIN +2. Before any gene: first one HELD x2.",
		"fx": [{"t": "prime", "n": 2}], "cost": {"alveoli": 1}, "color": Color("e8c840")},
	"blank": {"name": "BLANK", "desc": "Pull 2 genes into the window. 2 Splices.",
		"fx": [{"t": "pull", "n": 2}, {"t": "splice", "n": 2}], "cost": {"myelin": 1}, "color": Color("b0b8c8")},
	"adrenal": {"name": "ADRENAL", "desc": "+2 Charge now.",
		"fx": [{"t": "charge", "n": 2}], "cost": {"clot": 1, "plasma": 1}, "color": Color("e8a040")},
	"suture": {"name": "SUTURE", "desc": "Clear every SEVER, GNAW, KNOT mark. +6 Film.",
		"fx": [{"t": "unmark"}, {"t": "film", "n": 6}], "cost": {"myelin": 1, "alveoli": 1}, "color": Color("a8d0f0")},
	"lancet": {"name": "LANCET", "desc": "Deal 12. Double against a wind-up.",
		"fx": [{"t": "stagger_dmg", "n": 12}], "cost": {"clot": 2}, "color": Color("e06048")},
	"steady": {"name": "STEADY", "desc": "Fray -2.",
		"fx": [{"t": "fray", "n": -2}], "cost": {"myelin": 2}, "color": Color("9888c0")},
}


## The booster's data, or a harmless stub for an unknown id.
static func info(id: String) -> Dictionary:
	if BOOSTERS.has(id):
		return BOOSTERS[id]
	return {"name": id.to_upper().left(8), "desc": "", "fx": [], "cost": {}, "color": Color("b0b8c8")}
