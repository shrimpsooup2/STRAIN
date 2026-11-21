extends Control
## Pokemon-style colony bar: dark frame, fill that drains smoothly, colour by fraction.
## Damage leaves a pale "ghost" chunk that holds briefly, then shrinks to the new value;
## any change flashes the fill. set_values(v, m, true) snaps everything (no ghost, no flash).

const GHOST_HOLD := 0.35
const FLASH_T := 0.18
const C_GHOST := Color("f0e098")

var max_value := 1.0
var value := 1.0
var shown := 1.0
var ghost := 1.0
var _ghost_hold := 0.0
var _flash := 0.0
var _inited := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(v: float, m: float, instant := false) -> void:
	var old := value
	max_value = maxf(1.0, m)
	value = clampf(v, 0.0, max_value)
	if instant or not _inited:
		if instant:
			shown = value
			ghost = value
			_ghost_hold = 0.0
			_flash = 0.0
		_inited = true
	elif value < old - 0.001:
		ghost = maxf(ghost, shown)
		_ghost_hold = GHOST_HOLD
		_flash = FLASH_T
	elif value > old + 0.001:
		_flash = FLASH_T
	shown = minf(shown, max_value)
	ghost = clampf(ghost, shown, max_value)
	queue_redraw()


func _process(dt: float) -> void:
	var dirty := false
	if not is_equal_approx(shown, value):
		var spd := maxf(8.0, max_value * 0.9)
		if value < shown:
			spd *= 3.0
		shown = move_toward(shown, value, spd * dt)
		dirty = true
	if ghost < shown:
		ghost = shown
		dirty = true
	elif ghost > shown:
		if _ghost_hold > 0.0:
			_ghost_hold -= dt
		else:
			ghost = move_toward(ghost, shown, maxf(6.0, max_value * 0.7) * dt)
		dirty = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt)
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.C_INK)
	var inner := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(inner, Color("283038"))
	var frac := clampf(shown / max_value, 0.0, 1.0)
	var w := roundf(inner.size.x * frac)
	if value > 0.0 and w < 1.0:
		w = 1.0
	var gw := roundf(inner.size.x * clampf(ghost / max_value, 0.0, 1.0))
	if gw > w:
		var gc := C_GHOST if _ghost_hold <= 0.0 or fmod(_ghost_hold, 0.1) < 0.06 else Color.WHITE
		draw_rect(Rect2(inner.position + Vector2(w, 0), Vector2(gw - w, inner.size.y)), gc)
	if w > 0.0:
		var col := UI.bar_color(frac)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), col)
		draw_rect(Rect2(inner.position, Vector2(w, 1)), col.lightened(0.35))
		if _flash > 0.0:
			draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), Color(1, 1, 1, 0.7 * _flash / FLASH_T))
