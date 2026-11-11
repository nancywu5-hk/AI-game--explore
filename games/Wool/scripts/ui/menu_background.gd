extends Control

@onready var close_button: Button = $CloseButton

func _ready() -> void:
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)

func _on_close_button_pressed() -> void:
	AudioManager.play_sound(AudioManager.GAME.CLICK)
