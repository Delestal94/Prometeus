# Revisión del diseño de la expansión "modo Empresa" (D-0140)

> Pasada de `abogado-del-diablo` (2026-10-22) sobre el diseño completo (D-0101 a D-0139), contrastado con el código de
> `origin/main`, las tablas de grupo, `detalle/`, `revisar/` y `docs/marketing/`. No repite los recortes de D-0112
> ([critica-alcance.md](critica-alcance.md) §4, 287 IDs): ataca lo que quedó en pie. Respeta la fila 5 de
> [decisiones delegadas](../../decisiones/2026-10-04-expansion-decisiones-delegadas.md): cuando algo nombrado por el
> usuario sale caro, la propuesta cambia **cómo** se hace y nunca lo saca. Qué se aplicó y qué no: §10.
> Decisión: [2026-10-22-revision-diseno](../../decisiones/2026-10-22-revision-diseno.md).

## 1. Resumen

**Veredicto: el diseño está bien pensado, pero F1 no está cerrado aunque los papeles digan que casi.** El bot da
`BOT_OK` porque él mismo hace de puerta del cliente. La promesa central ("lo que armás es lo que sufrís") hoy existe
solo como metadato. Y la compuerta de fases de las rutinas se abrió con un documento, no con una medición.

- **La puerta no cobra y el alquiler no se descuenta en el juego.** `OrderSettlement.settle` y `FixedCosts.settle`
  solo se llaman desde `tests/` (verificado: 0 llamadas en `scripts/`). `bot_company_day` llama
  `OrderSettlement.settle` por su cuenta y termina en `BOT_OK`. Choca con [corte-vertical.md](corte-vertical.md) §4:
  el corte no se cierra con stubs.
- **La intensidad de la trampa no la lee nadie.** `BoxToPackage` y `CompanyPackages` escriben `META_TRAP_PLAN` y
  `META_LOOSE_BOX` (`box_to_package.gd:52-54`, `company_packages.gd:134`) y ningún comportamiento de trampa los
  consulta (verificado). El armado solo cambia `impact_absorption`. D-0710 estaba ✅ con un test que mira el plan, no
  el viaje.
- **Se construyeron 12 tareas F2 con F1 abierto** (D-0616, D-0617, D-0621, D-0721, D-0723, D-0726, D-0727, D-0729,
  D-0731, D-0732, D-0734, D-0931; están en `detalle/F2-*.md`). La causa: `.claude/rutinas/desarrollador.md` §2 decía
  "F0 y F1 hasta que D-0111 esté `[x]`", y D-0111 es la tarea que **escribe** el corte, ✅ desde F0. La regla del
  README ("no se arranca F2 sin F1 cerrado y medido") nunca frenó nada.

## 2. Contradicciones entre documentos

