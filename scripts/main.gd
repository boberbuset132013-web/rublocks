extends Control

const RULE_CATALOG = preload("res://scripts/rule_catalog.gd")
const RULE_ENGINE = preload("res://scripts/rule_engine.gd")
const PLAYER_CONTROLLER = preload("res://scripts/player_controller.gd")
const API_BASE := "https://rublocks.boberbuset132013.workers.dev"

var page := "boot"
var current_user: Dictionary = {}
var auth_token := ""
var auth_register_mode := true
var auth_name_edit: LineEdit
var auth_password_edit: LineEdit
var auth_error_label: Label
var local_places: Array[Dictionary] = []
var remote_places: Array[Dictionary] = []
var current_place: Dictionary = {}
var selected_object_id := ""
var menu_places_box: VBoxContainer
var objects_list: VBoxContainer
var rules_list: VBoxContainer
var properties_box: VBoxContainer
var editor_viewport_container: SubViewportContainer
var editor_root: Node3D
var editor_objects_root: Node3D
var editor_camera: Camera3D
var editor_tab := "objects"
var active_subviewport: SubViewport
var active_world: Node3D
var active_camera: Camera3D
var auth_cube_nodes: Array[Node3D] = []
var player_body: CharacterBody3D
var game_camera: Camera3D
var game_objects_root: Node3D
var game_object_nodes: Dictionary = {}
var remote_player_nodes: Dictionary = {}
var last_network_send_ms := 0
var game_overlay: Control
var game_overlay_mode := ""
var game_hud: Control
var chat_input: LineEdit
var chat_display: Label
var chat_messages: Array[String] = []
var online_players: Array[String] = []
var network_socket: WebSocketPeer
var runtime_state: Dictionary = {"score": 0}
var touching_object_ids: Dictionary = {}
var rules_second_timer := 0.0
var volume_value := 0.8

func _ready() -> void:
	get_window().title = "RUblocks"
	get_window().min_size = Vector2i(900, 600)
	var icon_texture := load("res://assets/rublocks_icon.svg") as Texture2D
	if icon_texture != null:
		DisplayServer.set_icon(icon_texture.get_image())
	_load_saved_places()
	_show_boot()

func _process(delta: float) -> void:
	for cube in auth_cube_nodes:
		if is_instance_valid(cube):
			cube.rotate_x(delta * 0.7)
			cube.rotate_y(delta * 1.1)
			cube.position.y -= delta * float(cube.get_meta("fall_speed", 1.0))
			if cube.position.y < -7.0:
				cube.position.y = 7.0
				cube.position.x = randf_range(-9.0, 9.0)
	if page == "game" and is_instance_valid(player_body) and is_instance_valid(game_camera):
		game_camera.position = player_body.global_position + Vector3(0.0, 6.0, 11.0)
		game_camera.look_at(player_body.global_position + Vector3(0.0, 0.7, 0.0), Vector3.UP)
		_update_touch_rules()
		rules_second_timer += delta
		if rules_second_timer >= 1.0:
			rules_second_timer = 0.0
			_execute_rules("Каждую секунду")
		_poll_network()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if page == "game":
				_toggle_game_menu()
			elif page == "editor":
				_show_main_menu()
			elif page == "auth" or page == "settings":
				_show_main_menu()
		elif event.keycode == KEY_E and page == "game" and game_overlay == null:
			_execute_rules("При нажатии клавиши E")
	if page == "game" and game_overlay == null and event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if get_viewport().gui_get_focus_owner() == null:
				_try_click_object(mouse_event.position)

func _full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _layout(control: Control, left: float, top: float, right: float, bottom: float, offsets: Vector4 = Vector4.ZERO) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = offsets.x
	control.offset_top = offsets.y
	control.offset_right = offsets.z
	control.offset_bottom = offsets.w

func _clear_screen() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	auth_cube_nodes.clear()
	active_subviewport = null
	active_world = null
	active_camera = null
	game_overlay = null
	game_hud = null
	game_objects_root = null
	game_object_nodes.clear()
	remote_player_nodes.clear()
	player_body = null
	game_camera = null
	editor_root = null
	editor_objects_root = null
	editor_viewport_container = null
	menu_places_box = null
	objects_list = null
	rules_list = null
	properties_box = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _add_background(color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	_full_rect(bg)
	add_child(bg)
	return bg

func _label(parent: Node, text_value: String, size: int = 18, color: Color = Color(0.88, 0.91, 0.97)) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, action: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(160, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.36, 0.92) if accent else Color(0.10, 0.13, 0.20)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.46, 1.0) if accent else Color(0.16, 0.20, 0.29)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	parent.add_child(button)
	if action.is_valid():
		button.pressed.connect(action)
	return button

func _card(parent: Node, min_width: float = 320.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.095, 0.97)
	style.border_color = Color(0.14, 0.22, 0.36)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

func _show_boot() -> void:
	page = "boot"
	_clear_screen()
	_add_background(Color(0.015, 0.055, 0.22))
	var center := CenterContainer.new()
	_full_rect(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	_label(box, "RUblocks", 52, Color(0.82, 0.9, 1.0))
	_label(box, "Подготовка игрового мира", 19, Color(0.72, 0.81, 0.96))
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(420, 16)
	progress.max_value = 100
	progress.show_percentage = false
	box.add_child(progress)
	var status := _label(box, "Проверка ресурсов…", 14, Color(0.63, 0.76, 0.96))
	for value in range(0, 101, 5):
		if page != "boot":
			return
		progress.value = value
		if value == 30:
			status.text = "Загрузка интерфейса…"
		elif value == 65:
			status.text = "Подготовка мира…"
		elif value == 90:
			status.text = "Почти готово…"
		await get_tree().create_timer(0.035).timeout
	if page == "boot":
		_show_main_menu()

func _show_main_menu() -> void:
	page = "menu"
	_clear_screen()
	_add_background(Color(0.018, 0.027, 0.055))
	var margin := MarginContainer.new()
	_full_rect(margin)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var logo := _label(header, "RUblocks", 28, Color(0.38, 0.65, 1.0))
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not current_user.is_empty():
		_label(header, "Привет, %s" % str(current_user.get("username", "Игрок")), 15)
		_button(header, "Выйти из аккаунта", _logout)
	else:
		_button(header, "Войти", _show_login.bind(false))
		_button(header, "Регистрация", _show_login.bind(true), true)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 18)
	column.add_child(main)
	var hero := _card(main, 430)
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(hero, "Создавай миры.\nСобирай игры.", 34, Color(0.95, 0.97, 1.0))
	_label(hero, "3D-конструктор с объектами, спавнами, чатом и визуальными правилами — без необходимости писать скрипты для каждого действия.", 16, Color(0.67, 0.73, 0.84))
	_button(hero, "Создать новый плейс", _create_new_place, true)
	_button(hero, "Открыть редактор", _create_new_place)
	_button(hero, "Настройки", _show_settings)
	var places_panel := _card(main, 440)
	places_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(places_panel, "Плейсы", 24)
	_label(places_panel, "Локальные проекты и опубликованные миры", 13, Color(0.61, 0.69, 0.82))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	places_panel.add_child(scroll)
	menu_places_box = VBoxContainer.new()
	menu_places_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_places_box.add_theme_constant_override("separation", 10)
	scroll.add_child(menu_places_box)
	_populate_menu_places()
	call_deferred("_refresh_remote_places")

