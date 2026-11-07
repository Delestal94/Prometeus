class_name FixedCostsHook
extends Node
## Host: charges the day's fixed costs (FixedCosts, the rent) when the day goes to CLOSING (expansion D-0509.b).
## It follows CompanyNet's day_phase events itself, like SupplierAutoOrderHook, so DayCycle and CompanyRoot do not
## know about it: the 20:00 transition and DayCycle.close_early() are the same event, and closing early does not
## dodge the rent. CLOSING lasts at least one poll, so the charge is in the ledger before DaySummary.build() runs
## and before the save at SUMMARY.
##
## The money moves as one wallet_moved per reason (CompanyNet.publish_wallet), never CompanyState.charge()
## straight, so every peer sees the same balance and history. A cut day leaves nothing behind: the slot is the
## day's opening (D-0251), so playing that day again pays its rent once. Once per day: a CLOSING event can repeat
## (the shed freezing or thawing is a day_phase too). A client's hook does nothing.
##
## CompanyRoot attaches it after the supplier's hook, on purpose: event_applied calls them in that order, and the
## automatic order reads a wallet that has not paid the rent yet (SupplierOrderCart.suggested keeps it apart).


## What FixedCosts.settle() charges on the host: the wallet of the whole crew, through CompanyNet.
class CrewWallet:
	extends RefCounted

	var net: CompanyNet

	func _init(company_net: CompanyNet) -> void:
		net = company_net

	func charge(amount: int, reason: StringName) -> bool:
		return net.publish_wallet(-amount, reason)


var net: CompanyNet = null
## The last day this hook charged.
var _done_day: int = 0


## Hooks a new hook, child of `parent`, to `company_net`'s events. Null without a CompanyNet.
static func attach(parent: Node, company_net: CompanyNet) -> FixedCostsHook:
	if parent == null or company_net == null:
		return null
	var hook := FixedCostsHook.new()
	hook.name = "FixedCostsHook"
	hook.net = company_net
	company_net.event_applied.connect(hook._on_event_applied)
	parent.add_child(hook)
	return hook


func _exit_tree() -> void:
	if net != null and is_instance_valid(net) and net.event_applied.is_connected(_on_event_applied):
		net.event_applied.disconnect(_on_event_applied)


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind != CompanyNet.DAY_PHASE or data.get("phase") != DayCycle.PHASE_NAMES[DayCycle.Phase.CLOSING]:
		return
	var day: int = int(data.get("day", 0))
	if day < 1 or day == _done_day or net == null or not is_instance_valid(net) or not net.is_host():
		return
	_done_day = day
	FixedCosts.settle(CrewWallet.new(net))