| # | Doc A dice | Doc B dice | Qué se hace |
|---|---|---|---|
| C1 | `corte-vertical.md` §2 #12: Campo abierto en F1 desde el día 1 | `README.md` (fases), `vision.md`, `mapa.md`: Campo es F2, detrás de reputación 60; `hitos.md` lo reconoce como "F1 abierto, F2 cerrado" | **Aplicado:** F1 = solo Centro (I3) |
| C2 | `README.md`: "vidrio sin burbuja **es** Frágil" (el armado elige la trampa) | `armado-y-trampas.md` y `vision.md`: "el armado **no cambia qué trampa es**, cambia cuánto pega" | Corregir el README (la página y el tráiler copian esa frase) |
| C3 | `roles-tripulacion.md`: la regla de 2 min es "sin caja ni volante"; `portapapeles.md`: el portapapeles cuenta como "sin caja" | `onboarding.md`: "ninguno pasa 120 s **sin línea guía** ni caja" | Unificar en "sin caja ni volante" |
| C4 | `roles-tripulacion.md` §6.2 (ayuda 2): con 1 jugador el último pedido entra a las 15:00 porque "a las 20:00 del mundo el galpón marca ~14:00" | La misma cuenta en `clientes.md` | La hora 14-15 sigue sin entrar nunca: la ayuda no tapa el hueco que la justifica (§4, roles) |
| C5 | `distritos.md`: Centro admite "bici, camioneta" | `distritos.md` (tabla de vehículos): además carrito y 4x4; `data/zones/centro.tres`: `bike` y `van` | Alinear la tabla con el `.tres` |
| C6 | `glosario.md`: el autoelevador es "solo el del depósito de Partida rápida" | `corte-vertical.md`, D-0606 y `2026-10-22-autoelevador-en-el-mundo.md`: hay autoelevador en el galpón | Corregir el glosario (lo usa `test_ui_translations`) |
| C7 | `glosario.md`: "permiso" es término descartado | `hitos.md`: `permit_suburbio`, "Permiso de Suburbio" | Si sobrevive (§4, hitos), que se llame licencia |
| C8 | `glosario.md`: el recurso es `DistrictDefinition` | Código y `distritos.md`: `ZoneDefinition` | Texto |
| C9 | `narrativa-empresa.md`: "montaña (4x4)" | `2026-10-04-mapa-continuo.md`: Montaña se alcanza en avioneta | Texto |
| C10 | `eventos-del-dia.md`: seis eventos rotulados "Núcleo · F1" | `corte-vertical.md` §2 (sin eventos) y el mismo documento: "no entra al corte" | Renombrar "Núcleo" como "primera tanda", post-corte (D-0551) |
| C11 | `eventos-del-dia.md`, riesgo 5: roles §1 describe distinto el reloj de pedidos | `roles-tripulacion.md` ya dice "entran y vencen con la hora del galpón" (D-0813.1) | Riesgo vencido: borrarlo |
| C12 | `critica-alcance.md` R4: una zona cerrada un día entero es un fallo sin decisión (por eso se recortaron D-1338 y D-1629) | `17-volcan.md`: D-1716 "Erupción programada… cierra zonas" | **Aplicado:** D-1716 no cierra zonas |
| C13 | `2026-10-04-mapa-continuo.md`: trazado fijo; por semilla solo casas, decorado, eventos y clima | D-1310 (xhigh) "archipiélago por semilla"; D-1601 y D-1701 "ruta generada" | **Aplicado** en las tablas 13, 16 y 17 |
| C14 | `corte-vertical.md` y `detalle/F0-20-red-y-ci.md`: D-2016 es el bot `bot_company_day` | Tabla del grupo 20: D-2016 es "Recorrido de QA… guion" | **Aplicado:** la fila dice lo mismo que el detalle |
| C15 | `hitos.md`: ningún proveedor baja el costo más del 10 % | `data/suppliers/importadora_express.tres`: `price_factor = 0.85` | Ver I5 |
| C16 | `flota.md`: bici, licencia "ninguna" | `hitos.md`: la bici sale con `reputation_55` (`flota.md` lo admite al pie) | Texto |

**Erratas que la crítica anterior pidió arreglar.** `critica-alcance.md` pedía tres correcciones en
`corte-vertical.md`: D-0217 → D-0213 era real (**aplicada**); "D-0306 es el GPS" y "`test_company_cells` es de
D-0313" eran falsas. En `detalle/F1-03-distritos.md` D-0306 es "Bloqueos (`GateRequirement`)" y D-0303 es "Módulo
`world_cells`" (con `test_company_cells`). La crítica leyó la tabla `03-mapa-y-distritos.md`, que tiene títulos de
antes del mapa continuo (D-0301, D-0303, D-0304, D-0306, D-0308, D-0313, D-0318). **Aplicado:** cada una de esas filas
nombra ahora el título del detalle y dice que manda el detalle.

## 3. Diseño que la implementación ya contradice o dejó atrás

