# 🐠 デジタル水族館システム｜セッション引き継ぎ情報

このファイルは別セッションへの引き継ぎ用です。  
グリルセッションで確定した設計判断をすべて記載しています。

---

## 📌 プロジェクト基本情報

| 項目 | 内容 |
|------|------|
| リポジトリ | https://github.com/dreamthread-dev/digital-aquarium |
| 実装プラン | https://dreamthread-dev.github.io/digital-aquarium/ |
| GitHub アカウント | Boom0115（組織: dreamthread-dev） |
| ユーザーメール | takahashi@dreamthread.co.jp |
| プロジェクト性質 | イベント用デモ（締め切りなし） |
| バージョン | v1.0.0 |

---

## 🎯 システム概要

イベント会場中央に **4K縦モニター 4枚横並び（8640×3840）** を設置し、  
巨大な横長 2D 水槽を表示する。  
参加者（主に子ども）がタブレットで魚の線画を塗り絵し、放流ボタンで送信すると  
巨大スクリーンに魚が出現して泳ぎ始める。

**3システム構成：**
1. Godot 4.6（巨大スクリーン側）
2. Python FastAPI WebSocket サーバー
3. HTML5 Web アプリ（Android タブレット側）

---

## ✅ 確定仕様（グリルで決定した全事項）

### インフラ
- **モニター**: 4枚・8640×3840・PC 1台（RTX4090）
- **Godot**: 4.6
- **サーバー**: FastAPI 1本（WebSocket + 静的ファイル配信を統合）
- **ネットワーク**: 開発時 → PC ホットスポット / 本番 → Wi-Fi ルーター（5GHz）
- **タブレット**: Android × 4〜6台（Chrome）
- **開発者スキル**: 全技術（Godot / Python / JS / WebSocket）で本番実装経験あり
- **推奨OS構成**:
  - **1台運用時**: Windows 11 (Pro)。RTX 4090 による 8640×3840 画面出力（NVIDIA Mosaic）とサーバー動作を同PCで統合。
  - **2台分割時**:
    - 表示PC① (Godot): Windows 11 (Pro) (GPU制御のため必須)。
    - サーバーPC② (FastAPI): Windows 11 (モバイルホットスポットの容易さ重視) または Linux (Ubuntu Server) (連続稼働の安定性重視)。
- **開発・実行環境方針**:
  - **FastAPI サーバー**: 環境の再現性や本番環境（Linux 等）との一貫性のため、Docker / Dev Containers の使用を推奨（ポート `8000` はホストにマッピング）。
  - **Godot**: GPU（RTX 4090）のネイティブ性能とマルチディスプレイへの安定描画を確保するため、コンテナ化せず必ずホストOS上で直接実行する。

### 水槽・魚
- **最大匹数**: 300匹。超えたら最古の魚が泡パーティクルで消滅
- **デフォルト魚**: 起動時 20〜30匹（内蔵単色 PNG）。参加者の魚と混在
- **Boids**: 全種混在（同種グループなし）・Quadtree 空間分割・MultiMeshInstance2D
- **ふらつき**: FastNoiseLite（Perlin Noise）・個体ごとの固有 ID で異なる位相
- **速度**: 80〜150 px/秒・個体差 ±20%
- **方向転換**: `flip_v` + `velocity.angle()` + `lerp_angle()` でなめらか
- **体の揺れ**: Vertex Shader（sin 波・尾びれほど振幅大）
- **サイズ**: 基準 200px・ランダム 0.75〜1.25 倍スケール
- **奥行き**: `depth`（0.0〜1.0）で scale / modulate / z_index を制御
- **登場演出**: 上から落下 → 着水時に水しぶきパーティクル（CPUParticles2D）
- **消滅演出**: 泡パーティクル（CPUParticles2D・上方向に浮かぶ泡 + フェードアウト）
- **背景 Shader**: Caustics（深海ブルー + 光の揺らぎ・TIME アニメーション）
- **画面 UI**: 魚数カウンター + イベント名（半透明帯）・F2 で非表示切り替え
- **デバッグ UI**: F1 で ON/OFF・Boids 全パラメータをリアルタイムスライダー調整

### Boids パラメータ初期値（F1 デバッグ UI で調整可能）
- 基準速度: 120 px/秒
- Separation 半径: 80 px
- Alignment 半径: 150 px
- Cohesion 半径: 200 px
- 壁反発距離: 300 px
- Wander Strength: 30.0
- 体の揺れ強度: 0.03

### タブレット（塗り絵アプリ）
- **UI**: 縦型 3ステップ（線画選択 → 塗り絵 → 放流）
- **線画テンプレート**: 8種類程度・手書きスキャン or AI生成・事前二値化
- **塗り絵方式**: バケツ塗りのみ（Flood Fill）・完全一致・二値化済み線画前提
- **カラーパレット**: 12色 + リセットボタン・明るめの子ども向け配色
- **送信 PNG**: 1024×1024px・Canvas を toBlob() → Base64 → WebSocket 送信
- **放流後演出**: 魚が右へ泳いで画面外へ消えるアニメ（CSS・1〜2秒）→「放流しました！」テキスト（2秒）→ 自動で線画選択へ戻る
- **1セッション**: 1匹のみ
- **効果音**: 放流時に着水音（Web Audio API）
- **再接続**: 切断時に 3秒リトライ自動再接続（接続インジケーター表示）

### サーバー（FastAPI）
- **エンドポイント**: `/ws`（WebSocket）・`/`（index.html）・`/static/`（線画 PNG）
- **接続管理**: `type` フィールドで `"godot"` / `"tablet"` を分類
- **放流キュー**: `asyncio.Queue(maxsize=50)`・0.5秒間隔でブロードキャスト
- **Godot 再接続**: 切断時に 3秒リトライ

