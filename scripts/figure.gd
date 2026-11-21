class_name Figure
extends RefCounted
## Articulated blocky human (lab hub, cutscenes, endings) on a 32-unit grid with classic
## block-character proportions: 8-cube head, 8x12x4 trunk, 4x12x4 arms and legs, limbs
## flush against the trunk. Clean boxes only: no face, no props, no trinkets.
## build() returns a Node3D whose origin is at the feet, facing -Z (Godot forward).
## Direct children (all pivots, posed by pose() / walk() / idle()):
##   "LegL"/"LegR"  hip pivots       -> "ThighL", "KneeL" (knee pivot) -> "ShinL", "ShoeL"
##   "Body"         trunk pivot at the hip centre -> "Torso",
##                  "CoatTailL"/"CoatTailR" (waist pivots) -> "FlapL"/"FlapR"
##   "Head"         neck pivot       -> "Skull", "HairTop", "HairBack"
##   "ArmL"/"ArmR"  shoulder pivots  -> "UpperArmL", "ElbowL" (elbow pivot) ->
##                  "SleeveL", "WristL", "HandL"
## Limbs hang along -Y from their pivots; +rotation.x swings a limb forward.
## The LEFT arm carries the infection (see infect()).

const SKIN := Color("d8a888")
const COAT := Color("e8ecec")
const TROUSERS := Color("2c3440")
const HAIR := Color("3a2a20")
const SHOES := Color("1c1a1a")
const GREEN := Color("58d040")
const LEFT_GREEN := Color("70d850")

const U := 0.5 / 12.0  ## one grid unit: legs are 12 units tall
const HIP_Y := 12.0 * U
const HIP_W := 2.0 * U
const THIGH := 6.0 * U
const SHIN := 6.0 * U  ## knee to sole
const SHOULDER := Vector3(6.0 * U, 10.0 * U, 0.0)  ## from the trunk pivot
const NECK := Vector3(0.0, 12.0 * U, 0.0)  ## from the trunk pivot


static func build(coat := COAT, left_hand := SKIN, hair := HAIR, trousers := TROUSERS) -> Node3D:
	var root := Node3D.new()
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sfx := "L" if i == 0 else "R"
		var leg := _pivot(root, "Leg" + sfx, Vector3(HIP_W * side, HIP_Y, 0.0))
		# Each lower segment starts inside the one above so bends never open a gap;
		# lower segments are a hair narrower so the overlaps never z-fight.
		_part(leg, "Thigh" + sfx, Vector3(4.0, 6.5, 4.0) * U, trousers, Vector3(0.0, -2.75, 0.0) * U)
		var knee := _pivot(leg, "Knee" + sfx, Vector3(0.0, -THIGH, 0.0))
		_part(knee, "Shin" + sfx, Vector3(3.9, 5.5, 3.9) * U, trousers.darkened(0.08), Vector3(0.0, -2.25, 0.0) * U)
		_part(knee, "Shoe" + sfx, Vector3(4.1, 1.0, 4.6) * U, SHOES, Vector3(0.0, -5.5, -0.3) * U)

	var body := _pivot(root, "Body", Vector3(0.0, HIP_Y, 0.0))
	_part(body, "Torso", Vector3(8.0, 12.0, 4.0) * U, coat, Vector3(0.0, 6.0, 0.0) * U)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sfx := "L" if i == 0 else "R"
		# Coat skirt over each thigh, a touch wider and deeper than the leg.
		var tail := _pivot(body, "CoatTail" + sfx, Vector3(2.2 * side, 0.0, 0.0) * U)
		_part(tail, "Flap" + sfx, Vector3(4.4, 6.0, 4.4) * U, coat.darkened(0.04), Vector3(0.0, -2.0, 0.0) * U)

	var head := _pivot(root, "Head", Vector3(0.0, HIP_Y + NECK.y, 0.0))
	_part(head, "Skull", Vector3(8.0, 8.0, 8.0) * U, SKIN, Vector3(0.0, 4.0, 0.0) * U)
	_part(head, "HairTop", Vector3(8.5, 2.5, 8.5) * U, hair, Vector3(0.0, 7.0, 0.0) * U)
	_part(head, "HairBack", Vector3(8.5, 5.0, 1.2) * U, hair, Vector3(0.0, 4.5, 3.65) * U)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sfx := "L" if i == 0 else "R"
		var arm := _pivot(root, "Arm" + sfx, Vector3(SHOULDER.x * side, HIP_Y + SHOULDER.y, 0.0))
		_part(arm, "UpperArm" + sfx, Vector3(4.0, 6.0, 4.0) * U, coat.darkened(0.06), Vector3(0.0, -1.0, 0.0) * U)
		var elbow := _pivot(arm, "Elbow" + sfx, Vector3(0.0, -4.0, 0.0) * U)
		_part(elbow, "Sleeve" + sfx, Vector3(3.9, 4.5, 3.9) * U, coat.darkened(0.06), Vector3(0.0, -1.75, 0.0) * U)
		var hand_col: Color = left_hand if i == 0 else SKIN
		_part(elbow, "Wrist" + sfx, Vector3(3.9, 0.5, 3.9) * U, SKIN.lerp(hand_col, 0.6), Vector3(0.0, -4.25, 0.0) * U)
		_part(elbow, "Hand" + sfx, Vector3(4.0, 1.5, 4.0) * U, hand_col, Vector3(0.0, -5.25, 0.0) * U)
	pose(root, 0.0, 0.0)
	return root