func _populate_menu_places() -> void:
	if not is_instance_valid(menu_places_box):
		return
	_clear_container(menu_places_box)
	var all_places: Array[Dictionary] = []
	for place in local_places:
		all_places.append(place)
	for place in remote_places:
		all_places.append(place)
	if all_places.is_empty():
		_label(menu_places_box, "Плейсов пока нет. Создай первый!", 15)
	for place in all_places:
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.07, 0.09, 0.14)
		style.set_corner_radius_all(9)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		row.add_theme_stylebox_override("panel", style)
		menu_places_box.add_child(row)
		var row_box := VBoxContainer.new()
		row.add_child(row_box)
		var cover_path := str(place.get("cover_image", place.get("background_image", "")))
		if not cover_path.is_empty() and FileAccess.file_exists(cover_path):
			var cover_image := Image.new()
			if cover_image.load(cover_path) == OK:
				var cover := TextureRect.new()
				cover.texture = ImageTexture.create_from_image(cover_image)
				cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				cover.custom_minimum_size = Vector2(240, 78)
				row_box.add_child(cover)
		_label(row_box, str(place.get("title", "Без названия")), 17, Color(0.9, 0.94, 1.0))
		_label(row_box, str(place.get("description", "3D-мир RUblocks")), 12, Color(0.62, 0.69, 0.81))
		var actions := HBoxContainer.new()
		row_box.add_child(actions)
		_button(actions, "Играть", _open_place.bind(place), true)
		var place_id := str(place.get("id", ""))
		for local_place in local_places:
			if str(local_place.get("id", "")) == place_id:
				_button(actions, "Изменить", _edit_place.bind(place))
				break

func _show_login(register_mode: bool = true) -> void:
	page = "auth"
	auth_register_mode = register_mode
	_clear_screen()
	_add_background(Color.BLACK)
	var container := _create_3d_viewport("auth")
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(34):
		var cube := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.32, 0.85), randf_range(0.32, 0.85), randf_range(0.32, 0.85))
		cube.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.75 + randf_range(0.0, 0.24), 0.025, 0.07 + randf_range(0.0, 0.1))
		material.metallic = 0.15
		material.roughness = 0.3
		cube.material_override = material
		cube.position = Vector3(randf_range(-9.0, 9.0), randf_range(-7.0, 7.0), randf_range(-4.0, 2.0))
		cube.rotation = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
		cube.set_meta("fall_speed", randf_range(0.45, 1.8))
		active_world.add_child(cube)
		auth_cube_nodes.append(cube)
	var center := CenterContainer.new()
	_full_rect(center)
	add_child(center)
	var box := _card(center, 410)
	_label(box, "RUblocks", 34, Color(0.95, 0.14, 0.22))
	_label(box, "Регистрация" if auth_register_mode else "Вход в аккаунт", 23)
	_label(box, "Имя: 3–20 символов, латиница, цифры или _", 12, Color(0.61, 0.68, 0.8))
	auth_name_edit = LineEdit.new()
	auth_name_edit.placeholder_text = "Имя пользователя"
	auth_name_edit.max_length = 20
	auth_name_edit.custom_minimum_size.y = 42
	box.add_child(auth_name_edit)
	auth_password_edit = LineEdit.new()
	auth_password_edit.placeholder_text = "Пароль (не менее 8 символов)"
	auth_password_edit.secret = true
	auth_password_edit.max_length = 128
	auth_password_edit.custom_minimum_size.y = 42
	box.add_child(auth_password_edit)
	auth_error_label = _label(box, "", 13, Color(1.0, 0.35, 0.4))
	_button(box, "Создать аккаунт" if auth_register_mode else "Войти", _submit_auth, true)
	_button(box, "Переключить на вход" if auth_register_mode else "Переключить на регистрацию", _show_login.bind(not auth_register_mode))
	_button(box, "Назад в меню", _show_main_menu)
	auth_name_edit.grab_focus()

func _submit_auth() -> void:
	if auth_name_edit == null or auth_password_edit == null:
		return
	var username := auth_name_edit.text.strip_edges()
	var password := auth_password_edit.text
	if username.length() < 3 or password.length() < 8:
		auth_error_label.text = "Проверь имя и пароль (минимум 8 символов)."
		return
	auth_error_label.text = "Связь с сервером…"
	var endpoint := "/api/register" if auth_register_mode else "/api/login"
	var response: Dictionary = await _api_call(HTTPClient.METHOD_POST, endpoint, {"username": username, "password": password}, false)
	if not bool(response.get("ok", false)):
		var data: Dictionary = response.get("data", {})
		auth_error_label.text = str(data.get("error", "Сервер недоступен. Проверь Worker и D1."))
		return
	var data: Dictionary = response.get("data", {})
	current_user = data.get("user", {"username": username})
	auth_token = str(data.get("token", ""))
	_show_main_menu()

func _logout() -> void:
	current_user = {}
	auth_token = ""
	_show_main_menu()

func _show_settings() -> void:
	page = "settings"
	_clear_screen()
	_add_background(Color(0.018, 0.027, 0.055))
	var center := CenterContainer.new()
	_full_rect(center)
	add_child(center)
	var box := _card(center, 440)
	_label(box, "Настройки RUblocks", 28)
	_label(box, "Громкость", 15)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = volume_value
	volume.value_changed.connect(func(value: float) -> void:
		volume_value = value
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.001)))
	)
	box.add_child(volume)
	_label(box, "Управление: WASD или стрелки, пробел — прыжок, Esc — меню плейса.", 14, Color(0.65, 0.72, 0.84))
	_button(box, "Назад", _show_main_menu, true)