| # | El diseño dice | El código hace | Evidencia |
|---|---|---|---|
| I1 | La puerta cobra al entregar (`2026-10-22-cobro-al-entregar.md`, D-0815 ✅) y el cierre cobra el alquiler (D-0509 ✅) | Nadie cobra en el juego | 0 llamadas a `settle` en `scripts/`. `guardado.md` §5 ya lo avisaba. Es el "nada se usa en una escena" de las auditorías del 10-12 y 10-19, que **empeoró**: ahora el bot lo tapa |
| I2 | La intensidad sale de `Q` y cambia el viaje (`armado-y-trampas.md` §5; la promesa de `vision.md`) | Solo pesa `impact_absorption`; el nivel y la Equilibrio extra quedan en metadatos que nadie lee | `box_trap.gd`, `box_to_package.gd`. En gallina, cachorro, masa madre y mapache, armar bien o mal no cambia la ruta |
| I3 | Campo abierto en F1 | Campo cerrado y sin forma de abrirlo: no hay hitos (grupo 04 sin ✅) | `data/zones/campo.tres` (`gates = [gate_campo_obra]`), `data/gates/gate_campo_obra.tres` (`reputation_60`). La curva de `economia.md` (envío 50, mitad Campo) no es la que se juega (40) |
| I4 | No arrancar F2 sin F1 cerrado | 12 tareas F2 hechas o a medias, incluido pulido en gris: D-0606.c3 (motor, hidráulica, baliza del autoelevador), D-0731, D-0732, D-0816.b | `detalle/F2-*.md`; compuerta de `desarrollador.md` §2 |
| I5 | Proveedores extra como recompensa de hito y 1 solo proveedor en F1 | Cinco proveedores con otros ids, sin hito que los habilite, uno con −15 % | `data/suppliers/*.tres`; D-0621 es de `detalle/F2-06-stock.md` |
| I6 | El galpón congelado no castiga a nadie (fila 4 de las decisiones delegadas; `vision.md`) | "a frozen shed costs day time instead of being free" | `day_cycle.gd`. De ahí salen dos relojes, el `lag`, la ayuda 2 del modo solo, la regla 4 de clientes y `SOLO_ORDER_LAST_ARRIVAL_MIN` |
| I7 | `riesgos.md` R-16: `CompanyNet` cerca del tope, P2 | `company_net.gd` 999 líneas y `company_root.gd` 1000, con `max-file-lines: 1000` | **Aplicado:** R-16 → P1 y tarea D-0254 |
| I8 | El bot del corte con 2 jugadores, 6 cajas y ganancia > 0 | Un solo host, arma **una** caja, no mide la regla de 2 min ni el alquiler, salta el reloj a las 20:00 | Encabezado de `tests/bot_company_day.gd` ("None of that is replicated to clients yet"). **Aplicado:** D-2016.4 y R-17 |
| I9 | Revisión del 10-19 (`auditorias/2026-10-19-revision.md`): insumos infinitos en F1, borrar la balanza D-0713, nada del grupo 09 hasta cerrar el corte | Se construyeron D-0718, D-0713, D-0931.a y D-0948 | Las recomendaciones se ignoraron porque la compuerta (I4) las dejaba pasar |

## 4. Lista por documento o sistema

- **corte-vertical.md — REHACER §2 #12 y §4.** El criterio de cierre daba verde sin puerta, sin alquiler, con 1 caja
  y sin red; medir Campo suma D-0315.b y el riesgo R-07 sin aportar. **Aplicado:** F1 = solo Centro; §4 pide que la
  puerta del mundo cobre, 6 cajas, alquiler cobrado por el juego y ningún tramo > 120 s sin caja ni volante; el
  chequeo de frames es "galpón a la última casa de Centro"; cada stub imprime `BOT_STUB` y bloquea `BOT_OK`.
- **Compuerta de las rutinas — REHACER.** **Aplicado:** F2 se ata a D-2016 `[x]` (con .3 y .4), no a D-0111. Sin
  esto entran tareas F2 fáciles y quedan sin dueño las F1 difíciles: D-0304 ◐, D-0314, D-1501, D-0340, D-2011 a
  D-2013 y D-2017.
- **armado-y-trampas.md — MANTENER el documento, REHACER la implementación de D-0710.** Alternativa barata: cada
  trampa ya tiene dificultad 1-4 en su `.tres`; el nivel low/mid/high elige la variante que el comportamiento ya sabe
  ejecutar, y la caja floja suma Equilibrio con el mismo mecanismo de "trampa extra" del ×1,5 de flota. Si no se
  hace, el plano E1 del tráiler funciona (Frágil usa la absorción) pero en 6 de 10 productos la promesa es falsa.
  **Aplicado:** D-0710 ◐ con D-0710.b.
