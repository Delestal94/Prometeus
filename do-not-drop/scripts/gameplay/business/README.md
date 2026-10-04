# business

Data and logic of the company mode ("Modo Empresa", expansion): ProductDefinition (D-0204), Inventory (D-0211, stock by product and location with reservations) OrderRequirement (D-0806, the six order requirements as data in `data/order_requirements/`) and what comes next.

Every number of the mode lives in `scripts/core/company/company_tuning.gd` (`CompanyTuning`, D-0202); the scripts here read it from there.
