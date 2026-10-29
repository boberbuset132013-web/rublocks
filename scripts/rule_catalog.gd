extends RefCounted
class_name RuleCatalog

static func all_rules() -> Array[Dictionary]:
	var events := [
		"При старте плейса", "При нажатии на объект", "При касании игроком",
		"При нажатии клавиши E", "При входе игрока", "При выходе игрока",
		"Каждую секунду", "При падении здоровья", "При смерти игрока",
		"При возрождении", "При достижении цели", "При истечении таймера"
	]
	var actions := [
		"Переместить объект", "Повернуть объект", "Изменить цвет", "Изменить размер",
		"Показать объект", "Скрыть объект", "Телепортировать игрока", "Добавить очки",
		"Показать сообщение", "Создать объект", "Открыть дверь", "Изменить скорость"
	]
	var result: Array[Dictionary] = []
	for event_index in range(events.size()):
		for action_index in range(actions.size()):
			var number := event_index * actions.size() + action_index + 1
			result.append({
				"id": "rule_%03d" % number,
				"title": "%s → %s" % [events[event_index], actions[action_index]],
				"event": events[event_index],
				"action": actions[action_index],
				"description": "Готовое правило без написания скрипта.",
				"enabled": true
			})
	return result

static func rules_count() -> int:
	return all_rules().size()