func _create_3d_viewport(mode: String) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	_full_rect(container)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	active_subviewport = viewport
	var world := Node3D.new()
	world.name = "WorldRoot"
	viewport.add_child(world)
	active_world = world
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.012, 0.025) if mode == "auth" else Color(0.035, 0.05, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.92)
	environment.ambient_light_energy = 0.7
	if mode == "game":
		_apply_place_environment(environment)
	environment_node.environment = environment
	world.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.15
	world.add_child(light)
	var camera := Camera3D.new()
	camera.current = true
	if mode == "auth":
		camera.position = Vector3(0.0, 0.0, 15.0)
		camera.fov = 68.0
	else:
		camera.position = Vector3(0.0, 7.0, 12.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
	world.add_child(camera)
	active_camera = camera
	if mode == "game":
		_build_game_world(world)
	elif mode == "editor":
		_build_editor_world(world)
	return container

func _apply_place_environment(environment: Environment) -> void:
	var path := str(current_place.get("background_image", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var image := Image.new()
	if image.load(path) != OK:
		return
	var texture := ImageTexture.create_from_image(image)
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = texture
	var sky := Sky.new()
	sky.sky_material = panorama
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

func _create_default_place() -> Dictionary:
	return {
		"id": Crypto.new().generate_random_bytes(16).hex_encode(),
		"title": "Мой новый плейс",
		"description": "Мой мир в RUblocks",
		"remote_id": "",
		"published": false,
		"can_reset": true,
		"spawn_position": [0.0, 1.0, 0.0],
		"background_image": "",
		"cover_image": "",
		"objects": [],
		"created_at": int(Time.get_unix_time_from_system()),
		"updated_at": int(Time.get_unix_time_from_system())
	}

func _create_new_place() -> void:
	current_place = _create_default_place()
	selected_object_id = ""
	_show_editor()

func _edit_place(place: Dictionary) -> void:
	current_place = place.duplicate(true)
	if not current_place.has("objects"):
		current_place["objects"] = []
	selected_object_id = ""
	if not current_place.objects.is_empty():
		selected_object_id = str(current_place.objects[0].get("id", ""))
	_show_editor()

func _open_place(place: Dictionary) -> void:
	var is_local := false
	for local_place in local_places:
		if str(local_place.get("id", "")) == str(place.get("id", "")):
			is_local = true
			break
	current_place = place.duplicate(true)
	if not is_local and bool(place.get("published", false)):
		var downloaded: Dictionary = await _api_call(HTTPClient.METHOD_GET, "/api/places/" + str(place.get("id", "")), {}, false)
		if not bool(downloaded.get("ok", false)):
			var download_error: Dictionary = downloaded.get("data", {})
			_show_message_overlay("Не удалось загрузить плейс: " + str(download_error.get("error", "ошибка сервера")))
			return
		var response_data: Dictionary = downloaded.get("data", {})
		var remote_place: Dictionary = response_data.get("place", {})
		var remote_project: Variant = remote_place.get("project", {})
		if remote_project is Dictionary:
			current_place = remote_project.duplicate(true)
			current_place["remote_id"] = str(place.get("id", ""))
			current_place["published"] = true
	if not current_place.has("objects"):
		current_place["objects"] = []
	if not current_place.has("spawn_position"):
		current_place["spawn_position"] = [0.0, 1.0, 0.0]
	_show_game()

func _show_game() -> void:
	page = "game"
	_clear_screen()
	_add_background(Color(0.018, 0.027, 0.055))
	if current_place.is_empty():
		current_place = _create_default_place()
	_create_3d_viewport("game")

func _add_floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.position = Vector3(0.0, -0.5, 0.0)
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 1.0, 60.0)
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60.0, 1.0, 60.0)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.19, 0.15)
	material.roughness = 0.9
	mesh.material_override = material
	body.add_child(mesh)

func _build_game_world(world: Node3D) -> void:
	_add_floor(world)
	game_objects_root = Node3D.new()
	game_objects_root.name = "PlacedObjects"
	world.add_child(game_objects_root)
	game_object_nodes.clear()
	for object_data in current_place.get("objects", []):
		_create_game_object(object_data)
	player_body = CharacterBody3D.new()
	player_body.name = "Player"
	player_body.set_script(PLAYER_CONTROLLER)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	player_body.add_child(collision)
	var player_mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.38
	capsule_mesh.height = 1.8
	player_mesh.mesh = capsule_mesh
	var player_material := StandardMaterial3D.new()
	player_material.albedo_color = Color(0.22, 0.52, 1.0)
	player_mesh.material_override = player_material
	player_body.add_child(player_mesh)
	world.add_child(player_body)
	var spawn: Array = current_place.get("spawn_position", [0.0, 1.0, 0.0])
	player_body.position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
	game_camera = active_camera
	online_players = [str(current_user.get("username", "Вы"))]
	runtime_state = {"score": 0, "spawn_position": spawn}
	chat_messages.clear()
	touching_object_ids.clear()
	_create_game_hud()
	_connect_room()
	_execute_rules("При старте плейса")
	_execute_rules("При входе игрока")

func _create_game_object(object_data: Dictionary) -> void:
	var id := str(object_data.get("id", ""))
	var body := StaticBody3D.new()
	body.name = str(object_data.get("title", "Объект"))
	body.set_meta("rublocks_id", id)
	var scale_data: Array = object_data.get("scale", [1.0, 1.0, 1.0])
	body.scale = Vector3(float(scale_data[0]), float(scale_data[1]), float(scale_data[2]))
	var pos: Array = object_data.get("position", [0.0, 0.5, 0.0])
	body.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	body.collision_layer = 1 if bool(object_data.get("collidable", true)) else 2
	body.collision_mask = 1
	game_objects_root.add_child(body)
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE
	collision.shape = box_shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mesh.mesh = box
	var color_data: Array = object_data.get("color", [0.25, 0.55, 1.0, 1.0])
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]), float(color_data[3]) if color_data.size() > 3 else 1.0)
	mesh.material_override = material
	body.add_child(mesh)
	game_object_nodes[id] = body

