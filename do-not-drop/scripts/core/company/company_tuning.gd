class_name CompanyTuning
extends RefCounted
## Every number of the company mode ("Modo Empresa", expansion D-0202).
##
## Values from docs/expansion-distritos/detalle/supuestos.md (the vertical-slice
## assumptions that D-0117 will tune). Only constants live here: no node, no
## autoload, no UI class (lesson N-919), so any script can name it, also in a
## --script run. The scripts that used to hold a copy (Order, Pallet,
## ProductDefinition) now read it from here; a number that changes is changed
## once, here, or in a .tres of data/ when it belongs to one product.
## Times are game minutes since midnight unless the name says REAL.

# --- Company at the start ---
const STARTING_MONEY: int = 500
const STARTING_DAY: int = 1
const STARTING_REPUTATION: float = 50.0
const REPUTATION_MIN: float = 0.0
const REPUTATION_MAX: float = 100.0

# --- Day and clock (S3) ---
## 08:00 and 20:00. A trip out at closing time is not cut: the day waits for it.
const DAY_START_MIN: int = 8 * 60
const DAY_END_MIN: int = 20 * 60
const MINUTES_PER_DAY: int = 24 * 60
## One game hour is 90 real seconds, so a day (12 h) lasts 18 real minutes.
const SECONDS_PER_GAME_HOUR: float = 90.0
## OPENING state of DayCycle (D-0203): real seconds before the day operates.
const OPENING_REAL_SECONDS: float = 5.0

# --- Fixed costs ---
const RENT_PER_DAY: int = 100

# --- Packing grid and boxes ---
## Side of one packing-grid cell, in meters (S6).
const GRID_CELL_M: float = 0.2
## Box size id -> cells (X x Y x Z). The XL box bounds every product axis.
const BOX_CELLS: Dictionary = {
	&"S": Vector3i(2, 2, 2),
	&"M": Vector3i(3, 3, 3),
	&"L": Vector3i(4, 3, 3),
	&"XL": Vector3i(4, 4, 4),
}
## Box size id -> what one empty box costs.
const BOX_COST: Dictionary = {&"S": 2, &"M": 3, &"L": 5, &"XL": 8}
## Padding costs this per cell filled. Tape, label and stamp are per box.
const FILL_COST_PER_CELL: int = 1
const TAPE_COST: int = 1
const LABEL_COST: int = 0
const STAMP_COST: int = 0

# --- Products and pricing ---
## What the supplier charges per unit goes in each product's .tres, in this range.
const BUY_PRICE_MIN: int = 20
const BUY_PRICE_MAX: int = 80
## Sell price = buy price x this, when the product's sell_price is 0.
const SELL_MARKUP: float = 1.6
## One pallet holds up to this many units of one product.
const PALLET_MAX_UNITS: int = 24

# --- Orders ---
## Shipping fee added to an order's pay, by zone id (unknown zones pay 0).
const SHIPPING_FEE: Dictionary = {&"centro": 40, &"campo": 60}
## Orders a day: base + per player, capped.
const ORDERS_BASE_PER_DAY: int = 6
const ORDERS_PER_PLAYER: int = 2
const ORDERS_MAX_PER_DAY: int = 16
## Weight of each game hour (08:00 to 18:00, the last order hour) in the day's order arrivals (D-0803):
## slow opening, rush at 10-12, lunch dip, afternoon bump, thin last hour.
const ORDER_HOUR_WEIGHTS: Array[float] = [1.0, 2.0, 3.0, 3.0, 2.5, 1.0, 1.0, 2.0, 2.5, 2.0, 0.5]
## Orders do not arrive in the last hour of the day: the crew would have no time to ship them.
const ORDER_LAST_ARRIVAL_MIN: int = 19 * 60
## Products an order may ask for (distinct products, any quantity each).
const ORDER_ITEMS_MIN: int = 1
const ORDER_ITEMS_MAX: int = 3
## Delivery window from the moment the order comes in: 4 game hours.
const ORDER_WINDOW_MIN: int = 240
## Share of the pay lost when the order arrives late.
const LATE_PENALTY: float = 0.25
## A broken product is not charged (its share of the pay is 0).
const BROKEN_PRODUCT_PAY_FACTOR: float = 0.0
const BROKEN_PRODUCT_REPUTATION: float = -5.0
## A wrong or missing product makes that whole box pay 0.
const WRONG_BOX_PAY_FACTOR: float = 0.0
const WRONG_BOX_REPUTATION: float = -3.0

# --- Supplier ---
## One truck a day, at 08:30, with what was ordered the day before.
const SUPPLIER_TRUCKS_PER_DAY: int = 1
const SUPPLIER_ARRIVAL_MIN: int = 8 * 60 + 30
## It waits this long at the dock (3 game hours).
const SUPPLIER_WAIT_MIN: int = 180

# --- Packing quality (base of D-0709 and D-0710) ---
const QUALITY_START: float = 100.0
const QUALITY_MISMATCH_PENALTY: float = 40.0
## Times the share of free cells left without padding.
const QUALITY_FREE_CELLS_PENALTY: float = 30.0
## Multiplier of that penalty when any product in the box is fragile.
const QUALITY_FRAGILE_FACTOR: float = 1.5
const QUALITY_MISSING_SEAL_PENALTY: float = 15.0
const QUALITY_NO_TAPE_OR_LABEL_PENALTY: float = 10.0
## impact_absorption = lerp(ABSORPTION_UNPADDED, ABSORPTION_FULL_PADDING, protection),
## where protection is the share of free cells that carry padding.
const ABSORPTION_UNPADDED: float = 1.0
const ABSORPTION_FULL_PADDING: float = 0.6
## More free cells than this without padding adds the Balance trap (low intensity).
const OVERSIZED_FREE_RATIO: float = 0.5
