# Eventos del día del modo Empresa (D-0123) — 2026-10-22

## Decisión
15 eventos del día (6 Núcleo F1, 5 Ampliación F1, 4 Ampliación F2), en
`docs/expansion-distritos/diseno/eventos-del-dia.md`:
- La "huelga" es un paro de **transporte** anunciado la víspera, que se prepara comprando antes de las
  14:00; la huelga de empleados (D-1036) sigue recortada (R4).
- El host sortea el plan del día D al cerrar el D−1 con una corriente nueva `CompanySeed.EVENTS` y lo
  guarda: hay aviso la víspera, recargar no cambia el sorteo y no se corren los sorteos de pedidos y
  proveedores (D-0246).
- 0 eventos los días 1-3, sin negativos hasta el día 8, como mucho 1 por día hasta el 15 y nunca más de 1
  con un solo jugador. Techo diario: 150 en multas, 300 en premios, ±5 de reputación; una multa nunca
  deja la caja en rojo por sí sola y con la empresa en rojo solo salen eventos positivos.
- Los efectos viajan dentro de los eventos del sistema que tocan (`supply_arrived`, `order_added` con su
  `pay`); en red solo se suman `day_event_*`, la petición `day_event_answer` y la parte de snapshot
  `day_events`, en una clase propia `CompanyDayEventsNet`.
- Ningún evento es de zona (P14 sigue pospuesto); la erupción (D-1716) reutiliza el formato.
- No entra en el corte vertical: se construye con tareas nuevas del grupo 05 después de cerrar F1.

## Por qué
El jugador arma y optimiza su galpón; sin algo que cambie de un día a otro, el día 10 es igual al 6. Los
eventos son el antagonista (referencias-logistica.md) sin verbos nuevos: cambian números o ponen una hora,
siempre con aviso y una respuesta posible, que es el criterio con el que R4 recortó lo que quitaba plata
sin decisión.

## Alternativas
- Huelga de empleados: recortada por R4 (castigo sin decisión) y necesita F2.
- Sorteo en la apertura: sin aviso la víspera, los eventos que se preparan comprando no tendrían respuesta.
- Eventos por zona: es P14, pospuesto a post-lanzamiento.
