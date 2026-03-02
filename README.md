# 転校生ガチャ！ — 開発 README

> **Claude Code 向け作業ガイド。新規セッションでもここを読めばすぐ動ける。**

---

## プロジェクト概要

| 項目 | 値 |
|---|---|
| タイトル | 転校生ガチャ！ |
| ジャンル | ローグライト × 配置パズル × 学園シミュレーション |
| エンジン | Godot 4.x / GDScript |
| 解像度 | 1280×720 |
| 盤面 | 4×4 = 16席、30日ループ |

詳細仕様 → `CLAUDE_CODE_REQUIREMENTS.md`
ビジュアル方針 → `DESIGN_POLICY.md`

---

## ディレクトリ構成

```
project-homeroom/
├── assets/
│   ├── sprites/               # 透過済みスプライト（RGBA 1024×1024）
│   │   └── raw/               # 生成直後の白背景 raw（常に保持）
│   └── backgrounds/           # 背景画像
├── data/                      # ゲームデータ JSON
│   ├── students.json          # 転校生9体のマスタ
│   ├── abilities.json         # 特殊能力10種
│   ├── types.json             # 4タイプ定義
│   └── cinematic_scenes.json  # オープニング演出
├── scenes/                    # Godot シーン（.tscn）
├── scripts/                   # GDScript（.gd）
├── tools/                     # Python ツール群
│   ├── generate_sprites.py    # 画像生成 & 背景除去パイプライン ★
│   └── remove_bg.py           # 単体背景除去
├── saves/                     # セーブデータ（git管理外）
├── CLAUDE_CODE_REQUIREMENTS.md
├── DESIGN_POLICY.md
└── README.md                  # このファイル
```

---

## 環境セットアップ

### 必須ツール

| ツール | パス / コマンド |
|---|---|
| Godot 4.6.1 | `C:\Program Files\Godot\Godot_v4.6.1-stable_win64_console.exe` |
| Python | `py -3`（`python` / `python3` は使用不可） |

### Python 依存ライブラリ（初回のみ）

```bash
py -3 -m pip install pillow numpy python-dotenv requests
```

### 環境変数

`.env` ファイルをプロジェクトルートに作成：

```
GEMINI_API_KEY=your_key_here
```

---

## 作業ルール

### 全般

- **変更前に必ずファイルを読む。** 読まずに編集しない
- **確認が必要な変更は必ずユーザーに見せてから適用する。**
  特に「全キャラ一括」「上書き」「削除」を伴う操作は事前確認必須
- **テスト出力ファイルはユーザーが確認できる間は削除しない**
- 画像・スプライト生成後は必ず `Read` ツールで目視確認してからユーザーに報告する

### git push ルール

- **push はユーザーの明示的な同意を得てから実行する。**
  作業が完了しても、push の指示がない限り自己判断で実行しない。
  同意なしの push は内容の正しさに関わらず禁止。

### git push 前のセキュリティチェック（必須）

**push を実行する前に、以下を必ず確認すること。**

1. **シークレットファイルが追跡されていないか確認する**

   ```bash
   git ls-files .env .env.* *.key *.pem *.secret
   # 出力があれば push 禁止。git rm --cached <file> で追跡を外す
   ```

2. **コミット差分にシークレットが含まれていないか確認する**

   ```bash
   git diff HEAD
   # API キー・パスワード・トークンの文字列が含まれていないか目視確認
   ```

3. **.gitignore に以下が含まれているか確認する**

   ```
   .env
   .env.*
   !.env.example
   ```

4. **過去のコミット履歴にシークレットが混入した場合は push しない。**
   ユーザーに報告し、キーの無効化と履歴の書き換え（`git filter-repo` 等）を相談する。

> シークレットの種類: API キー・パスワード・アクセストークン・秘密鍵ファイル（`.pem`/`.key`）・OAuth クレデンシャル等

### GDScript

- `py -3` で Python 実行（`python`/`python3` は不可）
- `class_name` を持つスクリプトは AutoLoad 内では型名ではなく `Node` で参照
- `Board.gd` はシーンアタッチ型 → `load('res://scripts/Board.gd').new()` で生成
- AutoLoad 登録済みスクリプト: `GameManager` / `StudentDB` / `SaveManager` /
  `CharacterState` / `FriendshipManager` / `LessonManager` / `FulfillmentCalc` / `AbilityEngine`

### Godot headless チェック

```bash
"/c/Program Files/Godot/Godot_v4.6.1-stable_win64_console.exe" \
  --headless --path "/c/Users/User/Documents/project-homeroom" --quit 2>&1
# Exit 0 = 正常
```

