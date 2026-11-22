extends RefCounted
## INJECTION (design §13): injection sites, dose tiers, the opts merge for
## Game.start_run(region, opts), and the track marks left on the body.
##
## Site opts use the start_run keys directly, plus two relative keys that
## build_opts() resolves against the dose:
##   "max_delta"    int  added to the dose's max_colony
##   "colony_delta" int  starting Colony relative to that max

const MISS_FRAY := 1
const MISS_COLONY := 3

## view: which close-up the site is drawn on (body_map draws these).
## at: crosshair on that close-up (art space 196x200).
## spot: where its track mark sits on the 3D body (body-local).
const SITES := {
	"wound": [
		{"id": "cut", "name": "THE CUT", "view": "hand", "at": Vector2(98, 148),
			"spot": Vector3(0.42, 0.74, 0.045),
			"desc": "The palm. The first way in. No change.", "opts": {}},
		{"id": "knuckle", "name": "KNUCKLE", "view": "hand", "at": Vector2(89, 108),
			"spot": Vector3(0.41, 0.685, 0.045),
			"desc": "Enter deeper: start on row 2. -6 COLONY.",
			"opts": {"start_row": 1, "colony_delta": -6}},
		{"id": "nail", "name": "UNDER THE NAIL", "view": "hand", "at": Vector2(111, 29),
			"spot": Vector3(0.435, 0.67, 0.045),
			"desc": "+1 FRAY. Carry a free CLOTTER booster.",
			"opts": {"fray": 1, "boosters": ["clotter"]}},
	],
	"rivers": [
		{"id": "forearm", "name": "FOREARM VEIN", "view": "arm", "at": Vector2(126, 104),
			"spot": Vector3(-0.39, 0.98, 0.07),
			"desc": "The median vein. Wide, easy. No change.", "opts": {}},
		{"id": "jugular", "name": "JUGULAR", "view": "neck", "at": Vector2(126, 88),
			"spot": Vector3(0.04, 1.6, 0.065),
			"desc": "Start on row 2. -8 COLONY. +1 UPTAKE.",
			"opts": {"start_row": 1, "colony_delta": -8, "uptake": 1}},
		{"id": "wrist", "name": "WRIST", "view": "arm", "at": Vector2(44, 110),
			"spot": Vector3(-0.41, 0.83, 0.07),
			"desc": "+6 MAX COLONY. +1 FRAY.",
			"opts": {"max_delta": 6, "fray": 1}},
	],
	"hollow": [
		{"id": "intercostal", "name": "INTERCOSTAL", "view": "chest", "at": Vector2(66, 118),
			"spot": Vector3(0.14, 1.29, 0.145),
			"desc": "Between the ribs. No change.", "opts": {}},
		{"id": "collarbone", "name": "UNDER THE COLLARBONE", "view": "neck", "at": Vector2(52, 164),
			"spot": Vector3(-0.13, 1.5, 0.145),
			"desc": "PRIMER +1: fights open on a HELD chain. +1 UPTAKE.",
			"opts": {"primer": 1, "uptake": 1}},
		{"id": "throat", "name": "THE THROAT", "view": "neck", "at": Vector2(98, 116),
			"spot": Vector3(0.0, 1.62, 0.065),
			"desc": "Start with 1 extra gene: HYMN.",
			"opts": {"genes": ["hymn"]}},
	],
	"archive": [
		{"id": "temple", "name": "THE TEMPLE", "view": "head", "at": Vector2(52, 78),
			"spot": Vector3(0.12, 1.88, 0.145),
			"desc": "Thin bone. No change.", "opts": {}},
		{"id": "eye", "name": "BEHIND THE EYE", "view": "head", "at": Vector2(78, 92),
			"spot": Vector3(-0.06, 1.84, 0.145),
			"desc": "Start on row 2. All FADED genes readable this run.",
			"opts": {"start_row": 1, "unfade": true}},
		{"id": "skull", "name": "BASE OF THE SKULL", "view": "head", "at": Vector2(150, 166),
			"spot": Vector3(0.145, 1.7, 0.02),
			"desc": "+1 random rare ADAPTATION. +2 FRAY.",
			"opts": {"adapt_rare": 1, "fray": 2}},
	],
	"root": [
		{"id": "heart", "name": "THE HEART", "view": "chest", "at": Vector2(112, 104),
			"spot": Vector3(-0.07, 1.38, 0.145),
			"desc": "Through the sternum. Straight in. No change.", "opts": {}},
	],
}