### 音響
- **タブレット**: 放流時に着水音
- **スクリーン**: 水の環境音ループ（AudioStreamPlayer + OGG）

### 通信仕様（JSON）
```json
{
  "type": "fish",
  "image": "data:image/png;base64,xxxx",
  "timestamp": 1234567890
}
```

---

## 📁 ファイル構成

```
digital-aquarium/
├── docs/
│   └── implementation-plan.html   ← 実装プラン（GitHub Pages で閲覧可）
├── CONTEXT.md                     ← このファイル
│
├── server/                        ← Python FastAPI サーバー
│   ├── main.py
│   ├── requirements.txt
│   ├── static/
│   │   ├── fish/                  ← 線画 PNG（二値化済み）
│   │   └── thumbnails/            ← サムネイル（256×256px）
│   └── tools/
│       └── binarize.py            ← 線画二値化スクリプト
│
├── webapp/                        ← タブレット塗り絵アプリ
│   ├── index.html
│   ├── style.css
│   └── main.js
│
└── godot/                         ← Godot 4.6 プロジェクト
    ├── project.godot
    ├── scenes/
    │   ├── AquariumScene.tscn
    │   ├── Fish.tscn
    │   └── DebugUI.tscn
    ├── scripts/
    │   ├── FishManager.gd         ← 300匹管理・FIFO
    │   ├── Fish.gd                ← Boids + Perlin Noise
    │   ├── Quadtree.gd            ← 空間分割
    │   ├── WebSocketClient.gd     ← 通信・自動再接続
    │   ├── DebugUI.gd             ← F1 パラメータ調整
    │   └── HUD.gd                 ← 魚数カウンター
    ├── shaders/
    │   ├── aquarium_bg.gdshader   ← Caustics 背景
    │   └── fish_body.gdshader     ← 体の揺れ Vertex Shader
    ├── fish/defaults/             ← 起動時デフォルト魚 PNG
    └── audio/
        ├── ambient_water.ogg
        └── splash.ogg
```

---

## 📌 GitHub Issues（#1〜#21）

### 🟣 Godot（#1〜#12）
| # | タイトル |
|---|---------|
| #1 | プロジェクト初期設定・巨大ウィンドウ（8640×3840） |
| #2 | 水槽背景 Shader（Caustics・光の揺らぎ） |
| #3 | Boids + Quadtree による 300匹群れシミュレーション |
| #4 | Perlin Noise ふらつき・方向転換・体の揺れ |
| #5 | 奥行き（depth）・サイズ・色の制御 |
| #6 | 魚の登場演出（上から落下 + 着水パーティクル） |
| #7 | 魚の消滅演出（泡パーティクル） |
| #8 | WebSocketClient.gd（PNG受信・Base64変換・自動再接続） |
| #9 | デフォルト魚（起動時 20〜30匹を内蔵） |
| #10 | デバッグ UI（F1 ON/OFF・Boids パラメータスライダー） |
| #11 | 画面 UI（魚数カウンター・イベント名） |
| #12 | 環境音（水のループ再生） |

### 🔵 Python FastAPI（#13〜#15）
| # | タイトル |
|---|---------|
| #13 | FastAPI 基本構成（WebSocket + 静的ファイル配信） |
| #14 | 接続管理・ブロードキャスト（タブレット / Godot） |
| #15 | 放流キュー（0.5秒間隔ブロードキャスト） |

### 🟡 Web アプリ（#16〜#19）
| # | タイトル |
|---|---------|
| #16 | 基本 HTML/CSS レイアウト（縦型3ステップ UI） |
| #17 | Canvas 塗り絵（Flood Fill・12色パレット・リセット） |
| #18 | PNG Base64 生成・WebSocket 送信・自動再接続 |
| #19 | 放流後演出（魚が泳いで消える → テキスト → 自動リセット） |

### 🟢 準備・統合（#20〜#23）
| # | タイトル |
|---|---------|
| #20 | 線画 PNG の作成・二値化処理 |
| #21 | 全体起動手順・接続確認・テスト |
| #22 | 【環境構築】FastAPI サーバー用開発コンテナ (Docker / Dev Containers) のセットアップ |
| #23 | 【準備】ディレクトリ構造の作成とプロジェクト骨組み（スケルトン）の初期配置 |

---

## 🚀 推奨実装順序

1. **#23** 【準備】ディレクトリ構造の作成とプロジェクト骨組み（スケルトン）の初期配置
2. **#22** 【環境構築】FastAPI サーバー用開発コンテナのセットアップ
3. **#20** 線画 PNG 準備・二値化（素材がないと他が進まない）
4. **#13〜#15** Python サーバー（最初に動かすと他のテストが楽）
5. **#16〜#19** Web 塗り絵アプリ（サーバーと並行開発可）
6. **#1〜#2** Godot 初期設定・背景 Shader
7. **#3〜#5** Boids / Quadtree / 奥行き
8. **#6〜#7** 登場・消滅演出
9. **#8** WebSocket 接続（サーバーと疎通確認）
10. **#9〜#12** デフォルト魚・UI・音
11. **#21** 全体統合テスト

---

## 💡 新セッションへの指示

このファイルと以下を読み込んで作業を開始してください：

```
gh repo clone dreamthread-dev/digital-aquarium
cat CONTEXT.md
```

実装プランの詳細は `docs/implementation-plan.html` または  
https://dreamthread-dev.github.io/digital-aquarium/ を参照してください。
