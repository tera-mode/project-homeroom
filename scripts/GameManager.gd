## GameManager.gd
## ゲーム進行統括。AutoLoadとして登録される。
## 日次ループ・フェーズ遷移・エンディング判定を管理する。
extends Node

# ゲームフェーズ
enum Phase {
	TITLE,
	PLAYER_SETUP, # 主人公設定（名前・性別・席）
	HOMEROOM,    # 朝のホームルーム（転校生が来る）
	PLACEMENT,   # 席配置（ドラッグ&ドロップ）
	DAY_RESULT,  # 放課後結果（日記形式）
	MISSION,     # ミッション進捗確認
	ENDING       # エンディング
}

# ゲーム状態
var current_phase: Phase = Phase.TITLE
var current_day: int = 1
const MAX_DAYS: int = 30

# 現在の転校生（今日の抽選結果）
var today_student: Dictionary = {}

# 席替えチケット枚数（初期0、最大3）
var swap_tickets: int = 0
const MAX_SWAP_TICKETS: int = 3

# 周回数（ローグライト）
var current_cycle: int = 1

# 既出学生IDリスト（重複抽選抑制用）
var placed_student_ids: Array = []

# 主人公データ
var player_name: String = "主人公"
var player_gender: String = "female"
var player_seat: int = -1

# 週間イベントデータ
var _event_defs: Array = []

# シグナル
signal phase_changed(new_phase: Phase)
signal day_advanced(day: int)
signal student_drawn(student_data: Dictionary)
signal event_triggered(event_data: Dictionary)
signal ending_reached(ending_id: String)
signal swap_ticket_changed(count: int)
signal cinematic_requested(scene_id: String)

func _ready() -> void:
	_load_events()

## 主人公設定フェーズへ移行する（タイトル→PlayerSetup）
func go_to_player_setup() -> void:
	_change_phase(Phase.PLAYER_SETUP)

## 主人公設定完了：シネマティックを要求する
func complete_player_setup(name: String, gender: String, seat: int) -> void:
	player_name = name
	player_gender = gender
	player_seat = seat
	cinematic_requested.emit("opening")

## ゲームを開始する（タイトル→最初の朝ホームルームへ）
func start_new_game() -> void:
	current_day = 1
	current_cycle = 1
	swap_tickets = 0
	placed_student_ids = []
	today_student = {}

	ParamStore.reset()
	MissionManager.reset()
	StudentDB.set_cycle(current_cycle)

	_change_phase(Phase.HOMEROOM)
	_begin_day()

## 翌日へ進む
func advance_to_next_day() -> void:
	current_day += 1
	day_advanced.emit(current_day)

	# 5日ごとにボーナスチケット
	if current_day % 5 == 0:
		_grant_swap_ticket()

	# 週1でサブミッション抽選（7日ごと）
	if current_day % 7 == 1 and current_day > 1:
		MissionManager.assign_sub_mission()

	if current_day > MAX_DAYS:
		_trigger_ending()
		return

	_change_phase(Phase.HOMEROOM)
	_begin_day()

## 配置フェーズへ進む（転校生カードを確認後）
func go_to_placement() -> void:
	_change_phase(Phase.PLACEMENT)

## 配置完了：放課後結果フェーズへ（boardが渡される）
func complete_placement(board: Node) -> void:
	# 効果パイプラインを実行
	var effect_engine = _get_effect_engine()
	if effect_engine:
		effect_engine.evaluate_and_apply(board)

	# 隠し特性のチェック（reveal_day 到達チェック）
	_check_hidden_traits(board)

	# 週間イベントのチェック
	_check_weekly_events(board)

	# ミッションチェック
	MissionManager.check_main_missions(current_day, board)
	MissionManager.check_sub_mission(board)

	# 自動セーブ
	SaveManager.save_game(board)

	_change_phase(Phase.DAY_RESULT)

## ミッション確認フェーズへ
func go_to_mission() -> void:
	_change_phase(Phase.MISSION)

## 席替えチケットを使用する（1枚消費）
func use_swap_ticket() -> bool:
	if swap_tickets <= 0:
		return false
	swap_tickets -= 1
	swap_ticket_changed.emit(swap_tickets)
	return true

## 席替えチケットを獲得する
func grant_swap_ticket_public() -> void:
	_grant_swap_ticket()

## セーブデータ用辞書を返す
func get_save_data() -> Dictionary:
	return {
		"current_day": current_day,
		"current_cycle": current_cycle,
		"swap_tickets": swap_tickets,
		"placed_student_ids": placed_student_ids.duplicate(),
		"player_name": player_name,
		"player_gender": player_gender,
		"player_seat": player_seat
	}

## セーブデータから復元する
func load_save_data(data: Dictionary) -> void:
	current_day = data.get("current_day", 1)
	current_cycle = data.get("current_cycle", 1)
	swap_tickets = data.get("swap_tickets", 0)
	placed_student_ids = data.get("placed_student_ids", []).duplicate()
	player_name = data.get("player_name", "主人公")
	player_gender = data.get("player_gender", "female")
	player_seat = data.get("player_seat", -1)
	StudentDB.set_cycle(current_cycle)

## 新規ゲーム（デバッグ用リセット）
func reset_and_start() -> void:
	SaveManager.delete_save()
	start_new_game()

## タイトルに戻るリセット（デバッグボタン用）
func reset_to_title() -> void:
	SaveManager.delete_save()
	current_day = 1
	current_cycle = 1
	swap_tickets = 0
	placed_student_ids = []
	today_student = {}
	ParamStore.reset()
	MissionManager.reset()
	StudentDB.set_cycle(1)
	_change_phase(Phase.TITLE)

