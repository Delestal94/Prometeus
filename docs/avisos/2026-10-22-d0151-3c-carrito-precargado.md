# D-0151.3c: el carrito del proveedor se abre precargado y dice "ya pedido"

Tocado en un archivo del dominio de Slatex: `scripts/ui/supplier_order_panel.gd`. Solo agrega; **ninguna firma
cambia**:

- El `ctx` de `open()` / `refresh()` / `update_totals()` acepta `already_ordered: int` (opcional). Mayor a 0, una
  línea nueva `Already` debajo del proveedor dice "Ya pedido para mañana: N unidades" (`UI_SUPPLIER_ALREADY`, clave
  nueva en `strings_ui.csv`). Sin la clave en el `ctx` el panel se ve como antes.
- `already_text()` nuevo, para tests.
- Quien llena el carrito es `SupplierBoard.preload_cart()` (expansión), no el panel.