func _create_game_hud() -> void:
	game_hud = Control.new()
	_full_rect(game_hud)
	game_hud.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(game_hud)
	var top := PanelContainer.new()
	_layout(top, 0.015, 0.015, 0.56, 0.105, Vector4.ZERO)
	game_hud.add_child(top)
	var top_row := HBoxContainer.new()
	top.add_child(top_row)
	_label(top_row, str(current_place.get("title", "Плейс")), 17, Color(0.94, 0.96, 1.0))
	var help := _label(top_row, "WASD — движение · Space — прыжок · E — правила · Esc — меню", 12, Color(0.63, 0.72, 0.86))
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chat_panel := PanelContainer.new()
	_layout(chat_panel, 0.015, 0.70, 0.36, 0.985, Vector4.ZERO)
	game_hud.add_child(chat_panel)
	var chat_box := VBoxContainer.new()
	chat_box.add_theme_constant_override("separation", 6)
	chat_panel.add_child(chat_box)
	_label(chat_box, "Чат", 14, Color(0.65, 0.77, 1.0))
	chat_display = _label(chat_box, "", 12, Color(0.88, 0.91, 0.97))
	chat_display.custom_minimum_size.y = 95
	var input_row := HBoxContainer.new()
	chat_box.add_child(input_row)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Сообщение…"
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(chat_input)
	_button(input_row, "Отправить", func(): _send_chat(chat_input.text))
	chat_input.text_submitted.connect(_send_chat)
	_refresh_chat()

func _toggle_game_menu() -> void:
	if is_instance_valid(game_overlay):
		_close_game_overlay()
	else:
		_show_game_escape_menu()

func _close_game_overlay() -> void:
	if is_instance_valid(game_overlay):
		game_overlay.queue_free()
	game_overlay = null
	game_overlay_mode = ""
	if is_instance_valid(player_body):
		player_body.set_physics_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _new_game_overlay(title: String) -> VBoxContainer:
	if is_instance_valid(game_overlay):
		game_overlay.queue_free()
	game_overlay = null
	game_overlay_mode = title
	game_overlay = Control.new()
	_full_rect(game_overlay)
	game_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(game_overlay)
	if is_instance_valid(player_body):
		player_body.set_physics_process(false)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.008, 0.02, 0.78)
	_full_rect(dim)
	game_overlay.add_child(dim)
	var center := CenterContainer.new()
	_full_rect(center)
	game_overlay.add_child(center)
	return _card(center, 440)

func _show_game_escape_menu() -> void:
	if page != "game":
		return
	var box := _new_game_overlay("menu")
	_label(box, "Меню плейса", 28)
	_label(box, "Игроки в этом плейсе", 15, Color(0.65, 0.76, 1.0))
	if online_players.is_empty():
		_label(box, "Вы", 14)
	else:
		for username in online_players:
			_label(box, "• " + username, 14)
	var reset_button := _button(box, "Сбросить персонажа", _reset_player, true)
	reset_button.disabled = not bool(current_place.get("can_reset", true))
	if not bool(current_place.get("can_reset", true)):
		_label(box, "Автор плейса отключил сброс персонажа.", 12, Color(0.9, 0.65, 0.65))
	_button(box, "Настройки", _show_game_settings)
	_button(box, "Продолжить", _close_game_overlay, true)
	_button(box, "Выйти из плейса", _leave_game)

func _show_game_settings() -> void:
	var box := _new_game_overlay("settings")
	_label(box, "Настройки плейса", 26)
	_label(box, "Громкость", 14)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume_value
	slider.value_changed.connect(func(value: float) -> void:
		volume_value = value
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.001)))
	)
	box.add_child(slider)
	_label(box, "Управление: WASD / стрелки, Space — прыжок, E — активировать правила.", 13)
	_button(box, "Назад к меню плейса", _show_game_escape_menu, true)
	_button(box, "Продолжить игру", _close_game_overlay)

func _reset_player() -> void:
	if not bool(current_place.get("can_reset", true)) or not is_instance_valid(player_body):
		return
	var spawn: Array = current_place.get("spawn_position", [0.0, 1.0, 0.0])
	player_body.global_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
	player_body.velocity = Vector3.ZERO
	_execute_rules("При возрождении")
	_close_game_overlay()

func _leave_game() -> void:
	if network_socket != null:
		network_socket.close()
	network_socket = null
	_close_game_overlay()
	_show_main_menu()

func _send_chat(text_value: String = "") -> void:
	var message := text_value.strip_edges()
	if message.is_empty():
		return
	if message.length() > 300:
		message = message.substr(0, 300)
	if network_socket != null and network_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		network_socket.send_text(JSON.stringify({"type": "chat", "text": message}))
	else:
		_append_chat("%s: %s" % [str(current_user.get("username", "Вы")), message])
	if is_instance_valid(chat_input):
		chat_input.clear()

func _append_chat(message: String) -> void:
	chat_messages.append(message)
	if chat_messages.size() > 7:
		chat_messages.pop_front()
	_refresh_chat()

func _refresh_chat() -> void:
	if is_instance_valid(chat_display):
		chat_display.text = "\n".join(chat_messages.slice(maxi(0, chat_messages.size() - 7), chat_messages.size()))

func _connect_room() -> void:
	if auth_token.is_empty():
		return
	var room_id := str(current_place.get("remote_id", current_place.get("id", "lobby")))
	if room_id.is_empty():
		room_id = "lobby"
	network_socket = WebSocketPeer.new()
	var url := API_BASE.replace("https://", "wss://") + "/api/rooms/" + room_id.uri_encode() + "/ws"
	network_socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + auth_token])
	var error_code := network_socket.connect_to_url(url)
	if error_code != OK:
		_append_chat("Чат сервера пока недоступен — используется локальный чат.")