# --- Private ---

func _begin_day() -> void:
	# 今日の転校生を抽選
	today_student = StudentDB.draw_random_student(placed_student_ids)
	student_drawn.emit(today_student)

func _change_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)

func _grant_swap_ticket() -> void:
	swap_tickets = min(swap_tickets + 1, MAX_SWAP_TICKETS)
	swap_ticket_changed.emit(swap_tickets)

# 隠し特性のreveal_day チェック
func _check_hidden_traits(board: Node) -> void:
	for entry in board.get_all_placed():
		var student = entry["student_data"]
		var hidden = student.get("hidden_trait", null)
		if hidden == null:
			continue

		var placed_day = student.get("_placed_day", current_day)
		var days_placed = current_day - placed_day
		var reveal_day = hidden.get("reveal_day", 999)

		if days_placed >= reveal_day and not student.get("_hidden_revealed", false):
			_apply_hidden_trait(board, entry["seat_index"], student, hidden)

# 隠し特性を適用する
func _apply_hidden_trait(board: Node, seat_index: int, student: Dictionary, hidden: Dictionary) -> void:
	var override = hidden.get("effect_override", {})

	# base_params_delta を反映
	var bp_delta = override.get("base_params_delta", {})
	if not bp_delta.is_empty():
		ParamStore.apply_deltas(bp_delta)

	# 学生データの_hidden_revealed フラグを設定
	student["_hidden_revealed"] = true

	# 追加エフェクトを学生データにマージ（次回評価から有効）
	var add_effects = override.get("add_effects", [])
	var effects = student.get("effects", [])
	effects.append_array(add_effects)
	student["effects"] = effects

	# 削除エフェクトを除去
	var remove_ids = override.get("remove_effects", [])
	student["effects"] = effects.filter(func(e): return not (e["effect_id"] in remove_ids))

func _check_weekly_events(board: Node) -> void:
	if _event_defs.is_empty():
		return

	for event in _event_defs:
		if _should_trigger_event(event, board):
			_execute_event(event, board)
			event_triggered.emit(event)
			break  # 1日1イベントまで

func _should_trigger_event(event: Dictionary, board: Node) -> bool:
	var trigger = event.get("trigger", {})
	match trigger.get("type", ""):
		"fixed_day":
			return current_day == trigger.get("day", -1)
		"random":
			var min_day = trigger.get("min_day", 0)
			var prob = trigger.get("probability_per_day", 0.0)
			return current_day >= min_day and randf() < prob
		"param_threshold":
			var param = trigger.get("param", "")
			var operator = trigger.get("operator", "<")
			var value = trigger.get("value", 0)
			var current = ParamStore.get_param(param)
			match operator:
				"<": return current < value
				">=": return current >= value
		"board_condition":
			var category = trigger.get("category", "")
			var count_min = trigger.get("count_min", 0)
			var min_day = trigger.get("min_day", 0)
			if current_day < min_day:
				return false
			var count = 0
			for entry in board.get_all_placed():
				if entry["student_data"].get("category", "") == category:
					count += 1
			return count >= count_min
		"day_range":
			var start = trigger.get("start", 0)
			var end = trigger.get("end", 999)
			return current_day >= start and current_day <= end
	return false

func _execute_event(event: Dictionary, board: Node) -> void:
	var effect = event.get("effect", {})
	match effect.get("type", ""):
		"shuffle_seats":
			var count = effect.get("count", 2)
			var placed = board.get_all_placed()
			placed.shuffle()
			for i in range(min(count, placed.size() - 1)):
				board.swap_seats(placed[i]["seat_index"], placed[i + 1]["seat_index"])
		"remove_random_student":
			var placed = board.get_all_placed()
			if not placed.is_empty():
				var idx = randi() % placed.size()
				board.remove_student(placed[idx]["seat_index"])
		"param_change":
			ParamStore.apply_deltas(effect.get("changes", {}))

func _trigger_ending() -> void:
	var ending_id = _determine_ending()
	_change_phase(Phase.ENDING)
	ending_reached.emit(ending_id)

# エンディング判定ロジック（要件書 §11）
func _determine_ending() -> String:
	var params = ParamStore.get_all_params()
	var flags = MissionManager.get_ending_flags()

	var study = params.get("study", 0)
	var romance = params.get("romance", 0)
	var friendship = params.get("friendship", 0)
	var popularity = params.get("popularity", 0)
	var happening = params.get("happening", 0)

	# ★ 伝説の学園生活
	if study >= 60 and romance >= 50 and friendship >= 60 and popularity >= 50 and happening >= 60:
		if MissionManager.completed_missions.size() >= 4:
			return "legendary"

	# ★ 青春フルコース
	if study >= 40 and romance >= 35 and friendship >= 40 and popularity >= 35:
		return "full_youth"

	# 恋愛エンド
	if romance >= 50 and romance > study and romance > friendship:
		return "romance"

	# ガリ勉エンド
	if study >= 50 and friendship < 20:
		return "studious"

	# ムードメーカーエンド
	if happening >= 50 and happening > study and happening > romance:
		return "mood_maker"

	# ぼっちエンド
	if friendship < 15:
		return "loner"

	# もう一度、この教室で
	return "restart"

func _load_events() -> void:
	var path = "res://data/events.json"
	if not FileAccess.file_exists(path):
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_event_defs = json.get_data().get("weekly_events", [])
	file.close()

func _get_effect_engine() -> Node:
	# Classroomシーンが持つEffectEngineを取得
	var classroom = get_tree().get_first_node_in_group("classroom")
	if classroom and classroom.has_node("EffectEngine"):
		return classroom.get_node("EffectEngine")
	return null
