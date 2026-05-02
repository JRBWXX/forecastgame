extends CanvasLayer
class_name HUD

@onready var state_label: Label = %StateLabel
@onready var info_label: Label = %InfoLabel
@onready var title_label: Label = %TitleLabel

func _ready() -> void:
	update_title("SPC Categorical Risk Forecast")
	update_state_info("")
	update_info("Scroll to zoom  |  Middle-click drag to pan  |  1-6 to draw risk")

func update_title(text: String) -> void:
	if title_label:
		title_label.text = text

func update_state_info(state_name: String) -> void:
	if state_label:
		if state_name == "":
			state_label.text = ""
		else:
			state_label.text = state_name

func update_info(text: String) -> void:
	if info_label:
		info_label.text = text
