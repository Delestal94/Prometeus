class_name OrderBoxLink
extends RefCounted
## Ties an order to the box that holds it (expansion D-0808, "Modo Empresa"): "the sheet goes
## with the box".
##
## Static and stateless; the link itself lives in the OrderBook (the order's box_id, state
## PACKED), so host, clients and a save agree without a second table. A box can be linked once
## the sheet's order is on its label (PackagingSupplies.label) and it is taped shut. What the
## box holds is not checked here: a wrong box is linked and pays 0 at the door (D-0712,
## BoxContentCheck), as in the hand-made flow.

const OK: StringName = &""
const ERR_UNKNOWN_ORDER: StringName = &"unknown_order"
const ERR_NOT_WAITING: StringName = &"order_not_waiting"
const ERR_NOT_TAPED: StringName = &"box_not_taped"
const ERR_LABEL_MISMATCH: StringName = &"label_mismatch"
const ERR_BOX_TAKEN: StringName = &"box_taken"


## Why the box cannot be linked to the order right now; OK when it can.
static func check(book: OrderBook, order_id: StringName, box_id: StringName, box: PackedBox) -> StringName:
	if book == null or not book.has(order_id):
		return ERR_UNKNOWN_ORDER
	var state: StringName = book.state_of(order_id)
	if state != Order.STATE_OPEN and state != Order.STATE_LATE:
		return ERR_NOT_WAITING
	if box == null or box_id == &"" or not box.taped:
		return ERR_NOT_TAPED
	if box.label_order_id != order_id:
		return ERR_LABEL_MISMATCH
	if order_of_box(book, box_id) != &"":
		return ERR_BOX_TAKEN
	return OK


## Links the box to the order (the order becomes PACKED). Returns OK or the reason it did not.
static func assign(book: OrderBook, order_id: StringName, box_id: StringName, box: PackedBox) -> StringName:
	var why: StringName = check(book, order_id, box_id, box)
	if why != OK:
		return why
	book.mark_packed(order_id, box_id)
	return OK


## The order whose box is box_id (an order still packed, not yet out); &"" when none.
static func order_of_box(book: OrderBook, box_id: StringName) -> StringName:
	if book == null or box_id == &"":
		return &""
	for order: Dictionary in book.open_orders():
		if order["state"] == Order.STATE_PACKED and book.box_of(order["id"]) == box_id:
			return order["id"]
	return &""


## Unlinks a packed order from its box (the box was opened or scrapped); false if it was not linked.
static func release(book: OrderBook, order_id: StringName) -> bool:
	return book != null and book.unpack(order_id)
