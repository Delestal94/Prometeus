class_name OrderNoticeFeed
extends Node
## Listens to an OrderBook and turns the orders that arrive in the same frame into one phone
## notice (expansion D-0814). It only emits `notice`; the HUD shows it as a toast
## (HudNotices.toast(text, priority)), the same on the host and on a client mirror.

signal notice(text: String, priority: int)

var _book: OrderBook
var _pending: Array[StringName] = []
var _flush_queued: bool = false


## Follows a book; a second call moves the feed to the new book.
func watch(book: OrderBook) -> void:
	if _book != null and _book.order_added.is_connected(_on_order_added):
		_book.order_added.disconnect(_on_order_added)
	_book = book
	_pending.clear()
	if _book != null:
		_book.order_added.connect(_on_order_added)


func _on_order_added(id: StringName) -> void:
	_pending.append(id)
	if not _flush_queued:
		_flush_queued = true
		flush.call_deferred()


## Emits one notice for everything pending. Public so a test can run it without a frame.
func flush() -> void:
	_flush_queued = false
	if _book == null:
		_pending.clear()
		return
	var orders: Array[Dictionary] = []
	for id: StringName in _pending:
		if _book.has(id):
			orders.append(_book.get_order(id))
	_pending.clear()
	var message: Dictionary = OrderNotice.message(orders)
	if not message.is_empty():
		notice.emit(message["text"], message["priority"])
