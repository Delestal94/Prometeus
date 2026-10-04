# Grupo 15 — Distritos de tierra: Barrio Centro, Suburbio, Campo y Puerto

> Fase **F1** (Barrio Centro en gris) / F2 · Dueño: Nacho · Depende de: D-0205, D-0304, D-0311.
> Campo ya existe (la ruta actual); los otros se construyen con el mismo sistema de tramos.

## Núcleo — Barrio Centro

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1501 | Barrio Centro: tramos de calle urbana (recta, esquina, rotonda, cuadra) | constructor-tramos | xhigh | ruta generada de 2-5 min con 4 tipos |
| D-1502 | Veredas, cordones y estacionamiento | constructor-tramos | medium | captura |
| D-1503 | Semáforos que cambian y multa si se cruza en rojo | constructor-tramos | high | test |
| D-1504 | Tránsito NPC simple (autos en carriles, frenan) | constructor-mundo | xhigh | bot sin choques absurdos 5 min |
| D-1505 | Peatones que cruzan | constructor-mundo | high | test |
| D-1506 | Edificios con portería, timbre y ascensor (entrega en piso) | constructor-mundo | high | entrega en un 3er piso funciona |
| D-1507 | Callejones angostos donde solo pasa la bici | constructor-tramos | medium | test |
| D-1508 | Decorado urbano (kioscos, árboles, carteles) por semilla | constructor-mundo | medium | captura |
| D-1509 | Kit modular de edificios en gris | modelador-blender* | high | 10 piezas |
| D-1510 | Perfil de clima y luz urbana (`WorldMood`) | constructor-mundo | medium | captura día y noche |
| D-1511 | Baches urbanos y lomos de burro como fuente de riesgo | constructor-tramos | medium | medición de carga |
| D-1512 | Clientes del Centro (oficinas, departamentos, locales) | constructor-progresion | low | `.tres` |
| D-1513 | Test de humo del Centro | escritor-tests | medium | test |
| D-1514 | `route_golden` del Centro | escritor-tests | low | archivo |
| D-1515 | Rendimiento del Centro con tránsito | perfilador-rendimiento | high | FPS ≥ objetivo |

## Núcleo — Suburbio y Campo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1516 | Suburbio: calles con casas con jardín, perros, rociadores | constructor-tramos | high | ruta generada |
| D-1517 | Barrio cerrado con garita (control de entrada) | constructor-mundo | medium | test |
| D-1518 | Perros por casa (reusa `chasing_dog.gd`) | constructor-mundo | low | variantes |
| D-1519 | Kit de casas suburbanas | modelador-blender* | high | 6 casas |
| D-1520 | Campo como distrito: la ruta actual con sus casas, barro, animales y tren | constructor-tramos | high | tests actuales verdes en modo Empresa |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1521 | Obras en la calle (desvío urbano) | constructor-tramos | medium | test |
| D-1522 | Hora pico (más tránsito a ciertas horas) | constructor-mundo | medium | test |
| D-1523 | Policía de tránsito que multa | constructor-mundo | low | evento |
| D-1524 | Feria callejera que corta calles (D-0335) | constructor-mundo | low | evento |
| D-1525 | Mascotas que se escapan en el Suburbio | constructor-mundo | low | evento |
| D-1526 | Rociadores que mojan la carga | constructor-mundo | low | test |
| D-1527 | Pileta en el jardín (paquete que cae al agua) | constructor-mundo | low | test |
| D-1528 | Chacras con tranqueras que hay que abrir en Campo | constructor-tramos | medium | test |
| D-1529 | Cosecha: tractores lentos en la ruta | constructor-mundo | medium | test |
| D-1530 | Pueblo del Campo con almacén como cliente grande | constructor-mundo | medium | escena |
| D-1531 | Tormenta de tierra en Campo | constructor-mundo | low | perfil |
| D-1532 | Escuela, hospital, municipalidad como clientes especiales | constructor-progresion | low | pedidos |
| D-1533 | Subte/tren urbano que cruza | constructor-tramos | medium | test |
| D-1534 | Estacionamiento en doble fila (riesgo de multa) | constructor-progresion | low | test |
| D-1535 | Puerto en tierra: contenedores, grúas, galpones portuarios, muelle | constructor-mundo | high | escena con entregas |
| D-1536 | Puerto: grúas pórtico que mueven contenedores (peligro) | constructor-mundo | medium | test |
| D-1537 | Puerto: aduana (control de paquetes) | constructor-progresion | low | test |
| D-1538 | Mercado de pescado como cliente/proveedor | constructor-negocio | low | `.tres` |
| D-1539 | Kit de Puerto (contenedores, grúas, bolardos) | modelador-blender* | high | kit |
| D-1540 | Ambiente sonoro urbano, suburbano y portuario | disenador-audio | medium | 3 loops |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1541 | Texturas de asfalto, vereda, adoquín | artista-shaders | medium | materiales |
| D-1542 | Luces de ciudad de noche (ventanas, faroles) | constructor-mundo | medium | captura |
| D-1543 | Grafitis y carteles con humor del juego | artista-conceptual* | low | 20 texturas |
| D-1544 | LOD y batching de edificios | perfilador-rendimiento | high | draw calls medidos |
| D-1545 | Revisión de arte de los 4 distritos | director-arte | medium | lista de refinamiento |
| D-1546 | Capturas de cada distrito | revisor-visual | low | 12 capturas |
| D-1547 | Balance de paga por distrito | pulidor-jugabilidad | medium | sim |
| D-1548 | QA de los 4 distritos | probador-qa | medium | tabla |
| D-1549 | Auditoría de red del tránsito NPC | auditor-red | high | sin P0-P1 |
| D-1550 | Test de humo de Suburbio y Puerto | escritor-tests | medium | test |
