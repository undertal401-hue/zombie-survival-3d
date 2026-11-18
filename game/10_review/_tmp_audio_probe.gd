extends Node

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for _i in range(10):
		await get_tree().process_frame
	var audio: Node = main.get_node_or_null("AudioDirector")
	if audio == null:
		print("AUDIO PROBE FAIL: sin AudioDirector")
		get_tree().quit(1)
		return
	audio.call("set_ambience", "rain")
	for _i in range(20):
		await get_tree().process_frame
	var external: bool = bool(audio.get("_external_ambience").has("rain"))
	var layer: Dictionary = audio.get("_layers").get("rain", {})
	var player: AudioStreamPlayer = layer.get("player", null) as AudioStreamPlayer
	var stream: AudioStream = player.stream if player != null else null
	var looping: bool = false
	if stream is AudioStreamOggVorbis:
		looping = (stream as AudioStreamOggVorbis).loop
	print("AUDIO PROBE external=", external, " stream=", stream.get_class() if stream != null else "none",
		" loop=", looping, " playing=", player.playing if player != null else false,
		" volume_db=", snappedf(player.volume_db, 2) if player != null else 0,
		" PASS=", external and stream is AudioStreamOggVorbis and looping)
	get_tree().quit(0)