func _poll_network() -> void:
	if network_socket == null:
		return
	network_socket.poll()
	if network_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var tick := Time.get_ticks_msec()
	if is_instance_valid(player_body) and tick - last_network_send_ms >= 100:
		last_network_send_ms = tick
		var position := player_body.global_position
		network_socket.send_text(JSON.stringify({
			"type": "move",
			"position": {"x": position.x, "y": position.y, "z": position.z}
		}))
	while network_socket != null and network_socket.get_ready_state() == WebSocketPeer.STATE_OPEN and network_socket.get_available_packet_count() > 0:
		var packet := network_socket.get_packet().get_string_from_utf8()
		var data: Variant = JSON.parse_string(packet)
		if not data is Dictionary:
			continue
		var kind := str(data.get("type", ""))
		var username := str(data.get("username", "Игрок"))
		var user_id := str(data.get("userId", ""))
		if kind == "connected":
			if not online_players.has(username):
				online_players.append(username)
			for existing_player in data.get("players", []):
				if existing_player is Dictionary:
					_register_remote_player(str(existing_player.get("userId", "")), str(existing_player.get("username", "Игрок")))
		elif kind == "player_joined":
			if not online_players.has(username):
				online_players.append(username)
			_register_remote_player(user_id, username)
		elif kind == "player_left":
			online_players.erase(username)
			_remove_remote_player(user_id)
		elif kind == "move":
			if user_id != str(current_user.get("id", "")):
				_register_remote_player(user_id, username)
				var remote: Node3D = remote_player_nodes.get(user_id)
				var position_data: Dictionary = data.get("position", {})
				if is_instance_valid(remote) and position_data.has("x") and position_data.has("y") and position_data.has("z"):
					remote.position = Vector3(float(position_data.x), float(position_data.y), float(position_data.z))
		elif kind == "chat":
			_append_chat("%s: %s" % [username, str(data.get("text", ""))])
		elif kind == "place_updated":
			_append_chat("Плейс обновлён. Возвращаемся в меню.")
			_leave_game()
			return
		elif kind == "error":
			_append_chat("Сервер: " + str(data.get("error", "ошибка")))

func _register_remote_player(user_id: String, username: String) -> void:
	if user_id.is_empty() or user_id == str(current_user.get("id", "")):
		return
	if remote_player_nodes.has(user_id) and is_instance_valid(remote_player_nodes[user_id]):
		return
	if not is_instance_valid(active_world):
		return
	var avatar := Node3D.new()
	avatar.name = "Remote_" + username
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.22, 0.28)
	mesh.material_override = material
	avatar.add_child(mesh)
	active_world.add_child(avatar)
	remote_player_nodes[user_id] = avatar

func _remove_remote_player(user_id: String) -> void:
	if not remote_player_nodes.has(user_id):
		return
	var avatar: Node3D = remote_player_nodes[user_id]
	if is_instance_valid(avatar):
		avatar.queue_free()
	remote_player_nodes.erase(user_id)

func _try_click_object(mouse_position: Vector2) -> void:
	if active_subviewport == null or active_camera == null or active_subviewport.world_3d == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var mapped := Vector2(mouse_position.x * 1280.0 / viewport_size.x, mouse_position.y * 720.0 / viewport_size.y)
	var origin := active_camera.project_ray_origin(mapped)
	var end := origin + active_camera.project_ray_normal(mapped) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 3
	var hit := active_subviewport.world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Node3D and collider.has_meta("rublocks_id"):
		_execute_rules("При нажатии на объект", collider as Node3D)

func _execute_rules(event_name: String, only_target: Node3D = null) -> void:
	if page != "game":
		return
	var target_id := ""
	if is_instance_valid(only_target):
		target_id = str(only_target.get_meta("rublocks_id", ""))
	for object_data in current_place.get("objects", []):
		var object_id := str(object_data.get("id", ""))
		if not target_id.is_empty() and object_id != target_id:
			continue
		var target: Node3D = game_object_nodes.get(object_id)
		if not is_instance_valid(target):
			continue
		for rule in object_data.get("rules", []):
			if bool(rule.get("enabled", true)) and str(rule.get("event", "")) == event_name:
				runtime_state = RULE_ENGINE.execute(target, player_body, rule, runtime_state)
				if runtime_state.has("message"):
					_append_chat(str(runtime_state.message))
					runtime_state.erase("message")

func _update_touch_rules() -> void:
	if not is_instance_valid(player_body):
		return
	var currently_touching: Dictionary = {}
	for object_data in current_place.get("objects", []):
		var object_id := str(object_data.get("id", ""))
		var target: Node3D = game_object_nodes.get(object_id)
		if not is_instance_valid(target):
			continue
		if player_body.global_position.distance_to(target.global_position) < 1.25:
			currently_touching[object_id] = true
			if not touching_object_ids.has(object_id):
				_execute_rules("При касании игроком", target)
	touching_object_ids = currently_touching

func _show_editor() -> void:
	page = "editor"
	_clear_screen()
	_add_background(Color(0.018, 0.026, 0.05))
	editor_viewport_container = _create_3d_viewport("editor")
	_layout(editor_viewport_container, 0.205, 0.095, 0.775, 0.91, Vector4(4, 0, -4, 0))
	var toolbar := HBoxContainer.new()
	_layout(toolbar, 0.01, 0.012, 0.99, 0.085, Vector4.ZERO)
	add_child(toolbar)
	_label(toolbar, "Редактор плейса", 21, Color(0.4, 0.68, 1.0))
	_button(toolbar, "Куб +", _add_editor_object.bind("Куб"), true)
	_button(toolbar, "Спавн", _set_spawn_point)
	_button(toolbar, "Фон и обложка", _choose_background)
	_button(toolbar, "Сохранить", _save_place)
	_button(toolbar, "Опубликовать / обновить", _publish_place)
	_button(toolbar, "Тест", _show_game)
	_button(toolbar, "Назад", _show_main_menu)
	var left_panel := PanelContainer.new()
	_layout(left_panel, 0.01, 0.10, 0.20, 0.91, Vector4.ZERO)
	add_child(left_panel)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 7)
	left_panel.add_child(left_box)
	_label(left_box, "Панель объектов", 17)
	_button(left_box, "Параметры плейса", _select_place_properties)
	var tabs := HBoxContainer.new()
	left_box.add_child(tabs)
	_button(tabs, "Объекты", func(): _set_editor_tab("objects"))
	_button(tabs, "Правила", func(): _set_editor_tab("rules"), true)
	var object_scroll := ScrollContainer.new()
	object_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(object_scroll)
	objects_list = VBoxContainer.new()
	objects_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_scroll.add_child(objects_list)
	var rule_scroll := ScrollContainer.new()
	rule_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(rule_scroll)
	rules_list = VBoxContainer.new()
	rules_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_scroll.add_child(rules_list)
	var right_panel := PanelContainer.new()
	_layout(right_panel, 0.78, 0.10, 0.99, 0.91, Vector4.ZERO)
	add_child(right_panel)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_scroll)
	properties_box = VBoxContainer.new()
	properties_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	properties_box.add_theme_constant_override("separation", 10)
	right_scroll.add_child(properties_box)
	_refresh_editor_lists()
	_refresh_editor_properties()
	_set_editor_tab("objects")

