# 転校生ガチャ！ — Claude Code 作業要件書
**project-homeroom / v1.0 / 2026年3月**

> ⚠️ このドキュメントは Claude Code が一から実装作業を開始するための完全仕様書です。
> 本ドキュメントを最初に熟読し、全体像を把握してから実装を開始してください。

---

## 0. 作業前チェックリスト

```
[ ] 本ドキュメントを末尾まで通読した
[ ] DESIGN_POLICY.md（同フォルダ）を読んだ
[ ] Godot 4.x がインストール済みで godot --headless が動作する
[ ] 作業フォルダ C:\Users\User\Documents\project-homeroom が存在する
[ ] 画像生成MCP（Gemini Imagen）の APIキー が環境変数に設定済み
      → project-vigil と同じキー（GEMINI_API_KEY）を流用
[ ] Python 3.x が使える（CSV→JSON変換スクリプト用）
```

---

## 1. プロジェクト概要

| 項目 | 値 |
|---|---|
| タイトル | 転校生ガチャ！ |
| プロジェクト名 | project-homeroom |
| ジャンル | ローグライト × 配置パズル × 学園シミュレーション |
| ターゲット | 小学高学年〜中学生（サブ：インディーゲーム好きな大人） |
| プラットフォーム | Steam (Windows / macOS)、Steam Deck 対応 |
| エンジン | Godot 4.x |
| 言語 | GDScript |
| 解像度 | 1280×720 |
| 1周プレイ時間 | 15〜25分（30日間） |
| 1セッション | 30秒〜1分 |
| 価格帯目標 | ¥300〜500 |

### コンセプト

> 「毎日やってくる転校生を、たった16席の教室に座らせろ。
> 君の学園生活の運命はそこにかかっている。」

Papers, Please の「全ての選択にコストがある」設計を学園ものに翻訳した、
シンプル操作 × 深い判断のローグライト。

---

## 2. 作業フォルダ構成

作業開始時にこのフォルダ構成を作成すること。

```
C:\Users\User\Documents\project-homeroom\
├── project.godot                  ← Godot プロジェクトファイル
├── CLAUDE_CODE_REQUIREMENTS.md    ← 本ファイル（参照用にコピー）
├── DESIGN_POLICY.md               ← デザインポリシー（参照用にコピー）
│
├── scenes\
│   ├── Main.tscn                  ← ゲームエントリーポイント
│   ├── Classroom.tscn             ← 教室シーン（4×4グリッド）
│   ├── StudentCard.tscn           ← 転校生情報カード
│   ├── DayResult.tscn             ← 放課後結果表示
│   ├── MissionPanel.tscn          ← ミッション進捗UI
│   └── EndingScreen.tscn          ← エンディング表示
│
├── scripts\
│   ├── GameManager.gd             ← ゲーム進行統括
│   ├── Board.gd                   ← 4×4盤面状態管理
│   ├── StudentDB.gd               ← 転校生データ読み込み・検索
│   ├── EffectEngine.gd            ← 効果評価・適用パイプライン
│   ├── ParamStore.gd              ← パラメータ集計管理
│   ├── MissionManager.gd          ← ミッション判定
│   ├── SaveManager.gd             ← 自動セーブ
│   └── ImageGenClient.gd          ← 画像生成MCP連携
│
├── data\
│   ├── params_definition.json     ← パラメータ定義（5種）
│   ├── students.json              ← 転校生マスタ（CSV変換済み）
│   ├── effects.json               ← 効果定義（students.jsonに統合でも可）
│   ├── missions.json              ← ミッション定義
│   └── events.json                ← 週間イベント定義
│
├── assets\
│   ├── sprites\                   ← キャラクタースプライト（48×48px）
│   ├── ui\                        ← UIパーツ
│   ├── backgrounds\               ← 背景（教室など）
│   └── fonts\                     ← 日本語フォント
│
├── tools\
│   ├── csv_to_json.py             ← CSV→JSON変換スクリプト
│   └── spreadsheet_template.csv  ← データ入力テンプレート
│
└── saves\                         ← セーブデータ格納先
```

---

## 3. 世界観・設定

### 舞台
**私立夕凪学園（ゆうなぎがくえん）**。全校生徒30人程度の小さな田舎の学校。
少子化による廃校危機を回避するため「転入自由制度」を導入。毎日転校生がやってくる。
教室は1つだけ。**4×4＝16席の窮屈な教室。**

