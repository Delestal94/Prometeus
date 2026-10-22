class_name CompanyShopNet
extends RefCounted
## The company's shop over the network (expansion D-0518, which merges D-0428): buying an item of data/shop/
## (CompanyShop, D-0511) is a CompanyNet request only the host's own gets through and an event every peer
## applies the same way (contract docs/expansion-distritos/diseno/red-autoridad.md, rules 1, 3, 5 and 6, row 25
## and section 13).
##
## CompanyNet hands it the shop requests (check(), host only) and the purchase events (apply(), every peer); it
## lives there as CompanyNet.shop. What a purchase changes (money, ledger, equipment, fleet, warehouse_stage) is
## the company's (CompanyState), which the snapshot already carries in its `company` part, so a late joiner gets
## it with no snapshot part of its own. Nothing here sends anything or names an autoload, and the only node it
## reads is the CompanyNet that asks (ask()).
##
##   shop_buy  {item: an item id of data/shop/, rid}  ->  shop_bought {item, money, minute}
##
## Decision (D-0518): only the host spends. A client may ask and hears host_only, before anything else is looked
## at, so a shop screen can tell it why nothing happened; the crew's vote is D-0518.b (it would come in where
## check() takes `by_host`, as D-0910.1 for building). The host checks with CompanyShop.check() and refuses with
## its key (WORLD_SHOP_ALREADY_OWNED, WORLD_SHOP_NEEDS_ITEM, WORLD_SHOP_WRONG_STAGE, WORLD_SHOP_CANNOT_AFFORD),
## a translation key the shop screen shows as is. An item that is not text or not an enabled item of the
## catalog is bad_data (rule 5). Neither the day's phase nor the frozen shed gate it, as for building (D-0910):
## the shop is the day's close screen (D-0511.2).
##
## The wallet travels absolute, as in CompanyLayoutNet: `money` is the host's balance after the purchase and
## `minute` the host's CompanyState.clock_minutes. Every peer starts the purchase from the host's balance before
## it (money + price) and buys with the same CompanyShop.buy(), so the wallet and the entry's balance (reason
## `shop`) end as the host's; the entry takes `minute` (a client's clock_minutes is never written: only the
## host's clock writes it). A copy whose balance was off is set right and remembers it (take_drift()):
## CompanyNet then asks for a snapshot for the rest of the history.
## Refusals: host_only, bad_data and CompanyShop's keys (above; WORLD_SHOP_NO_COMPANY without a company).

const BUY: StringName = &"shop_buy"
const BOUGHT: StringName = &"shop_bought"
const REQUEST_KINDS: Array[StringName] = [BUY]
const EVENT_KINDS: Array[StringName] = [BOUGHT]

## The requester is not the host: only the host spends (D-0518; the crew's vote is D-0518.b).
const REASON_HOST_ONLY: StringName = &"host_only"
const REASON_BAD_DATA: StringName = &"bad_data"
## A shop_bought carries exactly these.
const EVENT_KEYS: Array[String] = ["item", "money", "minute"]
## Largest balance a shop_bought may carry (no overflow adding a price back).
const MAX_MONEY: int = CompanyLayoutNet.MAX_MONEY

## The shop's catalog on this peer (CompanyShop.items()): every peer reads the same one. Tests point it
## at their own.
var dir: String = CompanyShop.SHOP_DIR

## True since an applied event found this copy's wallet off the host's (take_drift()).
var _drifted: bool = false


## Host: a shop_buy, as {reason} when it is refused or {reason: &"", kind, data} with the one event it leads
## to. `by_host` is whether the host itself asked (CompanyNet knows the sender, rule 3); `state` is the
## CompanyState-shaped company. Nothing changes here: the event does it (apply()).
func check(state: Object, data: Dictionary, by_host: bool) -> Dictionary:
	if not by_host:
		return {"reason": REASON_HOST_ONLY}
	var item: ShopItem = find(data.get("item"))
	if item == null or not is_instance_valid(state):
		return {"reason": REASON_BAD_DATA}
	var verdict: Dictionary = CompanyShop.check(state, item)
	if not bool(verdict["ok"]):
		return {"reason": StringName(verdict["key"])}
	var after: int = int(state.get(&"money")) - item.price
	return {
		"reason": &"", "kind": BOUGHT,
		"data": {"item": item.id, "money": after, "minute": int(state.get(&"clock_minutes"))},
	}


## Host: check() with what CompanyNet `net` holds: its `company`, and whether `peer` (RpcGuard.sender(), or the
## host itself in CompanyNet.request()) is the host.
func ask(net: Node, peer: int, data: Dictionary) -> Dictionary:
	return check(net.get(&"company"), data, peer == net.multiplayer.get_unique_id())


## Every peer, the host too (CompanyNet._apply_state()): a shop_bought in place with the same
## CompanyShop.buy() on every peer. Checked only as data (rule 6): exactly EVENT_KEYS, an enabled item of this
## peer's catalog, the host's balance after it (0..MAX_MONEY) and minute (an int of the day), and an item this
## copy can take (not owned yet, with what it requires and the stage before it; the wallet is the host's).
## False, changing nothing, when it doesn't fit: every check comes before the first change.
func apply(state: Object, data: Dictionary) -> bool:
	if not is_instance_valid(state):
		push_warning("CompanyShopNet: a %s event but no company here" % BOUGHT)
		return false
	if data.size() != EVENT_KEYS.size():
		return false
	var item: ShopItem = find(data.get("item"))
	var money: Variant = data.get("money")
	var minute: Variant = data.get("minute")
	if item == null or typeof(money) != TYPE_INT or typeof(minute) != TYPE_INT:
		return false
	if int(money) < 0 or int(money) > MAX_MONEY or int(minute) < 0 or int(minute) >= CompanyTuning.MINUTES_PER_DAY:
		return false
	var verdict: Dictionary = CompanyShop.check(state, item)
	# Only the wallet may be off here: set right next, from the host's balance.
	if not bool(verdict["ok"]) and verdict["key"] != CompanyShop.CANNOT_AFFORD:
		return false
	_set_balance(state, int(money) + item.price)
	if not bool(CompanyShop.buy(state, item)["ok"]):
		return false
	var ledger: Array = state.get(&"ledger")
	if not ledger.is_empty():
		ledger[ledger.size() - 1]["minute"] = int(minute)
	return true


## The enabled item of this peer's catalog (`dir`) whose id is `id`, or null when `id` is not short text or
## names none. The id is only compared with each item's: never a path.
func find(id: Variant) -> ShopItem:
	if not CompanyAsk.is_id(id) or String(id).is_empty() or String(id).length() > RpcGuard.MAX_TEXT_LENGTH:
		return null
	return CompanyShop.find(StringName(id), dir)


## True once, then false: an event applied since the last call found this copy's wallet off the host's
## balance (and set it right). The rest of what it missed (wallet history) needs a snapshot.
func take_drift() -> bool:
	var drifted: bool = _drifted
	_drifted = false
	return drifted


## The host's balance before the purchase: a copy that holds another missed something; it takes the host's
## (so the purchase ends on the host's balance) and remembers it (take_drift()).
func _set_balance(state: Object, before: int) -> void:
	var here: int = int(state.get(&"money"))
	if here == before:
		return
	push_warning("CompanyShopNet: this wallet held %d, the host's %d; set to the host's" % [here, before])
	state.set(&"money", before)
	_drifted = true
