class_name Fish
extends Node2D

const HALF_PI = PI / 2.0

# 状態の定義
enum State {
	STATE_SPAWNING,
	STATE_ACTIVE,
	STATE_DYING
}

# 静的型付け必須ルールを適用
var velocity: Vector2 = Vector2.RIGHT
var speed: float = 120.0
var max_speed: float = 180.0
var depth: float = 0.0
var noise_offset: float = 0.0

# 現在の状態
var current_state: State = State.STATE_ACTIVE

# 登場演出パラメータ
var gravity: float = 800.0
var water_level: float = 400.0

# 消滅演出パラメータ
var fade_duration: float = 1.5
var fade_timer: float = 0.0

# Boids パラメータ (FishManager から動的に上書き可能)
var separation_radius: float = 80.0
var alignment_radius: float = 150.0
var cohesion_radius: float = 200.0

var separation_weight: float = 1.5
var alignment_weight: float = 1.0
var cohesion_weight: float = 1.0
var wander_weight: float = 0.3
var wall_avoid_weight: float = 2.5

# 壁反発しきい値
var wall_margin: float = 300.0

# 子ノード参照
@onready var sprite: Sprite2D = $Sprite2D

# ふらつき用ノイズ (FishManager から渡される)
var noise_gen: FastNoiseLite = null

# パーティクルシーンのプリロード
var splash_scene: PackedScene = preload("res://scenes/splash_particles.tscn")
var bubble_scene: PackedScene = preload("res://scenes/bubble_particles.tscn")

func _ready() -> void:
	# 通常遊泳時は FishManager が一括更新するため、自身の _process は無効化しておく
	set_process(false)
	
	# 個体ごとの固有のノイズ位相ずれ
	noise_offset = randf_range(0.0, 10000.0)
	
	# スピードに±20%の個体差を付与
	speed = randf_range(96.0, 144.0)
	max_speed = speed * 1.5
	
	# 初期速度ベクトル
	var angle: float = randf_range(0.0, TAU)
	velocity = Vector2.from_angle(angle) * speed

# 奥行きの設定と描画更新
func set_depth(p_depth: float) -> void:
	depth = clampf(p_depth, 0.0, 1.0)
	
	# スケール: 手前(1.25倍) 〜 奥(0.6倍)
	var scale_val: float = lerp(1.25, 0.6, depth)
	scale = Vector2(scale_val, scale_val)
	
	# 色調（モジュレート）: 奥に行くほど水中ブルーにフェード
	# 奥：暗い深海ブルー Color(0.08, 0.20, 0.38, 1.0)
	var deep_color: Color = Color(0.08, 0.20, 0.38, 1.0)
	modulate = Color.WHITE.lerp(deep_color, depth)
	
	# 重なり順: 手前(100) 〜 奥(10)
	z_index = int(lerp(100.0, 10.0, depth))

# 位置と回転の更新 (FishManagerが一括で呼び出すため _process は不使用)
func update_movement(delta: float, neighbors: Array[Node2D], screen_size: Vector2) -> void:
	match current_state:
		State.STATE_SPAWNING:
			_update_spawning(delta)
		State.STATE_ACTIVE:
			_update_active(delta, neighbors, screen_size)
		State.STATE_DYING:
			_update_dying(delta)

# 登場演出（落下）の更新
func _update_spawning(delta: float) -> void:
	# 下方向へ重力落下
	velocity.y += gravity * delta
	if velocity.y > 600.0:
		velocity.y = 600.0
	
	position += velocity * delta
	
	# 落下方向（真下）に向く
	var target_angle: float = velocity.angle()
	rotation = lerp_angle(rotation, target_angle, 10.0 * delta)
	
	if sprite:
		sprite.flip_v = false
	
	# 水面到達判定
	if position.y >= water_level:
		position.y = water_level
		_spawn_splash()
		current_state = State.STATE_ACTIVE
		
		# 水中に入った直後はランダムな斜め上方向に泳ぎ出す
		var swim_angle: float = randf_range(-PI * 0.1, -PI * 0.4)
		if randf() > 0.5:
			swim_angle = randf_range(-PI * 0.9, -PI * 0.6)
		velocity = Vector2.from_angle(swim_angle) * speed

# 通常遊泳の更新
func _update_active(delta: float, neighbors: Array[Node2D], screen_size: Vector2) -> void:
	var force: Vector2 = Vector2.ZERO
	
	# Boidsの計算
	if neighbors.size() > 0:
		force += _calculate_boids(neighbors)
		
	# ふらつき (Wander) の追加
	force += _calculate_wander() * wander_weight
	
	# 壁回避の追加
	force += _calculate_wall_avoidance(screen_size) * wall_avoid_weight
	
	# 速度ベクトルの更新
	velocity += force * delta
	
	# 速度制限 (Boidsの加速しすぎ防止)
	var min_speed: float = speed * 0.75
	if velocity.length() > max_speed:
		velocity = velocity.limit_length(max_speed)
	elif velocity.length() < min_speed:
		velocity = velocity.normalized() * min_speed
		
	# なめらかな回転方向補間 (lerp_angle)
	var target_angle: float = velocity.angle()
	rotation = lerp_angle(rotation, target_angle, 5.0 * delta)
	
	# 移動の反映
	position += velocity * delta
	
	# 左右反転 (flip_v) の制御
	if sprite:
		var normalized_angle: float = fposmod(rotation, TAU)
		if normalized_angle > HALF_PI and normalized_angle < PI + HALF_PI:
			sprite.flip_v = true
		else:
			sprite.flip_v = false

