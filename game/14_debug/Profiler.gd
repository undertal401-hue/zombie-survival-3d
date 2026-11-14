class_name Profiler


extends Node
## Profiler simple: FPS, frame time, memoria, conteo de objetos.
## Accesible globalmente via `Profiler` (class_name).

signal frame_recorded(fps: float, frame_time: float, memory_mb: float, object_count: int)

var _samples: Array[Dictionary] = []
var _max_samples: int = 300
var _update_interval: float = 0.5
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_timer += delta
	if _timer < _update_interval:
		return
	_timer = 0.0
	_record()


func _record() -> void:
	var fps: float = 1.0 / maxf(get_process_delta_time(), 0.0001)
	var frame_time: float = get_process_delta_time() * 1000.0
	var mem: float = OS.get_static_memory_usage() / 1024.0 / 1024.0
	var obj_count: int = _count_objects()
	_samples.append({
		"fps": fps,
		"frame_time": frame_time,
		"memory": mem,
		"objects": obj_count,
		"time": Time.get_ticks_msec() / 1000.0,
	})
	if _samples.size() > _max_samples:
		_samples.pop_front()
	frame_recorded.emit(fps, frame_time, mem, obj_count)


func _count_objects() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		count += 1
	for node: Node in get_tree().get_nodes_in_group("projectiles"):
		count += 1
	return count


## Obtiene estadisticas resumidas.
func get_stats() -> Dictionary:
	if _samples.is_empty():
		return {}
	var fps_sum: float = 0.0
	var frame_sum: float = 0.0
	var mem_sum: float = 0.0
	for s: Dictionary in _samples:
		fps_sum += s.fps
		frame_sum += s.frame_time
		mem_sum += s.memory
	var min_fps: float = INF
	var max_fps: float = -INF
	for s: Dictionary in _samples:
		min_fps = minf(min_fps, s.fps)
		max_fps = maxf(max_fps, s.fps)
	return {
		"avg_fps": fps_sum / _samples.size(),
		"avg_frame_ms": frame_sum / _samples.size(),
		"avg_mem_mb": mem_sum / _samples.size(),
		"min_fps": min_fps,
		"max_fps": max_fps,
		"sample_count": _samples.size(),
	}


## Exporta CSV para analisis externo.
func export_csv() -> String:
	var lines: Array[String] = ["time,fps,frame_ms,memory_mb,objects"]
	for s: Dictionary in _samples:
		lines.append("%.3f,%.1f,%.2f,%.1f,%d" % [s.time, s.fps, s.frame_time, s.memory, s.objects])
	return "\n".join(lines)
