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
## Vehicles the new company owns (data/vehicles/<id>.tres, D-0207): the first van is a gift.
## CompanyState.new_company() still starts with an empty fleet until the dealer (D-1201) grants these.
const STARTING_FLEET: Array[StringName] = [&"van_classic"]

## Movements the wallet history keeps (D-0501); older ones are dropped.
const LEDGER_MAX: int = 200

# --- Day and clock (S3) ---
## 08:00 and 20:00. A trip out at closing time is not cut: the day waits for it.
const DAY_START_MIN: int = 8 * 60
const DAY_END_MIN: int = 20 * 60
const MINUTES_PER_DAY: int = 24 * 60
## One game hour is 90 real seconds, so a day (12 h) lasts 18 real minutes.
const SECONDS_PER_GAME_HOUR: float = 90.0
## OPENING state of DayCycle (D-0203): real seconds before the day operates.
const OPENING_REAL_SECONDS: float = 5.0
## S4: the frozen shed freezes or thaws at most once in this many real seconds (DayCycle, D-0203), so
## a player standing on the shed's door line can't send an event per frame. Shorter than a walk
## through the door; long enough that nobody gains by dancing on the line.
const SHED_FREEZE_SETTLE_REAL_SECONDS: float = 1.0
## Host rules of the company (DayCycle's poll, and what joins it: orders, suppliers, employees) run
## this many times a real second on BusinessTick (D-0232), not once per frame.
const BUSINESS_TICK_HZ: float = 4.0

# --- World cells (D-0303) ---
## The continuous map is cut in squares of this side, in meters (diseno/mapa.md).
const CELL_SIZE: float = 256.0
## Cells around an anchor that load, and the distance past which they unload (hysteresis).
const CELL_LOAD_RADIUS: int = 2
const CELL_UNLOAD_RADIUS: int = 3
## Cells around an anchor that show a one-piece stand-in when not loaded.
const CELL_IMPOSTOR_RADIUS: int = 5
## Instancing budget per frame, in real milliseconds (the N-917 lesson: never a big frame).
const CELL_SLICE_MSEC: float = 4.0

# --- GPS (D-0308) ---
## Typical speed on each street surface, in m/s: the GPS weighs a street by length / speed (time),
## so it prefers a longer asphalt road to a short mud track. Unknown surface: 10.
const SURFACE_SPEED: Dictionary = {&"asphalt": 14.0, &"cobble": 10.0, &"gravel": 9.0, &"dirt": 7.0}
## How far ahead along the route the GPS arrow points, in meters.
const GPS_LOOKAHEAD: float = 30.0

# --- Tow home (D-0307) ---
## "Volver con grua": a vehicle left stuck or broken on a trip is towed back to the shed's yard for this
## much money (spent from the company wallet, ledger reason `tow`). The undelivered orders fail, as in any
## trip that comes back with them. Low enough to be a way out, high enough that nobody wrecks a van to skip
## the drive (a failed order already costs more than it pays, docs/economia-y-contramedidas.md).
const TOW_COST: int = 50
## Real seconds of black screen while the vehicle is carried to the yard.
const TOW_BLACK_SCREEN_SECONDS: float = 3.0

# --- Crew split between the shed and the street (D-0316) ---
## Most vehicles out on a trip at once (docs/decisiones/2026-10-04-mapa-continuo.md, point 6): the
## dispatch board doesn't load a third one and the shed gate starts no third trip, with the reason.
## D-0317 confirms or raises it with D-2002's measurements.
const VEHICLES_FAR_MAX: int = 2
## Who gets a company vehicle's or loose box's updates (CompanyInterest): the peers whose player is
## within CELL_LOAD_RADIUS cells of it, until it is past CELL_UNLOAD_RADIUS. They look again this often,
## in real seconds: a vehicle at 100 km/h covers 7 m, far under a cell.
const INTEREST_UPDATE_REAL_SECONDS: float = 0.25
## A body hidden from a peer is still sent to it for INTEREST_PULSE_REAL_SECONDS this often, so
## SceneMultiplayer's 16-bit sync clock never falls half a turn behind (WorldCellInterest).
const INTEREST_KEEPALIVE_REAL_SECONDS: float = 20.0
const INTEREST_PULSE_REAL_SECONDS: float = 0.1

# --- Network (D-2002) ---
## Poses a second each player sends on foot in the company's world (D-2002.3): half the game's 30
## (player.tscn). Nobody goes fast in the shed, and at 30 the poses the host relays sent each client
## of a full crew 37 KB/s, over the shed's 24 (docs/rendimiento-pc.md). Riding a vehicle a player
## sends at the game's rate again (player_ride.gd set_on_foot_pose_rate(), CompanyRoot.join_crew()).
const SHED_POSE_RATE_HZ: int = 15