func _build_editor_world(world: Node3D) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "EditorGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(50.0, 50.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.15, 0.18)
	ground.material_override = material
	ground.position.y = -0.03
	world.add_child(ground)
	var grid := MeshInstance3D.new()
	var grid_mesh := PlaneMesh.new()
	grid_mesh.size = Vector2(50.0, 50.0)
	grid.mesh = grid_mesh
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.17, 0.22, 0.27, 0.35)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid.material_override = grid_mat
	grid.position.y = -0.02
	world.add_child(grid)
	editor_root = world
	editor_camera = active_camera
	editor_objects_root = Node3D.new()
	editor_objects_root.name = "EditorObjects"
	world.add_child(editor_objects_root)
	_render_editor_objects()

func _render_editor_objects() -> void:
	if not is_instance_valid(editor_objects_root):
		return
	for child in editor_objects_root.get_children():
		editor_objects_root.remove_child(child)
		child.queue_free()
	for object_data in current_place.get("objects", []):
		var object := MeshInstance3D.new()
		object.name = str(object_data.get("title", "Куб"))
		object.set_meta("rublocks_id", str(object_data.get("id", "")))
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		object.mesh = mesh
		var pos: Array = object_data.get("position", [0.0, 0.5, 0.0])
		var scale_data: Array = object_data.get("scale", [1.0, 1.0, 1.0])
		object.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		object.scale = Vector3(float(scale_data[0]), float(scale_data[1]), float(scale_data[2]))
		var color_data: Array = object_data.get("color", [0.25, 0.55, 1.0, 1.0])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]), float(color_data[3]) if color_data.size() > 3 else 1.0)
		object.material_override = mat
		editor_objects_root.add_child(object)

func _set_editor_tab(tab: String) -> void:
	editor_tab = tab
	if is_instance_valid(objects_list):
		objects_list.get_parent().visible = tab == "objects"
	if is_instance_valid(rules_list):
		rules_list.get_parent().visible = tab == "rules"
	if is_instance_valid(rules_list):
		_populate_rules_list()

func _refresh_editor_lists() -> void:
	if not is_instance_valid(objects_list):
		return
	_clear_container(objects_list)
	for object_data in current_place.get("objects", []):
		var object_id := str(object_data.get("id", ""))
		var text_value := str(object_data.get("title", "Объект"))
		if object_id == selected_object_id:
			text_value = "● " + text_value
		_button(objects_list, text_value, _select_editor_object.bind(object_id))
	if current_place.get("objects", []).is_empty():
		_label(objects_list, "Пока нет объектов. Нажми «Куб +».", 12, Color(0.61, 0.69, 0.82))
	_populate_rules_list()

func _populate_rules_list() -> void:
	if not is_instance_valid(rules_list):
		return
	_clear_container(rules_list)
	_label(rules_list, "Готовые правила: %d" % RULE_CATALOG.rules_count(), 13, Color(0.55, 0.73, 1.0))
	for rule in RULE_CATALOG.all_rules():
		var button := _button(rules_list, str(rule.get("title", "Правило")), _attach_rule.bind(rule))
		button.custom_minimum_size = Vector2(180, 34)
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = str(rule.get("description", "")) + "\nСобытие: " + str(rule.get("event", "")) + "\nДействие: " + str(rule.get("action", ""))

func _select_editor_object(object_id: String) -> void:
	selected_object_id = object_id
	_refresh_editor_lists()
	_refresh_editor_properties()

func _select_place_properties() -> void:
	selected_object_id = ""
	_refresh_editor_lists()
	_refresh_editor_properties()

func _get_selected_object() -> Dictionary:
	for object_data in current_place.get("objects", []):
		if str(object_data.get("id", "")) == selected_object_id:
			return object_data
	return {}

func _set_selected_position_axis(value: float, object_id: String, axis: int) -> void:
	for object_data in current_place.get("objects", []):
		if str(object_data.get("id", "")) == object_id:
			var position_data: Array = object_data.get("position", [0.0, 0.5, 0.0])
			position_data[axis] = value
			object_data["position"] = position_data
			_render_editor_objects()
			return

