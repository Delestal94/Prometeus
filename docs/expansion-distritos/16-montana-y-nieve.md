# Grupo 16 — Montaña y Nieve

> Fase **F3** · Dueño: Nacho · Depende de: D-1231 (4x4), D-0416, D-0417, D-0304.
> Montaña: cornisas, pendientes, desprendimientos. Nieve: hielo, frío que afecta la carga, avalanchas,
> pueblo de esquí y refugios en la cumbre.

## Núcleo — Montaña

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1601 | Tramos de montaña: subida, bajada, curva cerrada, cornisa | constructor-tramos | xhigh | ruta de 2-5 min generada |
| D-1602 | Pendiente afecta al vehículo (fuerza, frenado) y a la carga (se desliza) | constructor-camion | high | medición de carga en subida |
| D-1603 | Cornisa con caída: vehículo que se cae reaparece con daño | constructor-tramos | high | test |
| D-1604 | Desprendimiento de rocas (peligro con aviso) | constructor-tramos | medium | test |
| D-1605 | Niebla de montaña (reusa `low_visibility_event`) | constructor-mundo | low | variante |
| D-1606 | Casas de montaña: cabañas, refugio, puesto de guardaparque | constructor-mundo | high | 3 tipos de casa de entrega |
| D-1607 | Último tramo a pie por sendero con la caja | constructor-jugador | high | test |
| D-1608 | Terreno con laderas (`TerrainField` con más relieve) | constructor-tramos | xhigh | conforma sin errores; rendimiento medido |
| D-1609 | Kit de montaña (rocas, pinos, barandas, carteles de curva) | modelador-blender* | high | kit |
| D-1610 | Perfil de clima de montaña | constructor-mundo | medium | captura |

## Núcleo — Nieve

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1611 | Superficie de hielo y nieve (agarre bajo) por tramo | constructor-camion | high | test de frenado |
| D-1612 | Cadenas para ruedas (ponerlas como reparación, a mano) | constructor-camion | high | test |
| D-1613 | Frío: la carga y los jugadores tienen temperatura | constructor-jugador | high | test |
| D-1614 | Ropa de abrigo de la tripulación (D-0426) | constructor-jugador | medium | test |
| D-1615 | Productos que se congelan/rompen con frío (agua, plantas) | constructor-negocio | medium | test |
| D-1616 | Avalancha (evento con aviso, bloquea camino) | constructor-tramos | high | test |
| D-1617 | Ventisca (visibilidad y empuje lateral) | constructor-mundo | medium | test |
| D-1618 | Pueblo de esquí con clientes (hotel, tienda, escuela de esquí) | constructor-mundo | high | escena |
| D-1619 | Shader de nieve que se acumula en superficies | artista-shaders | high | material |
| D-1620 | Huellas y marcas en la nieve | artista-vfx | medium | decal medido |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1621 | Telesilla/teleférico que lleva paquetes a la cumbre | constructor-mundo | high | test |
| D-1622 | Trineo de carga tirado a mano en la cumbre | constructor-jugador | high | test |
| D-1623 | Moto de nieve (vehículo extra) | constructor-camion | high | test |
| D-1624 | Refugio en la cumbre solo por avioneta con esquís (D-1425) | constructor-mundo | medium | test |
| D-1625 | Grietas en el glaciar | constructor-tramos | medium | test |
| D-1626 | Animales de montaña (cabras, cóndor) que cruzan | constructor-mundo | low | variantes |
| D-1627 | Túnel de montaña (reusa túneles del tren) | constructor-tramos | medium | test |
| D-1628 | Quitanieves NPC que abre caminos | constructor-mundo | low | evento |
| D-1629 | Paso de montaña cerrado por nieve ciertos días | constructor-progresion | low | evento |
| D-1630 | Lago congelado que cruje | constructor-tramos | medium | test |
| D-1631 | Muñecos de nieve como obstáculo gracioso | constructor-mundo | low | prop |
| D-1632 | Productos de Montaña/Nieve (quesos, artesanías, equipo de esquí) | constructor-negocio | low | `.tres` |
| D-1633 | Pedidos especiales (rescate de montañistas, observatorio) | constructor-progresion | low | pedidos |
| D-1634 | Fogón/refugio para calentarse | constructor-jugador | low | test |
| D-1635 | Trampa "Derretible" al revés: congelable | constructor-trampas | medium | test |
| D-1636 | Eco que hace caer nieve si se toca la bocina (riesgo gracioso) | constructor-mundo | low | test |
| D-1637 | Esquiar con la caja (mini-modo de bajada) | critico-diseno | low | decisión |
| D-1638 | Hielo en el parabrisas que hay que raspar | constructor-camion | low | test |
| D-1639 | Mirador con postal (foto con `press_photo`) | constructor-mundo | low | test |
| D-1640 | Ambiente sonoro de montaña y nieve | disenador-audio | medium | 2 loops |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1641 | Kit de nieve (pinos nevados, cabañas, telesilla) | modelador-blender* | high | kit |
| D-1642 | Partículas de nieve y ventisca sin bajar FPS | artista-vfx | medium | medido |
| D-1643 | Aliento visible y escarcha en pantalla | artista-vfx | low | efecto |
| D-1644 | Cielo de altura | artista-shaders | low | material |
| D-1645 | Rendimiento con relieve y nieve | perfilador-rendimiento | high | FPS ≥ objetivo |
| D-1646 | Capturas de Montaña y Nieve | revisor-visual | low | 8 capturas |
| D-1647 | Balance de dificultad de los dos distritos | pulidor-jugabilidad | medium | bots |
| D-1648 | Auditoría de red (avalanchas, desprendimientos deterministas) | auditor-red | high | sin P0-P1 |
| D-1649 | QA de Montaña y Nieve | probador-qa | medium | tabla |
| D-1650 | Test de humo de los dos distritos | escritor-tests | medium | test |