# --- Fixed costs ---
const RENT_PER_DAY: int = 100
## Money the suggested supplier order leaves untouched besides the rent (D-0151,
## roles-tripulacion.md §6.3): the reserve of the economy curve.
const SOLO_ORDER_CASH_RESERVE: int = 100

# --- Bankruptcy (D-0510) ---
## A company that closes the day in the red opens the next one with this share of its orders
## (docs/expansion-distritos/diseno/economia.md: no reset, no forced loan).
const BANKRUPT_ORDER_SHARE: float = 0.6

# --- Order printer (D-0805) ---
## Sheets the printer tray holds; with the tray full the printer jams and new orders wait.
const PRINTER_TRAY_MAX: int = 4
## Order sheets one person can carry at once.
const SHEETS_IN_HAND_MAX: int = 3

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
## What one packing table holds (D-0718): empty boxes per size (`box_<size>`), tape (one per box)
## and padding (one per cell). Restocking is a chore that costs time, not money.
const SUPPLY_CAPACITY: Dictionary = {
	&"box_S": 6, &"box_M": 6, &"box_L": 4, &"box_XL": 3, &"tape": 10, &"fill": 30,
}
## A supply counts as low at or under this share of its capacity.
const SUPPLY_LOW_RATIO: float = 0.25

## Cooler with ice (D-0721, ColdPack): a cold product lasts COLD_BASE_MINUTES in a box without ice
## and COLD_PER_ICE_MINUTES more per ice pack (up to ICE_PACKS_MAX); an ice pack costs ICE_PACK_COST.
const COLD_BASE_MINUTES: float = 15.0
const COLD_PER_ICE_MINUTES: float = 25.0
const ICE_PACKS_MAX: int = 2
const ICE_PACK_COST: int = 2
## Cold stock outside a fridge (D-0616, ColdChain): a cold product rots after this many game minutes
## out of cold storage (2 h), counted per product and place; in a fridge the clock stops.
const COLD_SPOIL_MINUTES: float = 120.0

## Gift wrap (D-0723, GiftWrap): a gift order delivered in a wrapped box pays GIFT_WRAP_BONUS of its
## pay on top of the gift requirement's own bonus; the paper costs GIFT_WRAP_COST.
const GIFT_WRAP_BONUS: float = 0.15
const GIFT_WRAP_COST: int = 3

## Multi-box orders (D-0729, OrderParts): an order whose products need more than MULTI_BOX_FILL of one
## XL box is split into up to ORDER_BOXES_MAX boxes, all of them delivered together.
const ORDER_BOXES_MAX: int = 3
const MULTI_BOX_FILL: float = 0.75

## Products that must not share a box (D-0726, ProductCompatibility): assembly quality points lost
## per incompatible pair found in one box (a pair is two different groups, counted once per kind).
const INCOMPATIBLE_QUALITY_PENALTY: int = 30

## Upright-only products (D-0727, ProductOrientation): assembly quality points lost per such product
## in a box laid on its side.
const TIPPED_QUALITY_PENALTY: int = 25

# --- Warehouse grid (D-0904) ---
## Side of one warehouse floor cell, in meters (placeable footprints are counted in these).
const WAREHOUSE_GRID_M: float = 1.0
## Selling a placed object gives back this share of its price.
const PLACEABLE_REFUND_RATIO: float = 0.5

# --- Warehouse stages (D-0905) ---
## Shed stages, small to large: grid size in cells (X x Z) and what the upgrade INTO each stage
## costs (the first one is the starting shed, free). Same index in all three arrays.
const WAREHOUSE_STAGE_IDS: Array[StringName] = [&"small", &"medium", &"large", &"logistics_center"]
const WAREHOUSE_STAGE_GRID: Array[Vector2i] = [
	Vector2i(12, 8), Vector2i(18, 12), Vector2i(24, 16), Vector2i(32, 20)]
const WAREHOUSE_STAGE_PRICE: Array[int] = [0, 800, 2000, 5000]
## Most pieces (shelves, tables, zones...) a stage can hold, so the built shed stays inside the
## performance budget (D-0915): about one piece per six floor cells. Same index as the arrays above.
const WAREHOUSE_STAGE_MAX_PIECES: Array[int] = [16, 36, 64, 100]

