## EffectEngine.gd
## 効果評価・適用パイプライン。Board と ParamStore を橋渡しする。
## Phase 0〜5 の評価フローを実装する。
class_name EffectEngine
extends Node

# 評価結果（座席インデックス→パラメータ差分のマッピング）
# { seat_index: { param_id: delta, ... }, ... }
var _last_result: Dictionary = {}

# --- パブリックAPI ---

## 盤面全体のエフェクトを評価し、ParamStore に適用する
## board: Board ノード
func evaluate_and_apply(board: Node) -> void:
	var result = evaluate(board)
	_last_result = result

	# 全席の差分を集約してParamStoreに適用
	var total_deltas: Dictionary = {}
	for seat_index in result:
		for param_id in result[seat_index]:
			if param_id not in total_deltas:
				total_deltas[param_id] = 0
			total_deltas[param_id] += result[seat_index][param_id]

	ParamStore.apply_deltas(total_deltas)

## プレビュー用：仮配置状態で評価し、差分のみ返す（ParamStoreには反映しない）
## board: Board ノード（仮配置済みの状態）
## returns: 差分Dictionary { param_id: delta }
func evaluate_preview(board: Node) -> Dictionary:
	var result = evaluate(board)
	var total_deltas: Dictionary = {}
	for seat_index in result:
		for param_id in result[seat_index]:
			if param_id not in total_deltas:
				total_deltas[param_id] = 0
			total_deltas[param_id] += result[seat_index][param_id]
	return total_deltas

## 盤面を評価し、各席の差分を返す（Phase 1〜4）
## returns: { seat_index: { param_id: delta } }
func evaluate(board: Node) -> Dictionary:
	var result: Dictionary = {}

	# Phase 0: MetaContext収集（将来実装）
	var meta_context = _collect_meta_context(board)

	# Phase 1 & 2: 各生徒の base_params と effects を評価
	var placed = board.get_all_placed()
	for entry in placed:
		var seat_index: int = entry["seat_index"]
		var student: Dictionary = entry["student_data"]

		if seat_index not in result:
			result[seat_index] = {}

		# Phase 1: base_params を加算
		var base = student.get("base_params", {})
		for param_id in base:
			if param_id not in result[seat_index]:
				result[seat_index][param_id] = 0
			result[seat_index][param_id] += base[param_id]

		# Phase 2: effects を評価
		var effects = student.get("effects", [])
		for effect in effects:
			_apply_effect(effect, seat_index, student, board, result, meta_context)

	# Phase 3: param_deltas は既に result に集積済み

	# Phase 4: param_multipliers（将来実装）

	return result

# --- 条件評価 ---

## 要件書 §7 の条件評価ロジック
func evaluate_condition(condition: Dictionary, target: Dictionary, target_pos: int, board: Node) -> bool:
	if condition.has("always"):
		return true

	if condition.has("has_tag"):
		return condition["has_tag"] in target.get("tags", [])

	if condition.has("has_any_tag"):
		for tag in condition["has_any_tag"]:
			if tag in target.get("tags", []):
				return true
		return false

	if condition.has("is_category"):
		return target.get("category", "") == condition["is_category"]

	if condition.has("seat_in"):
		for label in condition["seat_in"]:
			if target_pos in board.seat_labels.get(label, []):
				return true
		return false

	if condition.has("and"):
		for sub in condition["and"]:
			if not evaluate_condition(sub, target, target_pos, board):
				return false
		return true

	if condition.has("or"):
		for sub in condition["or"]:
			if evaluate_condition(sub, target, target_pos, board):
				return true
		return false

	if condition.has("not"):
		return not evaluate_condition(condition["not"], target, target_pos, board)

	return false

# --- Private ---

## 単一エフェクトを評価して result に加算する
func _apply_effect(
	effect: Dictionary,
	source_index: int,
	source_student: Dictionary,
	board: Node,
	result: Dictionary,
	meta_context: Dictionary
) -> void:
	var effect_type = effect.get("type", "")
	var trigger = effect.get("trigger", {})
	var scope = trigger.get("scope", "orthogonal")
	var condition = trigger.get("condition", {})
	var apply_data = effect.get("apply", {})
	var target_rule = apply_data.get("target", "other")  # "self" / "other" / "both"
	var param_deltas = apply_data.get("param_deltas", {})

	match effect_type:
		"adjacency", "aura":
			var neighbors = board.get_neighbors(source_index, scope)
			for neighbor_idx in neighbors:
				if board.is_empty(neighbor_idx):
					continue

				var neighbor_student = board.get_student_at(neighbor_idx)
				if evaluate_condition(condition, neighbor_student, neighbor_idx, board):
					# target_rule に応じて差分を加算
					match target_rule:
						"other":
							_add_deltas(result, neighbor_idx, param_deltas)
						"self":
							_add_deltas(result, source_index, param_deltas)
						"both":
							_add_deltas(result, neighbor_idx, param_deltas)
							_add_deltas(result, source_index, param_deltas)

		"trigger":
			var targets = board.get_neighbors(source_index, scope)
			for target_idx in targets:
				if board.is_empty(target_idx):
					continue
				var target_student = board.get_student_at(target_idx)
				if evaluate_condition(condition, target_student, target_idx, board):
					match target_rule:
						"other":
							_add_deltas(result, target_idx, param_deltas)
						"self":
							_add_deltas(result, source_index, param_deltas)
						"both":
							_add_deltas(result, target_idx, param_deltas)
							_add_deltas(result, source_index, param_deltas)

		"conditional":
			# 席の位置条件で自分自身に効果
			if evaluate_condition(condition, source_student, source_index, board):
				_add_deltas(result, source_index, param_deltas)

## resultの指定インデックスに差分を加算するヘルパー
func _add_deltas(result: Dictionary, seat_index: int, deltas: Dictionary) -> void:
	if seat_index not in result:
		result[seat_index] = {}
	for param_id in deltas:
		if param_id not in result[seat_index]:
			result[seat_index][param_id] = 0
		result[seat_index][param_id] += deltas[param_id]

## Phase 0: MetaContext収集（block_seats / suppress_effect / force_seat）
## 将来実装。現在は空の辞書を返す。
func _collect_meta_context(board: Node) -> Dictionary:
	return {}

## 最後の評価結果を返す（デバッグ・UI表示用）
func get_last_result() -> Dictionary:
	return _last_result
