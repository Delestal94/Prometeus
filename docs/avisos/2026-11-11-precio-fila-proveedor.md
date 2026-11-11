# Precio por fila del tablero del proveedor

- **Qué cambió (`scripts/ui/supplier_order_panel.gd`, dominio de Slatex):** en `_add_row`, la etiqueta de cada fila
  (`UI_SUPPLIER_ROW`) muestra `cart.unit_price(product)`, el precio del proveedor con su `price_factor`, en vez de
  `SupplierPurchase.cost(product, 1, cart.products)`, que daba el precio de lista (`buy_price`). Ninguna firma ni señal
  cambió; la clave de traducción es la misma.
- **Por qué:** desde D-0503.b recibir un palet cobra a la empresa el precio del proveedor (el mismo que ya usaba el total
  del tablero). Con un proveedor de `price_factor` distinto de 1 (Mercado del Campo, la panadería) la fila decía un
  precio y la caja pagaba otro.
- **Qué tiene que hacer Slatex:** nada. Si la fila vuelve a armarse en otro lado, que use `cart.unit_price`.
  `test_company_supplier_panel` lo comprueba (`_test_row_price`).
