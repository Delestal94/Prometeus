# Grupo 17 — Volcán

> Fase **F4** · Dueño: Nacho · Depende de: D-1420 (paracaídas), D-0418, D-1231.
> Distrito final: base con 4x4 por caminos de ceniza, laderas con lava, y en la cumbre (observatorio,
> estación científica) solo por lanzamiento aéreo. El calor afecta la carga.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1701 | Tramos volcánicos: ceniza, piedra pómez, grietas | constructor-tramos | xhigh | tramos sobre aristas del grafo fijo (revisión D-0140) |
| D-1702 | Ríos de lava como obstáculo (cruce por puente o rodeo) | constructor-tramos | high | test |
| D-1703 | Calor: la carga sube de temperatura y los productos sensibles se arruinan | constructor-negocio | high | test |
| ~~D-1704~~ | ~~Trampa "Derretible" activa en Volcán (D-0738)~~ **Fusionada en D-0738 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-trampas | medium | test |
| D-1705 | Temblores que sacuden vehículo y carga (evento) (incluye D-1730, fusión de D-0112) | constructor-tramos | high | medición |
| D-1706 | Lluvia de ceniza (visibilidad y suciedad en parabrisas) (incluye D-1734, fusión de D-0112) | constructor-mundo | medium | test |
| D-1707 | Bombas volcánicas (rocas que caen con sombra de aviso) | constructor-tramos | high | test |
| D-1708 | Clientes: estación científica, observatorio, aldea de la ladera, aguas termales | constructor-mundo | high | 4 casas de entrega |
| D-1709 | Zona de lanzamiento en la cumbre (objetivo marcado) | constructor-mundo | medium | test con D-1420 |
| D-1710 | Gases (zona donde no se puede estar mucho a pie) | constructor-jugador | medium | test |
| D-1711 | Terreno volcánico (`TerrainField` con cono y cráter) | constructor-tramos | xhigh | rendimiento medido |
| D-1712 | Shader de lava con brillo (GL Compatibility) | artista-shaders | high | material medido en FPS |
| D-1713 | Luz del volcán (resplandor de noche) | constructor-mundo | medium | captura |
| D-1714 | Kit volcánico (rocas, pómez, carteles de peligro, estación) (incluye D-1737, fusión de D-0112) | modelador-blender* | high | kit |
| D-1715 | Perfil de clima volcánico | constructor-mundo | medium | captura |
| D-1716 | Erupción programada como evento del día (no cierra zonas: franja anunciada de bombas y ceniza dentro del Volcán; revisión D-0140) | constructor-progresion | medium | evento |
| ~~D-1717~~ | ~~Cajas térmicas obligatorias (D-0722)~~ **Fusionada en D-0722 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-negocio | low | test |
| ~~D-1718~~ | ~~Ropa ignífuga de la tripulación~~ **Fusionada en D-0426 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-jugador | low | test |
| D-1719 | Caer en lava: reaparición y caja perdida (con salvataje imposible) | constructor-jugador | medium | test |
| D-1720 | Pista de tierra en la base del volcán | constructor-mundo | medium | test |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1721 | Puentes que se derrumban si se tarda | constructor-tramos | medium | test |
| D-1722 | Géiseres que lanzan cajas | constructor-tramos | medium | test |
| ~~D-1723~~ | ~~Cueva de lava como atajo~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-tramos | medium | test |
| D-1724 | Productos de Volcán (piedras, azufre, souvenirs) | constructor-negocio | low | `.tres` |
| D-1725 | Pedido final de campaña (entregar algo absurdo en el cráter) | constructor-progresion | medium | evento final |
| ~~D-1726~~ | ~~Vehículo oruga (opcional)~~ **Recortada (D-0112, [crítica](diseno/critica-alcance.md))** | critico-diseno | low | decisión |
| ~~D-1727~~ | ~~Termales donde se recupera la tripulación~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-jugador | low | test |
| D-1728 | Científicos NPC con humor | documentador | low | 20 líneas |
| D-1729 | Mapa de riesgo volcánico en el tablero (qué zonas están activas hoy) | constructor-ui | medium | captura |
| ~~D-1730~~ | ~~Sismógrafo en la cabina que anticipa temblores~~ **Fusionada en D-1705 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-camion | low | test |
| ~~D-1731~~ | ~~Explosiva + calor = combo peligroso~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-trampas | medium | test |
| ~~D-1732~~ | ~~Lanzamiento con varios paracaídas a la vez~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-camion | medium | test |
| ~~D-1733~~ | ~~Paquete que hay que bajar del cráter (recogida)~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | low | pedido |
| ~~D-1734~~ | ~~Nubes de ceniza que afectan a la avioneta~~ **Fusionada en D-1706 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-camion | medium | test |
| ~~D-1735~~ | ~~Escena de cierre de campaña en el volcán~~ **Fusionada en D-0438 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-mundo | medium | escena |
| ~~D-1736~~ | ~~Rocas que ruedan por la ladera~~ **Fusionada en D-1604 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-tramos | low | test |
| ~~D-1737~~ | ~~Señalización de evacuación~~ **Fusionada en D-1714 (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-mundo | low | props |
| ~~D-1738~~ | ~~Desafío de récord en Volcán~~ **Pospuesta a post-lanzamiento (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-progresion | low | test |
| ~~D-1739~~ | ~~Volcán en Endless (si D-0128)~~ **Recortada (D-0112, [crítica](diseno/critica-alcance.md))** | constructor-tramos | low | test |
| D-1740 | Ambiente sonoro volcánico (retumbos, burbujeo) | disenador-audio | medium | loop |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1741 | Humo, chispas y distorsión por calor | artista-vfx | medium | efectos medidos |
| D-1742 | Rocas con brillo de lava en grietas | artista-shaders | medium | material |
| ~~D-1743~~ | ~~Cielo rojizo y ceniza~~ **Fusionada en D-1445 (D-0112, [crítica](diseno/critica-alcance.md))** | artista-shaders | low | material |
| D-1744 | Rendimiento del Volcán | perfilador-rendimiento | high | FPS ≥ objetivo |
| ~~D-1745~~ | ~~Capturas del Volcán (cápsula de Steam)~~ **Fusionada en D-2031 (D-0112, [crítica](diseno/critica-alcance.md))** | revisor-visual | low | 5 capturas |
| ~~D-1746~~ | ~~Revisión de arte del Volcán~~ **Fusionada en D-1843 (D-0112, [crítica](diseno/critica-alcance.md))** | director-arte | medium | lista |
| D-1747 | Balance del distrito final | pulidor-jugabilidad | medium | bots |
| D-1748 | Auditoría de red de eventos volcánicos | auditor-red | high | sin P0-P1 |
| D-1749 | QA del Volcán | probador-qa | medium | tabla |
| ~~D-1750~~ | ~~Test de humo del Volcán~~ **Fusionada en D-0350 (D-0112, [crítica](diseno/critica-alcance.md))** | escritor-tests | medium | test |