### プレイヤーの役割
プレイヤーは「日直当番」を兼任する「転校生対応係」。
校長先生（ポンコツおじいさん）が「今日の日直のきみが席を決めてくれ」と言う。
これが「席を決める権利」の自然な理由付け。

### 主人公
名前・性別は自由設定。自分の席は4×4の中から初回に選ぶ（以後固定）。
自分の席の位置も隣接効果の対象になるため、最初の戦略的判断になる。

---

## 4. ゲームループ

```
① 朝のホームルーム（転校生が来る）
      ↓
② 席配置（ドラッグ&ドロップ）
      ↓  ← 配置プレビュー（即時フィードバック）
③ 放課後イベント（結果発生・日記形式）
      ↓
④ ミッション進捗確認
      ↓
⑤ 翌日へ（30日でエンディング）
```

1日のセッションは **30秒〜1分** を目標とする。

---

## 5. パラメータシステム

### 基本パラメータ（5種）

| ID | 表示名 | アイコン | カラー | 初期値 | 最大値 | 備考 |
|---|---|---|---|---|---|---|
| `study` | 勉強 | 📚 | `#4A90D9` | 10 | 100 | |
| `romance` | 恋愛 | 💖 | `#E85B8A` | 5 | 100 | |
| `friendship` | 友情 | 🤝 | `#5BAE5F` | 10 | 100 | |
| `popularity` | 人気 | ⭐ | `#F5A623` | 5 | 100 | |
| `happening` | ハプニング | 🌟 | `#9B59B6` | 10 | 100 | 加重平均の総合指標 |

`happening` は他4パラメータの加重平均をベースに、ランダムイベントの結果が上乗せされる「総合指標」。エンディング分岐の最終判定に使用。

### パラメータ定義ファイル（`data/params_definition.json`）

```json
{
  "params": [
    { "id": "study", "display_name": "勉強", "icon": "📚", "color": "#4A90D9", "min": 0, "max": 100, "initial": 10 },
    { "id": "romance", "display_name": "恋愛", "icon": "💖", "color": "#E85B8A", "min": 0, "max": 100, "initial": 5 },
    { "id": "friendship", "display_name": "友情", "icon": "🤝", "color": "#5BAE5F", "min": 0, "max": 100, "initial": 10 },
    { "id": "popularity", "display_name": "人気", "icon": "⭐", "color": "#F5A623", "min": 0, "max": 100, "initial": 5 },
    {
      "id": "happening", "display_name": "ハプニング", "icon": "🌟", "color": "#9B59B6",
      "min": 0, "max": 100, "initial": 10, "derived": true, "formula": "weighted_average"
    }
  ]
}
```

---

## 6. 転校生システム

### カテゴリと出現率

| カテゴリID | 名称 | 特徴 | 出現率 |
|---|---|---|---|
| `honor` | 優等生タイプ | 勉強特化・社交性低め | 高 |
| `idol` | アイドルタイプ | 恋愛・人気特化 | 中 |
| `yankee` | ヤンキータイプ | 友情特化・トラブルあり | 中 |
| `entertainer` | エンタメタイプ | ハプニング特化・予測不能 | 低 |
| `wildcard` | ワイルドカード | 極端な効果・ハイリスクハイリターン | 極低 |

### 転校生データ構造（`data/students.json`）

```json
{
  "id": "student_rina",
  "name": "星宮リナ",
  "category": "idol",
  "rarity": 2,
  "sprite": "rina_48x48.png",
  "tags": ["明るい", "おしゃれ", "アイドル"],
  "hint_text": "前の学校でも注目されてたみたい。でも本当は…",
  "unlock_cycle": 1,
  "base_params": {
    "study": -1, "romance": 2, "friendship": 0, "popularity": 1, "happening": 0
  },
  "effects": [
    {
      "effect_id": "rina_synergy_01",
      "type": "adjacency",
      "trigger": { "scope": "orthogonal", "condition": { "has_tag": "明るい" } },
      "apply": { "target": "both", "param_deltas": { "popularity": 1 } },
      "flavor": "明るい子同士でキラキラオーラ発動！"
    },
    {
      "effect_id": "rina_crash_01",
      "type": "adjacency",
      "trigger": { "scope": "orthogonal", "condition": { "has_tag": "地味" } },
      "apply": { "target": "other", "param_deltas": { "friendship": -1 } },
      "flavor": "リナちゃんの隣はちょっと…きつい"
    }
  ],
  "hidden_trait": {
    "reveal_day": 3,
    "description": "実は勉強が得意だった",
    "effect_override": {
      "base_params_delta": { "study": 2 },
      "add_effects": [],
      "remove_effects": []
    }
  }
}
```

