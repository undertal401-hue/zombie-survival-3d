extends CanvasLayer
## CAPA 3 / ÍTEM 15 — menú principal.
## Escena ligera: no crea mundo, no toca el estado salvo a través de Main.
## Expone start_pressed / continue_pressed y los atajos start_game / continue_game.

signal start_pressed
signal continue_pressed

@onready var new_game_button: Button = $Root/Panel/VBox/NewGameButton
@onready var continue_button: Button = $Root/Panel/VBox/ContinueButton
@onready var quit_button: Button = $Root/Panel/VBox/QuitButton


func _ready() -> void:
	layer = 20
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	show_menu()


## "Continuar" solo existe cuando hay progreso guardado (partidas previas).
func _detect_save() -> bool:
	var parent_node: Node = get_parent()
	var meta: Node = null
	if parent_node != null:
		meta = parent_node.get_node_or_null("MetaProgress")
	if meta != null and meta.has_method("get_progress"):
		var data: Variant = meta.call("get_progress")
		if data is Dictionary and int((data as Dictionary).get("runs", 0)) > 0:
			return true
	return FileAccess.file_exists("user://meta_progress.json")


func show_menu() -> void:
	visible = true
	var has_save: bool = _detect_save()
	continue_button.visible = has_save
	new_game_button.grab_focus()


func hide_menu() -> void:
	visible = false


func _on_new_game_pressed() -> void:
	start_pressed.emit()
	start_game()


func _on_continue_pressed() -> void:
	continue_pressed.emit()
	continue_game()


## API pública para Main y para sondeos por introspección.
func start_game() -> void:
	hide_menu()


func continue_game() -> void:
	hide_menu()


func _on_quit_pressed() -> void:
	get_tree().quit(0)
