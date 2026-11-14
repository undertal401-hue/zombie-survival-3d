class_name Notifications


extends CanvasLayer
## Sistema de notificaciones flotantes (toast).
## Accesible globalmente via `Notifications` (class_name).

const MAX_NOTIFICATIONS: int = 6
const LIFETIME: float = 3.0
const FADE_TIME: float = 0.4

@onready var container: VBoxContainer = %Container

var _queue: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.ui_notification.connect(_on_notification)


func _process(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _queue:
		entry["time"] -= delta
		if entry["time"] <= 0.0:
			_fade_out(entry["label"])
		else:
			keep.append(entry)
	_queue = keep


func _on_notification(text: String, tone: StringName) -> void:
	if _queue.size() >= MAX_NOTIFICATIONS:
		_fade_out(_queue[0]["label"])
		_queue.pop_front()
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", _color_for_tone(tone))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)
	_queue.append({"label": label, "time": LIFETIME})


func _fade_out(label: Label) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.finished.connect(func(): label.queue_free())


func _color_for_tone(tone: StringName) -> Color:
	match tone:
		&"warning": return Color(1.0, 0.6, 0.1)
		&"error": return Color(1.0, 0.3, 0.3)
		&"reward": return Color(0.3, 1.0, 0.5)
	return Color(1.0, 1.0, 1.0)
