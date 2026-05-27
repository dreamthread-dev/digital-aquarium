import asyncio
import logging
import os
from contextlib import asynccontextmanager, suppress
from typing import Any, Literal

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("server")

ClientType = Literal["godot", "tablet"]
FishMessage = dict[str, Any]

BROADCAST_INTERVAL_SECONDS = 0.5
FISH_QUEUE_MAX_SIZE = 50


class ConnectionManager:
    def __init__(self) -> None:
        self.godot_connections: set[WebSocket] = set()
        self.tablet_connections: set[WebSocket] = set()

    def register(self, websocket: WebSocket, client_type: ClientType) -> None:
        if client_type == "godot":
            self.godot_connections.add(websocket)
        else:
            self.tablet_connections.add(websocket)
        logger.info("%s client registered", client_type.capitalize())

    def disconnect(self, websocket: WebSocket, client_type: ClientType | None) -> None:
        if client_type == "godot":
            self.godot_connections.discard(websocket)
        elif client_type == "tablet":
            self.tablet_connections.discard(websocket)

    @property
    def godot_count(self) -> int:
        return len(self.godot_connections)

    @property
    def tablet_count(self) -> int:
        return len(self.tablet_connections)

    async def broadcast_to_godot(self, data: FishMessage) -> None:
        logger.info("Broadcasting fish data to %d Godot client(s)", self.godot_count)
        for websocket in list(self.godot_connections):
            try:
                await websocket.send_json(data)
            except Exception as exc:
                logger.error("Failed to send to Godot client, discarding connection: %s", exc)
                self.godot_connections.discard(websocket)


manager = ConnectionManager()
fish_queue: asyncio.Queue[FishMessage] | None = None
queue_worker: asyncio.Task[None] | None = None

# webapp ディレクトリへのパスを取得
current_dir = os.path.dirname(os.path.abspath(__file__))
webapp_dir = os.path.abspath(os.path.join(current_dir, "..", "webapp"))
static_dir = os.path.join(current_dir, "static")


def get_fish_queue() -> asyncio.Queue[FishMessage]:
    if fish_queue is None:
        raise RuntimeError("Fish queue is not initialized")
    return fish_queue


async def fish_queue_worker(queue: asyncio.Queue[FishMessage]) -> None:
    while True:
        fish_data = await queue.get()
        try:
            await manager.broadcast_to_godot(fish_data)
            await asyncio.sleep(BROADCAST_INTERVAL_SECONDS)
        finally:
            queue.task_done()


@asynccontextmanager
async def lifespan(_: FastAPI):
    global fish_queue, queue_worker

    fish_queue = asyncio.Queue(maxsize=FISH_QUEUE_MAX_SIZE)
    queue_worker = asyncio.create_task(fish_queue_worker(fish_queue))
    logger.info("Fish queue worker started")
    try:
        yield
    finally:
        queue_worker.cancel()
        with suppress(asyncio.CancelledError):
            await queue_worker
        fish_queue = None
        queue_worker = None
        logger.info("Fish queue worker stopped")


app = FastAPI(title="Digital Aquarium Server", lifespan=lifespan)


@app.get("/health")
async def health_check() -> dict[str, Any]:
    queue = get_fish_queue()
    return {
        "status": "ok",
        "godot_clients": manager.godot_count,
        "tablet_clients": manager.tablet_count,
        "queue_size": queue.qsize(),
        "queue_max_size": FISH_QUEUE_MAX_SIZE,
    }


def resolve_client_type(data: dict[str, Any]) -> ClientType:
    if data.get("type") == "godot":
        return "godot"
    return "tablet"


async def handle_client_message(data: dict[str, Any], client_type: ClientType) -> None:
    message_type = data.get("type")
    if message_type == "fish":
        logger.info("Queued fish data from %s. Timestamp: %s", client_type, data.get("timestamp"))
        await get_fish_queue().put(data)
        return

    logger.info("Received message of type: %s from %s", message_type, client_type)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    logger.info("New WebSocket connection accepted")

    connection_type: ClientType | None = None
    try:
        # 初回メッセージでクライアントの種別を判定
        data = await websocket.receive_json()
        connection_type = resolve_client_type(data)
        manager.register(websocket, connection_type)
        await handle_client_message(data, connection_type)

        # 受信ループ
        while True:
            data = await websocket.receive_json()
            await handle_client_message(data, connection_type)

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected: %s", connection_type)
    except Exception as exc:
        logger.error("Error in websocket loop: %s", exc)
    finally:
        manager.disconnect(websocket, connection_type)

# 静的ファイルの配信設定
if os.path.exists(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")
    logger.info("Mounted server static files from: %s", static_dir)
else:
    logger.warning("Static directory not found at: %s", static_dir)

# ルート "/" にアクセスしたときに index.html が表示されるようにする
if os.path.exists(webapp_dir):
    app.mount("/", StaticFiles(directory=webapp_dir, html=True), name="webapp")
    logger.info("Mounted webapp static files from: %s", webapp_dir)
else:
    logger.warning("Webapp directory not found at: %s", webapp_dir)
