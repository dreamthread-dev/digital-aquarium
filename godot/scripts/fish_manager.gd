class_name FishManager
extends Node2D

# 静的型付け必須ルールを適用
@export var fish_scene: PackedScene = preload("res://scenes/fish.tscn")
@export var max_fishes: int = 300
@export var initial_fish_count: int = 25

var fishes: Array[Node2D] = []
var screen_size: Vector2 = Vector2(8640, 3840)
var base_speed: float = 120.0
var wall_margin: float = 300.0

@onready var ambient_player: AudioStreamPlayer = $"../AmbientPlayer"
@onready var splash_player: AudioStreamPlayer = $"../SplashPlayer"

# デフォルト魚のテクスチャプール
var default_textures: Array[Texture2D] = []

# ふらつき用Perlin Noiseのジェネレータ
var noise_gen: FastNoiseLite

# Boids グローバルパラメータ (デバッグUIと連携するためマネージャー側で保持)
var separation_radius: float = 80.0
var alignment_radius: float = 150.0
var cohesion_radius: float = 200.0

var separation_weight: float = 1.5
var alignment_weight: float = 1.0
var cohesion_weight: float = 1.0
var wander_weight: float = 0.3
var wall_avoid_weight: float = 2.5

func _ready() -> void:
	# ノイズの初期設定
	noise_gen = FastNoiseLite.new()
	noise_gen.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_gen.frequency = 0.02
	noise_gen.seed = randi()
	
	# デフォルト魚アセットのロード
	_load_default_textures()
	
	# 起動時のデフォルト魚の生成
	_spawn_initial_fishes()
	
	# WebSocket 接続のハンドリング
	var ws_node := get_node_or_null("../WebSocketClient")
	if ws_node:
		var ws_client := ws_node as WebSocketClient
		if ws_client:
			ws_client.fish_received.connect(_on_fish_received)
			logger_info("Connected to WebSocketClient fish_received signal.")
	
	# 環境音の読み込みと再生 (フォールバック対応)
	var ambient_path := "res://audio/ambient_water.ogg"
	if ResourceLoader.exists(ambient_path) and ambient_player:
		var stream := load(ambient_path) as AudioStream
		if stream:
			ambient_player.stream = stream
			ambient_player.play()
			logger_info("Playing ambient water loop.")
	
	logger_info("FishManager ready. Spawned initial fishes.")

func _load_default_textures() -> void:
	var paths: Array[String] = [
		"res://assets/default_fish/fish_01.png",
		"res://assets/default_fish/fish_02.png",
		"res://assets/default_fish/fish_03.png",
		"res://assets/default_fish/fish_04.png",
		"res://assets/default_fish/fish_05.png",
		"res://assets/default_fish/fish_06.png",
		"res://assets/default_fish/fish_07.png"
	]
	for path in paths:
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				default_textures.append(tex)
		else:
			push_warning("Default fish texture not found at path: " + path)

func _spawn_initial_fishes() -> void:
	if default_textures.size() == 0:
		push_error("Cannot spawn initial fishes: No textures loaded.")
		return
		
	for i in range(initial_fish_count):
		# ランダムなテクスチャを選択
		var tex: Texture2D = default_textures[randi() % default_textures.size()]
		if not tex:
			push_warning("Skipping initial fish spawn: Texture is null.")
			continue
		
		# 画面の有効範囲内のランダムな位置に配置
		var margin: float = 400.0
		var rx: float = randf_range(margin, screen_size.x - margin)
		var ry: float = randf_range(margin, screen_size.y - margin)
		var start_pos: Vector2 = Vector2(rx, ry)
		
		# 奥行き (depth) をランダムに付与 (0.0 手前 〜 1.0 奥)
		var p_depth: float = randf()
		
		spawn_fish(tex, start_pos, p_depth, false)