# --- Warehouse fixed areas (D-0906) ---
## Floor cells (X x Z) kept free in front of the loading dock (south wall, centered) and the
## customer exit (north wall, centered). No object can be placed there at any stage.
const WAREHOUSE_DOCK_CELLS: Vector2i = Vector2i(4, 2)
const WAREHOUSE_EXIT_CELLS: Vector2i = Vector2i(2, 2)

# --- Return bundle (D-0252) ---
## Where the return bundle (ReturnBundle) lies when a saved day loads, in the world at floor height: in the
## starting shed (stage 0, standing at the origin), the middle of cell (10, 1), at the north end of the aisle in
## front of the default packing tables (DefaultShed: table_1 and table_2 against the east wall, cells 11 x 2..5).
## A bigger stage keeps it in that cell, as it keeps every piece; a piece over it moves it (ReturnBundle.spot()).
const RETURN_BUNDLE_SPOT: Vector3 = Vector3(4.5, 0.0, -2.5)

# --- Warehouse lighting (D-0913) ---
## Ceiling lamps: one per tile of at most this many meters, so the number grows with the stage
## (2 lamps in the small shed, 12 in the logistics center).
const SHED_LAMP_SPACING_M: float = 8.0
## Range of a ceiling lamp, its energy, and the share of the range that counts as well lit (the
## farthest point of a tile is 5.7 m from its lamp, under 8.5 * 0.75 = 6.4).
const SHED_LAMP_RANGE_M: float = 8.5
const SHED_LAMP_ENERGY: float = 0.8
const SHED_LAMP_REACH: float = 0.75
## Task lamp over each packing table.
const SHED_TASK_LAMP_RANGE_M: float = 4.0
const SHED_TASK_LAMP_ENERGY: float = 0.9
## Most omni lights that may reach one surface at once (the GL Compatibility renderer lights an
## object with 8 at most; the extra ones would flicker).
const SHED_MAX_LIGHTS_PER_POINT: int = 8
## Height of the lamps above the floor, under the 4 m walls.
const SHED_LAMP_HEIGHT_M: float = 3.6

# --- Build mode (D-0901) ---
## Height of the build camera above the floor, in meters, at zoom 1.
const BUILD_CAMERA_HEIGHT_M: float = 14.0
## Zoom limits (multiplier of the camera height; lower is closer).
const BUILD_ZOOM_MIN: float = 0.5
const BUILD_ZOOM_MAX: float = 1.5
## Pitch of the build camera in degrees (90 = straight down).
const BUILD_CAMERA_PITCH_DEG: float = 70.0

