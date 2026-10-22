# Qué se guarda entre sesiones (D-0134)

> Qué guarda el modo Empresa y qué no. Cubre la empresa, el stock, los empleados y el día en curso, más lo que
> el código ya hace y lo que falta. El formato y los slots son de D-0206 y D-0235 (`CompanySave`), y los
> momentos de guardado, de D-0236 y D-2005 (`CompanyRoot`). Lo que falta construir lo hacen D-0251, D-0252 y
> D-0253. Revisado por `critico-diseno`.
> Fuentes: [riesgos.md](riesgos.md) R-03 y R-04, [red-autoridad.md](red-autoridad.md) §3,
> [eventos-del-dia.md](eventos-del-dia.md) §2.2, [onboarding.md](onboarding.md) y
> [portapapeles.md](portapapeles.md). Decisión: `docs/decisiones/2026-10-22-guardado.md`.

## 1. Reglas

1. **Un punto de guardado por día: la apertura.** El save siempre describe una empresa **a las 08:00 de un
   día que todavía no empezó**. Cargar siempre abre un día (`DayCycle.open_day`), nunca retoma uno a la mitad
   ni vuelve a mostrar un resumen. Ya pasa así con el cierre (D-0236 guarda "día + 1 a las 08:00"). **Crear la
   empresa guarda su apertura del día 1** (con el galpón por defecto y antes de los flags de desarrollo): sin eso,
   cortar el día 1 la borraría, porque no habría archivo.
2. **Un día que se corta vuelve a su apertura.** Salir al menú, que el host se vaya (D-2005), que se corte la
   luz o que el proceso muera: el día cortado **no deja nada**. La empresa queda como estaba al abrir ese día.
   Hoy el guardado de día interrumpido conserva plata, stock y libro de caja **del último evento**, con el
   reloj de vuelta a las 08:00. Eso es "a medias" (R-03, mitigación 2) y deja tres agujeros:
   - **Se cobra dos veces.** El libro de pedidos no se guarda. Al cargar, `CompanyDayOrders.plan` vuelve a
     sortear los mismos pedidos con la misma semilla, y `OrderSettlement` paga de nuevo lo que ya se había
     pagado (hoy no se nota porque el cobro todavía no está enganchado al juego; ver §5).
   - **Unidades varadas.** Lo que estaba en una caja abierta (`box:<id>`), en un paquete cerrado
     (`package:<id>`) o en un bulto del piso queda en el stock sin mesa, sin nodo y sin posición: no se puede
     tomar.
   - **El resumen suma de más.** `DaySummary` suma todo el libro de caja del día: el pedazo cortado más el día
     repetido.
   **Un corte no escribe la empresa:** el archivo que está ya es la apertura de este día (la escribió el cierre
   de ayer o la creación de la empresa). Solo se le marca `interrupted: true`, que ahora quiere decir "este día se
   cortó y se juega de nuevo desde la apertura", para que el menú lo avise. Así ningún dato de la mitad del día
   llega al disco y los flags de desarrollo tampoco. Lo construye **D-0251**.
   **Para cortar sin perder lo hecho, el host cierra el día antes** (pausa → "Cerrar el día", D-0253): el día
   pasa a `CLOSING` en ese momento. No entran pedidos nuevos, se espera a que vuelvan las salidas, viene el
   resumen y se guarda como cualquier cierre. Lo que no se entregó se penaliza igual que a las 20:00, así que no
   sirve para esquivar nada. Las dos salidas del menú lo avisan: "Salir ahora pierde lo hecho desde las 08:00".
3. **Solo guarda el host** (también jugando solo). Un cliente tiene un espejo, que nunca se escribe
   (red-autoridad §3). Al irse, el cliente recupera su propia empresa (`_restore_own_company`).
4. **Lo que se puede volver a calcular no se guarda.** Lo que sale de la semilla (`company_seed` +
   día + corriente, D-0246) o de otro dato guardado se recalcula al abrir. Así el save es chico y no hay dos
   fuentes de la verdad. Por eso un día que se repite saca los mismos pedidos, el mismo proveedor y, si el plan
   de eventos se sorteó en la apertura (día 1 o un save viejo), los mismos eventos: todo sorteo del día sale de
   su corriente de la semilla y de datos de la apertura, nunca de algo que pasó en el día.
5. **Una clave que cambia de significado sube la versión.** `CompanySave.VERSION` sube con una migración en
   `MIGRATIONS` y con un save de la versión anterior como fixture en `tests/` (R-04). Una clave nueva con un
   valor por defecto razonable no sube la versión: `from_dict` ya tolera que falte.

