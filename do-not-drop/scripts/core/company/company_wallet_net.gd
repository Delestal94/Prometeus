class_name CompanyWalletNet
extends RefCounted
## The company's wallet over the network (expansion D-0517): a movement of money that no shed request led to
## reaches every peer as one host event, wallet_moved, so the whole crew sees the same balance and the same
## history (CompanyState.money and its ledger). It lives in CompanyNet as CompanyNet.wallet; nothing here
## sends anything or names an autoload.
##
## The host's way in is CompanyNet.publish_wallet(amount, reason): the payment at the door (OrderSettlement),
## a tip (OrderTips), the rent (FixedCosts), the supplier's bill (SupplierPurchase), the shop (CompanyShop),
## an expansion (WarehouseStages) and an undo (BuildPlacement) take it once they are wired to the shared
## world, never CompanyState.earn() / spend() / charge() straight: those move only the host's wallet, and every
## client would hold an older balance until its next snapshot. What the host checks first (does the order
## pay, can the wallet afford a purchase: CompanyState.can_afford()) is the caller's; the event only moves
## the money, and a charge may leave the wallet in the red. Building and selling pieces and the packing
## tables' supplies already carry their money in their own events (CompanyLayoutNet, CompanyTableNet).
##
## Event (CompanyNet.WALLET, only the host publishes it; no request leads to it):
##   wallet_moved  {amount: signed int, never 0, at most MAX_MONEY either way; reason: the ledger's reason,
##                  a short lowercase id (reason_ok()); money: the host's balance after it, may be negative;
##                  minute: the host's CompanyState.clock_minutes}
## As the layout's and the tables' events, the wallet travels absolute: every peer, the host too, starts
## the movement from the host's balance before it (money - amount), so the wallet and the entry's balance
## end as the host's, and the entry takes `minute` (a client's clock_minutes is never written: only the
## host's clock writes it). A positive amount is one earn(), a negative one one charge(). The host builds
## the event from its own balance (moved()), so it applies it once and its "before" is its own wallet: no
## second charge. A copy whose balance was off is set right and remembers it (take_drift()): CompanyNet then
## asks for a snapshot for the history it missed.
##
## Shared with CompanyLayoutNet and CompanyTableNet: set_balance() and entry_minute(), the absolute wallet's
## two steps.

## A wallet movement of the host's (D-0517), CompanyNet.WALLET.
const MOVED: StringName = &"wallet_moved"
## Largest balance or movement, either sign, an event may carry: no overflow adding one to the other.
const MAX_MONEY: int = 1_000_000_000_000
## Longest reason a wallet event may carry (the ledger's are under 20: order_paid, warehouse_expand).
const MAX_REASON_LENGTH: int = 32

## True since an applied event found this copy's wallet off the host's (take_drift()).
var _drifted: bool = false


## Host: the wallet_moved that moves `state`'s wallet (CompanyState-shaped: money, clock_minutes) by `amount`
## for `reason`, with the balance after it and the host's minute; {} when `amount` is 0 or over MAX_MONEY,
## the reason is not a short id (reason_ok()), the balance would leave the range or there is no company.
func moved(state: Object, amount: int, reason: StringName) -> Dictionary:
	if state == null or not is_instance_valid(state) or amount == 0 or absi(amount) > MAX_MONEY:
		return {}
	if not reason_ok(reason):
		return {}
	var before: Variant = state.get(&"money")
	var minute: Variant = state.get(&"clock_minutes")
	if not (money_ok(before) and money_ok(int(before) + amount) and minute_ok(minute)):
		return {}
	return {"amount": amount, "reason": reason, "money": int(before) + amount, "minute": int(minute)}


## Every peer, the host too (CompanyNet._apply_state()): one wallet_moved in place, the same calls on every
## peer. Checked only as data (rule 6): ints in range (a float, a missing field or one out of range is
## refused), a reason that is a short id, a company with earn() and charge(). False, changing nothing, when
## it doesn't fit; every check comes before the first change.
func apply(state: Object, data: Dictionary) -> bool:
	if state == null or not is_instance_valid(state):
		push_warning("CompanyWalletNet: a %s event but no company here" % MOVED)
		return false
	if not (state.has_method(&"earn") and state.has_method(&"charge")):
		return false
	var amount: Variant = data.get("amount")
	var money: Variant = data.get("money")
	var reason: Variant = data.get("reason")
	if typeof(amount) != TYPE_INT or int(amount) == 0 or absi(int(amount)) > MAX_MONEY:
		return false
	if not (money_ok(money) and money_ok(int(money) - int(amount)) and reason_ok(reason)):
		return false
	if not minute_ok(data.get("minute")):
		return false
	_drifted = set_balance(state, int(money) - int(amount), "CompanyWalletNet") or _drifted
	if int(amount) > 0:
		state.earn(int(amount), StringName(reason))
	else:
		state.charge(-int(amount), StringName(reason))
	entry_minute(state, int(data["minute"]))
	return true


## True once, then false: an event applied since the last call found this copy's wallet off the host's
## balance (and set it right). The rest of what it missed (wallet history) needs a snapshot.
func take_drift() -> bool:
	var drifted: bool = _drifted
	_drifted = false
	return drifted


## The host's balance `before` an event's movement, on `state`: a copy that holds another missed something;
## it takes the host's (so the movement ends on the host's balance) with a warning naming `who`, and true is
## returned (the caller remembers the drift for its take_drift()). False when it already held it.
static func set_balance(state: Object, before: int, who: String) -> bool:
	var here: int = int(state.get(&"money"))
	if here == before:
		return false
	push_warning("%s: this wallet held %d, the host's %d; set to the host's" % [who, here, before])
	state.set(&"money", before)
	return true


## The wallet entry the event just wrote takes the host's `minute`; clock_minutes stays as it is.
static func entry_minute(state: Object, minute: int) -> void:
	var ledger: Array = state.get(&"ledger")
	if not ledger.is_empty():
		ledger[ledger.size() - 1]["minute"] = minute


## A ledger reason that came over the network: text (String or StringName) of 1 to MAX_REASON_LENGTH
## characters, lowercase letters, digits and "_", not starting with a digit (order_paid, rent, tip).
static func reason_ok(value: Variant) -> bool:
	if not CompanyAsk.is_id(value):
		return false
	var text: String = String(value)
	return text.length() <= MAX_REASON_LENGTH and text.is_valid_ascii_identifier() and text == text.to_lower()


## A balance from the host: an int from `minimum` up to MAX_MONEY (a float or anything else is not).
static func money_ok(value: Variant, minimum: int = -MAX_MONEY) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= MAX_MONEY


## A minute of the host's day: an int in 0..MINUTES_PER_DAY - 1.
static func minute_ok(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) < CompanyTuning.MINUTES_PER_DAY
