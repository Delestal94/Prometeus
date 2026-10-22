# Horario de clientes y ventanas de entrega (D-0136) — 2026-10-22

## Decisión
El diseño está en `docs/expansion-distritos/diseno/clientes.md`; lo construye D-0851.
- **Un solo horario para todos**: los clientes reciben mientras el día está abierto. Los horarios por cliente
  (D-0825) siguen pospuestos.
- **Desde las 20:00 no sale ningún vehículo**; lo que ya está en la ruta se entrega igual, aunque sea de noche, y
  una salida rechazada después de las 20:00 no traba el resumen.
- **La tardanza se mide con la hora del galpón** (la misma con la que corre la ventana), no con la del mundo.
- **Sin tope de ventana** al final del día.
- **En `CLOSING` se sigue venciendo** (y abandonando) mientras se espera a las salidas.
- **Al cierre de las 20:00**: lo vencido falla (−3 de reputación, como un abandono) y lo que está en ventana se
  cancela sin costo. Ningún pedido pasa al día siguiente.
- **Cierre anticipado**: todo lo no entregado falla con −3 (`guardado.md` regla 2: no sirve para esquivar nada).
- **Red**: el cierre de cada pedido es un evento de pedido de `CompanyOrdersNet`, no parte de `day_phase`; la
  reputación la escribe solo el host.
- Sin tope de reputación por día en F1; sin aviso de las 19:00 ni línea "Sin entregar" en el resumen (Pulido).

## Por qué
Lo más simple que encaja con S3 (el cierre espera a la salida), S4 (galpón congelado) y `guardado.md`. Medir la
tardanza con el mundo castigaría al que juega solo por una ventana que no corrió. Cancelar gratis lo que está en
ventana a las 20:00 no castiga la curva de llegada; hacerlo en el cierre anticipado lo convertiría en un botón
para borrar mañanas malas. Revisado por `critico-diseno`.

## Alternativas descartadas
- Clientes que reciben hasta las 21:00 y después no abren: suma una hora límite más y cajas que vuelven sin
  culpa clara.
- Recortar la ventana a las 20:00: los pedidos de la tarde nacerían casi vencidos.
- Cerrar los pedidos dentro del evento `SUMMARY`: el resumen ya está armado y cada espejo tendría que escribir
  la reputación.
