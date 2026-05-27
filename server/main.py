import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("server")

app = FastAPI(title="Digital Aquarium Server")

# 接続管理用のセット
godot_connections = set()
tablet_connections = set()

# webapp ディレクトリへのパスを取得
current_dir = os.path.dirname(os.path.abspath(__file__))
webapp_dir = os.path.abspath(os.path.join(current_dir, "..", "webapp"))

@app.get("/health")
async def health_check():
    return {
        "status": "ok", 
        "godot_clients": len(godot_connections), 
        "tablet_clients": len(tablet_connections)
    }

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("New WebSocket connection accepted")
    
    connection_type = None
    try:
        # 初回メッセージでクライアントの種別を判定
        data = await websocket.receive_json()
        if data.get("type") == "godot":
            connection_type = "godot"
            godot_connections.add(websocket)
            logger.info("Godot client registered")
        else:
            connection_type = "tablet"
            tablet_connections.add(websocket)
            logger.info("Tablet client registered")
            
            # 送られてきたデータが魚の場合
            if data.get("type") == "fish":
                logger.info(f"Received initial fish data from tablet")
                await handle_fish_data(data)
                
        # 受信ループ
        while True:
            data = await websocket.receive_json()
            if data.get("type") == "fish":
                logger.info(f"Received fish data. Timestamp: {data.get('timestamp')}")
                await handle_fish_data(data)
            else:
                logger.info(f"Received message of type: {data.get('type')}")
                
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: {connection_type}")
    except Exception as e:
        logger.error(f"Error in websocket loop: {e}")
    finally:
        if connection_type == "godot":
            godot_connections.discard(websocket)
        elif connection_type == "tablet":
            tablet_connections.discard(websocket)

async def handle_fish_data(data: dict):
    # Godotクライアントに受信データをそのまま転送 (ブロードキャスト)
    # ※ #15 にて 0.5秒間隔の放流キュー制御を追加します。
    logger.info(f"Broadcasting fish data to {len(godot_connections)} Godot client(s)")
    for ws in list(godot_connections):
        try:
            await ws.send_json(data)
        except Exception as e:
            logger.error(f"Failed to send to Godot client, discarding connection: {e}")
            godot_connections.discard(ws)

# 静的ファイルの配信設定
# ルート "/" にアクセスしたときに index.html が表示されるようにする
if os.path.exists(webapp_dir):
    app.mount("/", StaticFiles(directory=webapp_dir, html=True), name="webapp")
    logger.info(f"Mounted webapp static files from: {webapp_dir}")
else:
    logger.warning(f"Webapp directory not found at: {webapp_dir}")