- **roles-tripulacion.md (incluido §6, modo solo) — SIMPLIFICAR los relojes.** Propuesta: los pedidos **entran** por
  la hora del mundo y **vencen** por la del galpón; el solitario vuelve y encuentra los pedidos de la tarde
  esperando, y la ayuda 2 y `SOLO_ORDER_LAST_ARRIVAL_MIN` sobran. **Hueco no mencionado:** con 2 o 3 jugadores las
  tablas mandan al conductor **solo** con cajas que nadie cuida; el asistente de estante solo se activa con
  exactamente 1 jugador (`package_rescue.gd`, grupo `player`) y la regla de 2 min no lo ve porque manejar cuenta como
  ocupado. Propuesta: medir "% de cajas entregadas con un cuidador en la mano" y decidir si `solo_assist` cuenta
  jugadores en el vehículo. **No aplicado** (borra código hecho: va en un PR propio, §10).
- **economia.md — MANTENER, con un ajuste:** la curva supone envío 50 y en F1 es 40. D-0540 (`sim_economy`) es la
  única validación de hitos, licencias, eventos y precios de flota: debería ser lo primero después del corte.
- **flota.md — MANTENER.** La regla ×1,5 depende de D-0710.b. Corregir C16.
- **mapa.md — MANTENER.**
- **distritos.md — SIMPLIFICAR la sección de clima** (85 líneas de multiplicadores para efectos de altura de F3-F4).
  D-0324 queda en "un clima por día para el llano, lluvia = agarre ×0,75"; el resto se escribe cuando exista la zona
  (D-1610, D-1617, D-1715). Corregir C5.
- **clientes.md — MANTENER.** Tapa un agujero real (pedidos eternos). D-0851 tiene que entrar al corte: sin él, el día
  2 arrastra pedidos del día 1 que nunca vencen.
- **portapapeles.md — SIMPLIFICAR (posponer a F2, no recortar).** D-1902 es xhigh (replica `held_tool`, sube
  `PROTOCOL_VERSION`, toca `player.tscn` de Slatex). En F1 las dos hojas ya tienen tablero en la pared
  (`StockBoard`, `SupplierBoard`). Moverla a F2 junto con D-1004. **No aplicado** (posposición: PR propio).
- **guardado.md — MANTENER.** Su §5 ("la tarea que enganche el cobro lleva `Depende de: D-0251`") quedó sin dueño:
  ahora lo tienen D-0340 y D-0509.b.
- **red-autoridad.md — SIMPLIFICAR el formato.** 671 líneas; desde §5 es bitácora ("Lo construido (D-2003)"…). Dejar
  §1-§4 (el contrato) y pasar el resto al encabezado de cada script o a `revisar/`.
- **hitos.md (y licencias D-0124) — SIMPLIFICAR; los desbloqueos por hitos se quedan (fila 5).**
  1. Licencias como compra aparte: hasta tres compras por vehículo, y `license_4x4` "no abre nada por sí sola".
     Alternativa: el hito **ofrece el vehículo** y el bloqueo pide el hito o el vehículo.
  2. `permit_suburbio` (1 200) existe "para que cuadre la curva": subir el hito a ~30 entregas logra lo mismo.
  3. Campaña de 87 días jugando solo (~26 h; Montaña hacia el día 60): lo más caro que nombró el usuario lo va a ver
     una fracción mínima de los jugadores. **Aplicado:** D-0441 pide ≤ 40 días con 1 jugador.
  Los puntos 1 y 2 **no se aplican** aquí (cambian ítems de la tienda: PR propio, §10).
- **dificultad.md — MANTENER.** Ojo: `calm_days` apaga un sistema que no tiene tarea (ahora D-0551).
- **onboarding.md — MANTENER.** Corregir C3.
- **eventos-del-dia.md — SIMPLIFICAR.** 511 líneas, 15 eventos y 0 tareas. **Aplicado:** D-0551, solo la tanda mínima
  que el mismo documento propone (marco + `supplier_late`, `supplier_gift`, `shed_inspection`), en F2. Los otros 12
  quedan escritos y sin tarea hasta que lo pida el playtesting.
- **narrativa-empresa.md — MANTENER.** Corregir C9.
- **cosmeticos-empresa.md — MANTENER y congelar** hasta que se tome D-0437.
- **riesgos.md — MANTENER y corregir severidades.** **Aplicado:** R-16 → P1 y R-17 nuevo.
- **glosario.md — MANTENER.** Corregir C6, C7 y C8 antes de que `localizador` genere claves.
- **reutilizacion.md — MANTENER.**
- **catalogo-productos.md — MANTENER el contenido y ordenar el arte:** la cola de la PC (D-1802 a D-1805) sigue el
  orden de apertura de zonas; Nieve y Volcán al final.
