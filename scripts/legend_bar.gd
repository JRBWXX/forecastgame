extends Control
class_name LegendBar

## Renders a horizontal color ramp with labeled value stops.
## Updated whenever the active atmospheric parameter changes.

var _stops: Array[Dictionary] = []
var _unit: String = ""
var _label_font: Font
var _label_size := 11

func _ready() -> void:
	_label_font = ThemeDB.fallback_font
	custom_minimum_size.y = 36

func set_stops(stops: Array[Dictionary], unit: String) -> void:
	_stops = stops
	_unit = unit
	queue_redraw()

func _draw() -> void:
	if _stops.is_empty():
		return

	var w := size.x
	var bar_h := 16.0
	var bar_y := 4.0

	var val_min: float = _stops[0]["val"]
	var val_max: float = _stops[_stops.size() - 1]["val"]
	var val_range := val_max - val_min
	if val_range <= 0:
		return

	# Draw gradient bar as a series of thin vertical rectangles
	var segments := int(w)
	for px in range(segments):
		var t := float(px) / (segments - 1)
		var val := val_min + t * val_range
		var color := AtmosphereData.color_from_ramp(val, _stops)
		color.a = 1.0  # Always fully opaque in legend
		draw_rect(Rect2(px, bar_y, 1, bar_h), color)

	# Draw border around bar
	draw_rect(Rect2(0, bar_y, w, bar_h), Color(0.4, 0.4, 0.4, 0.6), false)

	# Draw value labels at key stops
	# Skip stops that are too close together on screen
	var last_label_x := -999.0
	var min_spacing := 40.0

	for stop in _stops:
		var val: float = stop["val"]
		var t := (val - val_min) / val_range
		var px := t * w

		if px - last_label_x < min_spacing:
			continue

		var label := _format_value(val)
		var text_size: Vector2 = _label_font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size)

		# Tick mark
		draw_line(Vector2(px, bar_y + bar_h),
				  Vector2(px, bar_y + bar_h + 4),
				  Color(0.7, 0.7, 0.7, 0.8), 1.0)

		# Label
		var label_x := clampf(px - text_size.x * 0.5, 0, w - text_size.x)
		draw_string(_label_font,
			Vector2(label_x, bar_y + bar_h + 4 + text_size.y),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size,
			Color(0.80, 0.82, 0.88, 1.0))

		last_label_x = px

	# Unit label on the right
	if _unit != "":
		var unit_size: Vector2 = _label_font.get_string_size(
			_unit, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size)
		draw_string(_label_font,
			Vector2(w - unit_size.x - 2, bar_y + bar_h + 4 + unit_size.y),
			_unit, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size,
			Color(0.55, 0.58, 0.65, 1.0))

func _format_value(val: float) -> String:
	if absf(val) >= 1000.0:
		return str(int(val / 100) * 100)
	elif absf(val) >= 100.0:
		return str(int(val / 10) * 10)
	return str(int(val))
