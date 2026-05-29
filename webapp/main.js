const FISH_TEMPLATES = [
    { id: 'fish_01', name: 'さかな', thumb: '/static/thumbnails/fish_01.png', template: '/static/template_fish/fish_01.png' },
    { id: 'fish_02', name: 'いか', thumb: '/static/thumbnails/fish_02.png', template: '/static/template_fish/fish_02.png' },
    { id: 'fish_03', name: 'たこ', thumb: '/static/thumbnails/fish_03.png', template: '/static/template_fish/fish_03.png' }
];

let selectedFishId = null;
let currentColor = '#ff5e57';
let templateImg = null;

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

// テンプレートグリッドの動的描画
function renderTemplateGrid() {
    const grid = document.getElementById('fish-select-grid');
    if (!grid) return;
    grid.innerHTML = '';
    
    FISH_TEMPLATES.forEach(tpl => {
        const item = document.createElement('div');
        item.className = 'fish-thumb';
        item.onclick = () => selectFish(tpl.id);
        
        const img = document.createElement('img');
        img.src = tpl.thumb;
        img.alt = tpl.name;
        img.className = 'fish-thumb-img';
        
        const label = document.createElement('span');
        label.className = 'fish-thumb-label';
        label.textContent = tpl.name;
        
        item.appendChild(img);
        item.appendChild(label);
        grid.appendChild(item);
    });
}

function selectFish(fishId) {
    console.log(`Selected fish: ${fishId}`);
    selectedFishId = fishId;
    sendButton.disabled = false;
    setSendStatus('');
    document.getElementById('step-select').classList.add('hidden');
    document.getElementById('step-paint').classList.remove('hidden');
    
    // キャンバスをクリア
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    const tpl = FISH_TEMPLATES.find(t => t.id === fishId);
    if (tpl) {
        templateImg = new Image();
        templateImg.onload = () => {
            ctx.drawImage(templateImg, 0, 0, canvas.width, canvas.height);
        };
        templateImg.src = tpl.template;
    }
}

function resetCanvas() {
    if (!selectedFishId || !templateImg) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(templateImg, 0, 0, canvas.width, canvas.height);
    setSendStatus('');
    console.log('Canvas reset to template');
}

function backToSelect() {
    selectedFishId = null;
    templateImg = null;
    sendButton.disabled = false;
    setSendStatus('');
    document.getElementById('step-select').classList.remove('hidden');
    document.getElementById('step-paint').classList.add('hidden');
}

function setColor(color, element) {
    console.log(`Color set to: ${color}`);
    currentColor = color;
    
    document.querySelectorAll('.color-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    if (element) {
        element.classList.add('active');
    }
}

// 16進数カラーコードをRGBオブジェクトに変換
function hexToRgb(hex) {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16)
    } : { r: 255, g: 255, b: 255 };
}

// スタックベースの Flood Fill アルゴリズム (境界透過保護付き)
function floodFill(startX, startY, fillRgb) {
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const data = imageData.data;
    const width = imageData.width;
    const height = imageData.height;

    const targetIdx = (startY * width + startX) * 4;
    const targetR = data[targetIdx];
    const targetG = data[targetIdx + 1];
    const targetB = data[targetIdx + 2];
    const targetA = data[targetIdx + 3];

    const fillR = fillRgb.r;
    const fillG = fillRgb.g;
    const fillB = fillRgb.b;
    const fillA = 255;

    // 輪郭線（完全な黒線）または輪郭付近の暗いピクセルは塗りつぶさない
    const isOutline = (targetR < 50 && targetG < 50 && targetB < 50 && targetA > 200);
    if (isOutline) {
        return;
    }

    // すでに同じ色で塗られている場合はスキップ
    if (targetR === fillR && targetG === fillG && targetB === fillB && targetA === fillA) {
        return;
    }

    const stack = [[startX, startY]];
    const visited = new Uint8Array(width * height);
    visited[startY * width + startX] = 1;
    
    const modifiedPixels = [];
    let touchesBorder = false;

    while (stack.length > 0) {
        const [cx, cy] = stack.pop();
        modifiedPixels.push((cy * width + cx) * 4);

        // キャンバスの境界（四辺）に到達したかチェック
        if (cx === 0 || cx === width - 1 || cy === 0 || cy === height - 1) {
            touchesBorder = true;
        }

        const neighbors = [
            [cx + 1, cy],
            [cx - 1, cy],
            [cx, cy + 1],
            [cx, cy - 1]
        ];

        for (const [nx, ny] of neighbors) {
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                const nIdx = ny * width + nx;
                if (visited[nIdx] === 0) {
                    const pIdx = nIdx * 4;
                    const r = data[pIdx];
                    const g = data[pIdx + 1];
                    const b = data[pIdx + 2];
                    const a = data[pIdx + 3];

                    // アルファチャンネルを含め、クリック対象色と一致するか判定
                    const isMatch = (r === targetR && g === targetG && b === targetB && a === targetA);
                    
                    if (isMatch) {
                        visited[nIdx] = 1;
                        stack.push([nx, ny]);
                    }
                }
            }
        }
    }

    // 境界に到達した場合は背景とみなして塗りつぶしを行わない（透過保護）
    if (touchesBorder) {
        console.log("Touched border. Background painting blocked.");
        setSendStatus("お魚のそと側はぬれないよ！", "error");
        setTimeout(() => {
            if (sendStatus.textContent === "お魚のそと側はぬれないよ！") {
                setSendStatus("");
            }
        }, 1500);
        return;
    }

    // 塗りつぶしの反映
    for (let i = 0; i < modifiedPixels.length; i++) {
        const idx = modifiedPixels[i];
        data[idx] = fillR;
        data[idx + 1] = fillG;
        data[idx + 2] = fillB;
        data[idx + 3] = fillA;
    }

    ctx.putImageData(imageData, 0, 0);
}