## Simple walk cycle; call every frame with accumulated time while moving.
static func walk(fig: Node3D, t: float, amount := 1.0) -> void:
	pose(fig, t * 9.0, amount, 0.0, t)


## Standing pose. Pass accumulated time `t` every frame for the idle breath;
## `limp` > 0 adds the sick sway.
static func idle(fig: Node3D, t := 0.0, limp := 0.0) -> void:
	pose(fig, 0.0, 0.0, limp, t)


## Full-body pose. `phase`: stride angle in radians (one stride per TAU, left leg
## forward at PI/2). `amount`: 0 standing .. 1 full walk. `limp`: 0..1, the left
## leg drags and buckles, the trunk lurches over it and hunches. `breath`: seconds,
## drives the idle breath and the standing sway. Never touches the root transform.
static func pose(fig: Node3D, phase: float, amount := 1.0, limp := 0.0, breath := 0.0) -> void:
	var s := sin(phase)
	var c := cos(phase)
	var w := maxf(amount, 0.0)
	var lw := clampf(limp, 0.0, 1.0)
	var still := 1.0 - minf(w, 1.0)
	var swing := 0.5 * w

	# Legs: hips swing; a knee folds while its leg travels forward (c > 0 for the left).
	# The bad left leg swings short, stays stiff in the air and buckles under weight.
	var hip_l := s * swing * (1.0 - 0.45 * lw)
	var hip_r := -s * swing
	var knee_l := -(0.1 + maxf(c, 0.0) * 0.85 * (1.0 - 0.6 * lw) + maxf(-c, 0.0) * 0.4 * lw) * w
	var knee_r := -(0.1 + maxf(-c, 0.0) * 0.85) * w

	# Bob: drop the trunk so the lower sole stays on the floor.
	var drop_l := THIGH * cos(hip_l) + SHIN * cos(hip_l + knee_l)
	var drop_r := THIGH * cos(hip_r) + SHIN * cos(hip_r + knee_r)
	var hip_y := HIP_Y + maxf(drop_l, drop_r) - (THIGH + SHIN)

	# Trunk: forward lean, counter-twist, breath, and the lurch over the bad leg.
	var b := sin(breath * 2.2)
	var lift := b * 0.007 * (0.4 + still)
	var lurch := lw * (0.1 * w * -c + 0.05 * w * sin(phase * 0.37 + 1.3) + 0.03 * still * sin(breath * 0.9 + 0.7))
	var rx := -0.05 * w - 0.08 * lw + b * 0.015 * still
	var ry := s * 0.08 * w
	var rz := lurch

	var leg_l: Node3D = fig.get_node("LegL")
	var leg_r: Node3D = fig.get_node("LegR")
	leg_l.position = Vector3(-HIP_W, hip_y, 0.0)
	leg_r.position = Vector3(HIP_W, hip_y, 0.0)
	leg_l.rotation = Vector3(hip_l, 0.0, 0.0)
	leg_r.rotation = Vector3(hip_r, 0.0, 0.0)
	var knee_ln: Node3D = leg_l.get_node("KneeL")
	var knee_rn: Node3D = leg_r.get_node("KneeR")
	knee_ln.rotation = Vector3(knee_l, 0.0, 0.0)
	knee_rn.rotation = Vector3(knee_r, 0.0, 0.0)

	var body: Node3D = fig.get_node("Body")
	body.position = Vector3(0.0, hip_y + lift, 0.0)
	body.rotation = Vector3(rx, ry, rz)
	var trunk := Transform3D(Basis.from_euler(Vector3(rx, ry, rz)), body.position)

	# Coat tails: follow the thighs part way, lag and flare with the stride.
	var sway := c * 0.06 * w
	var flare := 0.04 * w
	var tail_l: Node3D = body.get_node("CoatTailL")
	var tail_r: Node3D = body.get_node("CoatTailR")
	tail_l.rotation = Vector3((hip_l - rx) * 0.6 + sway, 0.0, -flare - rz * 0.6)
	tail_r.rotation = Vector3((hip_r - rx) * 0.6 - sway, 0.0, flare - rz * 0.6)

	# Arms: opposite to the legs; the infected left arm hangs and dangles under a limp.
	var out := 0.015 + b * 0.008 * still
	var arm_l: Node3D = fig.get_node("ArmL")
	var arm_r: Node3D = fig.get_node("ArmR")
	arm_l.position = trunk * Vector3(-SHOULDER.x, SHOULDER.y, 0.0)
	arm_r.position = trunk * Vector3(SHOULDER.x, SHOULDER.y, 0.0)
	var swing_l := -s * swing * 0.8 * (1.0 - 0.5 * lw) + lw * 0.1 * c * w
	var swing_r := s * swing * 0.8 * (1.0 + 0.3 * lw)
	arm_l.rotation = Vector3(swing_l + rx, 0.0, -out + rz)
	arm_r.rotation = Vector3(swing_r + rx, 0.0, out + rz)
	var elbow_l: Node3D = arm_l.get_node("ElbowL")
	var elbow_r: Node3D = arm_r.get_node("ElbowR")
	elbow_l.rotation = Vector3((0.12 + maxf(-s, 0.0) * 0.55 * w) * (1.0 - 0.5 * lw), 0.0, 0.0)
	elbow_r.rotation = Vector3(0.12 + maxf(s, 0.0) * 0.55 * w, 0.0, 0.0)

	# Head: rides the neck, steadies against the trunk, droops when sick.
	var head: Node3D = fig.get_node("Head")
	head.position = trunk * NECK
	head.rotation = Vector3(rx * 0.4 - 0.08 * lw + b * 0.01 * still, ry * 0.3, rz * 0.5 + lw * 0.04 * sin(breath * 0.6))


