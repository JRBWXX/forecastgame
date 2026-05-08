extends PanelContainer
class_name RiskPalette

## Compact floating palette showing drawing status and quick actions.
## Appears near top-right when a drawing tool is active.

signal undo_polygon_requested
signal clear_all_requested

var _status_label: Label
var _vertex_label: Label
var _polygon_label: Label
var _active_category: int = -1


func _ready() -> void:
	_build_ui()
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.92)
	style.border_color = Color(0.35, 0.38, 0.48, 0.7)
	style.set_border_width_all(1)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)


func show_drawing(category: int) -> void:
	_active_category = category
	visible = true
	var color: Color = RiskData.COLORS[category]
	var label: String = RiskData.LABELS[category]
	var full: String = RiskData.FULL_NAMES[category]
	_status_label.text = label + "  " + full
	_status_label.add_theme_color_override("font_color", color)
	_vertex_label.text = "Vertices: 0"


func hide_drawing() -> void:
	visible = false
	_active_category = -1


func update_vertex_count(count: int) -> void:
	_vertex_label.text = "Vertices: " + str(count)


func update_polygon_count(count: int) -> void:
	_polygon_label.text = "Polygons: " + str(count)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	root.add_child(_status_label)

	_vertex_label = Label.new()
	_vertex_label.text = "Vertices: 0"
	_vertex_label.add_theme_font_size_override("font_size", 11)
	_vertex_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	root.add_child(_vertex_label)

	_polygon_label = Label.new()
	_polygon_label.text = "Polygons: 0"
	_polygon_label.add_theme_font_size_override("font_size", 11)
	_polygon_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	root.add_child(_polygon_label)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	root.add_child(sep)

	var hint := Label.new()
	hint.text = "Enter/RClick — close\nBackspace — undo point\nEsc — cancel"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.42, 0.44, 0.54))
	root.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	root.add_child(btn_row)

	var undo_btn := Button.new()
	undo_btn.text = "Undo last"
	undo_btn.add_theme_font_size_override("font_size", 11)
	undo_btn.pressed.connect(func() -> void: undo_polygon_requested.emit())
	btn_row.add_child(undo_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear all"
	clear_btn.add_theme_font_size_override("font_size", 11)
	clear_btn.pressed.connect(func() -> void: clear_all_requested.emit())
	btn_row.add_child(clear_btn)
