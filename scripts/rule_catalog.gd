extends RefCounted
class_name RuleCatalog

static func all_rules() -> Array[Dictionary]:
	var events := [
		"При старте плейса",
		"При нажатии на объект",
		"При касании игроком",
		"При нажатии клавиши E",
		"При входе игрока",
		"При выходе игрока",
		"Каждую секунду",
		"При подборе предмета",
		"При добыче ресурса",
		"При достижении цели"
	]
	var actions := [
		"Переместить объект",
		"Повернуть объект",
		"Изменить цвет",
		"Изменить размер",
		"Переключить видимость",
		"Телепортировать игрока",
		"Добавить очки",
		"Показать сообщение",
		"Создать копию объекта",
		"Выдать предмет"
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
				"description": "Готовое визуальное правило №%d. Настройка без ручного кода." % number,
				"enabled": true
			})
	return result

static func rules_count() -> int:
	return all_rules().size()