## Infection level of the left hand for a given stage (0..1).
static func infect_level(stage: int) -> float:
	if stage <= 0:
		return 0.18
	return clampf(float(stage) / 5.0, 0.0, 1.0)


## Tints the LEFT hand by infection stage and grows the green up the wrist,
## forearm and, late, the upper arm. Calling again restages (old stains removed).
## Returns the hand's own material (animate "albedo" / "emission" for pulses).
static func infect(fig: Node3D, stage: int) -> ShaderMaterial:
	for n in fig.get_meta("stains", []):
		if is_instance_valid(n):
			var old := n as Node
			old.get_parent().remove_child(old)
			old.queue_free()
	var stains: Array[Node] = []
	var arm: Node3D = fig.get_node("ArmL")
	var elbow: Node3D = arm.get_node("ElbowL")
	var hand: MeshInstance3D = elbow.get_node("HandL")
	var k := infect_level(stage)
	var m := Retro.mat_unique(SKIN.lerp(LEFT_GREEN, k))
	hand.material_override = m
	var wrist: MeshInstance3D = elbow.get_node("WristL")
	wrist.material_override = Retro.mat(SKIN.lerp(LEFT_GREEN, k * 0.8))
	var vein := GREEN.darkened(0.25)
	var deep := GREEN.darkened(0.4)
	if stage >= 1:
		# A line across the back of the hand (it faces outward, -X).
		stains.append(_part(hand, "StainHand", Vector3(0.2, 1.2, 2.0) * U, vein, Vector3(-2.05, 0.0, 0.0) * U))
	if stage >= 2:
		# Soaked through the cuff.
		stains.append(_part(elbow, "StainCuff", Vector3(4.1, 1.2, 4.1) * U, GREEN.darkened(0.2), Vector3(0.0, -3.4, 0.0) * U))
	if stage == 2:
		stains.append(_part(elbow, "StainVein", Vector3(1.0, 2.0, 0.2) * U, vein, Vector3(0.6, -1.8, -2.0) * U))
	if stage >= 3:
		# The whole forearm, front and outer side.
		stains.append(_part(elbow, "StainFore", Vector3(1.2, 3.5, 0.2) * U, deep, Vector3(0.4, -1.5, -2.0) * U))
		stains.append(_part(elbow, "StainForeSide", Vector3(0.2, 3.0, 1.6) * U, deep, Vector3(-2.0, -1.8, 0.4) * U))
	if stage >= 4:
		# Past the elbow.
		stains.append(_part(arm, "StainUpper", Vector3(1.2, 5.0, 0.2) * U, deep, Vector3(0.4, -1.3, -2.05) * U))
		stains.append(_part(arm, "StainUpperSide", Vector3(0.2, 5.0, 1.6) * U, deep, Vector3(-2.05, -1.2, 0.4) * U))
	if stage >= 5:
		stains.append(_part(arm, "StainShoulder", Vector3(4.2, 2.2, 4.2) * U, deep, Vector3(0.0, 1.0, 0.0) * U))
	fig.set_meta("stains", stains)
	return m


static func _pivot(parent: Node3D, pivot_name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = pivot_name
	p.position = pos
	parent.add_child(p)
	return p


static func _part(parent: Node3D, part_name: String, size: Vector3, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := Retro.box(size, col, pos)
	mi.name = part_name
	parent.add_child(mi)
	return mi
