extends Camera2D
class_name MapCamera

## Camera with smooth pan and zoom for navigating the CONUS map.

@export var zoom_speed := 0.1
@export var zoom_min := 0.5
@export var zoom_max := 5.0
@export var pan_speed := 1.0

var _is_panning := false
var _pan_start := Vector2.ZERO
var _target_zoom := 1.0

func _ready() -> void:
	_target_zoom = zoom.x
	# Center on the map (map is roughly 1600x900)
	position = Vector2(800, 450)

func _unhandled_input(event: InputEvent) -> void:
	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = min(_target_zoom + zoom_speed, zoom_max)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = max(_target_zoom - zoom_speed, zoom_min)

			# Middle mouse button to pan
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_panning = true
				_pan_start = mb.position
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_panning = false

	# Pan with middle mouse drag
	if event is InputEventMouseMotion and _is_panning:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / zoom * pan_speed

func _process(delta: float) -> void:
	# Smooth zoom interpolation
	var current := zoom.x
	if not is_equal_approx(current, _target_zoom):
		var new_zoom := lerpf(current, _target_zoom, 10.0 * delta)
		zoom = Vector2(new_zoom, new_zoom)
