extends Node3D
## The human in the hub: a Figure on a 1-unit tile grid. Smooth tile steps,
## an articulated walk (knees, bob, coat sway), an idle breath, a limp from
## stage 3, a lying pose (floor / cot) and a left hand and forearm that turn
## green with the infection stage.

signal stepped(tile: Vector2i)

var tile := Vector2i.ZERO
var facing := Vector2i(0, 1)
var moving := false
var step_time := 0.2
var walkable: Callable  ## func(Vector2i) -> bool

var _fig: Node3D
var _pivot: Node3D
var _hand_mat: ShaderMaterial
var _hand_base := Color.WHITE
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _phase := 0.0
var _swing := 0.0
var _breath := 0.0
var _limp := 0.0  ## 0..1, from Game.stage 3


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_fig = Figure.build()
	_pivot.add_child(_fig)
	_limp = 0.0 if Game.stage < 3 else minf(1.0, 0.45 + 0.25 * float(Game.stage - 3))
	_set_left_hand()


## The left hand tint and the green climbing the wrist, forearm and arm by stage.
func _set_left_hand() -> void:
	_hand_base = Figure.SKIN.lerp(Figure.LEFT_GREEN, Figure.infect_level(Game.stage))
	_hand_mat = Figure.infect(_fig, Game.stage)


func place(t: Vector2i, dir := Vector2i(0, 1)) -> void:
	tile = t
	position = Vector3(t.x, 0, t.y)
	face(dir)


func face(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	facing = dir
	rotation.y = atan2(-float(dir.x), -float(dir.y))


func target_tile() -> Vector2i:
	return tile + facing


## Starts a one-tile step. Returns false (and just turns) if blocked.
func try_step(dir: Vector2i) -> bool:
	face(dir)
	if moving:
		return false
	var nt := tile + dir
	if walkable.is_valid() and not walkable.call(nt):
		return false
	_from = position
	_to = Vector3(nt.x, 0, nt.y)
	tile = nt
	_t = 0.0
	moving = true
	return true


func _process(dt: float) -> void:
	if moving:
		_t += dt / step_time
		_phase += dt / step_time * PI
		var k := minf(_t, 1.0)
		position = _from.lerp(_to, k)
		_swing = minf(1.0, _swing + dt * 10.0)
		if _t >= 1.0:
			moving = false
			position = _to
			stepped.emit(tile)
	else:
		_swing = maxf(0.0, _swing - dt * 8.0)
	_breath += dt
	Figure.pose(_fig, _phase, _swing, _limp, _breath)
	# Tremor in the idle hand once the shaking starts.
	if Game.stage >= 2 and _swing == 0.0:
		var arm: Node3D = _fig.get_node("ArmL")
		arm.rotation.z += sin(Time.get_ticks_msec() * 0.04) * 0.03 * Game.stage


## Lying flat on the back (floor / cot). `pos` is the hip point, `yaw_dir` where the feet point.
func lie(pos: Vector3, yaw_dir: Vector2i) -> void:
	face(yaw_dir)
	position = pos
	# Feet toward yaw_dir: rotate the figure onto its back.
	_pivot.rotation.x = PI / 2.0
	_pivot.position = Vector3(0, 0.16, -0.55)


## Gets up and stands on `t`. Awaitable.
func stand_up(t: Vector2i, dir: Vector2i) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(_pivot, "rotation:x", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_pivot, "position", Vector3.ZERO, 0.7)
	tw.tween_property(self, "position", Vector3(t.x, 0, t.y), 0.7)
	await tw.finished
	tile = t
	face(dir)


## The left hand flares green a few times. Awaitable.
func pulse_hand(times := 3) -> void:
	for i in times:
		var tw := create_tween()
		tw.tween_method(_hand_glow, 0.0, 1.0, 0.35)
		tw.tween_method(_hand_glow, 1.0, 0.0, 0.45)
		await tw.finished


func _hand_glow(k: float) -> void:
	_hand_mat.set_shader_parameter("albedo", _hand_base.lerp(Figure.LEFT_GREEN, k))
	_hand_mat.set_shader_parameter("emission", Color(0.2, 0.6, 0.15) * k)