### 初期実装キャラ（最低5体）

| ID | 名前 | カテゴリ | レア | 特徴 |
|---|---|---|---|---|
| `student_rina` | 星宮リナ | idol | ★★ | 恋愛+人気。隠し：実は勉強も得意 |
| `student_kenta` | 大樹ケンタ | honor | ★ | 勉強+3だが友情-人気。窓際で+1 |
| `student_ren` | 火坂レン | yankee | ★★ | 友情+人気オーラ。真面目と相性最悪 |
| `student_haru` | 七瀬ハル | entertainer | ★★ | ハプニング特化。笑いトリガー |
| `student_zero` | 謎の転校生ゼロ | wildcard | ★★★ | 全パラ+1だが毎日ランダム。3日後正体判明 |

---

## 7. 効果システム（EffectEngine）

### 効果スコープの種類

| scope | 説明 |
|---|---|
| `orthogonal` | 上下左右4マス |
| `surrounding` | 周囲8マス |
| `same_row` | 同じ行全員 |
| `same_col` | 同じ列全員 |
| `board_wide` | 盤面全員 |
| `self` | 自分のみ |

### 効果タイプ

| type | 説明 |
|---|---|
| `adjacency` | 隣接条件で発動 |
| `aura` | 常時エリア効果 |
| `trigger` | 特定条件で列・行・全体に発動 |
| `conditional` | 席の位置条件（窓際など）で発動 |
| `meta` | 他の効果・配置に干渉するメタ効果 |

### 評価パイプライン（Phase 1〜5）

```
Phase 0: MetaContext収集（block_seats / suppress_effect / force_seat）
Phase 1: base_params 合算
Phase 2: adjacency / aura / trigger 効果の評価
Phase 3: param_deltas 合算
Phase 4: param_multipliers 適用
Phase 5: ParamStore へのコミット + UI更新
```

### 条件評価（GDScript 参考実装）

```gdscript
func evaluate_condition(condition: Dictionary, target, target_pos, board) -> bool:
    if condition.has("always"):
        return true
    if condition.has("has_tag"):
        return condition["has_tag"] in target.tags
    if condition.has("has_any_tag"):
        for tag in condition["has_any_tag"]:
            if tag in target.tags: return true
        return false
    if condition.has("is_category"):
        return target.category == condition["is_category"]
    if condition.has("seat_in"):
        for label in condition["seat_in"]:
            if target_pos in board.seat_labels.get(label, []): return true
        return false
    if condition.has("and"):
        for sub in condition["and"]:
            if not evaluate_condition(sub, target, target_pos, board): return false
        return true
    if condition.has("or"):
        for sub in condition["or"]:
            if evaluate_condition(sub, target, target_pos, board): return true
        return false
    if condition.has("not"):
        return not evaluate_condition(condition["not"], target, target_pos, board)
    return false
```

### 配置時プレビュー

1. Board に仮配置
2. 全パイプライン実行（Phase 1〜5）
3. 現在値との差分を計算
4. UI に `+2! -1!` のアニメーション表示
5. ドラッグ離脱で仮配置取り消し
6. 確定で Board に永続反映

---

## 8. アーキテクチャ

```
┌─────────────────────────────────────────┐
│              GameManager                 │
│  ゲーム進行・日次ループ・ミッション判定   │
└───────┬─────────────┬─────────┬─────────┘
        │             │         │
  ┌─────▼──────┐ ┌────▼────┐ ┌──▼──────────┐
  │  StudentDB  │ │  Board  │ │EffectEngine │
  │ JSON読込    │ │ 4×4盤面 │ │ 効果パイプ  │
  └─────┬──────┘ └────┬────┘ └──┬──────────┘
        └─────────────┼──────────┘
                      │
             ┌────────▼──────┐
             │  ParamStore    │
             │ パラメータ集計 │
             └───────────────┘
```

各モジュールは **直接参照しない**。インターフェース（メソッド呼び出し）のみで通信する（疎結合）。

---

## 9. ミッションシステム

### メインミッション（全周共通）

