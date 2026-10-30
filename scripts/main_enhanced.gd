extends "res://scripts/main.gd"

const OBJECTS = preload("res://scripts/object_catalog.gd")
const RUSCRIPT = preload("res://scripts/script_runtime.gd")
const OBJECT_TYPES := ["Куб", "Шар", "Цилиндр", "Капсула", "Конус", "Плоскость", "Клин", "Платформа", "Ступенька", "Спавн", "Кирка", "Топор", "Молот", "Меч", "Руда", "Дерево", "Ящик", "Дверь", "Кнопка", "Лампа"]

var wardrobe_model: Node3D
var wardrobe_parts: Dictionary = {}
var wardrobe_dragging := false
var avatar_data: Dictionary = {"shirt": [0.16, 0.42, 0.88, 1.0], "pants": [0.12, 0.16, 0.24, 1.0], "skin": [0.92, 0.69, 0.52, 1.0], "hat": false}
var inventory: Array[Dictionary] = []
var inventory_buttons: Array[Button] = []
var selected_slot := -1

func _ready() -> void:
	super._ready()
	_load_avatar()

# Replaces the old await-loop loader with a tween and a hard fallback.
func _show_boot() -> void:
	page = "boot"
	_clear_screen()
	_add_background(Color(0.015, 0.055, 0.22))
	var center := CenterContainer.new()
	_full_rect(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	_label(box, "RUblocks", 52, Color(0.86, 0.92, 1.0))
	_label(box, "Подготовка игрового мира", 18)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(420, 16)
	progress.max_value = 100
	box.add_child(progress)
	var status := _label(box, "Загрузка интерфейса…", 13, Color(0.65, 0.77, 0.96))
	var tween := create_tween()
	tween.tween_property(progress, "value", 100.0, 1.0)
	tween.tween_callback(func():
		if is_instance_valid(status):
			status.text = "Готово"
		_finish_enhanced_boot()
	)
	get_tree().create_timer(2.5).timeout.connect(_finish_enhanced_boot)

func _finish_enhanced_boot() -> void:
	if page == "boot":
		_show_main_menu()

func _find_label_parent(root: Node, wanted: String) -> Node:
	if root is Label and (root as Label).text == wanted:
		return root.get_parent()
	for child in root.get_children():
		var found := _find_label_parent(child, wanted)
		if found != null:
			return found
	return null

func _show_main_menu() -> void:
	super._show_main_menu()
	var hero := _find_label_parent(self, "Создавай миры.\nСобирай игры.")
	if hero is VBoxContainer:
		_button(hero, "Гардероб персонажа", _show_wardrobe, true)

func _show_editor() -> void:
	super._show_editor()
	var explorer := _find_label_parent(self, "Панель объектов")
	if explorer is VBoxContainer:
		var header := HBoxContainer.new()
		explorer.add_child(header)
		_label(header, "Объекты сцены", 13, Color(0.64, 0.76, 1.0))
		var plus := MenuButton.new()
		plus.text = "+"
		plus.tooltip_text = "Добавить 1 из 20 типов объектов"
		plus.custom_minimum_size = Vector2(44, 34)
		header.add_child(plus)
		var popup := plus.get_popup()
		for i in range(OBJECT_TYPES.size()):
			popup.add_item(OBJECT_TYPES[i], i)
		popup.id_pressed.connect(func(id: int):
			if id >= 0 and id < OBJECT_TYPES.size():
				_add_editor_object(OBJECT_TYPES[id])
		)

func _show_game() -> void:
	inventory.clear()
	inventory_buttons.clear()
	selected_slot = -1
	super._show_game()

func _create_game_hud() -> void:
	super._create_game_hud()
	var bar := HBoxContainer.new()
	_layout(bar, 0.34, 0.91, 0.76, 0.99, Vector4.ZERO)
	bar.add_theme_constant_override("separation", 6)
	game_hud.add_child(bar)
	inventory_buttons.clear()
	for i in range(5):
		var button := _button(bar, "%d: —" % (i + 1), _select_slot.bind(i))
		button.custom_minimum_size = Vector2(105, 42)
		button.add_theme_font_size_override("font_size", 11)
		inventory_buttons.append(button)
	_refresh_inventory()

func _input(event: InputEvent) -> void:
	if page == "wardrobe":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			wardrobe_dragging = event.pressed and event.position.x < get_viewport_rect().size.x * 0.72
		elif event is InputEventMouseMotion and wardrobe_dragging and is_instance_valid(wardrobe_model):
			var motion := event as InputEventMouseMotion
			wardrobe_model.rotate_y(-motion.relative.x * 0.012)
			wardrobe_model.rotation.x = clampf(wardrobe_model.rotation.x - motion.relative.y * 0.006, -0.45, 0.45)
	if event is InputEventKey and event.pressed and not event.echo and page == "game" and game_overlay == null:
		if event.keycode == KEY_F:
			_use_selected_tool()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_select_slot(int(event.keycode - KEY_1))
			return
		if event.keycode == KEY_E and _pickup_nearby_item():
			return
	super._input(event)

func _render_editor_objects() -> void:
	if not is_instance_valid(editor_objects_root):
		return
	for child in editor_objects_root.get_children():
		child.queue_free()
	for data in current_place.get("objects", []):
		var node := MeshInstance3D.new()
		node.name = str(data.get("title", "Объект"))
		node.set_meta("rublocks_id", str(data.get("id", "")))
		var kind := str(data.get("kind", "Куб"))
		node.mesh = OBJECTS.make_mesh(kind)
		var p: Array = data.get("position", [0.0, 0.5, 0.0])
		var r: Array = data.get("rotation", [0.0, 0.0, 0.0])
		var sc: Array = data.get("scale", [1.0, 1.0, 1.0])
		node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		node.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
		node.scale = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
		var c: Array = data.get("color", OBJECTS.default_color(kind))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
		_apply_texture(mat, data)
		node.material_override = mat
		editor_objects_root.add_child(node)

func _add_editor_object(kind: String = "Куб") -> void:
	var all: Array = current_place.get("objects", [])
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	all.append({
		"id": id,
		"title": "%s %d" % [kind, all.size() + 1],
		"kind": kind,
		"position": [randf_range(-3.0, 3.0), 0.5, randf_range(-3.0, 3.0)],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"color": OBJECTS.default_color(kind),
		"collidable": true,
		"pickupable": OBJECTS.is_pickupable(kind),
		"texture_path": "",
		"rules": [],
		"script": ""
	})
	current_place["objects"] = all
	selected_object_id = id
	_render_editor_objects()
	_refresh_editor_lists()
	_refresh_editor_properties()

func _create_game_object(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var kind := str(data.get("kind", "Куб"))
	var body := StaticBody3D.new()
	body.name = str(data.get("title", kind))
	body.set_meta("rublocks_id", id)
	body.set_meta("rublocks_kind", kind)
	body.set_meta("pickupable", bool(data.get("pickupable", OBJECTS.is_pickupable(kind))))
	var p: Array = data.get("position", [0.0, 0.5, 0.0])
	var r: Array = data.get("rotation", [0.0, 0.0, 0.0])
	var sc: Array = data.get("scale", [1.0, 1.0, 1.0])
	body.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	body.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	body.scale = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	body.collision_layer = 1 if bool(data.get("collidable", true)) else 2
	body.collision_mask = 1
	game_objects_root.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = OBJECTS.make_mesh(kind)
	var c: Array = data.get("color", OBJECTS.default_color(kind))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
	_apply_texture(mat, data)
	mesh.material_override = mat
	body.add_child(mesh)
	game_object_nodes[id] = body

func _apply_texture(material: StandardMaterial3D, data: Dictionary) -> void:
	var path := str(data.get("texture_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var image := Image.new()
	if image.load(path) == OK:
		material.albedo_texture = ImageTexture.create_from_image(image)

func _refresh_editor_properties() -> void:
	super._refresh_editor_properties()
	var selected := _get_selected_object()
	if selected.is_empty() or not is_instance_valid(properties_box):
		return
	_label(properties_box, "Поворот объекта X / Y / Z", 13)
	var rotations: Array = selected.get("rotation", [0.0, 0.0, 0.0])
	var object_id := str(selected.get("id", ""))
	for axis in range(3):
		var row := HBoxContainer.new()
		properties_box.add_child(row)
		_label(row, ["X", "Y", "Z"][axis], 12)
		var spin := SpinBox.new()
		spin.min_value = -360
		spin.max_value = 360
		spin.step = 5
		spin.value = float(rotations[axis])
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_set_rotation_axis.bind(object_id, axis))
		row.add_child(spin)
	var pickup := CheckBox.new()
	pickup.text = "Можно взять в инвентарь"
	pickup.button_pressed = bool(selected.get("pickupable", false))
	pickup.toggled.connect(func(v: bool): selected["pickupable"] = v)
	properties_box.add_child(pickup)
	_button(properties_box, "Текстура + (PNG/JPG)", _choose_texture)
	_label(properties_box, "Текстура: " + ("назначена" if not str(selected.get("texture_path", "")).is_empty() else "нет"), 11)

func _set_rotation_axis(value: float, object_id: String, axis: int) -> void:
	for data in current_place.get("objects", []):
		if str(data.get("id", "")) == object_id:
			var values: Array = data.get("rotation", [0.0, 0.0, 0.0])
			values[axis] = value
			data["rotation"] = values
			_render_editor_objects()
			return

func _choose_texture() -> void:
	var selected := _get_selected_object()
	if selected.is_empty():
		return
	var dialog := FileDialog.new()
	dialog.title = "Выбери изображение для текстуры"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Изображения"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var image := Image.new()
		if image.load(path) != OK:
			_show_message_overlay("Не удалось загрузить изображение.")
			dialog.queue_free()
			return
		var folder := "user://places/textures"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var dest := folder + "/" + str(selected.get("id", "object")) + ".png"
		if image.save_png(dest) == OK:
			selected["texture_path"] = dest
			_render_editor_objects()
			_refresh_editor_properties()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(800, 600))

func _show_script_editor() -> void:
	var selected := _get_selected_object()
	if selected.is_empty():
		return
	var overlay := Control.new()
	_full_rect(overlay)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	_full_rect(dim)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	_full_rect(center)
	overlay.add_child(center)
	var box := _card(center, 700)
	_label(box, "RUscript — сценарий объекта", 22)
	_label(box, "Примеры: on При касании игроком; message Нашёл ресурс!; score 5; speed 10; give Кирка; jump; heal 20; rotate; hide; show; open. # — комментарий.", 12)
	var editor := TextEdit.new()
	editor.custom_minimum_size = Vector2(650, 300)
	editor.text = str(selected.get("script", ""))
	editor.placeholder_text = "on При нажатии клавиши E\nmessage Привет!\nscore 5"
	box.add_child(editor)
	_button(box, "Сохранить сценарий", func():
		selected["script"] = editor.text
		overlay.queue_free()
		_refresh_editor_properties()
	, true)
	_button(box, "Закрыть", func(): overlay.queue_free())

func _execute_rules(event_name: String, only_target: Node3D = null) -> void:
	super._execute_rules(event_name, only_target)
	var wanted_id := ""
	if is_instance_valid(only_target):
		wanted_id = str(only_target.get_meta("rublocks_id", ""))
	for data in current_place.get("objects", []):
		var id := str(data.get("id", ""))
		if not wanted_id.is_empty() and wanted_id != id:
			continue
		var target: Node3D = game_object_nodes.get(id)
		if not is_instance_valid(target):
			continue
		var source := str(data.get("script", ""))
		if not source.is_empty():
			runtime_state = RUSCRIPT.execute(source, event_name, target, player_body, runtime_state)
	_consume_enhanced_state()

func _consume_enhanced_state() -> void:
	if runtime_state.has("pending_item"):
		_add_item(str(runtime_state.pending_item))
		runtime_state.erase("pending_item")
	if runtime_state.has("message"):
		_append_chat(str(runtime_state.message))
		runtime_state.erase("message")

func _add_item(kind: String, amount: int = 1) -> bool:
	if kind.is_empty():
		return false
	for item in inventory:
		if str(item.get("kind", "")) == kind:
			item["count"] = int(item.get("count", 1)) + amount
			_refresh_inventory()
			return true
	if inventory.size() >= 5:
		return false
	inventory.append({"kind": kind, "title": kind, "count": amount})
	if selected_slot < 0:
		selected_slot = 0
	_refresh_inventory()
	return true

func _refresh_inventory() -> void:
	for i in range(inventory_buttons.size()):
		var button := inventory_buttons[i]
		if not is_instance_valid(button):
			continue
		if i < inventory.size():
			var item: Dictionary = inventory[i]
			button.text = "%d: %s ×%d" % [i + 1, str(item.get("title", item.get("kind", "?"))), int(item.get("count", 1))]
		else:
			button.text = "%d: —" % (i + 1)
		button.modulate = Color(0.75, 0.9, 1.0) if i == selected_slot else Color.WHITE

func _select_slot(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	selected_slot = index
	_refresh_inventory()

func _pickup_nearby_item() -> bool:
	if not is_instance_valid(player_body):
		return false
	var best_id := ""
	var best_body: Node3D
	var best_distance := 2.8
	for data in current_place.get("objects", []):
		if not bool(data.get("pickupable", OBJECTS.is_pickupable(str(data.get("kind", ""))))):
			continue
		var id := str(data.get("id", ""))
		var body: Node3D = game_object_nodes.get(id)
		if not is_instance_valid(body):
			continue
		var distance := player_body.global_position.distance_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best_id = id
			best_body = body
	if best_id.is_empty() or not is_instance_valid(best_body):
		return false
	var kind := str(best_body.get_meta("rublocks_kind", "Предмет"))
	if not _add_item(kind):
		_append_chat("Инвентарь заполнен.")
		return true
	_execute_rules("При подборе предмета", best_body)
	best_body.queue_free()
	game_object_nodes.erase(best_id)
	_append_chat("Подобрано: " + kind)
	return true

func _use_selected_tool() -> void:
	if selected_slot < 0 or selected_slot >= inventory.size():
		_append_chat("Сначала выбери предмет в инвентаре.")
		return
	var tool := str(inventory[selected_slot].get("kind", ""))
	var target_kind := "Руда" if tool == "Кирка" else ("Дерево" if tool == "Топор" else ("Ящик" if tool == "Молот" else ""))
	if target_kind.is_empty():
		_append_chat("Выбранный предмет пока нельзя использовать.")
		return
	var nearest_id := ""
	var nearest: Node3D
	var distance_limit := 3.2
	for data in current_place.get("objects", []):
		if str(data.get("kind", "")) != target_kind:
			continue
		var id := str(data.get("id", ""))
		var body: Node3D = game_object_nodes.get(id)
		if not is_instance_valid(body):
			continue
		var distance := player_body.global_position.distance_to(body.global_position)
		if distance < distance_limit:
			distance_limit = distance
			nearest_id = id
			nearest = body
	if nearest_id.is_empty():
		_append_chat("Рядом нет объекта «" + target_kind + "».")
		return
	_execute_rules("При добыче ресурса", nearest)
	var result := "Руда" if target_kind == "Руда" else ("Древесина" if target_kind == "Дерево" else "Детали")
	if _add_item(result):
		nearest.queue_free()
		game_object_nodes.erase(nearest_id)
		_append_chat("Получено: " + result)
	else:
		_append_chat("Инвентарь заполнен.")

func _load_avatar() -> void:
	if not FileAccess.file_exists("user://avatar.json"):
		return
	var file := FileAccess.open("user://avatar.json", FileAccess.READ)
	if file == null:
		return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if saved is Dictionary:
		for key in saved:
			avatar_data[key] = saved[key]

func _save_avatar() -> void:
	var file := FileAccess.open("user://avatar.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(avatar_data))
		file.close()
	_show_message_overlay("Внешний вид сохранён.")

func _avatar_color(key: String) -> Color:
	var value: Array = avatar_data.get(key, [1.0, 1.0, 1.0, 1.0])
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)

func _add_preview_part(name_value: String, mesh_value: Mesh, at: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = name_value
	part.mesh = mesh_value
	part.position = at
	part.scale = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	part.material_override = material
	wardrobe_model.add_child(part)
	wardrobe_parts[name_value] = part

func _build_wardrobe_preview() -> void:
	wardrobe_model = Node3D.new()
	active_world.add_child(wardrobe_model)
	wardrobe_parts.clear()
	_add_preview_part("torso", BoxMesh.new(), Vector3(0, 1.25, 0), Vector3(0.72, 0.9, 0.38), _avatar_color("shirt"))
	_add_preview_part("head", SphereMesh.new(), Vector3(0, 2.0, 0), Vector3(0.62, 0.62, 0.62), _avatar_color("skin"))
	_add_preview_part("arm_l", CapsuleMesh.new(), Vector3(-0.52, 1.28, 0), Vector3(0.28, 0.86, 0.28), _avatar_color("shirt"))
	_add_preview_part("arm_r", CapsuleMesh.new(), Vector3(0.52, 1.28, 0), Vector3(0.28, 0.86, 0.28), _avatar_color("shirt"))
	_add_preview_part("leg_l", BoxMesh.new(), Vector3(-0.2, 0.43, 0), Vector3(0.3, 0.82, 0.34), _avatar_color("pants"))
	_add_preview_part("leg_r", BoxMesh.new(), Vector3(0.2, 0.43, 0), Vector3(0.3, 0.82, 0.34), _avatar_color("pants"))
	_add_preview_part("hat", CylinderMesh.new(), Vector3(0, 2.34, 0), Vector3(0.78, 0.16, 0.78), Color(0.85, 0.1, 0.16))
	(wardrobe_parts["hat"] as MeshInstance3D).visible = bool(avatar_data.get("hat", false))

func _set_wardrobe_color(part: String, values: Array) -> void:
	avatar_data[part] = values
	var target_names := ["torso", "arm_l", "arm_r"] if part == "shirt" else ["leg_l", "leg_r"]
	if part == "skin":
		target_names = ["head"]
	for name_value in target_names:
		if wardrobe_parts.has(name_value):
			var node: MeshInstance3D = wardrobe_parts[name_value]
			(node.material_override as StandardMaterial3D).albedo_color = _avatar_color(part)

func _show_wardrobe() -> void:
	page = "wardrobe"
	_clear_screen()
	_add_background(Color(0.015, 0.022, 0.04))
	var viewport := _create_3d_viewport("editor")
	_layout(viewport, 0.0, 0.0, 0.72, 1.0, Vector4.ZERO)
	editor_camera.position = Vector3(0.0, 1.5, 5.8)
	editor_camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	_build_wardrobe_preview()
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(16, 16)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.08, 0.11, 0.17)
	floor.material_override = floor_mat
	floor.position.y = -0.04
	active_world.add_child(floor)
	var right := PanelContainer.new()
	_layout(right, 0.73, 0.04, 0.98, 0.96, Vector4.ZERO)
	add_child(right)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 9)
	right.add_child(panel)
	_label(panel, "Гардероб", 25)
	_label(panel, "Зажми ЛКМ и двигай мышь, чтобы вращать модель.", 12)
	_button(panel, "Синяя одежда", func(): _set_wardrobe_color("shirt", [0.12, 0.36, 0.86, 1.0]), true)
	_button(panel, "Красная одежда", func(): _set_wardrobe_color("shirt", [0.82, 0.08, 0.12, 1.0]))
	_button(panel, "Зелёная одежда", func(): _set_wardrobe_color("shirt", [0.12, 0.58, 0.28, 1.0]))
	_button(panel, "Тёмные штаны", func(): _set_wardrobe_color("pants", [0.08, 0.1, 0.16, 1.0]))
	_button(panel, "Светлые штаны", func(): _set_wardrobe_color("pants", [0.55, 0.58, 0.63, 1.0]))
	_button(panel, "Переключить шапку", func():
		avatar_data["hat"] = not bool(avatar_data.get("hat", false))
		(wardrobe_parts["hat"] as MeshInstance3D).visible = bool(avatar_data["hat"])
	)
	_button(panel, "Сохранить образ", _save_avatar, true)
	_button(panel, "Назад", _show_main_menu)
