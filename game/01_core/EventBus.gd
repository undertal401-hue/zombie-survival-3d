extends Node

signal player_damaged(amount: float, source: Node)
signal player_health_changed(hp: float, max_hp: float)
signal player_stamina_changed(stamina: float, max_stamina: float)
signal zombie_died(zombie: Node2D)
signal wave_started(wave: int)
signal interaction_prompt(text: String)
signal interaction_cleared
signal notification(text: String)
signal victory
signal game_over
