#!/usr/bin/env python3
"""
使い方:
  python3 tools/remove_bg.py <入力PNG> <出力PNG>
例:
  python3 tools/remove_bg.py assets/sprites/rina_raw.png assets/sprites/rina.png
"""
import sys
from pathlib import Path
from PIL import Image
import numpy as np
from collections import deque


def remove_background(input_path: str, output_path: str, tolerance: int = 30) -> None:
    """
    ボーダーから繋がった白ピクセルをフラッドフィルで透過する。
    フラットカラーアニメ素材向け（MLモデル不使用）。
    """
    img = Image.open(input_path).convert("RGBA")
    w, h = img.size
    data = np.array(img, dtype=np.float32)

    # 白からの距離マスク（tolerance 以内 → 背景候補）
    rgb = data[:, :, :3]
    white_dist = np.sqrt(np.sum((rgb - 255.0) ** 2, axis=2))
    is_bg_candidate = white_dist < tolerance

    # BFS: 画像の外周ピクセルから繋がった背景候補のみ透過対象とする
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()

    for x in range(w):
        if is_bg_candidate[0, x] and not visited[0, x]:
            visited[0, x] = True
            queue.append((0, x))
        if is_bg_candidate[h - 1, x] and not visited[h - 1, x]:
            visited[h - 1, x] = True
            queue.append((h - 1, x))
    for y in range(h):
        if is_bg_candidate[y, 0] and not visited[y, 0]:
            visited[y, 0] = True
            queue.append((y, 0))
        if is_bg_candidate[y, w - 1] and not visited[y, w - 1]:
            visited[y, w - 1] = True
            queue.append((y, w - 1))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_candidate[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    # 透過適用
    result = data.astype(np.uint8)
    result[:, :, 3] = np.where(visited, 0, 255)

    out = Image.fromarray(result)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    out.save(output_path, "PNG")
    print(f"[OK] Saved: {output_path}  size: {out.size}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python3 remove_bg.py <input> <output>")
        sys.exit(1)
    remove_background(sys.argv[1], sys.argv[2])
