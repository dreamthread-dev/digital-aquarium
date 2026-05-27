let selectedFishId = null;
let currentColor = '#ff5e57';
const canvas = document.getElementById('paint-canvas');
const ctx = canvas.getContext('2d');
const connectionStatus = document.getElementById('connection-status');
const connectionLabel = document.getElementById('connection-label');
const sendStatus = document.getElementById('send-status');
const sendButton = document.getElementById('send-btn');
const RECONNECT_DELAY_MS = 3000;

let reconnectTimerId = null;

function setConnectionState(state) {
    const labels = {
        connecting: '接続中',
        connected: '接続済み',
        reconnecting: '再接続中',
        disconnected: '未接続'
    };

    connectionStatus.dataset.state = state;
    connectionLabel.textContent = labels[state] || labels.disconnected;
}

function setSendStatus(message, state = '') {
    sendStatus.textContent = message;
    sendStatus.dataset.state = state;
}

function buildWebSocketUrl() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host || '127.0.0.1:8000';

    return `${protocol}//${host}/ws`;
}

function scheduleReconnect() {
    if (reconnectTimerId !== null) {
        return;
    }

    setConnectionState('reconnecting');
    reconnectTimerId = window.setTimeout(() => {
        reconnectTimerId = null;
        connectWebSocket();
    }, RECONNECT_DELAY_MS);
}

function connectWebSocket() {
    if (window.ws && [WebSocket.CONNECTING, WebSocket.OPEN].includes(window.ws.readyState)) {
        return;
    }

    setConnectionState('connecting');

    let socket = null;
    try {
        socket = new WebSocket(buildWebSocketUrl());
    } catch (error) {
        console.error('Failed to create WebSocket:', error);
        scheduleReconnect();
        return;
    }

    window.ws = socket;

    socket.addEventListener('open', () => {
        if (window.ws !== socket) {
            return;
        }

        setConnectionState('connected');
        socket.send(JSON.stringify({ type: 'tablet' }));
    });

    socket.addEventListener('message', (event) => {
        console.log('WebSocket message:', event.data);
    });

    socket.addEventListener('close', () => {
        if (window.ws !== socket) {
            return;
        }

        window.ws = null;
        scheduleReconnect();
    });

    socket.addEventListener('error', (error) => {
        if (window.ws === socket) {
            setConnectionState('disconnected');
        }

        console.error('WebSocket error:', error);
        socket.close();
    });
}

function getOpenWebSocket() {
    if (window.ws && window.ws.readyState === WebSocket.OPEN) {
        return window.ws;
    }

    return null;
}

function getFishShape() {
    return {
        centerX: canvas.width / 2,
        centerY: canvas.height / 2,
        bodyRadiusX: canvas.width * 0.29,
        bodyRadiusY: canvas.height * 0.16,
        tailWidth: canvas.width * 0.1,
        tailHeight: canvas.height * 0.12,
        outlineWidth: canvas.width * 0.02
    };
}

function drawFishOutline() {
    const shape = getFishShape();

    ctx.strokeStyle = '#000000';
    ctx.lineWidth = shape.outlineWidth;
    ctx.lineCap = 'round';

    ctx.beginPath();
    ctx.ellipse(
        shape.centerX,
        shape.centerY,
        shape.bodyRadiusX,
        shape.bodyRadiusY,
        0,
        0,
        2 * Math.PI
    );
    ctx.moveTo(shape.centerX - shape.bodyRadiusX, shape.centerY);
    ctx.lineTo(shape.centerX - shape.bodyRadiusX - shape.tailWidth, shape.centerY - shape.tailHeight);
    ctx.lineTo(shape.centerX - shape.bodyRadiusX * 1.2, shape.centerY);
    ctx.lineTo(shape.centerX - shape.bodyRadiusX - shape.tailWidth, shape.centerY + shape.tailHeight);
    ctx.closePath();
    ctx.stroke();
}

function fillFishBody() {
    const shape = getFishShape();

    ctx.fillStyle = currentColor;
    ctx.beginPath();
    ctx.ellipse(
        shape.centerX,
        shape.centerY,
        shape.bodyRadiusX * 0.93,
        shape.bodyRadiusY * 0.88,
        0,
        0,
        2 * Math.PI
    );
    ctx.fill();
}

function selectFish(fishId) {
    console.log(`Selected fish: ${fishId}`);
    selectedFishId = fishId;
    sendButton.disabled = false;
    setSendStatus('');
    document.getElementById('step-select').classList.add('hidden');
    document.getElementById('step-paint').classList.remove('hidden');
    
    // キャンバスをクリア
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    drawFishOutline();
}

function backToSelect() {
    selectedFishId = null;
    sendButton.disabled = false;
    setSendStatus('');
    document.getElementById('step-select').classList.remove('hidden');
    document.getElementById('step-paint').classList.add('hidden');
}

function setColor(color) {
    console.log(`Color set to: ${color}`);
    currentColor = color;
}

// キャンバスクリック時にその領域を現在の色で塗りつぶす (モック)
canvas.addEventListener('click', () => {
    // 簡易モック: クリックしたら魚の胴体を塗りつぶす動作を擬似的に行う
    fillFishBody();
    
    // 輪郭線を再描画して上書きを防ぐ
    drawFishOutline();
    
    console.log('Canvas clicked. Dummy filled.');
});

function canvasToPngDataUrl() {
    return new Promise((resolve, reject) => {
        if (!canvas.toBlob) {
            resolve(canvas.toDataURL('image/png'));
            return;
        }

        canvas.toBlob((blob) => {
            if (!blob) {
                reject(new Error('PNG blob generation failed'));
                return;
            }

            const reader = new FileReader();
            reader.addEventListener('load', () => resolve(reader.result));
            reader.addEventListener('error', () => reject(new Error('PNG Base64 conversion failed')));
            reader.readAsDataURL(blob);
        }, 'image/png');
    });
}

async function sendFish() {
    const socket = getOpenWebSocket();
    if (!socket) {
        setSendStatus('水槽に接続できていません', 'error');
        connectWebSocket();
        return;
    }

    if (!selectedFishId) {
        setSendStatus('魚を選んでください', 'error');
        return;
    }

    sendButton.disabled = true;
    setSendStatus('送信中', 'pending');
    let sent = false;

    try {
        const dataUrl = await canvasToPngDataUrl();
        const message = {
            type: 'fish',
            image: dataUrl,
            timestamp: Math.floor(Date.now() / 1000)
        };

        console.log('Generated Base64 PNG size:', dataUrl.length);
        socket.send(JSON.stringify(message));
        console.log('Sent message via WebSocket');
        setSendStatus('放流しました！', 'success');
        sent = true;
        window.setTimeout(backToSelect, 1000);
    } catch (error) {
        console.error('Failed to send fish:', error);
        setSendStatus('送信できませんでした', 'error');
    } finally {
        if (!sent) {
            sendButton.disabled = false;
        }
    }
}

connectWebSocket();
