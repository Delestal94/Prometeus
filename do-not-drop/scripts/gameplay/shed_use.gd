class_name ShedUse
extends RefCounted
## Host: what a crew member's use of a piece of the shed asks CompanyNet for (out of company_root.gd in D-0254).
##
## The shed (CompanyShed) only says who used what: piece_used for a placed piece, jack_used for the pallet jack.
## Here that becomes a request made on the user's behalf (CompanyNet.request_for(), or PalletJackUse), so the
## host's own checks (reach, hands, stock, the truck, the floor) decide in CompanyNet, same as for any request,
## and every peer sees the result as the event it leads to. Nothing here runs on a client. A piece whose use is
## new (a packing table, a pallet) adds its branch here, not in CompanyRoot.
##
## CompanyRoot holds one (CompanyRoot.shed_use, attach()); the picking carts have their own (PickingCartGrip).

var _net: CompanyNet
var _shed: CompanyShed
## The slot each crew member last picked from, by "<peer>/<shelf uid>" (ShelfPicking, D-0609).
var _pick_after: Dictionary = {}


## The use of `shed`'s pieces and of its pallet jack, asked of `net`. The caller keeps what this returns:
## the shed's signals don't.
static func attach(net: CompanyNet, shed: CompanyShed) -> ShedUse:
	var use := ShedUse.new()
	use._net = net
	use._shed = shed
	shed.piece_used.connect(use._on_piece_used)
	shed.jack_used.connect(use._on_jack_used)
	return use


## Host: a crew member used a piece of the shed. A shelf puts the units of one of its slots in their
## hands (D-0609): the slot rotates over the filled ones while the hands are empty (_pick_after), and
## the host's own checks (reach, hands, stock) decide in CompanyNet, same as for any units request.
func _on_piece_used(uid: StringName, role: StringName, peer_id: int) -> void:
	if role != &"storage" or _net == null or not _net.is_host():
		return
	var key: String = "%d/%s" % [peer_id, uid]
	var plan: Dictionary = ShelfPicking.plan(uid, _shed.shelves.get(uid) as Shelf, _net.inventory,
		CompanyNet.hands_location(peer_id), int(_pick_after.get(key, -1)))
	if plan.has("reason"):
		return
	var hands: StringName = CompanyNet.hands_location(peer_id)
	var before: int = _net.inventory.count(plan["product"], hands)
	_net.request_for(peer_id, CompanyUnitsNet.TAKE,
		{"station": plan["station"], "product": plan["product"], "qty": plan["qty"]})
	if _net.inventory.count(plan["product"], hands) > before:
		_pick_after[key] = plan["slot"]


## Host: a crew member worked the pallet jack (D-0605.b): pick a pallet up or put it down, or push the jack.
## PalletJackUse asks the host's own CompanyNet on their behalf, which checks reach, the truck and the floor.
func _on_jack_used(action: StringName, peer_id: int, from: Vector3) -> void:
	if _net == null or not _net.is_host():
		return
	PalletJackUse.use(_net, _shed.yard, action, peer_id, from)
