class_name WebSocketClient
extends Node

# 静的型付け必須ルールを適用
@export var websocket_url: String = "ws://127.0.0.1:8000/ws"
@export var reconnect_interval: float = 3.0

var socket: WebSocketPeer = WebSocketPeer.new()
var is_connected_to_server: bool = false
var reconnect_timer: float = 0.0

# 魚画像デコード成功時のシグナル
signal fish_received(texture: Texture2D)

func _ready() -> void:
	print("[WebSocket] Starting client. Target URL: ", websocket_url)
	_connect_to_server()

# サーバーへの接続開始
func _connect_to_server() -> void:
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1024 * 1024 * 8 # 8MB (画像転送などの大容量パケットに対応)
	socket.outbound_buffer_size = 1024 * 1024 * 8 # 8MB
	var err := socket.connect_to_url(websocket_url)
	if err != OK:
		print("[WebSocket] Connection attempt failed immediately. Code: ", err)
		is_connected_to_server = false
		reconnect_timer = reconnect_interval
	else:
		print("[WebSocket] Connecting...")
		is_connected_to_server = false

func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected_to_server:
			is_connected_to_server = true
			print("[WebSocket] Successfully connected to server.")
			
			# 初回メッセージでクライアントタイプ "godot" を登録
			var reg_msg := {
				"type": "godot"
			}
			var json_str := JSON.stringify(reg_msg)
			var send_err := socket.send_text(json_str)
			if send_err != OK:
				print("[WebSocket] Failed to send registration message. Code: ", send_err)
		
		# メッセージ受信処理
		_process_messages()
		
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected_to_server:
			is_connected_to_server = false
			print("[WebSocket] Connection closed.")
		
		# 自動再接続のカウントダウン
		reconnect_timer -= delta
		if reconnect_timer <= 0.0:
			reconnect_timer = reconnect_interval
			print("[WebSocket] Reconnecting to server...")
			_connect_to_server()
			
	elif state == WebSocketPeer.STATE_CONNECTING:
		# 接続中
		pass
		
	elif state == WebSocketPeer.STATE_CLOSING:
		# 切断中
		pass

# 受信キューの処理
func _process_messages() -> void:
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		var text := packet.get_string_from_utf8()
		_handle_message(text)

# メッセージ解析と画像デコード
func _handle_message(text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[WebSocket] Failed to parse incoming JSON message.")
		return
		
	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return
		
	var msg_dict := data as Dictionary
	var msg_type: Variant = msg_dict.get("type")
	
	if msg_type == "fish":
		var b64_img: String = msg_dict.get("image", "")
		if b64_img.is_empty():
			push_error("[WebSocket] Received fish message without image data.")
			return
			
		# Base64 プレフィックスの除去
		var prefix := "data:image/png;base64,"
		if b64_img.begins_with(prefix):
			b64_img = b64_img.substr(prefix.length())
			
		# Base64 文字列をバイト配列にデコード
		var img_bytes := Marshalls.base64_to_raw(b64_img)
		if img_bytes.size() == 0:
			push_error("[WebSocket] Base64 decoding failed for fish image.")
			return
			
		# PNG バッファから Image を生成
		var image := Image.new()
		var parse_err := image.load_png_from_buffer(img_bytes)
		if parse_err != OK:
			push_error("[WebSocket] Failed to load PNG from buffer. Code: ", parse_err)
			return
			
		# ImageTexture に変換してシグナルで配送
		var texture := ImageTexture.create_from_image(image)
		print("[WebSocket] Successfully received and decoded new fish image. Emitting fish_received signal.")
		fish_received.emit(texture)
