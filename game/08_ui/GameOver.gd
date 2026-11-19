extends CanvasLayer
## CAPA 3 / ÍTEM 15 — pantalla de fin dedicada (victoria / derrota).
## Se superpone al EndOverlay del HUD: se conserva el overlay histórico que
## comprueban los arneses de Capas 0-2. No pausa ni recarga por su cuenta.

signal retry_pressed
signal return_to_menu_pressed

@onready var title_label: Label = $Root/Panel/VBox/TitleLabel
@onready var stats_label: Label = $Root/Panel/VBox/StatsLabel
@onready var retry_button: Button = $Root/Panel/VBox/RetryButton
@onready var menu_button: Button = $Root/Panel/VBox/MenuButton


func _ready() -> void:
	layer = 30
	visible = false
	retry_button.pressed.connect(_on_retry_pressed)
	menu_button.pressed.connect(_on_return_to_menu_pressed)


## API pública. Main muestra esta pantalla al recibir game_over / victory.
func show_result(victory: bool, wave: int, kills: int, seconds: float) -> void:
	var total: int = maxi(0, int(seconds))
	title_label.text = "¡EXTRACCIÓN LOGARDA!" if victory else "HAS CAÍDO"
	title_label.add_theme_color_override(
		"font_color", Color(0.663, 0.749, 0.369, 1) if victory else Color(0.910, 0.337, 0.235, 1))
	stats_label.text = "OLEADAS   %d\nBAJAS   %d\nTIEMPO   %02d:%02d" % [
		maxi(0, wave), maxi(0, kills), (total / 60) % 100, total % 60
	]
	visible = true
	retry_button.grab_focus()


func hide_result() -> void:
	visible = false


## Atajos públicos (útiles para Main y para sondeos por introspección).
func retry() -> void:
	retry_pressed.emit()


func return_to_menu() -> void:
	return_to_menu_pressed.emit()


func restart() -> void:
	retry_pressed.emit()


func _on_retry_pressed() -> void:
	retry_pressed.emit()


func _on_return_to_menu_pressed() -> void:
	return_to_menu_pressed.emit()
