# suppliers

One SupplierDefinition .tres per supplier (expansion D-0218): products it sells, price factor, arrival time and how long it waits.

Five today (D-0621): `distribuidora_central` (everything, list price, 08:30, waits 3 h), `feria_de_antiguedades`, `importadora_express`, `mercado_del_campo`, `panaderia_mayorista`. An order names its supplier (D-0621.b, `CompanySupplierNet.SUPPLIER_KEY`); one that names none is `distribuidora_central`'s (`SupplierIds.DEFAULT`, by id, not by file order), whose truck is the one the shed draws and keeps `CompanyTuning.SUPPLIER_ARRIVAL_MIN` / `SUPPLIER_WAIT_MIN`: its `.tres` must say the same (`test_company_suppliers`). Ids are lowercase letters, digits and `_`, at most 24 long (`SupplierIds.ok`): they go into pallet ids.
