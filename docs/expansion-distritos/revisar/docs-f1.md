# Revisar la pasada de docs de F1 (2026-11-11, PR #@@PR@@)

Pasada solo de documentación: las tablas de grupo y los archivos de `detalle/` de F1 quedaron diciendo lo que hace el
código de `main`. No cambió código ni tests. La regla que se usó está en
[la decisión](../../decisiones/2026-11-11-hecho-es-hecho-en-el-juego.md).

## Probar a mano

- Nada que jugar. Para comprobar una marca: buscá en `do-not-drop/scripts/` la clase que nombra la fila. Si solo
  aparece en `tests/` y en su propio archivo, la fila tiene que estar ◐ con su subtarea abierta. Ejemplos que hoy dan
  cero llamadas fuera de `tests/`: `OrderSettlement.settle`, `TripResult.build`, `OrderDoorReaction.react`, y ningún
  script instancia `WorldGate`.
- Abrí la sala de control (el panel web): las filas que pasaron de ✅ a ◐ tienen que bajar la cuenta de hechas de los
  grupos 03, 05, 07 y 08. D-0616 vuelve a contarse en el grupo 06 (la marca estaba en la columna del ID y el panel no
  leía la fila).

## Decidir al final

Lo que elegí:

- **Volvieron de ✅ a ◐ nueve filas** porque lo que prometen no pasa en el juego: D-0306 (los bloqueos no están en el
  mundo), D-0320 y D-0520 (nadie arma el resultado de una salida), D-0701 y D-0702 (la mesa y el dispensador no se
  pueden usar), D-0715 (su propio detalle decía que el ✅ era parcial), D-0815, D-0816 y D-0817 (la puerta no cobra, no
  califica y no reacciona). D-0314 ya era parcial en el detalle y le faltaba la marca. Si preferís que ✅ signifique
  "la lógica y su test están", alcanza con revertir esas marcas; las subtareas con casilla sirven igual.
- **Subtareas nuevas con casilla, escritas con lo que el código ya tiene:** D-0306.b (un `WorldGate` por nodo `gate`
  del grafo), D-0320.b (el host arma `TripResult` al cerrar cada salida) y el bloque de detalle de D-0340 (la puerta
  cobra y publica `order_delivered`, D-0815.b). Son propuestas de cómo engancharlas; quien las construya puede elegir
  otro camino si cumple el "Hecho cuando".
- **D-0312 quedó `[x]`** (su test pasa y la tabla ya decía ✅) con D-0312.1 y D-0312.2 abiertas como seguimiento fuera
  del corte. La otra opción era dejarla ◐ hasta el cartel de calle en las esquinas.
- **Subtareas fuera de la lista del corte no le sacan el ✅ a su tarea:** D-0518.b y D-0910.1 (votos), D-0713.b
  (balanza), D-0719.b (desarmar), D-0805.b (impresora), D-0811.b (pedidos en espera). Quedan con casilla y dicen que
  no frenan F1. Si querés que entren a F1, hay que pasar su fila a ◐.

Lo que no decidí, con mi recomendación:

- **Dónde va el botón de la grúa (D-0307.1.a).** La tarea lo pone en el tablero de despacho, que está en el galpón, y
  `CompanyTow.may_ask()` solo acepta al conductor o a quien va adentro: un conductor solo, varado en la calle, no
  llega al botón. Recomiendo un aviso con tecla para quien va en el vehículo varado y dejar el botón del tablero para
  quien quedó en el galpón.
- **D-0307.1.c no se puede cerrar en F1.** Pide el estado `BROKEN`, y nada rompe todavía una camioneta de la empresa.
  Mientras siga dentro de D-0307.1, D-0307 queda ◐ aunque la grúa funcione. Recomiendo pasarla a F2 con las fallas
  del vehículo.
- **El frío corre en F1 aunque el corte dice que no.** `corte-vertical.md` §3 manda D-0616 a F2 ("el campo
  temperatura existe y se ignora"), pero `ColdChainTick` corre en `CompanyRoot` sin mirar la fase. Como todavía no se
  pueden sacar unidades de un palet (D-0607.c), lo frío del primer camión se echa a perder siempre. Recomiendo
  apagarlo hasta F2 o hacer D-0607.c antes de cerrar F1; es una decisión de diseño y no la tomé.
- **Cuándo se abre F2.** `.claude/rutinas/desarrollador.md` §2 abre F2 con D-2016 `[x]`; `corte-vertical.md` §4 pide
  además `bench_company` dentro del presupuesto (D-2012), D-2013 y D-2017, y esas dos dependen de D-2016. Con la regla
  de la rutina, F2 arranca antes de medirlas. Recomiendo que la rutina espere también a D-2012, D-2013 y D-2017.
- **D-2017 pide que el despacho corra en un cliente** y `company_dispatch.gd` solo deja cargar al host. O el guion
  prueba que el cliente deja la caja en la zona y el host carga, o cambia la regla.
- **`OrderNoticeFeed` quedó sin usar** (el aviso de pedido nuevo sale por `ShedEventFeed`). Borrarlo o enchufarlo al
  celular.
- **Filas de la tabla 03 con título viejo.** D-0301, D-0304, D-0306, D-0308, D-0313 y D-0318 conservan el título de
  antes del mapa continuo con la nota "en `detalle/` es: ...". Cambié el título solo en D-0307, D-0310 y D-0314, que
  eran las que no tenían nota. Reemplazar los demás es mecánico si se prefiere una sola forma.

Lo que vi y no toqué porque lo está cambiando otra tarea en curso, o porque no es un documento:

- Las filas y bloques de D-0254, D-0303, D-0503, D-0517, D-0710, D-0804, D-0851, D-2012, D-2016, D-2019 y D-2020,
  con sus "PR pendiente". La fila D-0302 conserva el ✅ en la columna del ID por estar pegada a la de D-0303.
- `docs/qa-recorrido.md` (sección del bot de empresa) y [`D-2016.md`](D-2016.md) dicen que el bot todavía no sigue
  el grafo de calles y que `CompanyRoot` no llena `CompanyNet.stations`; las dos cosas ya están hechas. Los corrige
  D-2016.4 al reescribir esa sección.
- Comentarios de código: el encabezado de `tests/bot_company_day.gd` repite lo anterior, y el de `company_tow.gd`
  llama D-0307.2 a lo que el detalle llama D-0307.1.c (lo anoté en el detalle).
- El issue #470 (D-0113) sigue abierto aunque la decisión está tomada y escrita en
  `docs/decisiones/2026-11-04-recortes-zona-gris.md`: se puede cerrar con un link a ese archivo.
- [`D-0304.md`](D-0304.md) pide cerrar el PR #735 sin mezclarlo: sigue pendiente y la nota queda como está.
- Varias ramas de reclamo viejas siguen en `origin` para tareas con subtareas abiertas (D-0607, D-0701, D-0710,
  D-0715, D-0815, D-0817). La regla 2.1 de la rutina salta una tarea que tiene rama `origin/exp/<ID>-*`, así que
  justo esas no se toman solas: hay que retomarlas con la regla 15 del README de rutinas.
