## GameManager.gd
## ゲーム進行統括。AutoLoadとして登録される。
## 日次ループ・フェーズ遷移・エンディング判定を管理する。
extends Node

enum Phase {
	TITLE,
	PLAYER_SETUP,  # 主人公設定
	START_PHASE,   # 始業: 転校生ガチャ + 席配置
	CLASS_PHASE,   # 授業: 科目発表 + テスト
	RETURN_PHASE,  # 帰宅: 結果表示
	ENDING
}

var current_phase: Phase = Phase.TITLE
var current_day: int = 1
const MAX_DAYS: int = 30

var current_cycle: int = 1

# 今日の転校生（ガチャ結果）
var today_student: Dictionary = {}

# 当日パイプライン結果（ResultPresenterに渡す）
var last_day_result: Dictionary = {}

# プレイヤーデータ
var player_name: String = "主人公"
var player_gender: String = "female"
var player_seat: int = -1
var player_type: String = "futsu"
var player_like_type: String = ""
var player_dislike_type: String = ""

# 初期クラスメイト配置定義
const INITIAL_STUDENTS: Array = [
	{"id": "student_rina",  "seat": 0},
	{"id": "student_kenta", "seat": 3},
	{"id": "student_haru",  "seat": 12}
]

# シグナル
signal phase_changed(new_phase: Phase)
signal day_advanced(day: int)
signal student_drawn(student_data: Dictionary)
signal ending_reached(ending_id: String)
signal cinematic_requested(scene_id: String)

## タイトル→PlayerSetup
func go_to_player_setup() -> void:
	_change_phase(Phase.PLAYER_SETUP)

## 主人公設定完了 → シネマティックへ
func complete_player_setup(name: String, gender: String, p_type: String,
		like_type: String, dislike_type: String, seat: int) -> void:
	player_name    = name
	player_gender  = gender
	player_type    = p_type
	player_like_type    = like_type
	player_dislike_type = dislike_type
	player_seat    = seat
	cinematic_requested.emit("opening")

## ゲーム開始（オープニングシネマティック終了後に Main.tscn から呼ばれる）
func start_new_game(board: Node) -> void:
	current_day    = 1
	current_cycle  = 1
	today_student  = {}
	last_day_result = {}

	CharacterState.reset()
	FriendshipManager.reset()
	StudentDB.set_cycle(current_cycle)

	# プレイヤーを CharacterState に登録
	CharacterState.init_character("player", {
		"gender":       player_gender,
		"type":         player_type,
		"like_type":    player_like_type,
		"dislike_type": player_dislike_type,
		"initial_study":   2,
		"initial_sports":  2,
		"initial_art":     2,
		"abilities":       []
	})
	FriendshipManager.init_for_character("player", [])

	# 初期クラスメイト3人を配置
	for entry in INITIAL_STUDENTS:
		var s_data = StudentDB.get_student_by_id(entry["id"])
		if s_data.is_empty():
			continue
		board.place_student(entry["seat"], s_data)
		_register_character(entry["id"], s_data)

	# プレイヤーとの仲良し度を初期化
	FriendshipManager.init_for_character("player", CharacterState.get_all_active_ids())

	_change_phase(Phase.START_PHASE)
	_begin_day()

## 転校生配置後 → 授業フェーズへ
## placed_new: 今日の転校生を盤面に配置した場合 true
func go_to_class_phase(board: Node, placed_new: bool) -> void:
	if placed_new and not today_student.is_empty():
		var s_id = today_student.get("id", "")
		if s_id != "" and not CharacterState.get_state(s_id).has("study"):
			_register_character(s_id, today_student)
			FriendshipManager.init_for_character("player", CharacterState.get_all_active_ids())
	_change_phase(Phase.CLASS_PHASE)

## 日次処理パイプライン実行 → 帰宅フェーズへ（CLASS_PHASE から呼ぶ）
func advance_day(board: Node) -> void:
	last_day_result = _run_daily_pipeline(board)
	if current_phase != Phase.ENDING:
		_change_phase(Phase.RETURN_PHASE)

## 翌日へ（RETURN_PHASE 確認後に呼ぶ）
func next_day() -> void:
	current_day += 1
	day_advanced.emit(current_day)
	if current_day > MAX_DAYS:
		_trigger_ending()
		return
	_change_phase(Phase.START_PHASE)
	_begin_day()

## デバッグ: タイトルリセット
func reset_to_title() -> void:
	SaveManager.delete_save()
	current_day    = 1
	current_cycle  = 1
	today_student  = {}
	last_day_result = {}
	player_name    = "主人公"
	player_gender  = "female"
	player_seat    = -1
	player_type    = "futsu"
	player_like_type    = ""
	player_dislike_type = ""
	CharacterState.reset()
	FriendshipManager.reset()
	StudentDB.set_cycle(1)
	_change_phase(Phase.TITLE)

# --- セーブ/ロード ---

func get_save_data() -> Dictionary:
	return {
		"current_day":          current_day,
		"current_cycle":        current_cycle,
		"player_name":          player_name,
		"player_gender":        player_gender,
		"player_seat":          player_seat,
		"player_type":          player_type,
		"player_like_type":     player_like_type,
		"player_dislike_type":  player_dislike_type
	}

