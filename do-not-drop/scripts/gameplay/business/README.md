# business

Data and logic of the company mode ("Modo Empresa", expansion): ProductDefinition (D-0204), Inventory (D-0211, stock by product and location with reservations) OrderRequirement (D-0806, the six order requirements as data in `data/order_requirements/`) OrderBook (D-0210, active orders and their states, host authority) OrderRhythm (D-0803, how many orders a day and when they arrive) and what comes next.

Every number of the mode lives in `scripts/core/company/company_tuning.gd` (`CompanyTuning`, D-0202); the scripts here read it from there.