# --- Products and pricing ---
## What the supplier charges per unit goes in each product's .tres, in this range.
const BUY_PRICE_MIN: int = 20
const BUY_PRICE_MAX: int = 80
## Sell price = buy price x this, when the product's sell_price is 0.
const SELL_MARKUP: float = 1.6
## One pallet holds up to this many units of one product.
const PALLET_MAX_UNITS: int = 24
## One labeled shelf slot holds up to this many units of its product (D-0608): one pallet.
const SHELF_SLOT_CAPACITY: int = 24
## Units a player carries in their hands, all of one product (red-autoridad.md section 2,
## row 5; CompanyNet checks it on units_take, D-2003). Picking (D-0609) and D-0117 tune it.
const HAND_MAX_UNITS: int = 4
## Units a picking cart carries in total, products mixed (D-0610, the "carries 6" of its table row). More than
## the hands (HAND_MAX_UNITS) so the cart is worth the trip; PickingCart refuses the unit that would pass it.
const CART_MAX_UNITS: int = 6
## One push of a picking cart (D-0610.b): how far it rolls, in metres, away from whoever pushes it.
const CART_PUSH_STEP_M: float = 1.2
## How close to a wall or a piece of furniture (m, from the cart's centre) the cart may be left.
const CART_CLEARANCE_M: float = 0.7
## Holding the cart's handle (D-0610.c2.b, PickingCartGrip): the cart keeps at least CART_GRIP_DISTANCE_M from
## whoever holds it (centre of the cart to their feet, m, on the floor), pushed ahead at most once every
## CART_GRIP_INTERVAL_S, plus a lead: how far they walk towards it in CART_GRIP_LEAD_S (the interval and the
## cushion a remote player is drawn with on the host) plus their round trip, at most CART_GRIP_MAX_LEAD_M. So
## the step their peer sees late is already ahead of where they walk by then, and the next one comes in time.
## The deck is solid: a player (radius 0.35) touches it at most 0.93 m from the centre (towards a corner), so
## (CART_GRIP_DISTANCE_M - 0.93) / CART_GRIP_INTERVAL_S stays over Player.WALK_SPEED: even with no lead a
## holder pressed against the deck gets room faster than they walk and is never held back.
## The shortest step worth a request; who is CART_GRIP_RELEASE_M away lets go (past DISTANCE + MAX_LEAD, where
## a cart that ran ahead stops, and within reach of it); after a `blocked` the grip waits CART_GRIP_BLOCKED_PAUSE_S.
const CART_GRIP_DISTANCE_M: float = 1.5
const CART_GRIP_LEAD_S: float = 0.25
const CART_GRIP_MAX_LEAD_M: float = 1.5
const CART_GRIP_RELEASE_M: float = 3.6
const CART_GRIP_MIN_STEP_M: float = 0.1
const CART_GRIP_INTERVAL_S: float = 0.15
const CART_GRIP_BLOCKED_PAUSE_S: float = 0.6
## How close two picking carts may stand, centre to centre on the floor (m, D-0610.c): past the diagonal of the
## 1.0 x 0.6 m platform, so two carts never overlap whichever way they face.
const CART_SPACING_M: float = 1.2

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
## With a crew of one the day's arrival hours are squeezed so the last order comes in by 15:00 of the
## shed (D-0151, roles-tripulacion.md §6.2): the shed stands still while the only player drives (S4),
## and with three trips the afternoon orders would never come in. The count does not change.
const SOLO_ORDER_LAST_ARRIVAL_MIN: int = 15 * 60
## Products an order may ask for (distinct products, any quantity each).
const ORDER_ITEMS_MIN: int = 1
const ORDER_ITEMS_MAX: int = 3
## The first days ask for fewer distinct products (D-0812): up to ORDER_ITEMS_EARLY_MAX on days
## 1 to ORDER_EARLY_DAYS, so a crew still learning the shed packs one or two products per box.
const ORDER_EARLY_DAYS: int = 3
const ORDER_ITEMS_EARLY_MAX: int = 2
## Delivery window from the moment the order comes in: 4 game hours.
const ORDER_WINDOW_MIN: int = 240
## Share of the pay lost when the order arrives late.
const LATE_PENALTY: float = 0.25
## A late order nobody has put on the road is dropped by the customer this many minutes after its
## due time (D-0807): one more window. Costs ABANDONED_REPUTATION and pays nothing.
const ORDER_ABANDON_MIN: int = 240
const ABANDONED_REPUTATION: float = -3.0
## Packing quality 0-100 (D-0709, AssemblyQuality): starts at QUALITY_MAX and loses these.
const QUALITY_MAX: float = 100.0
## Contents that do not match the order.
const QUALITY_WRONG_CONTENT: float = 40.0
## Times the share of the box left empty and unpadded; multiplied when a product is fragile.
const QUALITY_GAP_WEIGHT: float = 30.0
const QUALITY_GAP_FRAGILE_FACTOR: float = 1.5
## Control scale (D-0713): the box passes when real and expected weight differ by at most this (kg).
const SCALE_TOLERANCE_KG: float = 0.05
## Per required seal the box lacks.
const QUALITY_MISSING_SEAL: float = 15.0
## Once, when the box has no tape or no label.
const QUALITY_UNSEALED: float = 10.0
## A box delivered in at least this packing quality (0-100, D-0709) earns the condition
## bonus: this share of the pay on top (D-0502).
const CONDITION_BONUS_MIN_QUALITY: float = 90.0
const CONDITION_BONUS: float = 0.10
## A broken product is not charged (its share of the pay is 0).
const BROKEN_PRODUCT_PAY_FACTOR: float = 0.0
const BROKEN_PRODUCT_REPUTATION: float = -5.0
## A wrong or missing product makes that whole box pay 0.
const WRONG_BOX_PAY_FACTOR: float = 0.0
const WRONG_BOX_REPUTATION: float = -3.0
## A box labeled for another order (or not labeled) pays this share less and costs reputation (D-0506).
const MISLABEL_PAY_LOSS: float = 0.15
const MISLABEL_REPUTATION: float = -1.0
## One delivery never costs more reputation than this, however many products broke.
const PENALTY_REPUTATION_CAP: float = -10.0
## A perfect delivery (no penalty) made within this share of the delivery window tips this share
## of the order's base pay and earns a little reputation (D-0507).
const TIP_FAST_WINDOW_SHARE: float = 0.5
const TIP_RATE: float = 0.15
const TIP_REPUTATION: float = 1.0
## Reputation a delivery with nothing wrong with it earns on top of its pay (D-0815); the tip adds
## its own TIP_REPUTATION when it was also quick.
const CLEAN_DELIVERY_REPUTATION: float = 0.5
## The customer's rating of a delivery, 1 to 5 stars (D-0816, OrderRating). Only information for now:
## it moves no money and no reputation. A clean delivery earns 4 stars, 5 when it also tipped (quick);
## otherwise the worst failure decides: a wrong box 1, a broken product 2, lateness or a label of
## another order 3.
const STARS_MIN: int = 1
const STARS_MAX: int = 5
const STARS_CLEAN_SLOW: int = 4
const STARS_WRONG_BOX: int = 1
const STARS_BROKEN: int = 2
const STARS_LATE: int = 3
const STARS_MISLABELED: int = 3
## The customer's reaction at the door, from the stars (D-0817, OrderDoorReaction): 4 or 5 stars cheer,
## 3 shrugs, 1 or 2 are angry.
const REACTION_CHEER_MIN_STARS: int = 4
const REACTION_SHRUG_MIN_STARS: int = 3
## Merit the carrier of an intact delivery earns when a trip closes (D-0320, TripResult).
const TRIP_MERIT_INTACT: int = 10