func load_save_data(data: Dictionary) -> void:
	current_day          = data.get("current_day", 1)
	current_cycle        = data.get("current_cycle", 1)
	player_name          = data.get("player_name", "主人公")
	player_gender        = data.get("player_gender", "female")
	player_seat          = data.get("player_seat", -1)
	player_type          = data.get("player_type", "futsu")
	player_like_type     = data.get("player_like_type", "")
	player_dislike_type  = data.get("player_dislike_type", "")
	StudentDB.set_cycle(current_cycle)

# --- Private ---

func _begin_day() -> void:
	var placed_ids = CharacterState.get_all_active_ids()
	today_student = StudentDB.draw_random_student(placed_ids)
	student_drawn.emit(today_student)

func _register_character(char_id: String, master_data: Dictionary) -> void:
	CharacterState.init_character(char_id, master_data)
	FriendshipManager.init_for_character(char_id, CharacterState.get_all_active_ids())

func _run_daily_pipeline(board: Node) -> Dictionary:
	var result = {
		"day":               current_day,
		"subject":           "",
		"is_test":           false,
		"test_results":      {},
		"ability_log":       [],
		"fulfillment_deltas": {},
		"transfers":         []
	}

	# Step 1: 科目決定
	var subject  = LessonManager.pick_subject()
	var is_test  = LessonManager.is_test_day(current_day)
	result["subject"] = subject
	result["is_test"]  = is_test

	# Step 2: 全キャラに授業効果（充実度10以上は×2）
	for char_id in CharacterState.get_all_active_ids():
		var fulfillment = CharacterState.get_state(char_id).get("fulfillment", 0)
		var mult = 2 if fulfillment >= 10 else 1
		CharacterState.apply_param_delta(char_id, subject, mult)

	# Step 3: 好き/嫌いタイプによる仲良し度変動
	_apply_like_dislike(board)

	# Step 4: 特殊能力適用
	result["ability_log"] = AbilityEngine.apply_all_abilities(board)

	# Step 5: 充実度を集計して適用
	var f_deltas: Dictionary = {}
	for char_id in CharacterState.get_all_active_ids():
		var delta = FulfillmentCalc.calc_daily_fulfillment_delta(char_id)
		CharacterState.apply_fulfillment_delta(char_id, delta)
		f_deltas[char_id] = delta
	result["fulfillment_deltas"] = f_deltas

	# Step 6: テスト日なら判定・反映
	if is_test:
		var test_results: Dictionary = {}
		var passing = LessonManager.get_passing_score(current_day)
		for char_id in CharacterState.get_all_active_ids():
			var passed = LessonManager.evaluate_test_for_char(char_id, subject, current_day)
			FulfillmentCalc.apply_test_result(char_id, passed)
			test_results[char_id] = passed
		result["test_results"] = test_results

	# Step 7: 転校判定（充実度≤-10のキャラを退場）
	var transfers = FulfillmentCalc.get_transfer_candidates("player")
	for char_id in transfers:
		var seat = _find_seat_for(board, char_id)
		if seat >= 0:
			board.remove_student(seat)
		CharacterState.remove_character(char_id)
		FriendshipManager.remove_character(char_id)
	result["transfers"] = transfers

	# Step 8: エンディング判定
	if current_day >= MAX_DAYS:
		_trigger_ending()
	else:
		# Step 9: セーブ
		SaveManager.save_game(board)

	return result

func _apply_like_dislike(board: Node) -> void:
	for entry in board.get_all_placed():
		var char_id = entry["student_data"].get("id", "")
		if char_id == "":
			continue
		var state    = CharacterState.get_state(char_id)
		var like_t   = state.get("like_type", "")
		var dislike_t = state.get("dislike_type", "")

		for other_entry in board.get_all_placed():
			var other_id = other_entry["student_data"].get("id", "")
			if other_id == "" or other_id == char_id:
				continue
			var other_type = CharacterState.get_state(other_id).get("type", "")
			if like_t != "" and other_type == like_t:
				FriendshipManager.apply_friendship_delta(char_id, other_id, 1)
			if dislike_t != "" and other_type == dislike_t:
				FriendshipManager.apply_friendship_delta(char_id, other_id, -1)

	# プレイヤーの like/dislike も適用
	for entry in board.get_all_placed():
		var other_id   = entry["student_data"].get("id", "")
		if other_id == "":
			continue
		var other_type = CharacterState.get_state(other_id).get("type", "")
		if player_like_type != "" and other_type == player_like_type:
			FriendshipManager.apply_friendship_delta("player", other_id, 1)
		if player_dislike_type != "" and other_type == player_dislike_type:
			FriendshipManager.apply_friendship_delta("player", other_id, -1)

func _find_seat_for(board: Node, char_id: String) -> int:
	for entry in board.get_all_placed():
		if entry["student_data"].get("id", "") == char_id:
			return entry["seat_index"]
	return -1

func _trigger_ending() -> void:
	var ending_id = _determine_ending()
	_change_phase(Phase.ENDING)
	ending_reached.emit(ending_id)

func _determine_ending() -> String:
	var fulfillment = CharacterState.get_state("player").get("fulfillment", 0)
	if fulfillment >= 30:
		return "true_ending"
	elif fulfillment >= 10:
		return "normal_ending"
	elif fulfillment >= -9:
		return "plain_ending"
	else:
		return "bad_ending"

func _change_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)
