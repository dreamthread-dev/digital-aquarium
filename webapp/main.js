let selectedFishId = null;
let currentColor = '#ff5e57';
const canvas = document.getElementById('paint-canvas');
const ctx = canvas.getContext('2d');

function selectFish(fishId) {
    console.log(`Selected fish: ${fishId}`);
    selectedFishId = fishId;
    document.getElementById('step-select').classList.add('hidden');
    document.getElementById('step-paint').classList.remove('hidden');
    
    // キャンバスをクリア
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // 簡易的なダミー線画（魚の形の輪郭線）を描く
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 10;
    ctx.lineCap = 'round';
    
    // 簡易的な魚の形
    ctx.beginPath();
    // 胴体
    ctx.ellipse(canvas.width / 2, canvas.height / 2, 150, 80, 0, 0, 2 * Math.PI);
    // 尾びれ
    ctx.moveTo(canvas.width / 2 - 150, canvas.height / 2);
    ctx.lineTo(canvas.width / 2 - 200, canvas.height / 2 - 60);
    ctx.lineTo(canvas.width / 2 - 180, canvas.height / 2);
    ctx.lineTo(canvas.width / 2 - 200, canvas.height / 2 + 60);
    ctx.closePath();
    ctx.stroke();
}

function backToSelect() {
    document.getElementById('step-select').classList.remove('hidden');
    document.getElementById('step-paint').classList.add('hidden');
}

function setColor(color) {
    console.log(`Color set to: ${color}`);
    currentColor = color;
}

// キャンバスクリック時にその領域を現在の色で塗りつぶす (モック)
canvas.addEventListener('click', (e) => {
    // 簡易モック: クリックしたら魚の胴体を塗りつぶす動作を擬似的に行う
    ctx.fillStyle = currentColor;
    ctx.beginPath();
    ctx.ellipse(canvas.width / 2, canvas.height / 2, 140, 70, 0, 0, 2 * Math.PI);
    ctx.fill();
    
    // 輪郭線を再描画して上書きを防ぐ
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 10;
    ctx.beginPath();
    ctx.ellipse(canvas.width / 2, canvas.height / 2, 150, 80, 0, 0, 2 * Math.PI);
    ctx.stroke();
    
    console.log("Canvas clicked. Dummy filled.");
});

function sendFish() {
    console.log("Sending fish data...");
    
    // Canvas から Base64 データを取得
    const dataUrl = canvas.toDataURL('image/png');
    
    // サーバーへの送信メッセージ作成
    const message = {
        type: 'fish',
        image: dataUrl,
        timestamp: Math.floor(Date.now() / 1000)
    };
    
    console.log("Generated Base64 PNG size:", dataUrl.length);
    
    // WebSocketが有効な場合は送信を試みる（後ほど実装）
    if (window.ws && window.ws.readyState === WebSocket.OPEN) {
        window.ws.send(JSON.stringify(message));
        console.log("Sent message via WebSocket");
    } else {
        console.log("WebSocket is not connected. Message not sent via WS.");
    }
    
    alert("放流メッセージを生成しました！(コンソールログを確認してください)");
    backToSelect();
}
