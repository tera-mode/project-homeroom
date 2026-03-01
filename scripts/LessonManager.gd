## LessonManager.gd
## AutoLoad: 授業・テストのロジックを担う
extends Node

const TEST_DAYS: Array = [4, 8, 12, 16, 20, 24, 28]
const SUBJECTS: Array = ["study", "sports", "art"]

func is_test_day(day: int) -> bool:
	return day in TEST_DAYS

func get_passing_score(day: int) -> int:
	return int(floor(day / 2.0))

func pick_subject() -> String:
	return SUBJECTS[randi() % SUBJECTS.size()]

func evaluate_test_for_char(char_id: String, subject: String, day: int) -> bool:
	var state = CharacterState.get_state(char_id)
	if state.is_empty():
		return false
	return state.get(subject, 0) >= get_passing_score(day)