# --- Supplier ---
## One truck a day, at 08:30, with what was ordered the day before.
const SUPPLIER_TRUCKS_PER_DAY: int = 1
const SUPPLIER_ARRIVAL_MIN: int = 8 * 60 + 30
## It waits this long at the dock (3 game hours).
const SUPPLIER_WAIT_MIN: int = 180
## The truck NPC's drive (D-0601, SupplierTruck): grey-box size in meters (width, height, length),
## the gap between the shed's floor edge and its rear when parked (the south wall is 0.3 thick), the
## turn radius, how far it reverses in a straight line, the straight run before the turn, and the
## game minutes it takes to drive in (it is parked at SUPPLIER_ARRIVAL_MIN) and to drive out (it
## starts at the departure minute).
const SUPPLIER_TRUCK_SIZE_M: Vector3 = Vector3(2.4, 3.2, 6.4)
const SUPPLIER_TRUCK_REAR_GAP_M: float = 0.6
const SUPPLIER_TRUCK_TURN_RADIUS_M: float = 6.0
const SUPPLIER_TRUCK_REVERSE_M: float = 10.0
const SUPPLIER_TRUCK_APPROACH_M: float = 16.0
const SUPPLIER_DRIVE_IN_MIN: float = 6.0
const SUPPLIER_DRIVE_OUT_MIN: float = 4.0
## The pallet jack (D-0605, PalletJack): a pallet's footprint on the floor in meters (width, depth)
## and how close the jack's holder must stand to pick one up.
const PALLET_FOOTPRINT_M: Vector2 = Vector2(1.2, 0.8)
const PALLET_JACK_REACH_M: float = 1.6
## One push of the pallet jack in the world (D-0605.b): how far it rolls, in metres, away from whoever pushes
## it. More than a pallet's long side (1.2 m), so a pallet put down is never under the next one.
const JACK_PUSH_STEP_M: float = 1.3
## The forklift (D-0606, PalletForklift): how high the forks go (m), how fast they rise (m/s, the
## depot's staff forklift speed) and how close to a level they must be to take or leave a pallet.
const FORKLIFT_MAX_LIFT_M: float = 2.4
const FORKLIFT_LIFT_SPEED: float = 0.55
const FORKLIFT_LEVEL_TOLERANCE_M: float = 0.12
## The forklift in the world (D-0606.b): how far ahead of its driver the middle of a pallet on the forks lies
## (m), and how long one mast request moves the forks at most (s: the driver asks again while the key is held,
## so a lost "stop" cannot send the forks to the top).
const FORKLIFT_TIP_M: float = 1.2
const FORKLIFT_MAST_BURST_S: float = 0.5
## How fast its driver goes (m/s, D-0606.c2): a forklift's 8 km/h, under walking pace (3.6), and no running.
const FORKLIFT_DRIVE_SPEED_MPS: float = 2.2

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
## Trap intensity from packing quality (D-0710, BoxTrap): 1 - quality / 100, read as low below
## TRAP_INTENSITY_MID, high from TRAP_INTENSITY_HIGH. A loose box adds Balance at this intensity.
const TRAP_INTENSITY_MID: float = 0.1
const TRAP_INTENSITY_HIGH: float = 0.25
const TRAP_LOOSE_BOX_INTENSITY: float = 0.3
