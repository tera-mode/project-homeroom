#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
csv_to_json.py -- 転校生ガチャ！ CSV->JSON変換スクリプト
tools/spreadsheet_template.csv を読み込み、
data/students.json を生成する。

使用法:
    python tools/csv_to_json.py
    python tools/csv_to_json.py --input tools/my_students.csv --output data/students.json
"""

import csv
import json
import os
import sys
import argparse
import io
from pathlib import Path

# Windows cp932 対策: stdout を UTF-8 に強制
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# 有効なパラメータID
VALID_PARAMS = {"study", "romance", "friendship", "popularity", "happening"}
# 有効なscopeの値
VALID_SCOPES = {"orthogonal", "surrounding", "same_row", "same_col", "board_wide", "self"}
# 有効なカテゴリ
VALID_CATEGORIES = {"honor", "idol", "yankee", "entertainer", "wildcard"}


def parse_json_field(value: str, field_name: str, row_num: int) -> object:
    """JSON文字列フィールドをパースする。エラー時はNoneを返す。"""
    if not value or value.strip() == "":
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError as e:
        print(f"  警告: 行{row_num} {field_name} のJSONパースエラー: {e}", file=sys.stderr)
        print(f"  値: {value!r}", file=sys.stderr)
        return None


def validate_param_deltas(deltas: dict, row_num: int) -> dict:
    """param_deltasのキーが有効なパラメータIDかチェックする。"""
    invalid = set(deltas.keys()) - VALID_PARAMS
    if invalid:
        print(f"  警告: 行{row_num} 不正なパラメータ名: {invalid}", file=sys.stderr)
    return {k: v for k, v in deltas.items() if k in VALID_PARAMS}


def parse_tags(tags_str: str) -> list:
    """カンマ区切りのタグ文字列をリストに変換する。"""
    if not tags_str:
        return []
    return [t.strip() for t in tags_str.split(",") if t.strip()]


def read_csv_sections(filepath: str) -> dict[str, list[dict]]:
    """
    CSVファイルを読み込み、## Sheet N: セクションごとに分割する。
    戻り値: {"students": [...], "effects": [...], "hidden_traits": [...]}
    """
    sections = {"students": [], "effects": [], "hidden_traits": []}
    current_section = None
    headers = None

    section_map = {
        "Sheet 1": "students",
        "Sheet 2": "effects",
        "Sheet 3": "hidden_traits"
    }

    with open(filepath, encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        for row_num, row in enumerate(reader, start=1):
            if not row:
                continue

            first_cell = row[0].strip()

            # セクションヘッダー検出
            if first_cell.startswith("## Sheet"):
                for key, section_name in section_map.items():
                    if key in first_cell:
                        current_section = section_name
                        headers = None  # 次の非コメント行をヘッダーとして扱う
                        break
                continue

            # コメント行スキップ
            if first_cell.startswith("##") or first_cell.startswith("#"):
                continue

            # 空行スキップ
            if all(cell.strip() == "" for cell in row):
                headers = None
                continue

            if current_section is None:
                continue

            # ヘッダー行
            if headers is None:
                headers = [h.strip() for h in row]
                continue

            # データ行
            if len(row) < len(headers):
                row.extend([""] * (len(headers) - len(row)))
            record = {headers[i]: row[i].strip() for i in range(len(headers))}
            sections[current_section].append((row_num, record))

    return sections


def build_students(sections: dict) -> list[dict]:
    """転校生マスタ・エフェクト・隠し特性を統合してstudenetsリストを構築する。"""
    student_rows = sections["students"]
    effect_rows = sections["effects"]
    hidden_rows = sections["hidden_traits"]

    # エフェクトをstudent_idでグループ化
    effects_by_id: dict[str, list[dict]] = {}
    for row_num, row in effect_rows:
        sid = row.get("student_id", "").strip()
        if not sid:
            continue
        if sid not in effects_by_id:
            effects_by_id[sid] = []

        scope = row.get("scope", "orthogonal")
        if scope not in VALID_SCOPES:
            print(f"  警告: 行{row_num} 不正なscope値: {scope!r}", file=sys.stderr)

        condition = parse_json_field(row.get("condition_json", ""), "condition_json", row_num) or {}
        param_deltas = parse_json_field(row.get("param_deltas_json", ""), "param_deltas_json", row_num) or {}
        if param_deltas:
            param_deltas = validate_param_deltas(param_deltas, row_num)

        effect = {
            "effect_id": row.get("effect_id", ""),
            "type": row.get("type", "adjacency"),
            "trigger": {
                "scope": scope,
                "condition": condition
            },
            "apply": {
                "target": row.get("target", "other"),
                "param_deltas": param_deltas
            },
            "flavor": row.get("flavor", "")
        }
        effects_by_id[sid].append(effect)

    # 隠し特性をstudent_idでマップ化
    hidden_by_id: dict[str, dict] = {}
    for row_num, row in hidden_rows:
        sid = row.get("student_id", "").strip()
        if not sid:
            continue

        reveal_day = int(row.get("reveal_day", "3")) if row.get("reveal_day", "").isdigit() else 3
        base_params_delta = parse_json_field(row.get("base_params_delta_json", ""), "base_params_delta_json", row_num) or {}
        add_effects = parse_json_field(row.get("add_effects_json", ""), "add_effects_json", row_num) or []
        remove_effects = parse_json_field(row.get("remove_effects_json", ""), "remove_effects_json", row_num) or []

        hidden_by_id[sid] = {
            "reveal_day": reveal_day,
            "description": row.get("description", ""),
            "effect_override": {
                "base_params_delta": base_params_delta,
                "add_effects": add_effects,
                "remove_effects": remove_effects
            }
        }

    # 転校生データを組み立てる
    students = []
    for row_num, row in student_rows:
        sid = row.get("id", "").strip()
        if not sid:
            print(f"  警告: 行{row_num} idが空のためスキップ", file=sys.stderr)
            continue

        category = row.get("category", "honor")
        if category not in VALID_CATEGORIES:
            print(f"  警告: 行{row_num} 不正なカテゴリ: {category!r}", file=sys.stderr)

        rarity_str = row.get("rarity", "1")
        rarity = int(rarity_str) if rarity_str.isdigit() else 1

        # base_params を組み立てる
        base_params = {}
        for param_id in VALID_PARAMS:
            val_str = row.get(param_id, "0").strip()
            try:
                base_params[param_id] = int(val_str)
            except ValueError:
                base_params[param_id] = 0

        # unlock_cycle
        cycle_str = row.get("unlock_cycle", "1")
        unlock_cycle = int(cycle_str) if cycle_str.isdigit() else 1

        student = {
            "id": sid,
            "name": row.get("name", sid),
            "category": category,
            "rarity": rarity,
            "sprite": row.get("sprite", sid + "_48x48.png"),
            "tags": parse_tags(row.get("tags", "")),
            "hint_text": row.get("hint_text", ""),
            "unlock_cycle": unlock_cycle,
            "base_params": base_params,
            "effects": effects_by_id.get(sid, []),
            "hidden_trait": hidden_by_id.get(sid, None)
        }
        students.append(student)
        print(f"  [OK] {sid} ({row.get('name', sid)}) -- effects: {len(student['effects'])}, hidden_trait: {'あり' if student['hidden_trait'] else 'なし'}")

    return students


def validate_students(students: list[dict]) -> list[str]:
    """生成されたデータのバリデーション。エラーメッセージのリストを返す。"""
    errors = []
    ids_seen = set()

    for s in students:
        sid = s["id"]

        # ID重複チェック
        if sid in ids_seen:
            errors.append(f"[{sid}] IDが重複しています")
        ids_seen.add(sid)

        # カテゴリチェック
        if s["category"] not in VALID_CATEGORIES:
            errors.append(f"[{sid}] 不正なカテゴリ: {s['category']}")

        # base_paramsチェック
        for param_id in VALID_PARAMS:
            if param_id not in s["base_params"]:
                errors.append(f"[{sid}] base_paramsに{param_id}がありません")

        # エフェクトチェック
        for effect in s.get("effects", []):
            eid = effect.get("effect_id", "")
            scope = effect.get("trigger", {}).get("scope", "")
            if scope not in VALID_SCOPES:
                errors.append(f"[{sid}] effect {eid!r} の不正なscope: {scope}")

    return errors


def main():
    parser = argparse.ArgumentParser(description="CSV→JSON変換スクリプト（転校生ガチャ！）")
    parser.add_argument("--input", default="tools/spreadsheet_template.csv",
                        help="入力CSVファイルのパス")
    parser.add_argument("--output", default="data/students.json",
                        help="出力JSONファイルのパス")
    parser.add_argument("--dry-run", action="store_true",
                        help="JSONを生成せずバリデーションのみ実行")
    args = parser.parse_args()

    # プロジェクトルートに移動
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    os.chdir(project_root)

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        print(f"エラー: 入力ファイルが見つかりません: {input_path}", file=sys.stderr)
        sys.exit(1)

    print(f"読み込み中: {input_path}")
    sections = read_csv_sections(str(input_path))
    print(f"  転校生: {len(sections['students'])}行, エフェクト: {len(sections['effects'])}行, 隠し特性: {len(sections['hidden_traits'])}行")

    print("\n転校生データを構築中...")
    students = build_students(sections)

    print(f"\nバリデーション中...")
    errors = validate_students(students)
    if errors:
        print("エラーが見つかりました:")
        for err in errors:
            print(f"  ❌ {err}", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"  [OK] バリデーション通過 ({len(students)}体)")

    if args.dry_run:
        print("\n--dry-run モード: ファイルへの書き込みをスキップしました")
        return

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_data = {"students": students}
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False, indent=2)

    print(f"\n[DONE] 生成完了: {output_path}")
    print(f"   転校生数: {len(students)}体")


if __name__ == "__main__":
    main()