# 新規魚の生成 (WebSocket等からの受信時も呼び出す共通IF)
func spawn_fish(texture: Texture2D, start_pos: Vector2 = Vector2.ZERO, p_depth: float = -1.0, start_falling: bool = true) -> void:
	if not texture:
		push_error("FishManager: spawn_fish called with null texture. Aborting spawn.")
		return

	if not fish_scene:
		push_error("FishManager: fish_scene PackedScene is not configured.")
		return
		
	var fish_instance := fish_scene.instantiate() as Fish
	if not fish_instance:
		push_error("FishManager: Failed to instantiate fish scene.")
		return
		
	# 初期パラメータ設定
	if start_pos == Vector2.ZERO:
		var rx: float = randf_range(500.0, screen_size.x - 500.0)
		if start_falling:
			start_pos = Vector2(rx, -150.0) # 画面外上部
		else:
			var ry: float = randf_range(400.0, screen_size.y - 400.0)
			start_pos = Vector2(rx, ry)
	
	fish_instance.position = start_pos
	fish_instance.noise_gen = noise_gen
	
	# Boidsパラメータの初期同期
	_sync_fish_params(fish_instance)
	
	# 落下状態の初期化
	if start_falling:
		fish_instance.current_state = Fish.State.STATE_SPAWNING
		fish_instance.velocity = Vector2(0.0, 200.0) # 下方向への初速
	else:
		fish_instance.current_state = Fish.State.STATE_ACTIVE
	
	# シーンに追加 (描画されるようにする)
	add_child(fish_instance)
	
	# テクスチャの適用 (必ず add_child 後に行う)
	if fish_instance.sprite:
		fish_instance.sprite.texture = texture
	
	# 奥行きの適用
	var depth_val: float = p_depth if p_depth >= 0.0 else randf()
	fish_instance.set_depth(depth_val)
	
	# 配列へ登録
	fishes.append(fish_instance)
	
	# FIFO制御 (最大匹数を超えた場合は最古の魚を消滅)
	if fishes.size() > max_fishes:
		var oldest: Node2D = fishes.pop_front()
		var oldest_fish := oldest as Fish
		if is_instance_valid(oldest_fish):
			oldest_fish.start_dying()

func _on_fish_received(texture: Texture2D) -> void:
	spawn_fish(texture, Vector2.ZERO, -1.0, true)
	logger_info("Spawned a new fish from WebSocket connection.")

# 各魚個体へBoidsパラメータを一括同期させる
func _sync_fish_params(fish: Fish) -> void:
	fish.separation_radius = separation_radius
	fish.alignment_radius = alignment_radius
	fish.cohesion_radius = cohesion_radius
	
	fish.separation_weight = separation_weight
	fish.alignment_weight = alignment_weight
	fish.cohesion_weight = cohesion_weight
	fish.wander_weight = wander_weight
	fish.wall_avoid_weight = wall_avoid_weight
	
	# 速度と壁マージンの同期
	fish.speed = base_speed * fish.speed_factor
	fish.max_speed = fish.speed * 1.5
	fish.wall_margin = wall_margin

# デバッグUIなどからパラメータが一括更新された際、稼働中の魚全てへ反映する
func update_all_fish_params() -> void:
	for f in fishes:
		var fish := f as Fish
		if is_instance_valid(fish):
			_sync_fish_params(fish)

# 毎フレームの更新処理（Boids一括処理 & 空間分割）
func _process(delta: float) -> void:
	# 1. 空間分割ツリー (Quadtree) の構築
	# 水槽全体 (8640x3840) の境界ボックス
	var boundary: Rect2 = Rect2(Vector2.ZERO, screen_size)
	var qtree: Quadtree = Quadtree.new(boundary, 8)
	
	# 有効かつアクティブな魚のみをインサート
	for f in fishes:
		if is_instance_valid(f):
			var fish := f as Fish
			if fish and fish.current_state == Fish.State.STATE_ACTIVE:
				qtree.insert(f)
			
	# 2. 各魚の近傍探索と移動更新
	for f in fishes:
		var fish := f as Fish
		if not is_instance_valid(fish):
			continue
			
		var neighbors: Array[Node2D] = []
		
		# アクティブな魚のみ近傍探索を行う
		if fish.current_state == Fish.State.STATE_ACTIVE:
			# 周囲の探索範囲 (最も大きい半径を基準にする)
			var query_radius: float = maxf(cohesion_radius, maxf(alignment_radius, separation_radius))
			var query_rect: Rect2 = Rect2(
				fish.global_position - Vector2(query_radius, query_radius),
				Vector2(query_radius * 2.0, query_radius * 2.0)
			)
			qtree.query(query_rect, neighbors)
		
		# 位置と方向の物理移動更新を実行 (落下中の魚も update_movement 内で落下が処理される)
		fish.update_movement(delta, neighbors, screen_size)

# 着水音の再生 (フォールバック対応)
func play_splash_sound() -> void:
	var splash_path := "res://audio/splash.ogg"
	if ResourceLoader.exists(splash_path) and splash_player:
		if not splash_player.stream:
			var stream := load(splash_path) as AudioStream
			if stream:
				splash_player.stream = stream
		if splash_player.stream:
			splash_player.play()

# ロガーヘルパー
func logger_info(msg: String) -> void:
	print("[FishManager] INFO: " + msg)
