#!/usr/bin/env python3
"""
画像生成 & 背景除去パイプライン

使い方:
  # 全キャラ一括
  py -3 tools/generate_sprites.py

  # 1キャラだけ再生成
  py -3 tools/generate_sprites.py --id student_rina

  # 既存 raw PNG に背景除去だけ適用（生成スキップ）
  py -3 tools/generate_sprites.py --id player_male --raw-only

出力先:
  assets/sprites/<id>_48x48.png   ... 背景透過済み最終ファイル
  assets/sprites/raw/<id>_raw.png ... 生成直後の raw（白背景）
"""
import os, sys, requests, base64, io, argparse
from pathlib import Path
from PIL import Image
from dotenv import load_dotenv
import numpy as np
from collections import deque

load_dotenv()
API_KEY = os.environ["GEMINI_API_KEY"]
MODEL   = "gemini-2.5-flash-image"
API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={API_KEY}"

OUT_DIR = Path("assets/sprites")
RAW_DIR = Path("assets/sprites/raw")

# ── キャラクター定義 ───────────────────────────────────
CHARACTERS = [
    # 転校生9体
    {"id": "student_rina",  "desc": "pink twin-tails, sparkly eyes, ribbon accessories",           "adj": "cheerful sparkling"},
    {"id": "student_kenta", "desc": "short dark hair, glasses, tidy uniform",                       "adj": "serious studious"},
    {"id": "student_ren",   "desc": "spiky dyed-brown hair, partially open collar, wristband",      "adj": "confident cool"},
    {"id": "student_haru",  "desc": "wavy orange hair, wide grin, colorful bag",                    "adj": "energetic funny"},
    {"id": "student_zero",  "desc": "black hair covering one eye, expressionless, simple uniform",  "adj": "mysterious silent"},
    {"id": "student_maki",  "desc": "long straight black hair, neat bow tie, calm expression",      "adj": "elegant quiet"},
    {"id": "student_goro",  "desc": "short spiky red hair, broad shoulders, bandana around neck",   "adj": "energetic tough"},
    {"id": "student_sora",  "desc": "messy blue hair, oversized uniform, headphones around neck",   "adj": "daydreaming relaxed"},
    {"id": "student_taku",  "desc": "brown bowl-cut hair, plain uniform, gentle smile",             "adj": "friendly average"},
    # 主人公・校長
    {"id": "player_male",   "desc": "short spiky brown hair, white dress shirt, navy pants, light blue necktie, waving hand",  "adj": "friendly energetic"},
    {"id": "player_female", "desc": "plain straight dark brown bob cut, no accessories, white sailor uniform, navy skirt",     "adj": "calm neutral"},
    {"id": "principal",     "desc": "grey hair, glasses, formal suit, gentle expression",                                      "adj": "dignified calm"},
]

CHAR_MAP = {c["id"]: c for c in CHARACTERS}

# ── プロンプトビルダー ─────────────────────────────────
def build_prompt(desc: str, adj: str) -> str:
    return (
        f"Cute chibi anime character, 2-head proportion, big head small body, {desc}, "
        "Japanese school uniform, thick black outline, flat colors, no gradient, pastel palette, "
        "pure white background, NO white sticker border, NO drop shadow, "
        f"large expressive eyes, {adj} pose, clean vector-like style, game sprite style"
    )

# ── 画像生成（Gemini API）────────────────────────────
def generate_image(prompt: str) -> bytes:
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    res = requests.post(API_URL, json=payload)
    res.raise_for_status()
    for part in res.json()["candidates"][0]["content"]["parts"]:
        if "inlineData" in part:
            return base64.b64decode(part["inlineData"]["data"])
    raise ValueError("No image data in response")

# ── 背景除去（BFS フラッドフィル）────────────────────
def remove_bg(png_bytes: bytes, tolerance: int = 30) -> Image.Image:
    img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    w, h = img.size
    data = np.array(img, dtype=np.float32)

    is_bg = np.sqrt(np.sum((data[:, :, :3] - 255.0) ** 2, axis=2)) < tolerance

    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg[y, x] and not visited[y, x]:
                visited[y, x] = True; queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg[y, x] and not visited[y, x]:
                visited[y, x] = True; queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg[ny, nx]:
                visited[ny, nx] = True; queue.append((ny, nx))

    result = data.astype(np.uint8)
    result[:, :, 3] = np.where(visited, 0, 255)
    return Image.fromarray(result)

# ── 1キャラ処理 ────────────────────────────────────────
def process(char: dict, raw_only: bool = False) -> None:
    sid = char["id"]
    raw_path = RAW_DIR / f"{sid}_raw.png"
    out_path = OUT_DIR / f"{sid}_48x48.png"

    if raw_only:
        if not raw_path.exists():
            print(f"[NG] {sid}: raw file not found -> {raw_path}")
            return
        print(f"[...] {sid} removing bg from existing raw...")
        raw_bytes = raw_path.read_bytes()
    else:
        print(f"[...] {sid} generating...")
        raw_bytes = generate_image(build_prompt(char["desc"], char["adj"]))
        raw_path.write_bytes(raw_bytes)
        print(f"      raw saved -> {raw_path}")

    img = remove_bg(raw_bytes)
    img.save(out_path, "PNG")
    print(f"[OK]  {sid} -> {out_path}")

# ── エントリポイント ───────────────────────────────────
if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    parser = argparse.ArgumentParser(description="Sprite generation & bg removal pipeline")
    parser.add_argument("--id",       help="対象キャラID（省略時は全キャラ）")
    parser.add_argument("--raw-only", action="store_true", help="既存rawに背景除去だけ適用（生成スキップ）")
    args = parser.parse_args()

    if args.id:
        if args.id not in CHAR_MAP:
            print(f"[NG] Unknown id: {args.id}")
            print(f"     Available: {', '.join(CHAR_MAP)}")
            sys.exit(1)
        targets = [CHAR_MAP[args.id]]
    else:
        targets = CHARACTERS

    for char in targets:
        try:
            process(char, raw_only=args.raw_only)
        except Exception as e:
            print(f"[NG] {char['id']} failed: {e}")
