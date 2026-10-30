extends RefCounted
class_name ScriptRuntime

# RUscript deliberately interprets a small command set instead of arbitrary OS/GDScript code.
static func execute(source: String, event_name: String, target: Node3D, player: Node3D, state: Dictionary) -> Dictionary:
	var lines := source.split("\n")
	var has_event_filters := false
	for line_value in lines:
		if str(line_value).strip_edges().to_lower().begins_with("on "):
			has_event_filters = true
			break
	var active := not has_event_filters
	for raw_line in lines:
		var line := str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.to_lower().begins_with("on "):
			active = line.substr(3).strip_edges() == event_name
			continue
		if not active:
			continue
		var parts := line.split(" ", false, 1)
		var command := str(parts[0]).to_lower()
		var argument := str(parts[1]) if parts.size() > 1 else ""
		match command:
			"message":
				state["message"] = argument.substr(0, 240)
			"score":
				state["score"] = int(state.get("score", 0)) + clampi(int(argument), -1000, 1000)
				state["message"] = "Очки: %d" % int(state["score"])
			"speed":
				if is_instance_valid(player):
					player.set("move_speed", clampf(float(argument), 1.0, 30.0))
			"give":
				state["pending_item"] = argument if not argument.is_empty() else "Предмет"
			"jump":
				if is_instance_valid(player) and player is CharacterBody3D:
					(player as CharacterBody3D).velocity.y = 5.5
			"heal":
				state["health"] = clampi(int(state.get("health", 100)) + clampi(int(argument), 1, 100), 0, 100)
				state["message"] = "Здоровье: %d" % int(state["health"])
			"rotate":
				if is_instance_valid(target):
					target.rotate_y(deg_to_rad(45.0))
			"hide":
				if is_instance_valid(target):
					target.visible = false
			"show":
				if is_instance_valid(target):
					target.visible = true
			"open":
				if is_instance_valid(target):
					target.position.y += 2.0
			"teleport":
				if is_instance_valid(player) and is_instance_valid(target):
					player.global_position = target.global_position + Vector3(0.0, 2.0, 0.0)
			_:
				state["message"] = "Неизвестная команда RUscript: " + command
	return state
