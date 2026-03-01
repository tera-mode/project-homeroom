## Board.gd
## 4×4盤面の状態管理。AutoLoadではなく、Classroom.tscnにアタッチして使う。
## 席の配置・取得・移動・空席チェックを担当する。
class_name Board
extends Node

const ROWS = 4
const COLS = 4
const TOTAL_SEATS = ROWS * COLS

# 盤面データ: インデックス0〜15、各マスのStudentData or null
var _grid: Array = []

# 席ラベル（特殊効果用）
# seat_labels["window"] = [0, 4, 8, 12, 3, 7, 11, 15]  （左右の列）
# seat_labels["back"] = [12, 13, 14, 15]  （最後列）
# seat_labels["front"] = [0, 1, 2, 3]  （最前列）
var seat_labels: Dictionary = {
	"window": [0, 4, 8, 12, 3, 7, 11, 15],
	"back": [12, 13, 14, 15],
	"front": [0, 1, 2, 3],
	"center": [5, 6, 9, 10]
}

# プレイヤー自身の席インデックス（初回に設定）
var player_seat: int = -1

# 配置済み学生IDのセット（重複チェック用）
var _placed_ids: Array = []

# シグナル
signal student_placed(seat_index: int, student_data: Dictionary)
signal student_removed(seat_index: int, student_id: String)
signal board_changed()

func _ready() -> void:
	_initialize_grid()

# グリッドを空で初期化する
func _initialize_grid() -> void:
	_grid = []
	for i in range(TOTAL_SEATS):
		_grid.append(null)
	_placed_ids = []

# 指定マスに生徒を配置する（成功: true, 失敗: false）
func place_student(seat_index: int, student_data: Dictionary) -> bool:
	if not _is_valid_index(seat_index):
		push_warning("Invalid seat index: %d" % seat_index)
		return false

	if not is_empty(seat_index):
		push_warning("Seat %d is already occupied" % seat_index)
		return false

	var student_id = student_data.get("id", "")
	_grid[seat_index] = student_data.duplicate(true)
	_placed_ids.append(student_id)

	student_placed.emit(seat_index, student_data)
	board_changed.emit()
	return true

# 指定マスの生徒を取り除く（席替えチケット使用時）
func remove_student(seat_index: int) -> bool:
	if not _is_valid_index(seat_index):
		return false

	if is_empty(seat_index):
		return false

	var student_id = _grid[seat_index].get("id", "")
	_placed_ids.erase(student_id)
	_grid[seat_index] = null

	student_removed.emit(seat_index, student_id)
	board_changed.emit()
	return true

# 2つのマスを入れ替える（席替えシャッフルイベント用）
func swap_seats(index_a: int, index_b: int) -> bool:
	if not _is_valid_index(index_a) or not _is_valid_index(index_b):
		return false

	var temp = _grid[index_a]
	_grid[index_a] = _grid[index_b]
	_grid[index_b] = temp

	board_changed.emit()
	return true

# 指定マスの生徒データを返す（空ならnull）
func get_student_at(seat_index: int) -> Variant:
	if not _is_valid_index(seat_index):
		return null
	return _grid[seat_index]

# 指定マスが空かどうか
func is_empty(seat_index: int) -> bool:
	return _grid[seat_index] == null

# 空いているマスのインデックス一覧
func get_empty_seats() -> Array:
	var empties = []
	for i in range(TOTAL_SEATS):
		if is_empty(i):
			empties.append(i)
	return empties

# 配置済みの生徒データ一覧（{seat_index, student_data}のArray）
func get_all_placed() -> Array:
	var result = []
	for i in range(TOTAL_SEATS):
		if not is_empty(i):
			result.append({"seat_index": i, "student_data": _grid[i]})
	return result

# 隣接マスのインデックスを返す（scope指定）
func get_neighbors(seat_index: int, scope: String) -> Array:
	var row = seat_index / COLS
	var col = seat_index % COLS
	var result = []

	match scope:
		"orthogonal":
			# 上下左右4マス
			var candidates = [
				seat_index - COLS,  # 上
				seat_index + COLS,  # 下
				seat_index - 1,     # 左
				seat_index + 1      # 右
			]
			for idx in candidates:
				if _is_valid_index(idx):
					# 行またぎチェック（左右）
					if idx == seat_index - 1 and (idx % COLS) == COLS - 1:
						continue
					if idx == seat_index + 1 and (idx % COLS) == 0:
						continue
					result.append(idx)

		"surrounding":
			# 周囲8マス
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if dr == 0 and dc == 0:
						continue
					var nr = row + dr
					var nc = col + dc
					if nr >= 0 and nr < ROWS and nc >= 0 and nc < COLS:
						result.append(nr * COLS + nc)

		"same_row":
			# 同じ行全員（自分を除く）
			var row_start = row * COLS
			for c in range(COLS):
				var idx = row_start + c
				if idx != seat_index:
					result.append(idx)

		"same_col":
			# 同じ列全員（自分を除く）
			for r in range(ROWS):
				var idx = r * COLS + col
				if idx != seat_index:
					result.append(idx)

		"board_wide":
			# 盤面全員（自分を除く）
			for i in range(TOTAL_SEATS):
				if i != seat_index:
					result.append(i)

		"left_right":
			# 左右2マス（行またぎなし）
			var left = seat_index - 1
			if left >= 0 and (left % COLS) != COLS - 1:
				result.append(left)
			var right = seat_index + 1
			if right < TOTAL_SEATS and (right % COLS) != 0:
				result.append(right)

		"left_only":
			# 左1マス（行またぎなし）
			var left = seat_index - 1
			if left >= 0 and (left % COLS) != COLS - 1:
				result.append(left)

		"right_only":
			# 右1マス（行またぎなし）
			var right = seat_index + 1
			if right < TOTAL_SEATS and (right % COLS) != 0:
				result.append(right)

		"up_down":
			# 上下2マス
			var up = seat_index - COLS
			if up >= 0:
				result.append(up)
			var down = seat_index + COLS
			if down < TOTAL_SEATS:
				result.append(down)

		"self":
			result = [seat_index]

	return result

# 盤面状態をセーブ用辞書として返す
func get_save_data() -> Dictionary:
	var grid_data = []
	for i in range(TOTAL_SEATS):
		if _grid[i] != null:
			grid_data.append({"index": i, "student": _grid[i]})
		else:
			grid_data.append({"index": i, "student": null})
	return {
		"grid": grid_data,
		"player_seat": player_seat,
		"placed_ids": _placed_ids.duplicate()
	}

# セーブデータから盤面を復元する
func load_save_data(data: Dictionary) -> void:
	_initialize_grid()
	player_seat = data.get("player_seat", -1)
	_placed_ids = data.get("placed_ids", []).duplicate()

	for entry in data.get("grid", []):
		var idx = entry.get("index", -1)
		if _is_valid_index(idx) and entry["student"] != null:
			_grid[idx] = entry["student"]

	board_changed.emit()

# リセット
func reset() -> void:
	_initialize_grid()
	player_seat = -1
	board_changed.emit()

# --- Private ---

func _is_valid_index(idx: int) -> bool:
	return idx >= 0 and idx < TOTAL_SEATS
