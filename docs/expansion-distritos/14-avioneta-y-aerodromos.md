# Grupo 14 — Avioneta y aeródromos

> Fase **F4** · Dueño: Nacho · Depende de: D-0228 (`simple_flight`), D-0208, D-0418.
> Arcade, no simulador: despegar, volar a una zona y aterrizar en una pista de tierra o **lanzar el
> paquete con paracaídas** (lo que habilita Volcán y cumbres nevadas).

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1401 | Modelo de vuelo arcade (sustentación, pérdida suave, alabeo asistido) | constructor-camion | xhigh | bot despega, vuela a un punto y aterriza en 10 corridas |
| D-1402 | Rodaje y despegue desde pista | constructor-camion | high | test |
| D-1403 | Aterrizaje con tolerancia (rebote, carga sufre según dureza) | constructor-camion | high | impacto medido en la carga |
| D-1404 | Avioneta en red (predicción y suavizado a alta velocidad) | constructor-red | xhigh | test de red con 3 peers |
| D-1405 | Pista de aterrizaje anexa al galpón (aeródromo) | constructor-mundo | high | escena |
| D-1406 | Pistas de tierra en distritos (Montaña, Nieve, Volcán) | constructor-mundo | medium | 3 pistas |
| D-1407 | Asientos: piloto, copiloto (navega), 2-4 con carga | constructor-camion | medium | test |
| D-1408 | Turbulencia que sacude la carga | constructor-camion | high | medición |
| D-1409 | Instrumentos simples en la cabina (velocidad, altura, brújula) | constructor-camion | medium | captura |
| D-1410 | Navegación: humo de señal / baliza en el destino | constructor-mundo | medium | test |
| D-1411 | Terreno grande de baja resolución para volar (impostores lejanos) | constructor-tramos | xhigh | rendimiento medido |
| D-1412 | Choque y reaparición (sin perder toda la carga) | constructor-camion | medium | test |
| D-1413 | Límite de altura y bordes del mapa | constructor-mundo | low | test |
| D-1414 | Modelo 3D de la avioneta | modelador-blender* | high | modelo con hélice, flaps y cabina |
| D-1415 | Sonido de motor de hélice con Doppler | disenador-audio | medium | SFX |
| D-1416 | Cámara de piloto y de pasajero sin mareo | constructor-jugador | high | parámetros |
| D-1417 | Controles con mando y teclado (sin joystick de vuelo) | constructor-ui | high | test de input |
| D-1418 | Licencia de vuelo (D-0124) y tutorial de despegue | constructor-progresion | medium | test |
| D-1419 | Test de referencia de vuelo | escritor-tests | high | `test_reference_plane` |
| D-1420 | Lanzamiento con paracaídas: abrir compuerta, soltar caja, caída y aterrizaje | constructor-camion | xhigh | caja cae dentro de 15 m del objetivo con bot |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1421 | Puntería del lanzamiento (copiloto marca con mira) | constructor-jugador | high | test |
| D-1422 | Viento que desvía paracaídas | constructor-camion | medium | test |
| D-1423 | Paracaídas que no abre si el armado fue malo (trampa) | constructor-trampas | medium | test |
| D-1424 | Recoger paquete en vuelo (gancho, guiño a aviones postales) | critico-diseno | low | decisión |
| D-1425 | Esquís para nieve (aterrizar en la cumbre) | constructor-camion | medium | test |
| D-1426 | Flotadores (hidroavión) si D-1333 | constructor-camion | medium | test |
| D-1427 | Combustible y autonomía (si D-0505) | constructor-camion | low | test |
| D-1428 | Clima: nubes, niebla, tormenta eléctrica | constructor-mundo | medium | perfiles |
| D-1429 | Pájaros que chocan (bandadas existentes) | constructor-mundo | low | evento |
| D-1430 | Avioneta grande de carga (mejora) | constructor-camion | medium | test |
| D-1431 | Helicóptero (post-lanzamiento) | critico-diseno | low | decisión |
| D-1432 | Torre de control con NPC que da instrucciones graciosas | constructor-mundo | low | líneas |
| D-1433 | Aterrizaje de emergencia en una ruta | constructor-camion | low | test |
| D-1434 | Saltar con paracaídas personal para entrega a mano | constructor-jugador | high | test de red |
| D-1435 | Reabastecer en pistas lejanas | constructor-camion | low | test |
| D-1436 | Mantenimiento de la avioneta en el hangar | constructor-camion | low | test |
| D-1437 | Hangar en el aeródromo | constructor-mundo | medium | escena |
| D-1438 | Mapa del mundo visto desde el aire (los distritos conectados) | constructor-tramos | high | captura |
| D-1439 | Entregas aéreas a otras ciudades fuera del mapa (simuladas) | constructor-negocio | low | sim |
| D-1440 | Piloto NPC para salidas automáticas | constructor-negocio | low | sim |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1441 | Estela de humo y nubes atravesables | artista-vfx | medium | partículas |
| D-1442 | Animación de hélice y superficies de control | animador | low | procedural |
| D-1443 | Viento en la cabina abierta (audio) | disenador-audio | low | SFX |
| D-1444 | Paracaídas modelado y animado | modelador-blender* | medium | modelo |
| D-1445 | Cielo con nubes de capas (shader) | artista-shaders | medium | material |
| D-1446 | Rendimiento de vuelo (terreno, draw distance) | perfilador-rendimiento | high | FPS ≥ objetivo |
| D-1447 | Capturas aéreas para Steam | revisor-visual | low | 5 capturas |
| D-1448 | Auditoría de red de la avioneta | auditor-red | high | sin P0-P1 |
| D-1449 | QA de vuelo | probador-qa | medium | tabla |
| D-1450 | Balance de la avioneta (riesgo vs. paga) | pulidor-jugabilidad | medium | sim |