- **Grupos 13, 16 y 17 — SIMPLIFICAR cómo, nunca qué.** **Aplicado:** D-1310 "islas fijas; casas y muelles por
  semilla" (xhigh → high); D-1601 y D-1701 sobre aristas del grafo fijo; D-1716 sin cerrar zonas. Para la avioneta
  (D-1401, D-1411): un solo terreno lejano horneado y un corredor asistido de vuelo (despegue, aterrizaje y
  lanzamiento son lo jugable) bajarían D-1401 a high sin perder el paracaídas (D-1420) ni el copiloto (D-1421):
  queda como propuesta para cuando se detalle el grupo 14.

## 5. Riesgos del corte vertical F1

1. **La medición miente (P0).** `BOT_OK` sale con la puerta, el alquiler, el manejo hasta las casas y la red simulados
   (I1, I8). `docs/marketing/expansion-pagina-y-trailer.md` ya lo lee como "código casi entero" y pone "✅ en código"
   a "la caja define cuánto pega", que es falso según I2. → D-2016.4, R-17.
2. **La compuerta abierta (P0).** → corregida en `desarrollador.md` §2.
3. **Tope de líneas (P1).** Enchufar la puerta, el cobro, el alquiler y el despacho pasa por `company_root.gd` o
   `company_net.gd`; sin extracción previa el lint rechaza cada PR. → D-0254.
4. **Red sin probar (P1).** El bot corre solo en el host; D-2017 va a ser la primera vez que armado, despacho y puerta
   pasen por peers, y es lo más probable de traer retrabajo xhigh. → criterio nuevo de D-2017.
5. **Campo en el criterio (P1).** → sacado del corte.
6. **El modo solo sin medir.** El bot no tiene corrida de 1 jugador que mida la regla de 2 min. → D-2016.4.
7. **La pila de `revisar/`.** 223 archivos de "probar a mano / decidir al final". Si el corte se cierra sin pasar por
   los de F1, el playtesting diferido se traga semanas en marzo, donde `critica-alcance.md` no deja margen.

## 6. Lo que sobra o se pule de más

- **Documentos que nadie consume todavía:** `eventos-del-dia.md` (511 líneas, 0 tareas hasta D-0551),
  `cosmeticos-empresa.md`, `marketing/logros-expansion.md` (30 logros sin AppID ni hitos) y el clima de altura de
  `distritos.md`.
- **Documentos que crecen como bitácora:** `red-autoridad.md` §5-§15, `riesgos.md` y los "Parcial (fecha, PR
  pendiente)" de `detalle/` que repiten el commit en prosa.
- **Tablas que mentían:** títulos del grupo 03, D-2016 en el grupo 20, D-0416 a D-0418 con hitos viejos (**aplicado**:
  remiten a `hitos.md`).
- **Reglas sin tarea:** `VEHICLE_TRAP_AMPLIFY` (`flota.md`) no existe en `company_tuning.gd`; "ningún proveedor baja
  más del 10 %" ya se violó; "una sola regla del cierre como el alquiler" sobre un alquiler que no se cobraba.
- **Pulido en gris con F1 abierto:** D-0606.c3, D-0731, D-0732, D-0816.b y D-0723. Nada de eso aparece en una captura
  hasta el arte de F5.
- **"✅ con enchufe pendiente":** D-0815, D-0816 y D-0817 están ✅ con su `.b` de la puerta abierta. Es el mismo
  defecto que A-D.3 (`auditorias/2026-10-19-integral.md`) y empeoró: el ✅ se pone por la función pura.

## 7. Tareas ajustadas

Tipo: **T** = texto, criterio o dependencia; **R** = recorte o posposición de feature (PR propio, regla 3 de
`.claude/rutinas/README.md`); **N** = tarea nueva.

