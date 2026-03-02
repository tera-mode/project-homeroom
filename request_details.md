# 背景透過パイプライン — Claude Code テスト手順書

> **目的：** Gemini Imagen で生成した白背景スプライトを `rembg` で透過処理し、
> Godot プロジェクトの `assets/sprites/` に配置するまでを確認する。

---

## 0. 前提・ファイル構成

```
project-homeroom/
├── tools/
│   ├── remove_bg.py          # 単体テスト用（1枚処理）
│   └── generate_sprites.py   # 本番用（全キャラ一括）
├── assets/sprites/           # 生成物の出力先
└── .env                      # GEMINI_API_KEY を記述
```

---

## 1. 環境セットアップ

Claude Code のターミナルで以下を実行：

```bash
# rembg と依存ライブラリをインストール
pip install rembg pillow onnxruntime

# .env に API キーが入っているか確認
cat .env | grep GEMINI_API_KEY
```

> **初回だけ** rembg がモデルファイル（約170MB）をダウンロードするので少し時間がかかる。

---

## 2. Step 1 — 単体テスト（手持ちの PNG 1枚で確認）

### `tools/remove_bg.py`

```python
#!/usr/bin/env python3
"""
使い方:
  python3 tools/remove_bg.py <入力PNG> <出力PNG>
例:
  python3 tools/remove_bg.py assets/sprites/rina_raw.png assets/sprites/rina.png
"""
import sys
from pathlib import Path
from rembg import remove, new_session
from PIL import Image
import io

def remove_background(input_path: str, output_path: str) -> None:
    # アニメキャラに相性の良いモデルを指定
    session = new_session("u2net_human_seg")

    with open(input_path, "rb") as f:
        raw = f.read()

    # 背景除去（白背景の残像も消すオプション付き）
    result = remove(
        raw,
        session=session,
        alpha_matting=True,
        alpha_matting_foreground_threshold=240,
        alpha_matting_background_threshold=10,
    )

    img = Image.open(io.BytesIO(result)).convert("RGBA")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    img.save(output_path, "PNG")
    print(f"✅ 保存完了: {output_path}  サイズ: {img.size}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python3 remove_bg.py <input> <output>")
        sys.exit(1)
    remove_background(sys.argv[1], sys.argv[2])
```

### 実行コマンド

```bash
# テスト用にダミー画像を1枚用意して実行
python3 tools/remove_bg.py assets/sprites/student_rina_raw.png \
                           assets/sprites/student_rina_48x48.png

# 透過されているか確認（PNG の alpha チャンネルが存在するか）
python3 -c "
from PIL import Image
img = Image.open('assets/sprites/student_rina_48x48.png')
print('mode:', img.mode)   # RGBA ならOK
print('size:', img.size)
"
```

---

## 3. Step 2 — Imagen API 連携テスト（1キャラ生成 → 透過）

### `tools/generate_sprites.py`（まず1キャラで試す）