# 消滅演出の更新
func _update_dying(delta: float) -> void:
	# 徐々に減速してゆっくり上昇
	velocity = velocity.lerp(Vector2.UP * 20.0, 3.0 * delta)
	position += velocity * delta
	
	fade_timer += delta
	var progress: float = clampf(fade_timer / fade_duration, 0.0, 1.0)
	
	# フェードアウト
	var deep_color: Color = Color(0.08, 0.20, 0.38, 1.0)
	var base_color: Color = Color.WHITE.lerp(deep_color, depth)
	modulate = Color(base_color.r, base_color.g, base_color.b, 1.0 - progress)
	
	if progress >= 1.0:
		queue_free()

func _process(delta: float) -> void:
	if current_state == State.STATE_DYING:
		_update_dying(delta)

# 消滅演出の開始
func start_dying() -> void:
	if current_state == State.STATE_DYING:
		return
	current_state = State.STATE_DYING
	fade_timer = 0.0
	set_process(true) # 消滅アニメーション更新を有効化
	_spawn_bubbles()

# 水しぶき生成
func _spawn_splash() -> void:
	if not splash_scene:
		return
	var splash := splash_scene.instantiate() as CPUParticles2D
	if splash:
		get_parent().add_child(splash)
		splash.global_position = global_position
		splash.emitting = true

# 泡生成
func _spawn_bubbles() -> void:
	if not bubble_scene:
		return
	var bubbles := bubble_scene.instantiate() as CPUParticles2D
	if bubbles:
		get_parent().add_child(bubbles)
		bubbles.global_position = global_position
		var scale_val: float = lerp(1.25, 0.6, depth)
		bubbles.scale = Vector2(scale_val, scale_val)
		bubbles.emitting = true

# Boids 3原則（分離、整列、結合）の合算ベクトル算出
func _calculate_boids(neighbors: Array[Node2D]) -> Vector2:
	var separation_force: Vector2 = Vector2.ZERO
	var alignment_vel: Vector2 = Vector2.ZERO
	var cohesion_pos: Vector2 = Vector2.ZERO
	
	var separation_count: int = 0
	var alignment_count: int = 0
	var cohesion_count: int = 0
	
	var pos: Vector2 = global_position
	
	for neighbor in neighbors:
		if neighbor == self:
			continue
			
		var n_pos: Vector2 = neighbor.global_position
		var dist: float = pos.distance_to(n_pos)
		
		# 1. Separation (近すぎる魚から離れる)
		if dist > 0.01 and dist < separation_radius:
			# 距離が近いほど強い反発力
			var diff: Vector2 = (pos - n_pos).normalized() / dist
			separation_force += diff
			separation_count += 1
			
		# 2. Alignment (周囲と同じ向き・速度に合わせる)
		if dist < alignment_radius:
			var other_fish := neighbor as Fish
			if other_fish:
				alignment_vel += other_fish.velocity
				alignment_count += 1
				
		# 3. Cohesion (周囲の重心へ向かう)
		if dist < cohesion_radius:
			cohesion_pos += n_pos
			cohesion_count += 1
			
	var combined_force: Vector2 = Vector2.ZERO
	
	if separation_count > 0:
		separation_force = (separation_force / float(separation_count)).normalized() * speed
		combined_force += (separation_force - velocity) * separation_weight
		
	if alignment_count > 0:
		alignment_vel = (alignment_vel / float(alignment_count)).normalized() * speed
		combined_force += (alignment_vel - velocity) * alignment_weight
		
	if cohesion_count > 0:
		cohesion_pos = cohesion_pos / float(cohesion_count)
		var desired_vel: Vector2 = (cohesion_pos - pos).normalized() * speed
		combined_force += (desired_vel - velocity) * cohesion_weight
		
	return combined_force

# FastNoiseLite を使用した滑らかでランダムなふらつき
func _calculate_wander() -> Vector2:
	if not noise_gen:
		return Vector2.ZERO
		
	# 時間経過と固有オフセットからノイズ値を取得 (-1.0 〜 1.0)
	var time_ms: float = float(Time.get_ticks_msec()) * 0.05
	var val: float = noise_gen.get_noise_1d(time_ms + noise_offset)
	
	# 現在の速度方向から少し左右にそれる角度を計算
	var angle: float = velocity.angle() + (val * PI * 0.4)
	return Vector2.from_angle(angle) * speed - velocity

# 画面端に近づいた際に内側へ逃げる力
func _calculate_wall_avoidance(screen_size: Vector2) -> Vector2:
	var desired: Vector2 = Vector2.ZERO
	
	# 左壁
	if position.x < wall_margin:
		desired.x = speed
	# 右壁
	elif position.x > screen_size.x - wall_margin:
		desired.x = -speed
		
	# 上壁
	if position.y < wall_margin:
		desired.y = speed
	# 下壁
	elif position.y > screen_size.y - wall_margin:
		desired.y = -speed
		
	if desired != Vector2.ZERO:
		return desired.normalized() * speed - velocity
		
	return Vector2.ZERO
