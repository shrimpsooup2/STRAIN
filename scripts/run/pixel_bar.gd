extends Control
## Pokemon-style colony bar: dark frame, fill that drains smoothly, colour by fraction.

var max_value := 1.0
var value := 1.0
var shown := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(v: float, m: float, instant := false) -> void:
	max_value = maxf(1.0, m)
	value = clampf(v, 0.0, max_value)
	if instant:
		shown = value
	queue_redraw()


func _process(dt: float) -> void:
	if not is_equal_approx(shown, value):
		shown = move_toward(shown, value, maxf(8.0, max_value * 0.9) * dt)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.C_INK)
	var inner := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(inner, Color("283038"))
	var frac := clampf(shown / max_value, 0.0, 1.0)
	var w := roundf(inner.size.x * frac)
	if value > 0.0 and w < 1.0:
		w = 1.0
	if w > 0.0:
		var col := UI.bar_color(frac)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), col)
		draw_rect(Rect2(inner.position, Vector2(w, 1)), col.lightened(0.35))
