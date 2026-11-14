class_name Currency

extends RefCounted
## Moneda global del juego (saldo y contadores).
##
## Clase estatica: no hay nodo persistente. Emite `currency_changed` para que
## la UI y los sistemas reaccionen. Persiste via SaveSystem.
## Accesible globalmente via `Currency` (class_name).

static var balance: int = 0
static var total_earned: int = 0
static var total_spent: int = 0
static var total_picked: int = 0


## Inicializa el saldo.
## @param starting: saldo inicial (config).
static func reset(starting: int = 100) -> void:
	balance = maxi(starting, 0)
	total_earned = 0
	total_spent = 0
	total_picked = 0
	EventBus.currency_changed.emit(balance, 0)


## Anade saldo.
## @param amount: cantidad (>0).
## @param source: origen ("wave_reward", "pickup", "sell"...).
static func add(amount: int, source: StringName = &"misc") -> void:
	if amount <= 0:
		return
	balance += amount
	total_earned += amount
	if source == &"pickup":
		total_picked += amount
	EventBus.currency_changed.emit(balance, amount)


## Intenta gastar saldo.
## @param amount: coste.
## @param item_id: item comprado (para telemetria).
## @return true si se pudo pagar.
static func try_spend(amount: int, item_id: StringName = &"") -> bool:
	if amount <= 0:
		return true
	if balance < amount:
		EventBus.shop_refused.emit(item_id, &"insufficient_funds")
		return false
	balance -= amount
	total_spent += amount
	EventBus.currency_changed.emit(balance, -amount)
	EventBus.currency_spent.emit(amount, item_id)
	return true


## True si hay saldo suficiente.
static func can_afford(amount: int) -> bool:
	return balance >= amount


## Serializa el saldo.
static func to_dict() -> Dictionary:
	return {
		"balance": balance,
		"total_earned": total_earned,
		"total_spent": total_spent,
		"total_picked": total_picked,
	}


## Restaura el saldo.
static func from_dict(data: Dictionary) -> void:
	balance = int(data.get("balance", 0))
	total_earned = int(data.get("total_earned", 0))
	total_spent = int(data.get("total_spent", 0))
	total_picked = int(data.get("total_picked", 0))
