class_name SupplierBillHook
extends Node
## Host: charges the supplier's bill of a pallet in the moment its units enter the stock (expansion D-0503.b):
## the first put-down of a pallet of the truck's bed, on the floor with the jack or on a rack with the forklift.
## It follows CompanyNet's jack_placed events itself, like FixedCostsHook and SupplierAutoOrderHook, so CompanyNet
## and CompanyRoot do not know about it; CompanySupplierLink attaches it on the host.
##
## Which put-down receives a pallet is the pallet book's to say (PalletJack.take_received(): once per pallet, its
## place's `received`), so moving a pallet again bills nothing, and neither do the shed's first pallets (never on
## a bed: DefaultShed, the gift of a new company) nor what the truck took back (never put down: D-0618). The
## price is the pallet's units at the price of the supplier whose truck brought it (SupplierIds.pallet_supplier,
## SupplierPurchase.bill): what the order screen showed when it was placed.
##
## The money moves as one wallet_moved, reason `supplier` (CompanyNet.publish_wallet), never CompanyState.charge()
## straight, so every peer sees the same balance and history and the day's summary shows it. It goes through into
## the red: the goods are already in the shed (D-0510 says what the red means). The book's `received` and the
## wallet are saved together (the closed day) or not at all (a day cut short goes back to its opening, D-0251),
## so a loaded company never pays a pallet twice nor keeps one for free. A client's hook does nothing.

var net: CompanyNet = null


## Hooks a new hook, child of `parent`, to `company_net`'s events. Null without a CompanyNet.
static func attach(parent: Node, company_net: CompanyNet) -> SupplierBillHook:
	if parent == null or company_net == null:
		return null
	var hook := SupplierBillHook.new()
	hook.name = "SupplierBillHook"
	hook.net = company_net
	company_net.event_applied.connect(hook._on_event_applied)
	parent.add_child(hook)
	return hook


func _exit_tree() -> void:
	if net != null and is_instance_valid(net) and net.event_applied.is_connected(_on_event_applied):
		net.event_applied.disconnect(_on_event_applied)


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind != CompanyPallets.PLACED or net == null or not is_instance_valid(net):
		return
	# Taken before any check, so the book's note never outlives the event that set it; only the host bills.
	var received: StringName = net.pallets.book.take_received()
	if received == &"" or String(received) != String(data.get("pallet", "")) or not net.is_host():
		return
	if bill(received) <= 0:
		push_warning("SupplierBillHook: the pallet %s was received but not billed" % received)


## Host: charges the pallet `id` of the book to the crew's wallet. Returns what was charged (0: not the host, a
## pallet the book does not hold, a product the catalog does not know, or the event was refused).
func bill(id: StringName) -> int:
	if net == null or not is_instance_valid(net) or not net.is_host() or not net.pallets.book.places.has(id):
		return 0
	var pallet: Dictionary = net.pallets.book.places[id]["pallet"]
	var seller: SupplierDefinition = net.supplier.seller(SupplierIds.pallet_supplier(id))
	return SupplierPurchase.bill(FixedCostsHook.CrewWallet.new(net), pallet, net.supplier.products, seller)
