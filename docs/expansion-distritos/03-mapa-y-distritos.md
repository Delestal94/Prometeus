# Grupo 03 — Mapa del mundo, viajes y sistema de distritos

> Fase **F1** (núcleo) / F2 · Dueño: Nacho · Depende de: D-0104, D-0205, D-0214, D-0216.
> El sistema que lleva de "el galpón" a "un distrito" y vuelve. El contenido de cada distrito está en
> los grupos 13-17.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0301 | ✅ Flujo galpón → distrito → galpón según D-0104 (carga, viaje, regreso con resultados) — **en `detalle/` es: Boceto del mapa del mundo** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-mundo | xhigh | bot sale con la camioneta, entrega en Barrio Centro y vuelve al galpón sin errores |
| ✅ D-0302 | Portón de salida del galpón como punto de partida (reemplaza el arranque de la entrega actual) | constructor-mundo | high | la camioneta cargada sale por el portón y dispara la carga del distrito |
| D-0303 | Pantalla/tablero de despacho: elegir distrito, vehículo y pedidos que salen — **en `detalle/` es: Módulo `world_cells`: cargar el mapa por celdas** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-ui | high | test de UI: elegir y confirmar con mando y teclado |
| D-0304 | ✅ Generación de ruta por distrito: `RouteStreamer` con conjunto de tramos y decorado del distrito — **en `detalle/` es: Grafo de calles y tramos sobre aristas** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-tramos | xhigh | Barrio Centro y Campo generan rutas distintas con la misma semilla; `route_golden` por distrito |
| D-0305 | ✅ Varias paradas en una salida (entregar 3-6 pedidos en distintas casas antes de volver) | constructor-tramos | xhigh | ruta con N casas; test entrega las N |
| D-0306 | ◐ (el recurso, el nodo y los modelos están; falta D-0306.b: poner los `WorldGate` en el mundo de la empresa, hoy nada cierra Campo ni Suburbio en el juego) Orden de paradas: el jugador elige o lo sugiere el GPS — **en `detalle/` es: Bloqueos (`GateRequirement`)** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-camion | high | GPS muestra la próxima parada; test cambia el orden |
| D-0307 | ◐ (la regla de la grúa está, `TripTow`; falta D-0307.1: pedirla y verla en el juego; ver detalle) Volver al galpón manejando, con la opción de volver con grúa | constructor-mundo | medium | `test_company_tow_home` pasa (ya pasa) y D-0307.1 está cerrada |
| D-0308 | ✅ Bloqueo de distrito: no se puede despachar a un distrito bloqueado y se explica por qué — **en `detalle/` es: GPS y navegación por el grafo** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-progresion | medium | test: despacho rechazado con motivo |
| D-0309 | ✅ Requisito de vehículo por distrito (la lancha solo sale al agua, etc.) | constructor-progresion | medium | test: combinación inválida rechazada |
| D-0310 | ◐ (panel, estación y tablero con datos reales hechos; faltan D-0310.c, D-0310.d y D-0310.e, la captura) Tablero de despacho: la estación `dispatch` del galpón lista las cajas listas y el vehículo, y "Cargar" las sube (incluye D-0327, fusión de D-0112) | constructor-ui | high | `test_company_dispatch_panel` pasa y una captura de `revisor-visual` es legible a 1080p |
| D-0311 | ✅ Casas de entrega por distrito con `DeliveryHouse` y variantes (puerta, buzón, muelle, porche) (incluye D-0247, fusión de D-0112) | constructor-mundo | high | 4 variantes funcionan con el flujo de puerta actual |
| D-0312 | ✅ Direcciones: cada casa tiene calle y número legibles que coinciden con la etiqueta del paquete (incluye D-0326, D-0345, fusión de D-0112); quedan D-0312.1 y D-0312.2 (el cartel de calle en las esquinas), fuera de la lista del corte | constructor-mundo | medium | test: etiqueta y cartel de la casa coinciden |
| D-0313 | ✅ Cargar el distrito con la pantalla de carga existente sin congelar (N-408) — **en `detalle/` es: Arranque sin congelar y streaming sin tirones** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-mundo | high | `test_loading_no_freeze` pasa con el distrito |
| D-0314 | ◐ (D-0314.a hecha: Centro en gris está en el mundo; falta D-0314.b: que el bot entregue ahí, con D-2016.4, y las 3 capturas) Barrio Centro jugable en gris | constructor-mundo | high | `bot_company_day` entrega en Centro y `revisor-visual` manda 3 capturas sin agujeros en el piso ni casas flotando |
| D-0315 | ◐ **Pasó a F2 (revisión D-0140): Campo no entra al corte F1 y esta fila no se toma hasta que D-2016 lo cierre.** Lo hecho queda; falta D-0315.b (los eventos del Campo en el mundo y la entrega del bot ahí; ver detalle) Adaptar la ruta actual (Campo) como distrito con la misma calidad de hoy | constructor-tramos | high | tests de ruta actuales verdes en modo Empresa |
| D-0316 | ✅ Seguro contra jugadores perdidos: quien se queda en el galpón no se carga ni sufre la ruta | constructor-red | xhigh | test de red: 2 en ruta, 1 en galpón, nadie se teletransporta |
| ~~D-0317~~ | ~~Jugadores en distintos distritos a la vez (dos vehículos fuera) — sí/no por rendimiento~~ **Fusionada en D-2002 (D-0112, [crítica](diseno/critica-alcance.md))** | Plan | high | decisión con medición de costo; si sí, D-0318 |
| D-0318 | ✅ (Si D-0317 sí) varias instancias de distrito cargadas a la vez con capas de física separadas — **en `detalle/` es: Física lejos del jugador** (el título de esta fila es de antes del mapa continuo; manda el detalle) | constructor-red | xhigh | test de red con 2 vehículos en 2 distritos |
| D-0319 | ✅ Tiempo del viaje cuenta en el reloj del día | constructor-progresion | medium | test: ruta de 5 min avanza 1 h de juego (según D-0105) |
| D-0320 | ◐ (la lógica y su test están; falta D-0320.b: nadie llama a `TripResult` en el juego, así que una salida que vuelve no deja resumen ni mérito) Recompensa y resultado por salida (lo que se cobró, lo que se rompió) entra al cierre del día | constructor-progresion | high | resultados de la salida en `CompanyState` (test) |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| ~~D-0321~~ | ~~Atajos entre distritos (túnel, ferry, puente) que se desbloquean~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-tramos | high | atajo baja el largo de ruta medido |
| ~~D-0322~~ | ~~Puntos de interés por distrito (mirador, kiosco, estación de servicio) con efecto chico~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-mundo | medium | 3 por distrito colocados por semilla |
| ~~D-0323~~ | ~~Estación de servicio: cargar combustible (si D-0505 activa combustible)~~ **Recortada (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-camion | medium | test: tanque baja y se carga |
| D-0324 | Clima por distrito con `WorldMood` (perfiles nuevos), según [distritos.md](diseno/distritos.md#clima-y-temperatura-por-zona-d-0135) | constructor-mundo | high | perfil por distrito; captura de cada uno |
| D-0325 | Hora del día real en el distrito (salir de noche se ve de noche) | constructor-mundo | medium | test: hora del reloj → mood |
| ~~D-0326~~ | ~~Carteles de dirección por distrito con nombres de calles generados~~ **Fusionada en D-0312 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-mundo | medium | carteles legibles en captura |
| ~~D-0327~~ | ~~GPS con varias paradas y ruta sugerida dibujada en el tablero~~ **Fusionada en D-0310 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-camion | high | captura con 3 paradas |
| D-0328 | Desvíos: calle cortada que obliga a otra ruta (incluye D-1521, fusión de D-0112) | constructor-tramos | high | test: ruta alternativa existe y se toma |
| ~~D-0329~~ | ~~Puntos de recogida (devoluciones): buscar un paquete en una casa y traerlo~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | high | pedido de devolución completo en test |
| ~~D-0330~~ | ~~Hub secundarios: mini-depósito en Puerto y en Montaña para salir más cerca~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-mundo | high | despacho desde hub secundario funciona |
| ~~D-0331~~ | ~~Vista de mapa en el celular del jugador (ya existe el celular)~~ **Fusionada en D-1923 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-ui | medium | celular abre el mapa del distrito |
| D-0332 | Marcadores de ping del mapa compartidos entre jugadores (incluye D-1937, fusión de D-0112) | constructor-red | medium | ping visible en todos los clientes (test de red) |
| ~~D-0333~~ | ~~Zonas peatonales donde solo entran bici o carrito~~ **Fusionada en D-1507 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-tramos | medium | camioneta no puede entrar; bici sí (test) |
| ~~D-0334~~ | ~~Peajes y estacionamiento (costo chico, decisión de ruta)~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | low | cobro en test |
| ~~D-0335~~ | ~~Distrito "evento" temporal (feria, recital) con pedidos especiales~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | medium | se activa por calendario en sim |
| ~~D-0336~~ | ~~Viaje rápido pagando (taxi de carga) para saltar trayectos repetidos~~ **Recortada (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | low | opción del despacho funciona |
| D-0337 | Rutas con dos caminos (rápido y peligroso vs. lento y seguro) | constructor-tramos | high | bifurcación en 2 distritos |
| ~~D-0338~~ | ~~Persistencia del distrito (casas ya visitadas, clientes conocidos)~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | medium | se guarda y carga |
| ~~D-0339~~ | ~~Clientes que esperan afuera o salen a recibir (animación existente de casa)~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-mundo | medium | variantes por distrito |
| D-0340 | **Es del cierre de F1** ([corte vertical](diseno/corte-vertical.md) §2 #13 y D-2016.4; detalle en [F1-03-distritos.md](detalle/F1-03-distritos.md)): va antes que el resto de este bloque. Puerta del cliente revisa contenido contra el pedido (no solo daño) | constructor-trampas | high | test: producto faltante baja la paga ; la puerta llama `OrderSettlement.settle` con `CompanyTrips.delivery_minute()` (D-0851) y publica `order_delivered` (D-0815.b): fuera de `tests/` hay ≥ 1 llamada a `settle`. Depende de D-0254 (revisión D-0140) |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| ~~D-0341~~ | ~~Transición visual galpón → distrito (portón que se abre, fundido)~~ **Recortada (D-0112, [crítica](diseno/critica-alcance.md))** | artista-vfx | medium | captura de la transición |
| D-0342 | Nombres de distrito al entrar (cartel grande de bienvenida) | constructor-ui | low | cartel traducible |
| ~~D-0343~~ | ~~Música que cambia por distrito~~ **Fusionada en D-1929 (D-0112, [crítica](diseno/critica-alcance.md))** | disenador-audio | medium | crossfade sin cortes |
| ~~D-0344~~ | ~~Mapa del mundo con estilo de mapa de papel en el tablero~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | artista-conceptual* | medium | textura integrada en el tablero |
| ~~D-0345~~ | ~~Nombres de calles graciosos/localizados por distrito~~ **Fusionada en D-0312 (D-0112, [crítica](diseno/critica-alcance.md))** | documentador | low | lista traducible de 200 nombres |
| D-0346 | Revisar que ninguna ruta de distrito pase de 5 minutos (regla de oro N-102) | probador-qa | medium | bot mide todas las rutas |
| D-0347 | Revisar la legibilidad de las direcciones a distancia y de noche | revisor-visual | low | captura nocturna legible |
| D-0348 | Ícono por distrito para UI | artista-conceptual* | low | 9 íconos en `assets/ui/` |
| D-0349 | Auditoría de red del flujo de distritos | auditor-red | high | sin hallazgos P0-P1 |
| D-0350 | Test de humo de todos los distritos (cargar, entregar 1, volver) (incluye D-1350, D-1550, D-1650, D-1750, fusión de D-0112) | escritor-tests | high | `test_district_smoke` en CI |
