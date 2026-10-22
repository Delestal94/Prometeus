# F1 · Grupo 02 — Arquitectura (detalle)

> Carril 1 de la rutina `desarrollador`. Las tareas de arquitectura del grupo 02 que son de F1. Las de F0 están en
> [F0-02-arquitectura.md](F0-02-arquitectura.md).

### D-0251 · Un día cortado vuelve a su apertura — A · Opus 5.5 · medium · Aviso: no · F1
**Depende de:** D-0134 (diseño), D-0236, D-2005
**Qué:** [guardado.md](../diseno/guardado.md), regla 2. En `scripts/gameplay/company_root.gd`, solo en el host
(también jugando solo):
- [ ] D-0251.1 Al aplicarse el `day_phase` `OPENING`, guardar en memoria la empresa tal como abre el día:
  `to_dict()` con el stock de `CompanyNet` pasado por `stock_for_save()` y `pallets.to_save()`. Los flags de
  desarrollo ya se aplicaron antes de ese momento.
- [ ] D-0251.2 `save_interrupted_day()` escribe esa copia de la apertura con `interrupted: true`, en vez del estado
  del último evento. Sin copia (el mundo se cerró antes de `OPENING`), no escribe nada: el archivo que está ya es
  esa apertura.
- [ ] D-0251.3 Actualizar los comentarios de `company_save.gd` y `company_root.gd` ("same day, money and stock" pasa
  a "the day's opening") y `CompanyInterruptedDay` si su texto promete lo contrario. El resumen local del cliente
  (D-2005) no cambia: muestra lo que vio.
**Test** `test_company_autosave` (ampliado): abrir el día, cobrar un pedido con `OrderSettlement` (o `earn`), mover
unidades a una mano y a una caja, salir a mitad de día y cargar. Tienen que quedar la plata, el `ledger`, el stock y
`pallets` de la apertura, y `was_interrupted()` en true. Salir antes de `OPENING` no pisa el archivo. Salir en
`SUMMARY` sigue guardando el día siguiente. `test_company_host_leaves` se mantiene verde.
**Hecho cuando:** el test pasa y ninguna tarea que enganche el cobro o el alquiler al mundo se mezcla antes que esta
(guardado.md §5).

### D-0252 · Stock sin lugares en curso al guardar — A · Opus 5.5 · medium · Aviso: no · F1
**Depende de:** D-0134 (diseño), D-0236, D-0715 (cajas), D-2006 (bultos del piso)
**Qué:** [guardado.md](../diseno/guardado.md) §3.
- [ ] D-0252.1 `stock_for_save()` pasa también `floor:<n>`, `box:<id>` y `package:<id>` al bulto de devolución
  `floor:0` (`CompanyRoot.SAVED_HANDS_LOCATION`), con los totales por producto iguales. Las reservas de un pedido
  sobre esas unidades se sueltan, porque el pedido no pasa al día siguiente.
- [ ] D-0252.2 `CompanyTuning.RETURN_BUNDLE_SPOT` (al lado de las mesas del galpón por defecto, dentro del piso de
  la etapa 0). Al cargar, si hay stock en `floor:0`, `FloorBundles` le pone esa posición (el host la publica en el
  snapshot), así se puede tomar como cualquier bulto.
- [ ] D-0252.3 Si el lugar fijo queda tapado por una pieza del `layout`, usar el punto libre más cercano con la
  misma regla de alcance que los bultos (D-2006).
**Test:** guardar con unidades en una mano, en el piso, en una caja abierta y en un paquete. Cargar y verificar que
los totales por producto son los mismos, que todo está en estante, palet, carrito, muelle o `floor:0`, y que un
jugador con alcance puede tomar una unidad de `floor:0` (la petición la acepta el host).
**Hecho cuando:** el test pasa.