| 日 | ミッション | 条件 | 失敗時 |
|---|---|---|---|
| 第7日 | 中間テスト赤点回避 | `study >= 15` | 補習イベント（ペナルティ、ゲームオーバーなし） |
| 第14日 | 友達を3人以上作れ | `friendship >= 25` | ぼっち飯イベント（`happening` 大幅下落） |
| 第21日 | 好きな子と付き合え | `romance >= 30` | 片思いエンドフラグ |
| 第28日 | 期末テスト学年トップ | `study >= 40` | そこそこエンドフラグ |

### サブミッション（ランダム発生・週1回）

| ミッション | 条件 | 報酬 |
|---|---|---|
| 体育祭で優勝 | 運動系タグのキャラ3人以上 | `friendship +5` / 称号 |
| 文化祭クラス劇成功 | エンタメタイプ2人以上 | `happening +8` / 特殊イベント解放 |
| 恋のライバルに勝て | `romance` でライバルキャラを超える | `romance +3` / 告白イベント |
| トラブルを解決しろ | ケンカキャラを孤立させず3日経過 | `friendship +3` |

---

## 10. 特殊メカニクス

### 席替えチケット
- 通常、一度座った生徒は動かせない
- チケット使用で既存の生徒を1人だけ別の空席に移動可能
- 入手：サブミッション報酬、5日ごとのボーナス
- 保持上限：3枚
- 使用タイミング：その日の転校生配置前のみ

### 隠し特性
配置後 `reveal_day` 日経過後に自動発動。

- 「静かなる天才」→ 3日後、実はマンガがうまくてクラスで大人気（`popularity +3`）
- 「ケンカ大将」→ 3日後、実は寂しがり屋（クラッシュ効果→シナジーに変化）
- 「学園のマドンナ」→ 3日後、勉強意欲デバフが発動

「あの子どうなるんだろう？」のツァイガルニク効果で継続プレイを誘導する。

### 週間イベント

| イベント | 発生条件 | 効果 |
|---|---|---|
| 席替えシャッフル | 第10日固定 | ランダムに2人の席が入れ替わる |
| 転校生が去る | ランダム | ランダムな1人が転校（空席ができる） |
| 誰かが泣いてる | `friendship` が低い時 | 全員の `happening -2` |

---

## 11. エンディング（7種）

| エンディング | 判定条件 | 内容 |
|---|---|---|
| ★ 伝説の学園生活 | 全パラメータ最高水準 + 全メイン成功 | 「伝説の日直」として讃えられる卒業式 |
| ★ 青春フルコース | 全パラメータ高水準 | 「このクラスでよかった」 |
| 恋愛エンド | `romance` が突出 | 好きな子との2人きりエンディング |
| ガリ勉エンド | `study` 突出・`friendship`低 | 成績はトップだが寂しい卒業式 |
| ムードメーカーエンド | `happening` 突出 | 「楽しかったけど、何か成し遂げたかなあ…」 |
| ぼっちエンド | `friendship` 極端に低い | 誰にも声をかけられない卒業式 |
| もう一度、この教室で | `happening` 一定以下 | 「やり直せたらいいのに」——再挑戦動機をナラティブで提供 |

---

## 12. ローグライト構造・周回要素

### 周回ごとの解放

| 周回 | 解放内容 |
|---|---|
| 1周目 | 基本キャラ約15種。チュートリアル兼ねる |
| 2周目 | レアキャラ解放、ワイルドカード出現 |
| 3周目 | 隠し特性システム解放 |
| 4周目〜 | 難化モード（3×4 / 1日2人など） |

### 永続アンロック要素
- **学園図鑑**：出会った転校生情報の蓄積（隠し特性も記録）
- **称号コレクション**：特定条件達成で解放
- **初期クラスメイト選択**：2周目以降、初期メンバーの組み合わせを選べる

---

## 13. 画像生成MCP 連携仕様

### APIキー
```
project-vigil と同じ GEMINI_API_KEY を使用
環境変数 GEMINI_API_KEY または .env ファイルに設定
```

### キャラクタースプライト生成

- サイズ：**48×48px**（ゲーム内表示）、生成は **192×192px** → ダウンスケール
- スタイル：`DESIGN_POLICY.md` の「キャラクタービジュアル仕様」に完全準拠
- プロンプトテンプレート（英語）：
  ```
  Cute chibi anime character, {character_description}, 
  Japanese school uniform, flat colors, thick outline, 
  pastel color palette, white background, 
  simple expression, kawaii style, no shading, 
  pixel art friendly, 192x192 pixels
  ```

### `scripts/ImageGenClient.gd` の役割
- GDScript から HTTP リクエストで Gemini Imagen API を呼び出す
- 生成した画像を `assets/sprites/` に保存
- 非同期処理（`await` + シグナル）でゲームフローをブロックしない

