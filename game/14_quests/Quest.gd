class_name Quest
extends Resource

## Datos de una misión secundaria dinámica. Es un Resource liviano: el director
## crea una instancia por misión y expone to_dict() para que el HUD pueda
## consumirla sin conocer los internos del sistema.
## Sin impresiones por consola y sin dependencias de escena.

const TYPE_CLEAR_HORDE := "clear_horde"
const TYPE_SCAVENGE := "scavenge"
const TYPE_CRAFT_ITEM := "craft_item"
const TYPE_REACH_CLEARING := "reach_clearing"
const TYPE_REPAIR_VEHICLE := "repair_vehicle"
const TYPE_SURVIVE_NIGHT := "survive_night"

const TYPE_NAMES: Dictionary = {
    TYPE_CLEAR_HORDE: "Defensa",
    TYPE_SCAVENGE: "Recolección",
    TYPE_CRAFT_ITEM: "Artesanía",
    TYPE_REACH_CLEARING: "Exploración",
    TYPE_REPAIR_VEHICLE: "Mecánica",
    TYPE_SURVIVE_NIGHT: "Supervivencia",
}

## Etiquetas propias: se evita el id heredado "combustible" en recompensas.
const ITEM_LABELS: Dictionary = {
    "scrap": "chatarra",
    "cloth": "tela",
    "vehicle_fuel": "depósito de vehículo",
    "medkit": "botiquín",
    "pistol_ammo": "cartuchos",
    "zombie": "zombies",
}

@export var id: String = ""
@export var kind: String = ""
@export var title: String = ""
@export var description: String = ""
@export var objective: String = ""
@export var target_id: String = ""
@export var target_amount: float = 1.0
@export var progress_value: float = 0.0
@export var target_position: Vector2 = Vector2.ZERO
@export var reward: Dictionary = {}
@export var elapsed: float = 0.0
@export var completed: bool = false

## Datos auxiliares no serializables (por ejemplo, referencia al vehículo).
var metadata: Dictionary = {}

## Progreso normalizado 0..1. Un objetivo sin meta devuelve 0.
func ratio() -> float:
    if target_amount <= 0.0:
        return 0.0
    return clampf(progress_value / target_amount, 0.0, 1.0)

## Fija el progreso absoluto. Devuelve true solo si hubo un cambio real.
func set_progress(value: float) -> bool:
    var next: float = clampf(float(value), 0.0, maxf(target_amount, 0.0))
    if is_equal_approx(next, progress_value):
        return false
    progress_value = next
    return true

## Snapshot para HUD/QA. reward se duplica para que nadie mute la recompensa.
func to_dict() -> Dictionary:
    return {
        "id": id,
        "type": kind,
        "kind": kind,
        "title": title,
        "category": label_for_type(kind),
        "description": description,
        "objective": objective,
        "target_id": target_id,
        "target": target_amount,
        "progress": progress_value,
        "ratio": ratio(),
        "position": target_position,
        "reward": reward.duplicate(true),
        "reward_text": reward_text(reward),
        "completed": completed,
    }

static func label_for_type(kind: String) -> String:
    return String(TYPE_NAMES.get(kind, "Misión"))

static func label_for_item(item_id: String) -> String:
    return String(ITEM_LABELS.get(item_id, item_id))

## Texto determinista de recompensa: "3 chatarra, 1 botiquín".
static func reward_text(values: Dictionary) -> String:
    var parts: Array[String] = []
    for item_id in values:
        parts.append("%d %s" % [int(values[item_id]), label_for_item(String(item_id))])
    if parts.is_empty():
        return "sin recompensa"
    return ", ".join(parts)
