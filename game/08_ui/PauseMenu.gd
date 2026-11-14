class_name PauseMenu


extends Control
## Menu de pausa: continuar, ajustes, salir.
## Accesible globalmente via `PauseMenu` (class_name).

signal resume_requested
signal quit_requested

@onready var resume_btn: Button = %ResumeBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var quit_btn: Button = %QuitBtn
@onready var settings_panel: Panel = %SettingsPanel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var back_btn: Button = %BackBtn


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(_on_resume)
	quit_btn.pressed.connect(_on_quit)
	settings_btn.pressed.connect(_show_settings)
	back_btn.pressed.connect(_hide_settings)
	volume_slider.value_changed.connect(_on_master_volume)
	sfx_slider.value_changed.connect(_on_sfx_volume)
	music_slider.value_changed.connect(_on_music_volume)
	EventBus.pause_requested.connect(_show)
	EventBus.resume_requested.connect(_hide)
	_load_settings()


func _show() -> void:
	visible = true
	get_tree().paused = true


func _hide() -> void:
	visible = false
	get_tree().paused = false


func _on_resume() -> void:
	EventBus.resume_requested.emit()


func _on_quit() -> void:
	EventBus.resume_requested.emit()
	quit_requested.emit()


func _show_settings() -> void:
	settings_panel.visible = true
	resume_btn.visible = false
	settings_btn.visible = false
	quit_btn.visible = false


func _hide_settings() -> void:
	settings_panel.visible = false
	resume_btn.visible = true
	settings_btn.visible = true
	quit_btn.visible = true


func _on_master_volume(value: float) -> void:
	AudioManager.set_master_volume_db(value)


func _on_sfx_volume(value: float) -> void:
	AudioManager.set_sfx_volume_db(value)


func _on_music_volume(value: float) -> void:
	AudioManager.set_music_volume_db(value)


func _load_settings() -> void:
	volume_slider.value = AudioManager.get_master_volume_db()
	sfx_slider.value = AudioManager.get_sfx_volume_db()
	music_slider.value = AudioManager.get_music_volume_db()
