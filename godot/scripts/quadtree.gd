class_name Quadtree
extends RefCounted

# 静的型付け必須ルールを適用
var boundary: Rect2
var capacity: int
var fishes: Array[Node2D] = []
var is_divided: bool = false

# 子ノードの参照
var north_west: Quadtree = null
var north_east: Quadtree = null
var south_west: Quadtree = null
var south_east: Quadtree = null

func _init(p_boundary: Rect2, p_capacity: int = 8) -> void:
	boundary = p_boundary
	capacity = p_capacity

# 魚をツリーに挿入する
func insert(fish: Node2D) -> bool:
	# 境界ボックスの外側なら何もしない
	if not boundary.has_point(fish.global_position):
		return false
	
	# キャパシティに余裕があり、まだ分割されていなければ、このノードに格納
	if fishes.size() < capacity and not is_divided:
		fishes.append(fish)
		return true
	
	# 満杯の場合、まだ分割されていなければ分割する
	if not is_divided:
		_subdivide()
		
		# 自身が持っていた魚を子ノードへ再配分する
		var temp_fishes: Array[Node2D] = fishes.duplicate()
		fishes.clear()
		for f in temp_fishes:
			_insert_into_children(f)
			
	# 新しい魚を子ノードへインサート
	return _insert_into_children(fish)

# 子ノードへの再帰挿入
func _insert_into_children(fish: Node2D) -> bool:
	if north_west.insert(fish): return true
	if north_east.insert(fish): return true
	if south_west.insert(fish): return true
	if south_east.insert(fish): return true
	return false

# 4つの象限に分割する
func _subdivide() -> void:
	var x: float = boundary.position.x
	var y: float = boundary.position.y
	var w: float = boundary.size.x / 2.0
	var h: float = boundary.size.y / 2.0
	
	north_west = Quadtree.new(Rect2(x, y, w, h), capacity)
	north_east = Quadtree.new(Rect2(x + w, y, w, h), capacity)
	south_west = Quadtree.new(Rect2(x, y + h, w, h), capacity)
	south_east = Quadtree.new(Rect2(x + w, y + h, w, h), capacity)
	
	is_divided = true

# 範囲内のオブジェクトをクエリ（高速抽出）する
func query(range_rect: Rect2, found: Array[Node2D]) -> void:
	# 範囲と境界が交差していない場合は終了
	if not boundary.intersects(range_rect):
		return
	
	# 自身が格納しているオブジェクトを範囲判定して追加
	# （分割されている場合は fishes は空になっているため、分割前または末端のノードのみで判定が走る）
	for fish in fishes:
		if is_instance_valid(fish) and range_rect.has_point(fish.global_position):
			found.append(fish)
			
	# 分割されている場合は子ノードを再帰クエリ
	if is_divided:
		north_west.query(range_rect, found)
		north_east.query(range_rect, found)
		south_west.query(range_rect, found)
		south_east.query(range_rect, found)
