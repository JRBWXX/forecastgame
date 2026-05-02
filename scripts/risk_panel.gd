extends PanelContainer
class_name RiskPanel

## Side panel for selecting risk categories and managing polygons.
## Builds its own UI in _ready().

signal category_selected(category: RiskData.Category)
signal clear_requested
signal undo_requested

var _buttons: Dictionary = {}     # Category → Button
var _active_category: int = -1    # Currently selected, -1 = none
var _status_label: Label
var _vertex_label: Label
var _polygon_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Panel style
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.90)
	panel_style.set_content_margin_all(12.0)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_bottom_left = 8
	add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# Title
	var title := Label.new()
	title.text = "RISK OUTLOOK"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# Separator
	root.add_child(_make_separator())

	# Category buttons
	var categories := [
		RiskData.Category.TSTM,
		RiskData.Category.MRGL,
		RiskData.Category.SLGT,
		RiskData.Category.ENH,
		RiskData.Category.MDT,
		RiskData.Category.HIGH,
	]

	for i in range(categories.size()):
		var cat: RiskData.Category = categories[i]
		var btn := _make_category_button(cat, i + 1)
		root.add_child(btn)
		_buttons[cat] = btn

	# Separator
	root.add_child(_make_separator())

	# Action buttons
	var undo_btn := Button.new()
	undo_btn.text = "Undo last polygon"
	undo_btn.pressed.connect(func() -> void: undo_requested.emit())
	_style_action_button(undo_btn)
	root.add_child(undo_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear all"
	clear_btn.pressed.connect(func() -> void: clear_requested.emit())
	_style_action_button(clear_btn)
	root.add_child(clear_btn)

	# Separator
	root.add_child(_make_separator())

	# Status area
	_polygon_label = Label.new()
	_polygon_label.text = "Polygons: 0"
	_polygon_label.add_theme_font_size_override("font_size", 12)
	_polygon_label.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	root.add_child(_polygon_label)

	_status_label = Label.new()
	_status_label.text = "Select a category to draw"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	_vertex_label = Label.new()
	_vertex_label.text = ""
	_vertex_label.add_theme_font_size_override("font_size", 12)
	_vertex_label.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	root.add_child(_vertex_label)

	# Controls help
	root.add_child(_make_separator())

	var help := Label.new()
	help.text = "Left-click: vertex\nRight/Enter: close\nBackspace: undo point\nEsc: cancel\n1-6: category hotkey"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.38, 0.40, 0.48))
	root.add_child(help)

## Update visual state when a category is selected for drawing
func set_active_category(category: RiskData.Category) -> void:
	_active_category = category
	_update_button_states()
	_status_label.text = "Drawing: " + RiskData.LABELS[category]
	_status_label.add_theme_color_override("font_color", RiskData.COLORS[category])
	_vertex_label.text = "Vertices: 0"

## Update visual state when drawing ends
func clear_active_category() -> void:
	_active_category = -1
	_update_button_states()
	_status_label.text = "Select a category to draw"
	_status_label.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	_vertex_label.text = ""

func update_vertex_count(count: int) -> void:
	_vertex_label.text = "Vertices: " + str(count)

func update_polygon_count(count: int) -> void:
	_polygon_label.text = "Polygons: " + str(count)

# ── UI Construction Helpers ─────────────────────────────────

func _make_category_button(cat: RiskData.Category, number: int) -> Button:
	var btn := Button.new()
	var color: Color = RiskData.COLORS[cat]
	var label_text: String = RiskData.LABELS[cat]
	var full_name: String = RiskData.FULL_NAMES[cat]
	btn.text = "  " + str(number) + "  " + label_text + "  " + full_name

	# Normal style
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.16, 0.20)
	normal.border_color = color.darkened(0.3)
	normal.border_width_left = 4
	normal.set_content_margin_all(8.0)
	normal.content_margin_left = 6.0
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", normal)

	# Hover style
	var hover := normal.duplicate()
	(hover as StyleBoxFlat).bg_color = Color(0.18, 0.20, 0.26)
	(hover as StyleBoxFlat).border_color = color
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed style
	var pressed := normal.duplicate()
	(pressed as StyleBoxFlat).bg_color = color.darkened(0.6)
	(pressed as StyleBoxFlat).border_color = color
	(pressed as StyleBoxFlat).border_width_left = 6
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90))
	btn.add_theme_color_override("font_hover_color", color)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn.pressed.connect(_on_category_pressed.bind(cat))

	return btn

func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	return sep

func _style_action_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.17)
	style.border_color = Color(0.25, 0.27, 0.32)
	style.set_border_width_all(1)
	style.set_content_margin_all(6.0)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	(hover as StyleBoxFlat).bg_color = Color(0.16, 0.17, 0.22)
	(hover as StyleBoxFlat).border_color = Color(0.35, 0.38, 0.45)
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.60, 0.63, 0.70))
	btn.add_theme_color_override("font_hover_color", Color(0.75, 0.78, 0.85))

func _on_category_pressed(cat: RiskData.Category) -> void:
	category_selected.emit(cat)

func _update_button_states() -> void:
	for cat in _buttons:
		var btn: Button = _buttons[cat]
		var color: Color = RiskData.COLORS[cat]
		if cat == _active_category:
			# Active/selected look
			var active := StyleBoxFlat.new()
			active.bg_color = color.darkened(0.65)
			active.border_color = color
			active.border_width_left = 6
			active.set_content_margin_all(8.0)
			active.content_margin_left = 6.0
			active.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", active)
			btn.add_theme_color_override("font_color", color)
		else:
			# Reset to default look
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color(0.14, 0.16, 0.20)
			normal.border_color = color.darkened(0.3)
			normal.border_width_left = 4
			normal.set_content_margin_all(8.0)
			normal.content_margin_left = 6.0
			normal.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", normal)
			btn.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90))
