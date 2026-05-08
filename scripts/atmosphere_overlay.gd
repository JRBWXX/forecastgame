extends Node2D
class_name AtmosphereOverlay

## Renders an AtmosphereData grid as a smooth colored texture on the map.

signal parameter_changed(param_name: String)

const RENDER_WIDTH := 320
const RENDER_HEIGHT := 180

var _sprite: Sprite2D
var _current_data: AtmosphereData
var _current_param: String = ""
var _visible_overlay := true

var _ramp_map: Dictionary = {
	"SBCAPE": AtmosphereData.sbcape_stops,
	"MLCAPE": AtmosphereData.mlcape_stops,
	"CINH":   AtmosphereData.cinh_stops,
	"SHR03":  AtmosphereData.bulk_shear_stops,
	"SHR06":  AtmosphereData.bulk_shear_stops,
	"SFTD":   AtmosphereData.dewpoint_stops,
	"SRH01":  AtmosphereData.srh03_stops,
	"SRH03":  AtmosphereData.srh03_stops,
	"200MB":  AtmosphereData.wind_200mb_stops,
	"300MB":  AtmosphereData.wind_200mb_stops,
	"500MB":  AtmosphereData.bulk_shear_stops,
	"700MB":  AtmosphereData.wind_700mb_stops,
	"850MB":  AtmosphereData.wind_700mb_stops,
	"925MB":  AtmosphereData.wind_925mb_stops,
	"SFC":    AtmosphereData.wind_sfc_stops,
}

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)

func set_data(data: AtmosphereData, param_name: String) -> void:
	_current_data = data
	_current_param = param_name
	_render_texture()
	parameter_changed.emit(param_name)

func set_overlay_visible(vis: bool) -> void:
	_visible_overlay = vis
	_sprite.visible = vis

func is_overlay_visible() -> bool:
	return _visible_overlay

func get_current_param() -> String:
	return _current_param

func sample_at(map_pos: Vector2) -> float:
	if _current_data:
		return _current_data.sample(map_pos)
	return 0.0

func color_at(map_pos: Vector2) -> Color:
	if not _current_data or not _ramp_map.has(_current_param):
		return Color.TRANSPARENT
	var val := _current_data.sample(map_pos)
	return AtmosphereData.color_from_ramp(val, _ramp_map[_current_param])

func _render_texture() -> void:
	if not _current_data or not _ramp_map.has(_current_param):
		return
	var stops: Array[Dictionary] = _ramp_map[_current_param]
	var data := _current_data
	var img := Image.create(RENDER_WIDTH, RENDER_HEIGHT, false, Image.FORMAT_RGBA8)
	var map_w := data.map_max.x - data.map_min.x
	var map_h := data.map_max.y - data.map_min.y
	for py in range(RENDER_HEIGHT):
		for px in range(RENDER_WIDTH):
			var map_x := data.map_min.x + (float(px) / (RENDER_WIDTH - 1)) * map_w
			var map_y := data.map_min.y + (float(py) / (RENDER_HEIGHT - 1)) * map_h
			var val := data.sample(Vector2(map_x, map_y))
			var col := AtmosphereData.color_from_ramp(val, stops)
			img.set_pixel(px, py, col)
	var tex := ImageTexture.create_from_image(img)
	_sprite.texture = tex
	_sprite.position = data.map_min
	_sprite.scale = Vector2(map_w / RENDER_WIDTH, map_h / RENDER_HEIGHT)
