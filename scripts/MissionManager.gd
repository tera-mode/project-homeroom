## MissionManager.gd
## ミッション判定・進捗管理。AutoLoadとして登録される。
extends Node

# ミッション定義
var _main_missions: Array = []
var _sub_missions: Array = []

# 現在のサブミッション（週1で抽選）
var current_sub_mission: Dictionary = {}

# 完了/失敗したミッションIDのセット
var completed_missions: Array = []
var failed_missions: Array = []

# フラグ
var flags: Dictionary = {}

# シグナル
signal mission_completed(mission_id: String, mission_data: Dictionary)
signal mission_failed(mission_id: String, mission_data: Dictionary)
signal sub_mission_assigned(sub_mission: Dictionary)

func _ready() -> void:
	_load_missions()

# missions.json を読み込む
func _load_missions() -> void:
	var path = "res://data/missions.json"
	if not FileAccess.file_exists(path):
		push_error("missions.json not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse missions.json")
		return

	var data = json.get_data()
	_main_missions = data.get("main_missions", [])
	_sub_missions = data.get("sub_missions", [])

# 指定の日に発動するメインミッションをチェックする
## board は将来のboard_count条件チェック用（現在は未使用）
func check_main_missions(current_day: int, board = null) -> void:
	for mission in _main_missions:
		if mission["day"] != current_day:
			continue
		if mission["id"] in completed_missions or mission["id"] in failed_missions:
			continue

		if _evaluate_condition(mission["condition"], board):
			_on_mission_success(mission)
		else:
			_on_mission_failure(mission)

# 現在のサブミッションをチェックする
func check_sub_mission(board = null) -> void:
	if current_sub_mission.is_empty():
		return

	var condition = current_sub_mission.get("condition", {})
	if _evaluate_sub_condition(condition, board):
		_on_sub_mission_success()

# 週1でサブミッションを抽選する
func assign_sub_mission() -> void:
	if _sub_missions.is_empty():
		return

	# 重み付きランダム
	var total_weight = 0.0
	for m in _sub_missions:
		total_weight += m.get("spawn_weight", 1.0)

	var roll = randf() * total_weight
	var cumulative = 0.0
	for m in _sub_missions:
		cumulative += m.get("spawn_weight", 1.0)
		if roll <= cumulative:
			current_sub_mission = m.duplicate(true)
			sub_mission_assigned.emit(current_sub_mission)
			return

# フラグを設定する
func set_flag(flag_id: String, value: bool = true) -> void:
	flags[flag_id] = value

# フラグを確認する
func has_flag(flag_id: String) -> bool:
	return flags.get(flag_id, false)

# エンディング判定に必要なフラグ情報を返す
func get_ending_flags() -> Dictionary:
	return flags.duplicate()

# セーブデータを返す
func get_save_data() -> Dictionary:
	return {
		"completed_missions": completed_missions.duplicate(),
		"failed_missions": failed_missions.duplicate(),
		"current_sub_mission": current_sub_mission.duplicate(true),
		"flags": flags.duplicate()
	}

# セーブデータから復元する
func load_save_data(data: Dictionary) -> void:
	completed_missions = data.get("completed_missions", []).duplicate()
	failed_missions = data.get("failed_missions", []).duplicate()
	current_sub_mission = data.get("current_sub_mission", {}).duplicate(true)
	flags = data.get("flags", {}).duplicate()

# リセット
func reset() -> void:
	completed_missions = []
	failed_missions = []
	current_sub_mission = {}
	flags = {}

# --- Private ---

func _evaluate_condition(condition: Dictionary, board) -> bool:
	var param = condition.get("param", "")
	var operator = condition.get("operator", ">=")
	var value = condition.get("value", 0)
	var current = ParamStore.get_param(param)

	match operator:
		">=": return current >= value
		">":  return current > value
		"<=": return current <= value
		"<":  return current < value
		"==": return current == value

	return false

func _evaluate_sub_condition(condition: Dictionary, board) -> bool:
	var ctype = condition.get("type", "")
	match ctype:
		"board_count":
			if board == null:
				return false
			var tag = condition.get("has_tag", "")
			var count = condition.get("count", 0)
			var actual = 0
			for entry in board.get_all_placed():
				if tag in entry["student_data"].get("tags", []):
					actual += 1
			return actual >= count

		"board_category_count":
			if board == null:
				return false
			var category = condition.get("category", "")
			var count = condition.get("count", 0)
			var actual = 0
			for entry in board.get_all_placed():
				if entry["student_data"].get("category", "") == category:
					actual += 1
			return actual >= count

		"param_vs_rival":
			# 将来実装：ライバルキャラクターとの比較
			return false

		"days_without_isolation":
			# 将来実装：孤立チェック
			return false

	return false

func _on_mission_success(mission: Dictionary) -> void:
	completed_missions.append(mission["id"])
	if mission.has("sets_flag"):
		# 成功フラグはクリア
		pass
	mission_completed.emit(mission["id"], mission)

func _on_mission_failure(mission: Dictionary) -> void:
	failed_missions.append(mission["id"])
	if mission.has("sets_flag"):
		flags[mission["sets_flag"]] = true

	# ペナルティ適用
	var failure_effect = mission.get("failure_effect", {})
	if not failure_effect.is_empty():
		ParamStore.apply_deltas(failure_effect)

	mission_failed.emit(mission["id"], mission)

func _on_sub_mission_success() -> void:
	var reward = current_sub_mission.get("reward", {})
	if not reward.is_empty():
		ParamStore.apply_deltas(reward)

	completed_missions.append(current_sub_mission.get("id", ""))
	current_sub_mission = {}
