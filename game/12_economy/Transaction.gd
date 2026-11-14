class_name Transaction

extends Resource
## Registro inmutable de una transaccion de tienda.

enum TransactionType {
	NONE,
	PURCHASE,
	SELL,
	REFUND,
}

@export var transaction_id: StringName = &""
@export var item_id: StringName = &""
@export var type: TransactionType = TransactionType.NONE
@export var amount: int = 0
@export var wave_number: int = 0
@export var success: bool = false
@export var timestamp: int = 0


## Crea una transaccion.
static func make(p_item_id: StringName, p_type: TransactionType, p_amount: int,
		p_wave: int, p_success: bool) -> Transaction:
	var tx := Transaction.new()
	tx.transaction_id = &"tx_%d" % Time.get_ticks_msec()
	tx.item_id = p_item_id
	tx.type = p_type
	tx.amount = p_amount
	tx.wave_number = p_wave
	tx.success = p_success
	tx.timestamp = Time.get_unix_time_from_system()
	return tx


## Etiqueta del tipo.
func type_label() -> String:
	match type:
		TransactionType.PURCHASE: return "Compra"
		TransactionType.SELL: return "Venta"
		TransactionType.REFUND: return "Reembolso"
	return "—"
