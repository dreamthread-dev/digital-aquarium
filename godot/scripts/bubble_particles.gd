extends CPUParticles2D

func _ready() -> void:
	emitting = true
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
	timer.timeout.connect(_on_timeout)

func _on_timeout() -> void:
	queue_free()