// マウスおよびタッチイベントの座標スケーリング処理
function handleCanvasDraw(event) {
    event.preventDefault();
    if (!selectedFishId) return;

    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;

    let clientX, clientY;
    if (event.touches && event.touches.length > 0) {
        clientX = event.touches[0].clientX;
        clientY = event.touches[0].clientY;
    } else {
        clientX = event.clientX;
        clientY = event.clientY;
    }

    const x = Math.floor((clientX - rect.left) * scaleX);
    const y = Math.floor((clientY - rect.top) * scaleY);

    if (x >= 0 && x < canvas.width && y >= 0 && y < canvas.height) {
        const fillRgb = hexToRgb(currentColor);
        floodFill(x, y, fillRgb);
    }
}

// Web Audio API を用いた効果音（水しぶき・泡音）のシンセサイズ
function playSplashSound() {
    try {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (!AudioContext) return;
        const audioCtx = new AudioContext();
        
        // 1つ目の泡音 (ポッ)
        const osc1 = audioCtx.createOscillator();
        const gain1 = audioCtx.createGain();
        osc1.connect(gain1);
        gain1.connect(audioCtx.destination);
        
        const now = audioCtx.currentTime;
        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(120, now);
        osc1.frequency.exponentialRampToValueAtTime(750, now + 0.12);
        
        gain1.gain.setValueAtTime(0.12, now);
        gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.12);
        
        osc1.start(now);
        osc1.stop(now + 0.12);

        // 2つ目の泡音 (少し遅れて高いピッチで)
        setTimeout(() => {
            if (audioCtx.state === 'closed') return;
            const osc2 = audioCtx.createOscillator();
            const gain2 = audioCtx.createGain();
            osc2.connect(gain2);
            gain2.connect(audioCtx.destination);
            
            const now2 = audioCtx.currentTime;
            osc2.type = 'sine';
            osc2.frequency.setValueAtTime(220, now2);
            osc2.frequency.exponentialRampToValueAtTime(1100, now2 + 0.1);
            
            gain2.gain.setValueAtTime(0.08, now2);
            gain2.gain.exponentialRampToValueAtTime(0.001, now2 + 0.1);
            
            osc2.start(now2);
            osc2.stop(now2 + 0.1);
        }, 40);
        
    } catch (e) {
        console.error("Web Audio API synthesis failed:", e);
    }
}

canvas.addEventListener('click', handleCanvasDraw);
canvas.addEventListener('touchstart', handleCanvasDraw, { passive: false });

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
    setSendStatus('水槽へ放流中...', 'pending');
    let sent = false;

    try {
        const dataUrl = await canvasToPngDataUrl();
        const message = {
            type: 'fish',
            image: dataUrl,
            timestamp: Math.floor(Date.now() / 1000)
        };

        console.log('Sending Base64 PNG, length:', dataUrl.length);
        socket.send(JSON.stringify(message));
        
        // 効果音の再生
        playSplashSound();
        
        // 放流アニメーションの起動
        const container = document.getElementById('canvas-container');
        container.classList.add('swim-away');

        setSendStatus('放流しました！ 🐠', 'success');
        sent = true;

        // アニメーション完了後に画面を戻す
        window.setTimeout(() => {
            container.classList.remove('swim-away');
            backToSelect();
        }, 2000);

    } catch (error) {
        console.error('Failed to send fish:', error);
        setSendStatus('送信できませんでした', 'error');
    } finally {
        if (!sent) {
            sendButton.disabled = false;
        }
    }
}

// 動的な泡の生成
function startBubbleAnimation() {
    const container = document.getElementById('bubbles-container');
    if (!container) return;

    setInterval(() => {
        const bubble = document.createElement('div');
        bubble.className = 'bubble';
        
        const size = Math.random() * 30 + 10;
        bubble.style.width = `${size}px`;
        bubble.style.height = `${size}px`;
        bubble.style.left = `${Math.random() * 100}%`;
        
        const duration = Math.random() * 5 + 5;
        bubble.style.animationDuration = `${duration}s`;
        
        container.appendChild(bubble);
        
        setTimeout(() => {
            bubble.remove();
        }, duration * 1000);
    }, 800);
}

connectWebSocket();
renderTemplateGrid();
startBubbleAnimation();
