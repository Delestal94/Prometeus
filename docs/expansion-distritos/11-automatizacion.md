# Grupo 11 — Automatización

> Fase **F2** · Dueño: Nacho · Depende de: D-0226, D-0901, D-0414.
> Máquinas que reemplazan pasos: cintas, encintadora, etiquetadora, balanza, clasificador, robots.
> Los ítems en cinta se simulan como grafo (no física) y se dibujan con MultiMesh.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1101 | Cinta transportadora colocable (recta, curva, subida) | constructor-negocio | high | ítems avanzan en el grafo; test |
| D-1102 | Ítems en cinta dibujados con MultiMesh, con física solo al caer | perfilador-rendimiento | high | 300 ítems en cinta dentro del presupuesto |
| D-1103 | Cinta de descarga desde el camión del proveedor | constructor-negocio | medium | test |
| D-1104 | Encintadora automática (cierra cajas que pasan) | constructor-negocio | medium | test |
| D-1105 | Etiquetadora automática | constructor-negocio | medium | test |
| D-1106 | Balanza en línea que desvía cajas con peso incorrecto | constructor-negocio | medium | test |
| D-1107 | Clasificador por distrito (desvía a la rampa correcta) | constructor-negocio | high | test con 3 destinos |
| D-1108 | Rampas de despacho por distrito | constructor-negocio | medium | test |
| D-1109 | Máquina armadora de cajas (dobla la caja vacía) | constructor-negocio | medium | test |
| D-1110 | Dosificador de relleno | constructor-negocio | medium | test |
| D-1111 | Interacción jugador ↔ cinta (sacar/poner cajas) | constructor-jugador | high | test |
| D-1112 | Máquinas consumen insumos y se traban si faltan | constructor-negocio | medium | test |
| D-1113 | Atascos y averías que un jugador debe destrabar (golpe, palanca) | constructor-negocio | medium | test; guiño a `VehicleFaults` |
| D-1114 | Panel de cada máquina (estado, producción, insumos) | constructor-ui | medium | captura |
| D-1115 | Cintas replicadas en red sin mandar cada ítem cada tick | constructor-red | xhigh | ancho de banda < presupuesto con 300 ítems |
| D-1116 | Guardar máquinas y su contenido | constructor-progresion | medium | test |
| D-1117 | Tienda de automatización (D-0511) con máquinas desbloqueadas | constructor-progresion | low | test |
| D-1118 | Primera máquina (encintadora) en el hito de D-0414 | constructor-progresion | low | test |
| D-1119 | Modelos grises de cada máquina para el corte F2 | modelador-blender* | medium | 8 modelos |
| D-1120 | Benchmark de automatización (`bench_conveyor`) | perfilador-rendimiento | medium | número en `rendimiento-pc.md` |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1121 | Robot de picking que toma productos de estantes según pedido | constructor-negocio | xhigh | test: arma lista de picking |
| D-1122 | Brazo robótico armador (mete productos en la caja) | constructor-negocio | xhigh | test |
| D-1123 | AGV (vehículo autónomo) que lleva palets | constructor-negocio | high | test |
| D-1124 | Paletizadora para salidas grandes | constructor-negocio | medium | test |
| D-1125 | Envolvedora de film | constructor-negocio | low | test |
| D-1126 | Cámara de control de calidad automática | constructor-negocio | medium | test |
| D-1127 | Lógica programable simple (si-entonces) en clasificadores | constructor-negocio | high | test de reglas |
| D-1128 | Separadores y uniones de cintas | constructor-negocio | medium | test |
| D-1129 | Ascensor de cajas entre pisos | constructor-negocio | medium | test |
| D-1130 | Mejoras de velocidad por máquina | constructor-progresion | low | test |
| D-1131 | Consumo eléctrico y generador (si D-0912) | constructor-negocio | medium | test |
| D-1132 | Mantenimiento preventivo | constructor-negocio | low | test |
| D-1133 | Estadísticas de throughput por hora | constructor-ui | medium | gráfico |
| D-1134 | Máquinas de distrito (heladera industrial para Nieve, horno de prueba para Volcán) | constructor-negocio | low | 2 máquinas |
| D-1135 | Galpón completamente automatizado como meta de fin de campaña | constructor-progresion | low | hito |
| D-1136 | Modo "turbo": ver la línea funcionar acelerada | constructor-ui | low | test |
| D-1137 | Cajas que se caen de la cinta si va muy rápido (física de verdad) | constructor-negocio | medium | test |
| D-1138 | Trampas activas en la cinta (explosiva que explota en el galpón) | constructor-trampas | medium | evento |
| D-1139 | Empleado técnico que repara máquinas | constructor-negocio | low | rol |
| D-1140 | Tutorial de automatización | constructor-ui | medium | flujo guiado |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1141 | Modelos finales de máquinas | modelador-blender* | high | 14 modelos low-poly |
| D-1142 | Animaciones de máquinas (rodillos, brazos) | animador | medium | procedurales |
| D-1143 | Shader de rodillos de cinta en movimiento (UV scroll) | artista-shaders | low | material |
| D-1144 | Sonidos de máquinas con mezcla que no sature | disenador-audio | medium | mezcla medida |
| D-1145 | Chispas y humo en averías | artista-vfx | low | partículas |
| D-1146 | Balance de costo/beneficio de cada máquina | pulidor-jugabilidad | medium | sim |
| D-1147 | Test de grafo de cintas con ciclos | escritor-tests | medium | test |
| D-1148 | Test de red con 300 ítems en cintas | escritor-tests | high | test |
| D-1149 | QA de automatización un día completo | probador-qa | medium | tabla |
| D-1150 | Documentar cómo agregar una máquina | documentador | low | guía |
