# Aviso: pedido automático al proveedor al cierre del día (D-0151.3b)

Para: Slatex. De: Nacho (rutina desarrollador, carril 1).

- `scripts/ui/day_summary_panel.gd`: `open()` y `refresh()` reciben un `auto_units: int = 0` opcional y hay una
  etiqueta nueva `AutoOrder` ("Pedido automático al proveedor: %d unidades", clave `UI_FINANCE_AUTO_ORDER`),
  oculta cuando es 0. Las llamadas viejas siguen andando igual.
- `scripts/core/company/company_net.gd`: `CompanySupplierNet.ORDERED` entra en `HOST_EVENT_KINDS` (el host lo
  publica sin pedido). La forma del evento no cambia, sin `PROTOCOL_VERSION` nuevo.
- `NetworkManager.PROTOCOL_VERSION` sube a 54 (`supplier_ordered` con `peer` 0 viene del host sin pedido). Si otro PR en vuelo ya usó el 54 al mezclar, se sube al siguiente libre.
