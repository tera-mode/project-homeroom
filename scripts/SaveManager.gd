## SaveManager.gd
## 自動セーブ・ロード。AutoLoadとして登録される。
extends Node

const SAVE_PATH = "user://saves/save_data.json"
const SAVE_DIR  = "user://saves/"

signal save_completed()
signal load_completed()

func _ready() -> void:
	_ensure_save_dir()

func save_game(board: Node) -> void:
	var data = {
		"version":        2,
		"timestamp":      Time.get_datetime_string_from_system(),
		"game":           GameManager.get_save_data(),
		"board":          board.get_save_data(),
		"character_state": CharacterState.get_save_data(),
		"friendship":     FriendshipManager.get_save_data()
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: save file open failed")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	save_completed.emit()

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
		push_error("SaveManager: parse error")
		return false
	var data = json.get_data()
	GameManager.load_save_data(data.get("game", {}))
	board.load_save_data(data.get("board", {}))
	CharacterState.load_save_data(data.get("character_state", {}))
	FriendshipManager.load_save_data(data.get("friendship", {}))
	load_completed.emit()
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