```python
#!/usr/bin/env python3
"""
Gemini Imagen で生成 → rembg で透過 → assets/sprites/ に保存
"""
import os, requests, base64, io
from pathlib import Path
from rembg import remove, new_session
from PIL import Image
from dotenv import load_dotenv

load_dotenv()
API_KEY = os.environ["GEMINI_API_KEY"]
API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-001:predict?key={API_KEY}"

# ── キャラクター定義 ──────────────────────────────────
STUDENTS = [
    {
        "id": "student_rina",
        "desc": "pink twin-tails, sparkly eyes, ribbon accessories",
        "adj":  "cheerful sparkling",
    },
    {
        "id": "student_kenta",
        "desc": "short dark hair, glasses, tidy uniform",
        "adj":  "serious studious",
    },
    {
        "id": "student_ren",
        "desc": "spiky dyed-brown hair, partially open collar, wristband",
        "adj":  "confident cool",
    },
    {
        "id": "student_haru",
        "desc": "wavy orange hair, wide grin, colorful bag",
        "adj":  "energetic funny",
    },
    {
        "id": "student_zero",
        "desc": "black hair covering one eye, expressionless, simple uniform",
        "adj":  "mysterious silent",
    },
]

# ── プロンプトビルダー ─────────────────────────────────
def build_prompt(desc: str, adj: str) -> str:
    return (
        f"Cute chibi anime character, 2-head proportion, {desc}, "
        "Japanese school uniform (white shirt, navy skirt/pants), "
        "thick black outline, flat colors, no gradient, pastel color palette, "
        "pure white background, large expressive eyes, simple kawaii expression, "
        f"{adj} pose, no shading, clean vector-like style, "
        "192x192 pixels, game sprite style, isolated character on white"
    )

# ── 画像生成（Imagen API）────────────────────────────
def generate_image(prompt: str) -> bytes:
    payload = {
        "instances": [{"prompt": prompt}],
        "parameters": {"sampleCount": 1, "aspectRatio": "1:1"},
    }
    res = requests.post(API_URL, json=payload)
    res.raise_for_status()
    b64 = res.json()["predictions"][0]["bytesBase64Encoded"]
    return base64.b64decode(b64)

# ── 背景除去（rembg）─────────────────────────────────
_session = None
def get_session():
    global _session
    if _session is None:
        _session = new_session("u2net_human_seg")
    return _session

def remove_bg(png_bytes: bytes) -> Image.Image:
    result = remove(
        png_bytes,
        session=get_session(),
        alpha_matting=True,
        alpha_matting_foreground_threshold=240,
        alpha_matting_background_threshold=10,
    )
    return Image.open(io.BytesIO(result)).convert("RGBA")

# ── メイン処理 ─────────────────────────────────────────
def process_student(student: dict, out_dir: Path) -> None:
    sid   = student["id"]
    print(f"⏳ {sid} を生成中...")

    prompt    = build_prompt(student["desc"], student["adj"])
    raw_bytes = generate_image(prompt)

    # 中間ファイル（デバッグ用、不要なら削除可）
    raw_path = out_dir / f"{sid}_raw.png"
    raw_path.write_bytes(raw_bytes)

    # 背景除去
    img = remove_bg(raw_bytes)

    # 192→48px にリサイズ
    img = img.resize((48, 48), Image.LANCZOS)

    out_path = out_dir / f"{sid}_48x48.png"
    img.save(out_path, "PNG")
    print(f"✅ {sid} 完了 → {out_path}")

if __name__ == "__main__":
    out_dir = Path("assets/sprites")
    out_dir.mkdir(parents=True, exist_ok=True)

    # まず1キャラだけで試す場合は STUDENTS[:1] に変更
    for student in STUDENTS[:1]:
        try:
            process_student(student, out_dir)
        except Exception as e:
            print(f"❌ {student['id']} 失敗: {e}")
```

### 実行コマンド

```bash
# 1キャラだけ試す（STUDENTS[:1] がデフォルト）
python3 tools/generate_sprites.py

# 成功したら全キャラ処理（スクリプト内の [:1] を削除して再実行）
python3 tools/generate_sprites.py
```

---

## 4. 結果の確認方法

```bash
# ファイルが生成されているか
ls -la assets/sprites/

# alpha チャンネルの確認（全スプライト一括）
python3 -c "
from PIL import Image
from pathlib import Path
for p in sorted(Path('assets/sprites').glob('*_48x48.png')):
    img = Image.open(p)
    has_alpha = img.mode == 'RGBA'
    print(f'{'✅' if has_alpha else '❌'} {p.name}  mode={img.mode}  size={img.size}')
"
```

---

## 5. トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| 輪郭がボヤける | アンチエイリアスの残像 | `alpha_matting=True` のしきい値を調整 |
| キャラの一部が消える | 背景色とキャラ色が近い | プロンプトに `"pure white background"` を強調 |
| `u2net_human_seg` が遅い | 高精度モデル | テストは `"u2net"` に変えて速度優先 |
| RGBA でない | PIL の保存ミス | `.convert("RGBA")` 後に保存しているか確認 |
| API エラー 429 | レート制限 | `time.sleep(3)` をキャラ間に入れる |

---

## 6. Godot 側で確認

生成した PNG を Godot で表示する最小コード：

```gdscript
# 透過PNGをそのまま TextureRect に設定するだけでOK
var tex = ImageTexture.create_from_image(
    Image.load_from_file("res://assets/sprites/student_rina_48x48.png")
)
$CharacterSprite.texture = tex
```

> Godot の `TextureRect` は RGBA PNG をそのまま扱えるので追加設定は不要。

---

## まとめ・推奨順序

```
1. pip install rembg pillow onnxruntime
2. tools/remove_bg.py で手持ちPNG1枚をテスト → alpha確認
3. generate_sprites.py を STUDENTS[:1] で1キャラ試す
4. 品質OKなら全キャラ一括実行
5. Godot で表示確認
```