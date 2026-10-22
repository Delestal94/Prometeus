# suppliers

One SupplierDefinition .tres per supplier (expansion D-0218): products it sells, price factor, arrival time and how long it waits.

Five today (D-0621): `distribuidora_central` (everything, list price, 08:30, waits 3 h), `feria_de_antiguedades`, `importadora_express`, `mercado_del_campo`, `panaderia_mayorista`. The game orders from the first file by name (`company_supplier_net.gd`), so `distribuidora_central` has to stay first alphabetically until the order screen lets the crew pick (D-0621.b).
