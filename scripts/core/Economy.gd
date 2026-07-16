extends Node

# Session-scoped Credits balance — the player's money. In-memory only for
# now, same caveat as Discoveries/Research/Deposits (no save system yet).
# Selling cargo (SellCargoPanel, Q hotkey, Cockpit-only) is the first and so
# far only way to earn any; nothing spends Credits yet either — this stays
# deliberately minimal until there's something real to spend on, rather than
# building out a spend_credits() nothing calls.

signal balance_changed(new_balance: int)

# Flat, deliberately unrealistic placeholder rate — every material sells for
# the same 1 credit/unit right now regardless of rarity (Iron and Platinum
# sell identically). Real per-material pricing is a known, deliberate
# follow-up ("we'll sort out prices later"), not an oversight.
const CREDITS_PER_UNIT := 1

var balance: int = 0


func reset_for_new_game() -> void:
	balance = 0
	balance_changed.emit(balance)


func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	balance += amount
	balance_changed.emit(balance)


# Atomic — mirrors Deposits.spend_materials()'s check-then-subtract shape.
# Buildings construction is the first real caller.
func spend_credits(amount: int) -> bool:
	if amount > balance:
		return false
	balance -= amount
	balance_changed.emit(balance)
	return true
