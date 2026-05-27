import asyncio
import json
import socket
import time
import unittest
import urllib.request

import uvicorn
import websockets

import main
from main import BROADCAST_INTERVAL_SECONDS, app, manager


def reset_state() -> None:
    manager.godot_connections.clear()
    manager.tablet_connections.clear()
    if main.fish_queue is None:
        return

    while not main.fish_queue.empty():
        main.fish_queue.get_nowait()
        main.fish_queue.task_done()


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


async def read_url(url: str) -> tuple[int, str, bytes]:
    def _read() -> tuple[int, str, bytes]:
        with urllib.request.urlopen(url, timeout=3) as response:
            return response.status, response.headers.get("content-type", ""), response.read()

    return await asyncio.to_thread(_read)


class RunningServer:
    def __init__(self) -> None:
        self.port = find_free_port()
        config = uvicorn.Config(app, host="127.0.0.1", port=self.port, log_level="warning")
        self.server = uvicorn.Server(config)
        self.task: asyncio.Task[None] | None = None

    async def __aenter__(self) -> "RunningServer":
        self.task = asyncio.create_task(self.server.serve())
        await self._wait_until_ready()
        return self

    async def __aexit__(self, *_: object) -> None:
        self.server.should_exit = True
        if self.task is not None:
            await self.task

    async def _wait_until_ready(self) -> None:
        url = f"http://127.0.0.1:{self.port}/health"
        for _ in range(50):
            try:
                await read_url(url)
                return
            except Exception:
                await asyncio.sleep(0.1)
        raise TimeoutError("Server did not start in time")


class ServerTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        reset_state()

    async def test_health_endpoint_reports_connection_and_queue_state(self) -> None:
        async with RunningServer() as server:
            status, _, body = await read_url(f"http://127.0.0.1:{server.port}/health")

        self.assertEqual(status, 200)
        self.assertEqual(
            json.loads(body.decode("utf-8")),
            {
                "status": "ok",
                "godot_clients": 0,
                "tablet_clients": 0,
                "queue_size": 0,
                "queue_max_size": 50,
            },
        )

    async def test_static_template_assets_are_served(self) -> None:
        async with RunningServer() as server:
            status, content_type, _ = await read_url(
                f"http://127.0.0.1:{server.port}/static/template_fish/fish_01.png"
            )

        self.assertEqual(status, 200)
        self.assertEqual(content_type, "image/png")

    async def test_tablet_fish_message_is_queued_and_broadcast_to_godot(self) -> None:
        fish_message = {
            "type": "fish",
            "image": "data:image/png;base64,ZmFrZQ==",
            "timestamp": 1234567890,
        }

        async with RunningServer() as server:
            async with websockets.connect(f"ws://127.0.0.1:{server.port}/ws") as godot_ws:
                await godot_ws.send(json.dumps({"type": "godot"}))
                async with websockets.connect(f"ws://127.0.0.1:{server.port}/ws") as tablet_ws:
                    await tablet_ws.send(json.dumps({"type": "tablet"}))
                    await tablet_ws.send(json.dumps(fish_message))
                    received = json.loads(await godot_ws.recv())

        self.assertEqual(received, fish_message)

    async def test_fish_queue_broadcasts_at_half_second_intervals(self) -> None:
        first_message = {
            "type": "fish",
            "image": "data:image/png;base64,Zmlyc3Q=",
            "timestamp": 1,
        }
        second_message = {
            "type": "fish",
            "image": "data:image/png;base64,c2Vjb25k",
            "timestamp": 2,
        }

        async with RunningServer() as server:
            async with websockets.connect(f"ws://127.0.0.1:{server.port}/ws") as godot_ws:
                await godot_ws.send(json.dumps({"type": "godot"}))
                async with websockets.connect(f"ws://127.0.0.1:{server.port}/ws") as tablet_ws:
                    await tablet_ws.send(json.dumps({"type": "tablet"}))
                    await tablet_ws.send(json.dumps(first_message))
                    first_received = json.loads(await godot_ws.recv())
                    first_received_at = time.monotonic()

                    await tablet_ws.send(json.dumps(second_message))
                    second_received = json.loads(await godot_ws.recv())
                    second_received_at = time.monotonic()

        self.assertEqual(first_received, first_message)
        self.assertEqual(second_received, second_message)
        self.assertGreaterEqual(
            second_received_at - first_received_at,
            BROADCAST_INTERVAL_SECONDS * 0.8,
        )


if __name__ == "__main__":
    unittest.main()
