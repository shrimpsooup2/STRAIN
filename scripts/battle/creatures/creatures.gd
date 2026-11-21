extends RefCounted
## Creature factory. Battle calls:
##   var e := Creatures.build(enemy_id, region, cap, elite, boss)
## Returns a positioned Node3D with the creature interface (set_count, flash,
## lunge, recoil, top, home, alive, windup, stagger, die, attack_anim).
## Unknown ids fall back to the old ColonyCluster (which lacks windup/stagger/
## die/attack_anim; guard with has_method).

const Base := preload("res://scripts/battle/creatures/creature_base.gd")
const Cluster := preload("res://scripts/battle/colony_cluster.gd")
const E_POS := Vector3(7.6, 0.4, -4.2)

const SCRIPTS := {
	"creeper": preload("res://scripts/battle/creatures/creeper.gd"),
	"knot": preload("res://scripts/battle/creatures/knot.gd"),
	"fester": preload("res://scripts/battle/creatures/fester.gd"),
	"scab": preload("res://scripts/battle/creatures/scab.gd"),
	"pod": preload("res://scripts/battle/creatures/pod.gd"),
	"current": preload("res://scripts/battle/creatures/current.gd"),
	"leech": preload("res://scripts/battle/creatures/leech.gd"),
	"undertow": preload("res://scripts/battle/creatures/undertow.gd"),
	"choir_cell": preload("res://scripts/battle/creatures/choir_cell.gd"),
	"bellows": preload("res://scripts/battle/creatures/bellows.gd"),
	"shroud": preload("res://scripts/battle/creatures/shroud.gd"),
	"choir": preload("res://scripts/battle/creatures/choir.gd"),
	"mimic": preload("res://scripts/battle/creatures/mimic.gd"),
	"eraser": preload("res://scripts/battle/creatures/eraser.gd"),
	"palimpsest": preload("res://scripts/battle/creatures/palimpsest.gd"),
	"archivist": preload("res://scripts/battle/creatures/archivist.gd"),
	"tendril": preload("res://scripts/battle/creatures/tendril.gd"),
	"core": preload("res://scripts/battle/creatures/core.gd"),
}

const HOME_REGION := {
	"creeper": "wound", "knot": "wound", "fester": "wound", "scab": "wound",
	"pod": "rivers", "current": "rivers", "leech": "rivers", "undertow": "rivers",
	"choir_cell": "hollow", "bellows": "hollow", "shroud": "hollow", "choir": "hollow",
	"mimic": "archive", "eraser": "archive", "palimpsest": "archive", "archivist": "archive",
	"tendril": "root", "core": "root",
}


static func build(enemy_id: String, region: String, cap: int, elite: bool, boss: bool) -> Node3D:
	if not SCRIPTS.has(enemy_id):
		var cl: Cluster = Cluster.new()
		cl.position = E_POS + Vector3(0, 0.06, 0)
		cl.setup(Color("58b848"), maxi(cap, 1), 0.5 if boss else 0.44, 7 if boss else 4, hash(enemy_id), Color("2c6a24"))
		return cl
	var reg := region
	if not Cards.REGION_COLORS.has(reg):
		var home_reg: String = HOME_REGION.get(enemy_id, "wound")
		reg = home_reg
	var scr: GDScript = SCRIPTS[enemy_id]
	var c: Base = scr.new()
	c.position = E_POS + Vector3(0, 0.06, 0)
	c.setup(reg, maxi(cap, 1), elite, boss)
	return c