---

## 14. データ管理ルール

### CSV → JSON 変換パイプライン
```
tools/spreadsheet_template.csv 編集
      ↓
python tools/csv_to_json.py
      ↓
data/students.json + data/effects.json 自動生成
```

変換スクリプトが行うこと：
1. Sheet 1（転校生マスタ）→ `students.json`
2. Sheet 2（効果定義）→ `student_id` でグループ化し `effects` 配列に挿入
3. Sheet 3（隠し特性）→ `hidden_trait` フィールドに挿入
4. condition / param_deltas 列の JSON 文字列をパース
5. バリデーション（不正なパラメータ名・scope値の検出）

### 設計原則
1. **データ駆動**：キャラ追加はJSONのみでOK。GDScript変更不要
2. **疎結合**：StudentDB / Board / EffectEngine は直接参照しない
3. **汎用拡張性**：パラメータ名をコードにハードコードしない（Dictionaryキーで管理）

---

## 15. セーブシステム

- **自動セーブ**：毎日終了時
- 保存先：`saves/` フォルダ
- 保存内容：Board状態 / パラメータ値 / 現在日 / フラグ一覧 / 周回数 / 席替えチケット枚数

---

## 16. 実装優先度（フェーズ）

### Phase A：コア（最初に実装）

| 優先度 | 項目 |
|---|---|
| 1 | パラメータ定義JSON + ParamStore |
| 2 | StudentDB（JSON読み込み・最低5体） |
| 3 | Board（4×4盤面の状態管理・配置・取得） |
| 4 | EffectEngine 基本（base_params + adjacency orthogonal + has_tag条件） |
| 5 | 配置時プレビュー（仮配置→差分表示） |
| 6 | GameManager（日次ループ・3日分のコアループ確認） |
| 7 | 基本UI（教室グリッド・パラメータバー・転校生カード） |

### Phase B：効果拡張

| 項目 |
|---|
| scope拡張（surrounding / same_row / same_col / board_wide） |
| condition拡張（seat_in / is_category / and・or・not） |
| param_multipliers（乗算フェーズ） |
| 隠し特性（reveal_day 後の効果差し替え） |
| CSV→JSON 変換スクリプト |

### Phase C：メタ効果

| 項目 |
|---|
| MetaContext（Phase 0パイプライン） |
| block_seats / force_seat / suppress_effect |
| random_daily（日替わり効果） |

### Phase D：完成

| 項目 |
|---|
| 席替えチケット |
| ミッションシステム完全実装 |
| 週間イベント |
| 7種エンディング |
| ローグライト周回要素 |
| 学園図鑑・称号 |
| 難化モード |
| セーブ/ロード |

---

## 17. 品質チェック（実装後に確認）

8法則チェックシート（`シンプルなのにハマるインディーゲームの設計法則` より）

| 法則 | 実装内容 | チェック |
|---|---|---|
| 法則1：30秒ルール | 「転校生を空き席にドラッグするだけ」 | □ |
| 法則2：制約空間 | 4×4=16マス / 配置後移動不可 | □ |
| 法則3：段階的複雑化 | 1周目基本→2周目レア→3周目隠し特性→4周目難化 | □ |
| 法則4：即時フィードバック | 配置プレビュー + 放課後アニメーション | □ |
| 法則5：発見の連鎖 | 隠し特性 / シナジー発見 | □ |
| 法則6：感情のアンカリング | 配置（機械的）→放課後会話（感情的） | □ |
| 法則7：コスト期待値の逆転 | ¥300〜500で「この値段でこれ！？」 | □ |
| 法則8：プレイヤー自身の変容 | 「人を見た目で判断してた」気づき | □ |

---

## 18. 参照リソース

| リソース | 場所 |
|---|---|
| 本要件書 | `CLAUDE_CODE_REQUIREMENTS.md` |
| デザインポリシー | `DESIGN_POLICY.md` |
| project-vigil（参考実装） | `C:\Users\User\Documents\project-vigil` |
| 設計法則ナレッジ | プロジェクトナレッジ「シンプルなのにハマるインディーゲームの設計法則」 |
| テクニカルデザイン書 | プロジェクトナレッジ「転校生パラメータシステム & 盤面エフェクトシステム設計書」 |

---

*作業開始前に必ず `DESIGN_POLICY.md` も読むこと。ビジュアルはゲームの第一印象を決める。*
