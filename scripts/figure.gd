class_name Figure
extends RefCounted
## Low-poly human built from boxes (used by cutscenes / endings).
## Returns a Node3D whose origin is at the feet, facing -Z (Godot forward).
## Child names: legs "LegL"/"LegR", arms "ArmL"/"ArmR", "Head", "Body".
## Arms/legs pivot at the top.

const SKIN := Color("d8a888")
const COAT := Color("e8ecec")
const TROUSERS := Color("2c3440")
const HAIR := Color("3a2a20")


static func build(coat := COAT, left_hand := SKIN, hair := HAIR, trousers := TROUSERS) -> Node3D:
	var root := Node3D.new()
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(0.1 * side, 0.5, 0)
		leg.add_child(Retro.box(Vector3(0.16, 0.5, 0.18), trousers, Vector3(0, -0.25, 0)))
		root.add_child(leg)
	var body := Retro.box(Vector3(0.44, 0.5, 0.26), coat, Vector3(0, 0.74, 0))
	body.name = "Body"
	root.add_child(body)
	# Coat tail.
	root.add_child(Retro.box(Vector3(0.46, 0.18, 0.28), coat.darkened(0.08), Vector3(0, 0.47, 0)))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.12, 0)
	head.add_child(Retro.box(Vector3(0.28, 0.28, 0.26), SKIN))
	head.add_child(Retro.box(Vector3(0.3, 0.1, 0.28), hair, Vector3(0, 0.14, 0.01)))
	head.add_child(Retro.box(Vector3(0.3, 0.2, 0.08), hair, Vector3(0, 0.04, 0.13)))
	root.add_child(head)
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(0.29 * side, 0.96, 0)
		arm.add_child(Retro.box(Vector3(0.13, 0.44, 0.15), coat, Vector3(0, -0.2, 0)))
		var hand_col: Color = left_hand if side < 0 else SKIN
		arm.add_child(Retro.box(Vector3(0.12, 0.12, 0.12), hand_col, Vector3(0, -0.47, 0)))
		root.add_child(arm)
	return root


## Simple walk cycle; call every frame with accumulated time while moving.
static func walk(fig: Node3D, t: float, amount := 1.0) -> void:
	var s := sin(t * 9.0) * 0.5 * amount
	fig.get_node("LegL").rotation.x = s
	fig.get_node("LegR").rotation.x = -s
	fig.get_node("ArmL").rotation.x = -s * 0.8
	fig.get_node("ArmR").rotation.x = s * 0.8


static func idle(fig: Node3D) -> void:
	for n in ["LegL", "LegR", "ArmL", "ArmR"]:
		fig.get_node(n).rotation.x = 0.0