| ID | Cambio | Tipo | Estado |
|---|---|---|---|
| `desarrollador.md` §2 | F2 se ata a D-2016 `[x]` con D-2016.3 y D-2016.4; las de `detalle/F2-*` no se toman antes | T | aplicado |
| D-2016 | D-2016.4: puerta del mundo, 6 cajas, alquiler del juego, tramo ≤ 120 s, `--players=1`, `BOT_STUB` bloquea `BOT_OK`; fila del grupo 20 corregida | T | aplicado |
| D-0340 | "Hecho cuando" suma la llamada a `OrderSettlement.settle` y `order_delivered` (D-0815.b); depende de D-0254 | T | aplicado |
| D-0509.b | El cierre del host cobra el alquiler (`FixedCosts.settle` en `company_day_closing`) | N | aplicado (subtarea; D-0509 ◐) |
| D-0254 | Partir `company_root.gd` y `company_net.gd` antes de enganchar puerta y cobro | N | aplicado (grupo 02) |
| D-0710.b | Las trampas leen `trap_plan.level` y la caja floja suma Equilibrio; `sim_trap_balance` como criterio | N | aplicado (subtarea; D-0710 ◐) |
| D-0315 / corte | Campo fuera de F1; D-0315.b a F2; chequeo de frames en Centro; errata D-0217 → D-0213 | T | aplicado |
| D-2017 | Armado, despacho y puerta con el actor en un cliente | T | aplicado |
| D-0441 | Bot de 1 jugador termina la campaña en ≤ 40 días; pasa por `critico-diseno` antes de tocar `.tres` | T | aplicado |
| D-1310, D-1601, D-1701, D-1716 | Trazado fijo; D-1310 a high; la erupción no cierra zonas | T | aplicado |
| Tablas 03 y 04 | Títulos viejos remiten al detalle y a `hitos.md` | T | aplicado |
| D-0551 | Eventos del día, primera tanda (3 eventos), F2 | N | aplicado (grupo 05) |
| D-0151, D-0813.1 | Pedidos entran por hora del mundo y vencen por la del galpón; se va la ayuda 2 y `SOLO_ORDER_LAST_ARRIVAL_MIN` | R | **pendiente** (borra código hecho) |
| D-0407, D-0404 | Sin `license_*` ni `permit_suburbio`: el hito ofrece el vehículo; Suburbio con ~30 entregas | R | **pendiente** |
| D-1902 | Pasa a F2 con D-1004; en F1 bastan los tableros de la pared | R | **pendiente** |

## 8. Top 3 por mejora del juego por día de trabajo

1. **La compuerta y D-2016.4** (≈ 1 día): frena las fugas a F2 y convierte `BOT_OK` en verdad.
2. **D-0710.b** (2-3 días): es la frase de `vision.md`, el plano E1 del tráiler y lo que distingue la expansión de un
   tycoon de cajas.
3. **D-0254 + D-0340 + D-0815.b + D-0509.b** (3-4 días): el día del juego real cierra con plata y F1 se puede declarar
   cerrado.

## 9. Preguntas que el informe dejó abiertas y cómo se decidieron

Regla 3 de las rutinas: nadie contesta, la rutina decide con su recomendación. Ninguna es de plata, cuentas ni
licencias, así que no abren issue `decide-usuario`.

1. **Duración de la campaña** (~26 h hoy hasta el Volcán jugando solo). Decisión: objetivo ≤ 40 días con 1 jugador en
   D-0441; el número final lo mide el bot y lo revisa `critico-diseno`.
2. **Dúo y trío: el conductor que sale solo con cajas sin cuidar.** Decisión: se mide antes de cambiar nada (métrica
   de §4, roles); queda en [revisar/D-0140.md](../revisar/D-0140.md) "Decidir al final".
3. **F1 solo con Centro.** Decisión: sí; Campo llega con su hito en F2 (ya es lo que hace el código).
4. **Licencias como papel que se compra.** Decisión: se simplifican en un PR propio (R de §7); los desbloqueos por
   hito no se tocan.
5. **El trabajo F2 ya hecho** (cinco proveedores, frío, regalo, multi-caja). Decisión: queda apagado detrás de los
   hitos hasta F2; no entra a la curva de F1.

## 10. Qué aplicó el PR de D-0140

Las filas T y N de §7 (marcadas "aplicado"). Las R quedan como propuestas para un PR propio cada una (regla 3: un
recorte o posposición se tiene que poder revertir entero); las toma el carril dueño del grupo. Las contradicciones de
texto C2, C3, C5-C9, C11 y C16 quedan para `documentador` en el mantenimiento de los jueves.