## 2. Qué se guarda (la empresa)

Todo vive en `CompanyState.to_dict()`, dentro de `user://saves/company/<slot>.json` con
`{version, saved_at, interrupted, company}`.

| Clave | Qué es | Notas |
|---|---|---|
| `company_name`, `company_seed` | Nombre y semilla del mundo | La semilla no cambia nunca; un save viejo la saca del nombre |
| `money`, `ledger` | Billetera e historial (hasta `LEDGER_MAX`) | El resumen del día se arma con el `ledger` |
| `day`, `clock_minutes` | Día y hora | Siempre el día por abrir y `DAY_START_MIN` (regla 1) |
| `reputation`, `district_reputation` | Reputación general y por zona | — |
| `opened_gates`, `equipment` | Portones abiertos, equipo y licencias (`license_*`, D-0124) | Nunca se cierran ni se pierden |
| `milestones_done` | Hitos cumplidos | Los textos de "aprendiste X" van en el perfil (§4) |
| `fleet` | Vehículos comprados | Al cargar se estacionan en la salida, sin posición ni carga. Un vehículo prestado por un evento no entra |
| `employees` | Empleados contratados | En F1 está vacío. D-1016 suma la estación asignada; se guarda el contrato, no la posición ni la tarea en curso, y cada uno arranca en su estación. El temporal de un evento no se guarda (se va al cierre) |
| `layout`, `warehouse_stage` | Piezas del galpón con su `uid` y etapa del piso | `BuildLayoutSave.sanitize` descarta lo que no entra |
| `inventory` | Stock por producto y lugar | Al guardar, las manos pasan al piso. D-0252 normaliza el resto (§3) |
| `supplier_calendar` | Pedidos al proveedor y qué día llegan | La factura ya se cobró al pedir |
| `pallets` | Palets del proveedor, zorra, autoelevador, remito, `departed_day` | `departed_day` evita que el camión entregue dos veces lo mismo |

Por venir, cada uno en su tarea y con su prueba de ida y vuelta: `day_events` (el plan de mañana, sorteado al
cerrar, eventos-del-dia §2.2), `options` (los modificadores de dificultad, D-1919), máquinas y su contenido
(D-1116) y la estación de cada empleado (D-1016).

## 3. El stock al guardar

Un save de apertura no puede tener nada "en curso". Al guardar (D-0252), cada unidad queda en un lugar que
existe cuando se carga:

| Lugar en vivo | Al guardar | Por qué |
|---|---|---|
| `shelf:<id>`, `pallet:<id>`, `cart:<id>`, `dock` | Igual | Su estación o pieza se arma con el `layout` o con `pallets`. Los carritos vuelven a su lugar de `DefaultShed` con lo que llevaban |
| `hands:<peer>` | Al bulto de devolución | Ya pasa hoy (`stock_for_save`, a `floor:0`). D-0252 le da una posición |
| `floor:<n>` (bultos en el piso) | Al bulto de devolución | Las posiciones de `FloorBundles` no se guardan, así que un bulto cargado no se puede tomar |
| `box:<id>` (caja abierta en la mesa) | Al bulto de devolución | Las mesas no se guardan: el día siguiente arma cajas nuevas |
| `package:<id>` (caja cerrada sin despachar) | Al bulto de devolución, desarmada | El pedido de esa caja ya no existe al día siguiente, y una caja sin pedido no tiene a quién ir |
| Carga de un vehículo o de una salida | — | El resumen espera a que vuelvan todas las salidas (`trips_out() == 0`), así que al cierre no hay nada afuera. El corte a mitad de día no guarda (regla 2) |

**Las reservas quedan en 0 al guardar:** son de pedidos que al día siguiente ya no existen.

**El bulto de devolución** es un único `floor:0` que se guarda **con su posición**, en un punto fijo del galpón
al lado de las mesas (`CompanyTuning.RETURN_BUNDLE_SPOT`). Es un bulto normal: se toma de a una unidad y se lleva
al estante. No se cobra ni se pierde nada. El jugador que dejó una caja sin cerrar la encuentra desarmada en el
bulto a la mañana. Ordenarlo es trabajo de la apertura para los que cargan. Con 8 personas y un galpón de F2
puede ser mucho: D-0252 lo mide en el bot, y si hace falta se parte en un bulto por producto. Así el "Hecho cuando" de D-0252 se puede probar sin abrir el juego: después de cargar, ninguna
unidad del stock queda en un lugar sin estación.

## 4. Qué no se guarda, y de dónde sale al cargar

