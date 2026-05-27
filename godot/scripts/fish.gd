class_name Fish
extends Node2D

const HALF_PI = PI / 2.0

# 静的型付け必須ルールを適用
var velocity: Vector2 = Vector2.RIGHT
var speed: float = 120.0
var max_speed: float = 180.0
var depth: float = 0.0
var noise_offset: float = 0.0

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

func _ready() -> void:
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
	# 進む方向に応じてスプライトの上下反転を行い、魚が逆さまになるのを防ぐ
	if sprite:
		var normalized_angle: float = fposmod(rotation, TAU)
		if normalized_angle > HALF_PI and normalized_angle < PI + HALF_PI:
			sprite.flip_v = true
		else:
			sprite.flip_v = false

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