func _refresh_editor_properties() -> void:
	if not is_instance_valid(properties_box):
		return
	_clear_container(properties_box)
	var selected := _get_selected_object()
	if selected.is_empty():
		_label(properties_box, "Параметры плейса", 18)
		var title_edit := LineEdit.new()
		title_edit.text = str(current_place.get("title", "Мой плейс"))
		title_edit.placeholder_text = "Название плейса"
		properties_box.add_child(title_edit)
		title_edit.text_submitted.connect(func(value: String) -> void:
			current_place["title"] = value.substr(0, 80)
		)
		var description_edit := TextEdit.new()
		description_edit.custom_minimum_size.y = 72
		description_edit.text = str(current_place.get("description", ""))
		description_edit.placeholder_text = "Описание плейса"
		properties_box.add_child(description_edit)
		_button(properties_box, "Сохранить описание", func(): current_place["description"] = description_edit.text.substr(0, 2000))
		var reset_box := CheckBox.new()
		reset_box.text = "Разрешить игрокам reset"
		reset_box.button_pressed = bool(current_place.get("can_reset", true))
		reset_box.toggled.connect(func(value: bool): current_place["can_reset"] = value)
		properties_box.add_child(reset_box)
		_label(properties_box, "Правил в каталоге: %d" % RULE_CATALOG.rules_count(), 12, Color(0.6, 0.7, 0.84))
		return
	_label(properties_box, "Свойства объекта", 18)
	var title_edit := LineEdit.new()
	title_edit.text = str(selected.get("title", "Куб"))
	title_edit.placeholder_text = "Имя объекта"
	properties_box.add_child(title_edit)
	title_edit.text_submitted.connect(func(value: String) -> void:
		selected["title"] = value.substr(0, 80)
		_refresh_editor_lists()
		_render_editor_objects()
	)
	var color_picker := ColorPickerButton.new()
	var color_data: Array = selected.get("color", [0.25, 0.55, 1.0, 1.0])
	color_picker.color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]), float(color_data[3]) if color_data.size() > 3 else 1.0)
	color_picker.color_changed.connect(func(value: Color) -> void:
		selected["color"] = [value.r, value.g, value.b, value.a]
		_render_editor_objects()
	)
	properties_box.add_child(color_picker)
	_label(properties_box, "Позиция X / Y / Z", 13)
	var pos_data: Array = selected.get("position", [0.0, 0.5, 0.0])
	var object_id_for_position := str(selected.get("id", ""))
	for axis in range(3):
		var axis_row := HBoxContainer.new()
		properties_box.add_child(axis_row)
		_label(axis_row, ["X", "Y", "Z"][axis], 12)
		var axis_spin := SpinBox.new()
		axis_spin.min_value = -50.0
		axis_spin.max_value = 50.0
		axis_spin.step = 0.1
		axis_spin.value = float(pos_data[axis])
		axis_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_spin.value_changed.connect(_set_selected_position_axis.bind(object_id_for_position, axis))
		axis_row.add_child(axis_spin)
	_label(properties_box, "Размер", 13)
	var scale_spin := SpinBox.new()
	scale_spin.min_value = 0.2
	scale_spin.max_value = 10.0
	scale_spin.step = 0.1
	var scale_data: Array = selected.get("scale", [1.0, 1.0, 1.0])
	scale_spin.value = float(scale_data[0])
	scale_spin.value_changed.connect(func(value: float) -> void:
		selected["scale"] = [value, value, value]
		_render_editor_objects()
	)
	properties_box.add_child(scale_spin)
	var collidable := CheckBox.new()
	collidable.text = "Столкновения включены"
	collidable.button_pressed = bool(selected.get("collidable", true))
	collidable.toggled.connect(func(value: bool): selected["collidable"] = value)
	properties_box.add_child(collidable)
	_button(properties_box, "Добавить правило", func(): _set_editor_tab("rules"), true)
	var attached: Array = selected.get("rules", [])
	_label(properties_box, "Правила объекта: %d" % attached.size(), 13, Color(0.6, 0.75, 1.0))
	for rule in attached:
		var row := HBoxContainer.new()
		properties_box.add_child(row)
		_label(row, str(rule.get("event", "")) + " → " + str(rule.get("action", "")), 11)
		_button(row, "×", _remove_rule.bind(str(rule.get("id", ""))))
	_button(properties_box, "Редактировать скрипт", _show_script_editor)
	_button(properties_box, "Удалить объект", _remove_selected_object)

func _attach_rule(rule_data: Dictionary) -> void:
	var selected := _get_selected_object()
	if selected.is_empty():
		_show_message_overlay("Сначала выбери объект во вкладке «Объекты».")
		return
	var rules: Array = selected.get("rules", [])
	for existing in rules:
		if str(existing.get("id", "")) == str(rule_data.get("id", "")):
			return
	rules.append(rule_data.duplicate(true))
	selected["rules"] = rules
	_refresh_editor_properties()

func _remove_rule(rule_id: String) -> void:
	var selected := _get_selected_object()
	var kept: Array = []
	for rule in selected.get("rules", []):
		if str(rule.get("id", "")) != rule_id:
			kept.append(rule)
	selected["rules"] = kept
	_refresh_editor_properties()

func _show_script_editor() -> void:
	var selected := _get_selected_object()
	if selected.is_empty():
		return
	var overlay := Control.new()
	_full_rect(overlay)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.01, 0.88)
	_full_rect(dim)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	_full_rect(center)
	overlay.add_child(center)
	var box := _card(center, 700)
	_label(box, "Скрипт объекта", 22)
	_label(box, "Текст хранится в проекте. Для поведения без кода используй визуальные правила — произвольный код не запускается автоматически.", 12, Color(0.68, 0.75, 0.86))
	var code := TextEdit.new()
	code.custom_minimum_size = Vector2(650, 300)
	code.text = str(selected.get("script", ""))
	code.placeholder_text = "# Здесь можно хранить заметки и заготовки скрипта"
	box.add_child(code)
	_button(box, "Сохранить текст", _save_object_script.bind(selected, code, overlay), true)
	_button(box, "Закрыть", func(): overlay.queue_free())

func _save_object_script(selected: Dictionary, code: TextEdit, overlay: Control) -> void:
	selected["script"] = code.text
	overlay.queue_free()
	_refresh_editor_properties()

func _remove_selected_object() -> void:
	var kept: Array[Dictionary] = []
	for object_data in current_place.get("objects", []):
		if str(object_data.get("id", "")) != selected_object_id:
			kept.append(object_data)
	current_place["objects"] = kept
	selected_object_id = str(kept[0].get("id", "")) if not kept.is_empty() else ""
	_render_editor_objects()
	_refresh_editor_lists()
	_refresh_editor_properties()

func _add_editor_object(kind: String = "Куб") -> void:
	var existing_objects: Array = current_place.get("objects", [])
	var count: int = existing_objects.size() + 1
	var object_id := Crypto.new().generate_random_bytes(16).hex_encode()
	var object_data := {
		"id": object_id,
		"title": "%s %d" % [kind, count],
		"position": [randf_range(-3.0, 3.0), 0.5, randf_range(-3.0, 3.0)],
		"scale": [1.0, 1.0, 1.0],
		"color": [randf_range(0.15, 0.85), randf_range(0.25, 0.85), randf_range(0.45, 1.0), 1.0],
		"collidable": true,
		"rules": [],
		"script": ""
	}
	existing_objects.append(object_data)
	current_place["objects"] = existing_objects
	selected_object_id = object_id
	_render_editor_objects()
	_refresh_editor_lists()
	_refresh_editor_properties()

func _set_spawn_point() -> void:
	var selected := _get_selected_object()
	if not selected.is_empty():
		var pos: Array = selected.get("position", [0.0, 0.5, 0.0])
		var scale_data: Array = selected.get("scale", [1.0, 1.0, 1.0])
		current_place["spawn_position"] = [float(pos[0]), float(pos[1]) + float(scale_data[1]) * 0.5 + 1.0, float(pos[2])]
	else:
		current_place["spawn_position"] = [0.0, 1.0, 0.0]
	_show_message_overlay("Точка спавна установлена.")

