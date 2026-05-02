extends Node2D
class_name CONUSMap

## Renders the CONUS map with state boundaries.
## Handles hover detection and provides signals for interaction.

signal state_hovered(state_name: String)
signal state_clicked(state_name: String)

# Visual settings
@export var fill_color := Color(0.12, 0.14, 0.18)          # Dark background for states
@export var border_color := Color(0.35, 0.40, 0.45)        # State borders
@export var hover_color := Color(0.20, 0.24, 0.30)         # Hovered state fill
@export var border_width := 1.5
@export var ocean_color := Color(0.06, 0.08, 0.12)         # Background/ocean

# When atmosphere data is shown, use transparent fills so data is visible
@export var data_fill_color := Color(0.10, 0.12, 0.16, 0.35)
@export var data_hover_color := Color(0.18, 0.22, 0.28, 0.45)

## Set to true when atmosphere data overlay is visible.
var data_active := false

# State data: Dictionary of state_name -> Array[PackedVector2Array]
var _states: Dictionary = {}
var _hovered_state: String = ""

## When false, click events are ignored (e.g. during risk drawing)
var input_enabled := true
var _state_bboxes: Dictionary = {}

func _ready() -> void:
	_states = StateData.get_states()
	_precompute_bboxes()

func _precompute_bboxes() -> void:
	for state_name in _states:
		var min_x := INF
		var min_y := INF
		var max_x := -INF
		var max_y := -INF
		for poly: PackedVector2Array in _states[state_name]:
			for pt in poly:
				min_x = min(min_x, pt.x)
				min_y = min(min_y, pt.y)
				max_x = max(max_x, pt.x)
				max_y = max(max_y, pt.y)
		_state_bboxes[state_name] = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _draw() -> void:
	# Choose fill colors based on whether atmosphere data is visible
	var base_fill := data_fill_color if data_active else fill_color
	var base_hover := data_hover_color if data_active else hover_color

	# Draw all state fills
	for state_name in _states:
		var color := base_hover if state_name == _hovered_state else base_fill
		for poly: PackedVector2Array in _states[state_name]:
			if poly.size() >= 3:
				draw_colored_polygon(poly, color)

	# Draw all state borders on top
	for state_name in _states:
		for poly: PackedVector2Array in _states[state_name]:
			if poly.size() >= 3:
				draw_polyline(poly, border_color, border_width, true)

func _process(_delta: float) -> void:
	var mouse_pos := get_local_mouse_position()
	var new_hover := _get_state_at(mouse_pos)
	if new_hover != _hovered_state:
		_hovered_state = new_hover
		state_hovered.emit(_hovered_state)
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_state != "":
				state_clicked.emit(_hovered_state)

func _get_state_at(point: Vector2) -> String:
	for state_name in _states:
		# Quick bbox check first
		if not _state_bboxes[state_name].has_point(point):
			continue
		# Detailed point-in-polygon check
		for poly: PackedVector2Array in _states[state_name]:
			if _point_in_polygon(point, poly):
				return state_name
	return ""

func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var n := polygon.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in range(n):
		var pi := polygon[i]
		var pj := polygon[j]
		if ((pi.y > point.y) != (pj.y > point.y)) and \
			(point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	return inside

## Returns the polygon data for a given state (for overlay systems to use)
func get_state_polygons(state_name: String) -> Array:
	if _states.has(state_name):
		return _states[state_name]
	return []

## Returns all state names
func get_state_names() -> Array:
	return _states.keys()