| Estado | Al abrir el día cargado |
|---|---|
| Libro de pedidos del día (`CompanyOrdersNet.book`, `planned_day`) | `CompanyDayOrders.plan` en `OPENING`, con la semilla del día, la tripulación, las zonas abiertas y la plata |
| Salidas (`CompanyTrips`, `Trip`, resultados) | Ninguna: al cierre no hay salidas afuera |
| Mesas de armado, cajas, `_serial`, `DeliveryPackage` | Vacías. `_new_box_id` saltea los ids que todavía tienen stock |
| Posiciones de los bultos del piso | Solo la del bulto de devolución (§3) |
| `CompanyNet.seq`, rids, ids de snapshot | Desde 0. Cada cliente que entra recibe un snapshot nuevo (D-2004), así que la numeración no tiene que seguir (ver §6) |
| Reloj: velocidad y pausa (`GameClock`, `CompanySoloPause`) | Velocidad normal y en marcha desde las 08:00 |
| Avisos y feed de pedidos, alertas de stock | El feed arranca vacío; las alertas se recalculan del stock |
| Lo que tiene cada uno en la mano (`held_tool`, portapapeles) | Nada en la mano (portapapeles §3: no va al save) |
| Interés de red y celdas del mapa | Se arman según dónde está la tripulación |
| Flags de desarrollo (`--money=`, `--company-day=`, D-0238) | Se aplican después de cargar y **pisan** lo guardado. Es a propósito: son para tests y capturas |

**Del jugador, no de la empresa.** Lo que aprende cada persona se guarda en su perfil (`unlock_profile`), no en el
slot: `seen_tips` (onboarding §4), las opciones y las teclas. Jugar en la empresa de otro marca los consejos que
uno ya vio, y la empresa propia no se entera de quién la jugó.

## 5. Orden con el cobro

Hoy nada paga en el juego: `OrderSettlement.settle` y `FixedCosts.settle` solo los llama
`tests/bot_company_day.gd`. **D-0251 tiene que estar antes que la tarea que enganche el cobro o el alquiler al
mundo**, o el agujero de la regla 2 se abre en el juego. La tarea que enganche el cobro lleva
`Depende de: D-0251`.

## 6. Cambios a otros documentos

- [red-autoridad.md](red-autoridad.md) §3: "guardar `seq` en el slot (D-0206)" queda tachado. Un mundo cargado
  arranca en `seq` 0, y todo cliente que entra lo hace por snapshot, así que no hay eventos viejos que
  numerar.
- [red-autoridad.md](red-autoridad.md) §7, §9 y §10: tampoco se guardan las posiciones de los bultos, las mesas,
  `_serial` ni el libro de pedidos (tachado, con el motivo).
- [riesgos.md](riesgos.md): R-03, la mitigación 2 se resuelve con "vuelve a su apertura" (D-0251) y las unidades
  varadas con D-0252. R-14: el `OrderBook` no se guarda, se vuelve a sortear. R-04: lo nuevo del save es el plan
  de eventos, no pedidos ni mesas.
- `revisar/D-0236.md`: lleva una nota de que salir a mitad de día ya no guarda "con lo hecho".
- Los comentarios de `company_save.gd` ("what happened after it is kept") los corrige D-0251.

## 7. Qué se pierde y por qué está bien

- **Salir sin cerrar pierde el día entero.** Un día dura 12 h de juego × 90 s, unos 18 minutos reales, y con
  varias personas eso pesa. Por eso existe el cierre anticipado (regla 2, D-0253): quien tiene que irse a los 15
  minutos le pide al host que cierre, y lo hecho queda. Guardar el día a la mitad (pedidos, mesas, `_serial`,
  posiciones, salidas en la ruta) cuesta un formato nuevo por cada sistema y un test de ida y vuelta para cada
  uno. Eso queda para después de F1, y solo si las pruebas muestran que el cierre anticipado no alcanza.
- **Un día malo se puede repetir.** Salir a las 19:59, antes del cobro, vuelve a la apertura. Eso le saca peso a
  la quiebra y a las penalidades. Se acepta, como el reintento de nivel de *Overcooked*: es un juego coop para
  pasarla bien, la semilla da los mismos pedidos (no se puede "buscar" un día fácil) y repetirlo cuesta los 18
  minutos. Si en las pruebas se abusa, se cuentan los días cortados en el slot y se cobran en reputación.
- **Lo pedido o comprado en el día cortado también se pierde.** Eso incluye pedidos al proveedor, compras de la
  tienda y piezas puestas. Es parejo: la plata que se gastó en eso vuelve con la apertura.
- **Matar el proceso** ya vuelve al último cierre (D-0236), y con D-0251 no hay diferencia entre salir bien y
  salir mal.
