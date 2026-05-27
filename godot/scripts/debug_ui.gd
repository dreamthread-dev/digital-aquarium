extends CanvasLayer

# 静的型付け必須ルールを適用
@onready var panel: Panel = $Panel

@onready var speed_slider: HSlider = $Panel/VBoxContainer/SpeedRow/Slider
@onready var speed_val: Label = $Panel/VBoxContainer/SpeedRow/Value

@onready var sep_slider: HSlider = $Panel/VBoxContainer/SepRow/Slider
@onready var sep_val: Label = $Panel/VBoxContainer/SepRow/Value

@onready var align_slider: HSlider = $Panel/VBoxContainer/AlignRow/Slider
@onready var align_val: Label = $Panel/VBoxContainer/AlignRow/Value

@onready var cohesion_slider: HSlider = $Panel/VBoxContainer/CohesionRow/Slider
@onready var cohesion_val: Label = $Panel/VBoxContainer/CohesionRow/Value

@onready var wall_slider: HSlider = $Panel/VBoxContainer/WallRow/Slider
@onready var wall_val: Label = $Panel/VBoxContainer/WallRow/Value

@onready var wander_slider: HSlider = $Panel/VBoxContainer/WanderRow/Slider
@onready var wander_val: Label = $Panel/VBoxContainer/WanderRow/Value

var fish_manager: FishManager = null

func _ready() -> void:
	visible = false
	var parent := get_parent()
	if parent:
		fish_manager = parent.get_node_or_null("FishManager") as FishManager
	
	# スライダー値変更シグナルのバインド
	speed_slider.value_changed.connect(_on_speed_changed)
	sep_slider.value_changed.connect(_on_sep_changed)
	align_slider.value_changed.connect(_on_align_changed)
	cohesion_slider.value_changed.connect(_on_cohesion_changed)
	wall_slider.value_changed.connect(_on_wall_changed)
	wander_slider.value_changed.connect(_on_wander_changed)
	
	# 起動時に現在の値をマネージャーから同期
	if fish_manager:
		_sync_sliders_from_manager()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F1:
			visible = not visible
			if visible:
				_sync_sliders_from_manager()
			print("[DebugUI] Visibility toggled: ", visible)

func _sync_sliders_from_manager() -> void:
	if not fish_manager:
		return
	
	# マネージャーから値を読み出し、スライダーとラベルを同期
	speed_slider.value = fish_manager.base_speed
	speed_val.text = str(int(fish_manager.base_speed))
	
	sep_slider.value = fish_manager.separation_radius
	sep_val.text = str(int(fish_manager.separation_radius))
	
	align_slider.value = fish_manager.alignment_radius
	align_val.text = str(int(fish_manager.alignment_radius))
	
	cohesion_slider.value = fish_manager.cohesion_radius
	cohesion_val.text = str(int(fish_manager.cohesion_radius))
	
	wall_slider.value = fish_manager.wall_margin
	wall_val.text = str(int(fish_manager.wall_margin))
	
	wander_slider.value = fish_manager.wander_weight
	wander_val.text = "%.1f" % fish_manager.wander_weight

# --- シグナルハンドラ ---

func _on_speed_changed(val: float) -> void:
	if fish_manager:
		fish_manager.base_speed = val
		fish_manager.max_speed = val * 1.5
		fish_manager.update_all_fish_params()
	speed_val.text = str(int(val))

func _on_sep_changed(val: float) -> void:
	if fish_manager:
		fish_manager.separation_radius = val
		fish_manager.update_all_fish_params()
	sep_val.text = str(int(val))

func _on_align_changed(val: float) -> void:
	if fish_manager:
		fish_manager.alignment_radius = val
		fish_manager.update_all_fish_params()
	align_val.text = str(int(val))

func _on_cohesion_changed(val: float) -> void:
	if fish_manager:
		fish_manager.cohesion_radius = val
		fish_manager.update_all_fish_params()
	cohesion_val.text = str(int(val))

func _on_wall_changed(val: float) -> void:
	if fish_manager:
		fish_manager.wall_margin = val
		fish_manager.update_all_fish_params()
	wall_val.text = str(int(val))

func _on_wander_changed(val: float) -> void:
	if fish_manager:
		fish_manager.wander_weight = val
		fish_manager.update_all_fish_params()
	wander_val.text = "%.1f" % val