func _choose_background() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Выбери изображение фона и обложки"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Изображения"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var image := Image.new()
		if image.load(path) != OK:
			_show_message_overlay("Не удалось открыть это изображение.")
			dialog.queue_free()
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://places"))
		var dest := "user://places/bg_%s.png" % str(current_place.get("id", "place"))
		var save_error := image.save_png(dest)
		if save_error != OK:
			_show_message_overlay("Не удалось сохранить изображение локально.")
		else:
			current_place["background_image"] = dest
			current_place["cover_image"] = dest
			_show_message_overlay("Фон и обложка сохранены локально. Для других пользователей загрузку изображения нужно настроить на сервере.")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(800, 600))

func _show_message_overlay(message: String) -> void:
	var overlay := Control.new()
	_full_rect(overlay)
	add_child(overlay)
	var center := CenterContainer.new()
	_full_rect(center)
	overlay.add_child(center)
	var box := _card(center, 440)
	_label(box, message, 16)
	_button(box, "Закрыть", func(): overlay.queue_free(), true)

func _save_place() -> void:
	if current_place.is_empty():
		return
	if str(current_place.get("id", "")).is_empty():
		current_place["id"] = Crypto.new().generate_random_bytes(16).hex_encode()
	current_place["updated_at"] = int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://places"))
	var id := str(current_place.get("id", ""))
	var project_file := FileAccess.open("user://places/%s.json" % id, FileAccess.WRITE)
	if project_file == null:
		_show_message_overlay("Не удалось создать файл сохранения.")
		return
	project_file.store_string(JSON.stringify(current_place, "\t"))
	project_file.close()
	var ids: Array = []
	var index_file := FileAccess.open("user://places/index.json", FileAccess.READ)
	if index_file:
		var parsed: Variant = JSON.parse_string(index_file.get_as_text())
		index_file.close()
		if parsed is Array:
			ids = parsed
	if not ids.has(id):
		ids.append(id)
	var index_out := FileAccess.open("user://places/index.json", FileAccess.WRITE)
	if index_out:
		index_out.store_string(JSON.stringify(ids))
		index_out.close()
	var found := false
	for index in range(local_places.size()):
		if str(local_places[index].get("id", "")) == id:
			local_places[index] = current_place.duplicate(true)
			found = true
			break
	if not found:
		local_places.append(current_place.duplicate(true))
	_show_message_overlay("Плейс сохранён на этом компьютере.")

func _publish_place() -> void:
	if auth_token.is_empty():
		_show_message_overlay("Чтобы публиковать плейсы, сначала войди или зарегистрируйся.")
		return
	if current_place.is_empty():
		return
	current_place["updated_at"] = int(Time.get_unix_time_from_system())
	var remote_id := str(current_place.get("remote_id", ""))
	var body := {
		"title": str(current_place.get("title", "Без названия")),
		"description": str(current_place.get("description", "")),
		"project": current_place.duplicate(true)
	}
	if remote_id.is_empty():
		var created: Dictionary = await _api_call(HTTPClient.METHOD_POST, "/api/places", body)
		if not bool(created.get("ok", false)):
			var create_error: Dictionary = created.get("data", {})
			_show_message_overlay("Не удалось создать плейс на сервере: " + str(create_error.get("error", "проверь Worker/D1")))
			return
		var create_result_data: Dictionary = created.get("data", {})
		remote_id = str(create_result_data.get("place", {}).get("id", ""))
		current_place["remote_id"] = remote_id
	if remote_id.is_empty():
		_show_message_overlay("Сервер не вернул ID плейса.")
		return
	body["project"] = current_place.duplicate(true)
	body["published"] = true
	var updated: Dictionary = await _api_call(HTTPClient.METHOD_PUT, "/api/places/" + remote_id, body)
	if not bool(updated.get("ok", false)):
		var update_error: Dictionary = updated.get("data", {})
		_show_message_overlay("Не удалось опубликовать/обновить: " + str(update_error.get("error", "ошибка сервера")))
		return
	current_place["published"] = true
	_save_place()
	_show_message_overlay("Плейс опубликован. Сервер отправит уведомление открытым комнатам, но принудительное отключение клиентов ещё нужно реализовать в клиенте.")

func _load_saved_places() -> void:
	local_places.clear()
	local_places.append({
		"id": "starter-world",
		"title": "Стартовый мир",
		"description": "Песочница для теста управления и чата",
		"remote_id": "",
		"published": false,
		"can_reset": true,
		"spawn_position": [0.0, 1.0, 0.0],
		"background_image": "",
		"cover_image": "",
		"objects": [],
		"created_at": int(Time.get_unix_time_from_system()),
		"updated_at": int(Time.get_unix_time_from_system())
	})
	if not FileAccess.file_exists("user://places/index.json"):
		return
	var index_file := FileAccess.open("user://places/index.json", FileAccess.READ)
	if index_file == null:
		return
	var parsed: Variant = JSON.parse_string(index_file.get_as_text())
	index_file.close()
	if not parsed is Array:
		return
	for id_value in parsed:
		var path := "user://places/%s.json" % str(id_value)
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var data: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if data is Dictionary:
			var duplicate_index := -1
			for i in range(local_places.size()):
				if str(local_places[i].get("id", "")) == str(data.get("id", "")):
					duplicate_index = i
					break
			if duplicate_index >= 0:
				local_places[duplicate_index] = data
			else:
				local_places.append(data)

func _refresh_remote_places() -> void:
	var response: Dictionary = await _api_call(HTTPClient.METHOD_GET, "/api/places", {}, false)
	if not bool(response.get("ok", false)):
		return
	var data: Dictionary = response.get("data", {})
	var items: Variant = data.get("places", [])
	if items is Array:
		remote_places.clear()
		for item in items:
			if item is Dictionary:
				remote_places.append(item)
		_populate_menu_places()

func _api_call(method: int, path: String, body: Dictionary = {}, authorized: bool = true) -> Dictionary:
	var request_node := HTTPRequest.new()
	request_node.timeout = 12.0
	add_child(request_node)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if authorized and not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)
	var data := ""
	if method != HTTPClient.METHOD_GET:
		data = JSON.stringify(body)
	var err := request_node.request(API_BASE + path, headers, method, data)
	if err != OK:
		request_node.queue_free()
		return {"ok": false, "status": 0, "data": {"error": "Не удалось начать запрос к серверу."}}
	var completed: Array = await request_node.request_completed
	request_node.queue_free()
	var status_code := int(completed[1])
	var raw := (completed[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw)
	var result_data: Dictionary = parsed if parsed is Dictionary else {"error": raw.substr(0, 300)}
	return {"ok": status_code >= 200 and status_code < 300, "status": status_code, "data": result_data}

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
