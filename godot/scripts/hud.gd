extends CanvasLayer

# 静的型付け必須ルールを適用
@onready var count_label: Label = $Panel/HBoxContainer/CountLabel
var fish_manager: FishManager = null

func _ready() -> void:
	visible = true
	# シーンツリーから FishManager の参照を取得
	var parent := get_parent()
	if parent:
		fish_manager = parent.get_node_or_null("FishManager") as FishManager

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F2:
			visible = not visible
			print("[HUD] Visibility toggled: ", visible)

func _process(_delta: float) -> void:
	if visible and fish_manager and count_label:
		count_label.text = "魚の数: %d / %d" % [fish_manager.fishes.size(), fish_manager.max_fishes]
