extends RefCounted
class_name RuleEngine

static func execute(target: Node3D, player: Node3D, rule: Dictionary, state: Dictionary) -> Dictionary:
	var action := str(rule.get("action", ""))
	if not is_instance_valid(target) and action not in ["Добавить очки", "Показать сообщение", "Телепортировать игрока", "Изменить скорость"]:
		return state

	match action:
		"Переместить объект":
			target.position += Vector3(0.0, 0.5, 0.0)
		"Повернуть объект":
			target.rotate_y(deg_to_rad(45.0))
		"Изменить цвет":
			var mesh := target.get_node_or_null("MeshInstance3D") as MeshInstance3D
			if mesh:
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(1.0, 0.16, 0.22)
				mesh.material_override = material
		"Изменить размер":
			target.scale *= Vector3(1.1, 1.1, 1.1)
		"Показать объект":
			target.visible = true
		"Скрыть объект":
			target.visible = false
		"Телепортировать игрока":
			if is_instance_valid(player):
				if is_instance_valid(target):
					player.global_position = target.global_position + Vector3(0.0, 2.0, 0.0)
				elif state.has("spawn_position"):
					var spawn: Array = state.spawn_position
					player.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
		"Добавить очки":
			state["score"] = int(state.get("score", 0)) + 1
			state["message"] = "Очки: %d" % int(state.score)
		"Показать сообщение":
			state["message"] = str(rule.get("message", "Правило выполнено!"))
		"Создать объект":
			if is_instance_valid(target) and is_instance_valid(target.get_parent()):
				var created := MeshInstance3D.new()
				created.name = "Созданный_объект"
				var box := BoxMesh.new()
				box.size = Vector3.ONE
				created.mesh = box
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.22, 0.58, 1.0)
				created.material_override = material
				target.get_parent().add_child(created)
				created.global_position = target.global_position + Vector3(0.0, 2.0, 0.0)
		"Открыть дверь":
			if is_instance_valid(target):
				target.position.y += 2.0
		"Изменить скорость":
			if is_instance_valid(player):
				player.set("move_speed", 10.0)
	return state
