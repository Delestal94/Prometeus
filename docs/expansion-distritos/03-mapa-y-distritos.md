# Grupo 03 — Mapa del mundo, viajes y sistema de distritos

> Fase **F1** (núcleo) / F2 · Dueño: Nacho · Depende de: D-0104, D-0205, D-0214, D-0216.
> El sistema que lleva de "el galpón" a "un distrito" y vuelve. El contenido de cada distrito está en
> los grupos 13-17.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0301 | ✅ Flujo galpón → distrito → galpón según D-0104 (carga, viaje, regreso con resultados) | constructor-mundo | xhigh | bot sale con la camioneta, entrega en Barrio Centro y vuelve al galpón sin errores |
| D-0302 | Portón de salida del galpón como punto de partida (reemplaza el arranque de la entrega actual) | constructor-mundo | high | la camioneta cargada sale por el portón y dispara la carga del distrito |
| D-0303 | Pantalla/tablero de despacho: elegir distrito, vehículo y pedidos que salen | constructor-ui | high | test de UI: elegir y confirmar con mando y teclado |
| D-0304 | Generación de ruta por distrito: `RouteStreamer` con conjunto de tramos y decorado del distrito | constructor-tramos | xhigh | Barrio Centro y Campo generan rutas distintas con la misma semilla; `route_golden` por distrito |
| D-0305 | Varias paradas en una salida (entregar 3-6 pedidos en distintas casas antes de volver) | constructor-tramos | xhigh | ruta con N casas; test entrega las N |
| D-0306 | ✅ Orden de paradas: el jugador elige o lo sugiere el GPS | constructor-camion | high | GPS muestra la próxima parada; test cambia el orden |
| D-0307 | Regreso al galpón: viaje de vuelta corto o salto con pantalla de resumen (según D-0104) | constructor-mundo | high | regreso sin cargar la escena entera dos veces (medido) |
| D-0308 | Bloqueo de distrito: no se puede despachar a un distrito bloqueado y se explica por qué | constructor-progresion | medium | test: despacho rechazado con motivo |
| D-0309 | Requisito de vehículo por distrito (la lancha solo sale al agua, etc.) | constructor-progresion | medium | test: combinación inválida rechazada |
| D-0310 | Mapa del mundo 2D (tablero en el galpón) con distritos, estado y pedidos | constructor-ui | high | captura de `revisor-visual` legible a 1080p y Steam Deck |
| D-0311 | Casas de entrega por distrito con `DeliveryHouse` y variantes (puerta, buzón, muelle, porche) | constructor-mundo | high | 4 variantes funcionan con el flujo de puerta actual |
| D-0312 | Direcciones: cada casa tiene calle y número legibles que coinciden con la etiqueta del paquete | constructor-mundo | medium | test: etiqueta y cartel de la casa coinciden |
| D-0313 | Cargar el distrito con la pantalla de carga existente sin congelar (N-408) | constructor-mundo | high | `test_loading_no_freeze` pasa con el distrito |
| D-0314 | Unificar Barrio Centro como primer distrito jugable del corte vertical | constructor-mundo | high | ver D-1501; `--district=centro` arranca |
| D-0315 | Adaptar la ruta actual (Campo) como distrito con la misma calidad de hoy | constructor-tramos | high | tests de ruta actuales verdes en modo Empresa |
| D-0316 | Seguro contra jugadores perdidos: quien se queda en el galpón no se carga ni sufre la ruta | constructor-red | xhigh | test de red: 2 en ruta, 1 en galpón, nadie se teletransporta |
| D-0317 | Jugadores en distintos distritos a la vez (dos vehículos fuera) — sí/no por rendimiento | Plan | high | decisión con medición de costo; si sí, D-0318 |
| D-0318 | (Si D-0317 sí) varias instancias de distrito cargadas a la vez con capas de física separadas | constructor-red | xhigh | test de red con 2 vehículos en 2 distritos |
| D-0319 | Tiempo del viaje cuenta en el reloj del día | constructor-progresion | medium | test: ruta de 5 min avanza 1 h de juego (según D-0105) |
| D-0320 | Recompensa y resultado por salida (lo que se cobró, lo que se rompió) entra al cierre del día | constructor-progresion | high | resultados de la salida en `CompanyState` (test) |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0321 | Atajos entre distritos (túnel, ferry, puente) que se desbloquean | constructor-tramos | high | atajo baja el largo de ruta medido |
| D-0322 | Puntos de interés por distrito (mirador, kiosco, estación de servicio) con efecto chico | constructor-mundo | medium | 3 por distrito colocados por semilla |
| D-0323 | Estación de servicio: cargar combustible (si D-0505 activa combustible) | constructor-camion | medium | test: tanque baja y se carga |
| D-0324 | Clima por distrito con `WorldMood` (perfiles nuevos) | constructor-mundo | high | perfil por distrito; captura de cada uno |
| D-0325 | Hora del día real en el distrito (salir de noche se ve de noche) | constructor-mundo | medium | test: hora del reloj → mood |
| D-0326 | Carteles de dirección por distrito con nombres de calles generados | constructor-mundo | medium | carteles legibles en captura |
| D-0327 | GPS con varias paradas y ruta sugerida dibujada en el tablero | constructor-camion | high | captura con 3 paradas |
| D-0328 | Desvíos: calle cortada que obliga a otra ruta | constructor-tramos | high | test: ruta alternativa existe y se toma |
| D-0329 | Puntos de recogida (devoluciones): buscar un paquete en una casa y traerlo | constructor-progresion | high | pedido de devolución completo en test |
| D-0330 | Hub secundarios: mini-depósito en Puerto y en Montaña para salir más cerca | constructor-mundo | high | despacho desde hub secundario funciona |
| D-0331 | Vista de mapa en el celular del jugador (ya existe el celular) | constructor-ui | medium | celular abre el mapa del distrito |
| D-0332 | Marcadores de ping del mapa compartidos entre jugadores | constructor-red | medium | ping visible en todos los clientes (test de red) |
| D-0333 | Zonas peatonales donde solo entran bici o carrito | constructor-tramos | medium | camioneta no puede entrar; bici sí (test) |
| D-0334 | Peajes y estacionamiento (costo chico, decisión de ruta) | constructor-progresion | low | cobro en test |
| D-0335 | Distrito "evento" temporal (feria, recital) con pedidos especiales | constructor-progresion | medium | se activa por calendario en sim |
| D-0336 | Viaje rápido pagando (taxi de carga) para saltar trayectos repetidos | constructor-progresion | low | opción del despacho funciona |
| D-0337 | Rutas con dos caminos (rápido y peligroso vs. lento y seguro) | constructor-tramos | high | bifurcación en 2 distritos |
| D-0338 | Persistencia del distrito (casas ya visitadas, clientes conocidos) | constructor-progresion | medium | se guarda y carga |
| D-0339 | Clientes que esperan afuera o salen a recibir (animación existente de casa) | constructor-mundo | medium | variantes por distrito |
| D-0340 | Puerta del cliente revisa contenido contra el pedido (no solo daño) | constructor-trampas | high | test: producto faltante baja la paga |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0341 | Transición visual galpón → distrito (portón que se abre, fundido) | artista-vfx | medium | captura de la transición |
| D-0342 | Nombres de distrito al entrar (cartel grande de bienvenida) | constructor-ui | low | cartel traducible |
| D-0343 | Música que cambia por distrito | disenador-audio | medium | crossfade sin cortes |
| D-0344 | Mapa del mundo con estilo de mapa de papel en el tablero | artista-conceptual* | medium | textura integrada en el tablero |
| D-0345 | Nombres de calles graciosos/localizados por distrito | documentador | low | lista traducible de 200 nombres |
| D-0346 | Revisar que ninguna ruta de distrito pase de 5 minutos (regla de oro N-102) | probador-qa | medium | bot mide todas las rutas |
| D-0347 | Revisar la legibilidad de las direcciones a distancia y de noche | revisor-visual | low | captura nocturna legible |
| D-0348 | Ícono por distrito para UI | artista-conceptual* | low | 9 íconos en `assets/ui/` |
| D-0349 | Auditoría de red del flujo de distritos | auditor-red | high | sin hallazgos P0-P1 |
| D-0350 | Test de humo de todos los distritos (cargar, entregar 1, volver) | escritor-tests | high | `test_district_smoke` en CI |
