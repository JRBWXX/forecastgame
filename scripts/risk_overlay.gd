extends Node2D
class_name RiskOverlay

## Manages drawing and rendering of risk category polygons.
## The player clicks to place vertices and closes polygons to commit them.

signal drawing_started(category: RiskData.Category)
signal drawing_finished(category: RiskData.Category)
signal drawing_cancelled
signal polygon_count_changed(count: int)
signal vertex_placed(count: int)

const SNAP_SCREEN_PX := 18.0    # Screen pixels to snap-close
const VERTEX_RADIUS := 4.0
const SNAP_HIGHLIGHT_RADIUS := 9.0
const FILL_ALPHA := 0.40
const OUTLINE_ALPHA := 0.80
const PREVIEW_FILL_ALPHA := 0.25
const OUTLINE_WIDTH := 2.0

## Each committed risk polygon
var _polygons: Array[Dictionary] = []

## Drawing state
var _is_drawing := false
var _active_category: RiskData.Category
var _vertices: PackedVector2Array = PackedVector2Array()
var _mouse_map_pos := Vector2.ZERO

# ── Public API ──────────────────────────────────────────────

func is_drawing() -> bool:
	return _is_drawing

func get_active_category() -> RiskData.Category:
	return _active_category

func begin_drawing(category: RiskData.Category) -> void:
	if _is_drawing:
		_cancel_drawing()
	_is_drawing = true
	_active_category = category
	_vertices = PackedVector2Array()
	drawing_started.emit(category)
	queue_redraw()

func cancel_drawing() -> void:
	_cancel_drawing()

func clear_all() -> void:
	_polygons.clear()
	polygon_count_changed.emit(0)
	queue_redraw()

func undo_last_polygon() -> void:
	if _polygons.size() > 0:
		_polygons.pop_back()
		polygon_count_changed.emit(_polygons.size())
		queue_redraw()

func get_polygon_count() -> int:
	return _polygons.size()

func get_vertex_count() -> int:
	return _vertices.size()

func get_polygons() -> Array[Dictionary]:
	return _polygons

# ── Rendering ───────────────────────────────────────────────

## Returns true if the polygon can be triangulated (not degenerate).
func _is_valid_polygon(pts: PackedVector2Array) -> bool:
	if pts.size() < 3:
		return false
	return Geometry2D.triangulate_polygon(pts).size() > 0

func _draw() -> void:
	# Draw committed polygons (lowest category first for correct layering)
	for rp: Dictionary in _polygons:
		var cat: int = rp["category"]
		var pts: PackedVector2Array = rp["points"]
		if pts.size() < 3:
			continue

		var base_color: Color = RiskData.COLORS[cat]

		# Fill
		var fill := base_color
		fill.a = FILL_ALPHA
		if _is_valid_polygon(pts):
			draw_colored_polygon(pts, fill)

		# Outline
		var outline := base_color
		outline.a = OUTLINE_ALPHA
		draw_polyline(pts, outline, OUTLINE_WIDTH, true)

	# Draw in-progress polygon
	if not _is_drawing or _vertices.size() == 0:
		return

	var color: Color = RiskData.COLORS[_active_category]

	# Preview fill (when 3+ vertices, include mouse pos)
	if _vertices.size() >= 2:
		var preview := PackedVector2Array(_vertices)
		preview.append(_mouse_map_pos)
		if preview.size() >= 3 and _is_valid_polygon(preview):
			var pfill := color
			pfill.a = PREVIEW_FILL_ALPHA
			draw_colored_polygon(preview, pfill)

	# Lines between placed vertices
	for i in range(_vertices.size() - 1):
		draw_line(_vertices[i], _vertices[i + 1], color, 2.0)

	# Line from last vertex to mouse
	draw_line(_vertices[_vertices.size() - 1], _mouse_map_pos, color, 1.5)

	# Dashed-style preview line from mouse back to first vertex
	var ghost := color
	ghost.a = 0.3
	draw_line(_mouse_map_pos, _vertices[0], ghost, 1.0)

	# Draw vertex dots
	for pt: Vector2 in _vertices:
		draw_circle(pt, VERTEX_RADIUS, color)

	# Highlight first vertex when in snap range
	if _vertices.size() >= 3 and _is_near_first_vertex():
		var highlight := color
		highlight.a = 0.5
		draw_circle(_vertices[0], SNAP_HIGHLIGHT_RADIUS, highlight)
		draw_arc(_vertices[0], SNAP_HIGHLIGHT_RADIUS, 0.0, TAU, 32, color, 1.5)

# ── Input ───────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _is_drawing:
		_mouse_map_pos = get_local_mouse_position()
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	# Number keys to start drawing a category (works even when not drawing)
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = (event as InputEventKey).keycode
		if RiskData.HOTKEYS.has(key):
			var cat: RiskData.Category = RiskData.HOTKEYS[key]
			if _is_drawing and _active_category == cat:
				_cancel_drawing()
			else:
				begin_drawing(cat)
			get_viewport().set_input_as_handled()
			return

	if not _is_drawing:
		return

	# Keyboard controls while drawing
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = (event as InputEventKey).keycode
		match key:
			KEY_ESCAPE:
				_cancel_drawing()
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				_undo_last_vertex()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if _vertices.size() >= 3:
					_commit_polygon()
				get_viewport().set_input_as_handled()
		return

	# Mouse clicks while drawing
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _vertices.size() >= 3:
				_commit_polygon()
			else:
				_cancel_drawing()
			get_viewport().set_input_as_handled()

# ── Internal ────────────────────────────────────────────────

func _on_left_click() -> void:
	var pos := get_local_mouse_position()

	# Snap-close if near the first vertex with enough points
	if _vertices.size() >= 3 and _is_near_first_vertex():
		_commit_polygon()
		return

	_vertices.append(pos)
	vertex_placed.emit(_vertices.size())
	queue_redraw()

func _commit_polygon() -> void:
	if _vertices.size() < 3:
		return

	# Close the polygon by appending the first point
	var closed := PackedVector2Array(_vertices)
	closed.append(_vertices[0])

	_polygons.append({
		"category": _active_category,
		"points": closed,
	})

	var cat := _active_category
	_is_drawing = false
	_vertices = PackedVector2Array()
	polygon_count_changed.emit(_polygons.size())
	drawing_finished.emit(cat)
	queue_redraw()

func _cancel_drawing() -> void:
	_is_drawing = false
	_vertices = PackedVector2Array()
	drawing_cancelled.emit()
	queue_redraw()

func _undo_last_vertex() -> void:
	if _vertices.size() > 0:
		_vertices.resize(_vertices.size() - 1)
		vertex_placed.emit(_vertices.size())
		if _vertices.size() == 0:
			_cancel_drawing()
		queue_redraw()

func _is_near_first_vertex() -> bool:
	if _vertices.size() < 3:
		return false
	var snap_dist := SNAP_SCREEN_PX
	var cam := get_viewport().get_camera_2d()
	if cam:
		snap_dist /= cam.zoom.x
	return _mouse_map_pos.distance_to(_vertices[0]) < snap_dist
