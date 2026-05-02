extends Node2D
class_name WindBarbOverlay

## Draws standard meteorological wind barbs at regular grid intervals.

const BARB_SPACING := 70.0
const STAFF_LENGTH := 28.0
const FULL_BARB_LEN := 12.0
const HALF_BARB_LEN := 7.0
const PENNANT_WIDTH := 5.0
const BARB_GAP := 4.5
const MIN_SPEED := 3.0
const STATION_RADIUS := 2.0

var _data: AtmosphereData
var _barb_color := Color(0.90, 0.92, 0.95, 0.85)
var _staff_width := 1.5

func set_data(data: AtmosphereData) -> void:
	_data = data
	queue_redraw()

func clear() -> void:
	_data = null
	queue_redraw()

func _draw() -> void:
	if not _data or not _data.has_vector:
		return

	var cam := get_viewport().get_camera_2d()
	var zoom_factor := 1.0
	if cam:
		zoom_factor = 1.0 / cam.zoom.x

	var barb_scale := zoom_factor

	var spacing := BARB_SPACING * zoom_factor
	var map_w := _data.map_max.x - _data.map_min.x
	var map_h := _data.map_max.y - _data.map_min.y

	var cols := int(map_w / spacing)
	var rows := int(map_h / spacing)
	var x_offset := fmod(map_w, spacing) * 0.5 + _data.map_min.x + spacing * 0.5
	var y_offset := fmod(map_h, spacing) * 0.5 + _data.map_min.y + spacing * 0.5

	for row in range(rows):
		for col in range(cols):
			var map_pos := Vector2(
				x_offset + col * spacing,
				y_offset + row * spacing
			)
			var vec := _data.sample_vector(map_pos)
			var speed := vec.length()
			if speed < MIN_SPEED:
				continue
			_draw_barb(map_pos, speed, vec, barb_scale)

func _draw_barb(pos: Vector2, speed_kt: float, vec: Vector2, barb_scale: float) -> void:
	var angle := vec.angle()
	var staff_dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-staff_dir.y, staff_dir.x)

	var staff_len := STAFF_LENGTH * barb_scale
	var tip := pos + staff_dir * staff_len

	draw_circle(pos, STATION_RADIUS * barb_scale, _barb_color)
	draw_line(pos, tip, _barb_color, _staff_width * barb_scale)

	var remaining := int(round(speed_kt / 5.0)) * 5
	@warning_ignore("integer_division")
	var pennants := remaining / 50
	remaining -= pennants * 50
	@warning_ignore("integer_division")
	var full_barbs := remaining / 10
	remaining -= full_barbs * 10
	@warning_ignore("integer_division")
	var half_barbs := remaining / 5

	var barb_pos := tip
	var gap := BARB_GAP * barb_scale
	var full_len := FULL_BARB_LEN * barb_scale
	var half_len := HALF_BARB_LEN * barb_scale
	var pennant_w := PENNANT_WIDTH * barb_scale

	for i in range(pennants):
		var p1 := barb_pos
		var p2 := barb_pos + perp * full_len
		var p3 := barb_pos - staff_dir * pennant_w
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), _barb_color)
		barb_pos -= staff_dir * pennant_w

	if pennants > 0 and (full_barbs > 0 or half_barbs > 0):
		barb_pos -= staff_dir * (gap * 0.5)

	for i in range(full_barbs):
		var barb_end := barb_pos + perp * full_len
		draw_line(barb_pos, barb_end, _barb_color, _staff_width * barb_scale)
		barb_pos -= staff_dir * gap

	if half_barbs > 0:
		if pennants == 0 and full_barbs == 0:
			barb_pos -= staff_dir * gap
		var barb_end := barb_pos + perp * half_len
		draw_line(barb_pos, barb_end, _barb_color, _staff_width * barb_scale)
