## SaveManager.gd
## 自動セーブ・ロード。AutoLoadとして登録される。
## 毎日終了時に自動セーブ。saves/ フォルダに保存。
extends Node

const SAVE_PATH = "user://saves/save_data.json"
const SAVE_DIR = "user://saves/"

# シグナル
signal save_completed()
signal load_completed()

func _ready() -> void:
	_ensure_save_dir()

# セーブデータを保存する
func save_game(board: Node) -> void:
	var data = {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"game": GameManager.get_save_data(),
		"params": ParamStore.get_save_data(),
		"board": board.get_save_data(),
		"missions": MissionManager.get_save_data()
	}

	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file for writing")
		return

	file.store_string(json_str)
	file.close()
	save_completed.emit()

# セーブデータを読み込む
func load_game(board: Node) -> bool:
	if not has_save():
		return false

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false

	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse save data")
		return false

	var data = json.get_data()
	GameManager.load_save_data(data.get("game", {}))
	ParamStore.load_save_data(data.get("params", {}))
	board.load_save_data(data.get("board", {}))
	MissionManager.load_save_data(data.get("missions", {}))

	load_completed.emit()
	return true

# セーブデータが存在するか
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# セーブデータを削除する
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

# --- Private ---

func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