### JSON ファイル

- すべて UTF-8 で保存・読み込み（`open(..., encoding='utf-8')`）
- `data/` 以下のデータ変更はゲームロジックに直結するため慎重に

---

## スプライト生成 & 背景除去パイプライン

### 概要

```
Gemini API (gemini-2.5-flash-image)
    ↓ generate_image()
assets/sprites/raw/<id>_raw.png  ← 白背景 RGB（常に保持）
    ↓ remove_bg() BFS フラッドフィル
assets/sprites/<id>_48x48.png   ← 透過 RGBA（最終成果物）
```

**背景除去は ML モデル不使用。**
BFS フラッドフィルでボーダーから繋がった白ピクセルのみ透過するため、
フラットカラーのパステル部分が消えない。

### コマンド早見表

```bash
# 全キャラ再生成（生成 + 背景除去）
py -3 tools/generate_sprites.py

# 1キャラだけ再生成
py -3 tools/generate_sprites.py --id student_rina

# 既存 raw に背景除去だけ適用（生成スキップ）
py -3 tools/generate_sprites.py --id player_male --raw-only

# 任意の PNG を単体処理
py -3 tools/remove_bg.py <入力PNG> <出力PNG>
```

### キャラクター一覧

| ID | 説明 |
|---|---|
| `student_rina` | ピンクツインテール |
| `student_kenta` | メガネ黒髪 |
| `student_ren` | スパイキー茶髪 |
| `student_haru` | オレンジウェーブ |
| `student_zero` | 片目隠れ黒髪 |
| `student_maki` | ストレート黒髪 |
| `student_goro` | 短い赤スパイク |
| `student_sora` | 青メッシュ + ヘッドフォン |
| `student_taku` | 茶色マッシュ |
| `player_male` | 男主人公 |
| `player_female` | 女主人公 |
| `principal` | 校長 |

### 注意事項

- raw ファイルは **絶対に削除しない**（ユーザーが管理する）
- 生成後は必ず `Read` ツールで画像を確認してからユーザーに報告
- 全体適用前に **1キャラで試してユーザーに確認を取る**
- Windows ターミナルは cp932 のため print に絵文字を使わない

---

## ゲームフロー（実装済み v2.0）

```
TITLE → PLAYER_SETUP → CinematicPanel("opening")
  → START_PHASE（転校生カード表示 + 席配置）
  → CLASS_PHASE（授業科目表示 + 授業開始ボタン）
  → RETURN_PHASE（ResultPresenter: ステップ表示）
  → [30日後] ENDING
      充実度 ≥30 = true / 10-29 = normal / -9〜9 = plain / ≤-10 = bad
```

### 日次ループ処理順（`advance_day`）

1. 科目決定（LessonManager）
2. 全キャラ授業効果（充実度 ≥10 は ×2）
3. 好き/嫌いタイプで仲良し度 ±1
4. AbilityEngine.apply_all_abilities
5. FulfillmentCalc.calc_daily → apply
6. テスト日: evaluate → apply_test_result(±5)
7. 転校判定: 充実度 ≤-10 のキャラを退場
8. SaveManager.save_game

---

## 主要シグナル・API メモ

- `PlayerSetup.setup_complete(name, gender, p_type, like_type, dislike_type, seat)` — 引数6個
- `start_new_game(board)` — board を引数として受け取る（`_on_cinematic_finished` から呼ぶ）
- `SaveManager` のセーブ形式 version: 2（v1 と互換なし）
- テスト日: `LessonManager.TEST_DAYS = [4, 8, 12, 16, 20, 24, 28]`
- 初期配置: `student_rina`（席0）/ `student_kenta`（席3）/ `student_haru`（席12）

---

## よくあるトラブル

| 症状 | 対処 |
|---|---|
| `python` / `python3` が動かない | `py -3` を使う |
| JSON 読み込みで文字化け | `open(..., encoding='utf-8')` を明示 |
| Godot が起動しない | パスを確認（上記 headless チェック） |
| スプライトの頭が消える | `u2net_human_seg` は不適。`remove_bg.py`（BFS方式）を使う |
| 画像が小さくて矩形内で余白が多い | 生成後にクロップ or 再生成でサイズ指示を強調 |
| print で UnicodeEncodeError | 絵文字を使わず ASCII 文字で出力 |
| Gemini API 404 | モデル名を確認。`gemini-2.5-flash-image` が動作確認済み |
