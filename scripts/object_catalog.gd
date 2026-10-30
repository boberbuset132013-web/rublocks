extends RefCounted
class_name ObjectCatalog

static func is_pickupable(kind: String) -> bool:
	return kind in ["Кирка", "Топор", "Молот", "Меч"]

static func default_color(kind: String) -> Array:
	match kind:
		"Шар": return [0.2, 0.72, 0.92, 1.0]
		"Цилиндр": return [0.55, 0.65, 0.78, 1.0]
		"Конус": return [0.92, 0.48, 0.12, 1.0]
		"Плоскость", "Платформа": return [0.24, 0.48, 0.32, 1.0]
		"Кирка", "Топор", "Молот", "Меч": return [0.72, 0.74, 0.8, 1.0]
		"Руда": return [0.12, 0.78, 0.92, 1.0]
		"Дерево": return [0.25, 0.48, 0.2, 1.0]
		"Дверь": return [0.48, 0.24, 0.12, 1.0]
		"Кнопка": return [0.88, 0.12, 0.18, 1.0]
		"Лампа": return [1.0, 0.84, 0.22, 1.0]
	return [0.25, 0.55, 1.0, 1.0]

static func make_mesh(kind: String) -> Mesh:
	match kind:
		"Шар", "Руда", "Лампа":
			return SphereMesh.new()
		"Цилиндр", "Спавн", "Кнопка":
			return CylinderMesh.new()
		"Капсула":
			return CapsuleMesh.new()
		"Конус":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			return cone
		"Плоскость":
			return PlaneMesh.new()
		"Клин":
			return PrismMesh.new()
		"Кирка", "Топор", "Молот", "Меч", "Дерево":
			var narrow := BoxMesh.new()
			narrow.size = Vector3(0.35, 1.2, 0.35)
			return narrow
		"Ступенька":
			var step := BoxMesh.new()
			step.size = Vector3(1.0, 0.35, 1.0)
			return step
		"Ящик", "Дверь", "Платформа":
			return BoxMesh.new()
		_:
			return BoxMesh.new()