const DOSES := [
	{"id": "trace", "name": "TRACE", "desc": "MAX COLONY 24. Nothing else.",
		"opts": {"max_colony": 24}},
	{"id": "dose", "name": "DOSE", "desc": "MAX COLONY 30.",
		"opts": {"max_colony": 30}},
	{"id": "bolus", "name": "BOLUS", "desc": "MAX COLONY 38. +1 FRAY. +1 UPTAKE.",
		"opts": {"max_colony": 38, "fray": 1, "uptake": 1}},
]

const INT_KEYS := ["fray", "uptake", "primer", "adapt_rare"]
const ARRAY_KEYS := ["boosters", "adapt", "genes"]


static func sites(region: String) -> Array:
	return SITES.get(region, SITES["root"])


static func site(region: String, id: String) -> Dictionary:
	for s in sites(region):
		var d: Dictionary = s
		if String(d["id"]) == id:
			return d
	var first: Dictionary = sites(region)[0]
	return first


static func dose(id: String) -> Dictionary:
	for d in DOSES:
		var dd: Dictionary = d
		if String(dd["id"]) == id:
			return dd
	var mid: Dictionary = DOSES[1]
	return mid


## The full Game.start_run opts for this site + dose. A blown vein costs
## MISS_FRAY and MISS_COLONY.
static func build_opts(region: String, site_id: String, dose_id: String, blown: bool) -> Dictionary:
	var so: Dictionary = site(region, site_id).get("opts", {})
	var dop: Dictionary = dose(dose_id).get("opts", {})
	var out := {"site": site_id}
	var mx: int = int(dop.get("max_colony", 30)) + int(so.get("max_delta", 0))
	mx = maxi(1, mx)
	out["max_colony"] = mx
	var col: int = mx + int(so.get("colony_delta", 0))
	for k in INT_KEYS:
		var n: int = int(so.get(k, 0)) + int(dop.get(k, 0))
		if n != 0:
			out[k] = n
	var row: int = maxi(int(so.get("start_row", 0)), int(dop.get("start_row", 0)))
	if row > 0:
		out["start_row"] = row
	for k in ARRAY_KEYS:
		var arr: Array = []
		arr.append_array(so.get(k, []))
		arr.append_array(dop.get(k, []))
		if not arr.is_empty():
			out[k] = arr
	if bool(so.get("unfade", false)) or bool(dop.get("unfade", false)):
		out["unfade"] = true
	if blown:
		out["fray"] = int(out.get("fray", 0)) + MISS_FRAY
		col -= MISS_COLONY
	out["colony"] = clampi(col, 1, mx)
	return out


# ------------------------------------------------------------ track marks

static func marks() -> Array:
	var m: Variant = Game.flags.get("marks", [])
	if m is Array:
		return m
	return []


static func add_mark(region: String, site_id: String, blown: bool) -> void:
	var m: Variant = Game.flags.get("marks", null)
	if not (m is Array):
		m = []
		Game.flags["marks"] = m
	(m as Array).append({"region": region, "site": site_id, "day": Game.day, "blown": blown})


## "fresh" / "old" / "bruise" / "old_bruise"
static func mark_age(mark: Dictionary) -> String:
	var old: bool = Game.day - int(mark.get("day", Game.day)) >= 2
	if bool(mark.get("blown", false)):
		return "old_bruise" if old else "bruise"
	return "old" if old else "fresh"


static func mark_color(mark: Dictionary) -> Color:
	match mark_age(mark):
		"fresh":
			return Color("a82020")
		"old":
			return Color("7a6030")
		"bruise":
			return Color("4a2850")
		_:
			return Color("5a5a2c")


## Body-local 3D spot for the mark; repeated marks at one site scatter a little.
static func mark_spot(mark: Dictionary, index: int) -> Vector3:
	var s := site(String(mark.get("region", "wound")), String(mark.get("site", "")))
	var p: Vector3 = s.get("spot", Vector3(0.42, 0.74, 0.045))
	var h := hash("%d:%s" % [index, String(mark.get("site", ""))])
	var dx := float(h % 7 - 3) * 0.006
	var dy := float((h / 7) % 7 - 3) * 0.006
	return p + Vector3(dx, dy, 0.003)
