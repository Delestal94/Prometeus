# Grupo 10 — Empleados

> Fase **F2** · Dueño: Nacho · Depende de: D-0224, D-0908, D-0413.
> Inspirado en *Schedule I*: se contratan, se les asigna estación con el portapapeles, cobran por día,
> necesitan su lugar. Base: `depot_worker.gd` (los trabajadores ambientales actuales).

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1001 | Empleado como agente con estados (ocioso, yendo, trabajando, descansando) | constructor-negocio | high | test de transición de estados |
| D-1002 | Roles: descargador, repositor, armador, controlador, despachante | constructor-negocio | high | 5 roles con su ciclo de trabajo |
| D-1003 | Contratación desde el tablero o una agencia (candidatos con stats) | constructor-negocio | medium | test: contratar suma empleado |
| D-1004 | Asignar estación/rol con el portapapeles (D-0131) | constructor-ui | high | test de UI |
| D-1005 | Empleado descargador usa la zorra (D-0605) | constructor-negocio | high | bot: descarga un palet solo |
| D-1006 | Empleado repositor lleva productos a estanterías | constructor-negocio | high | test |
| D-1007 | Empleado armador arma cajas con calidad según su habilidad | constructor-negocio | xhigh | test: calidad media coincide con stat ±10 |
| D-1008 | Empleado despachante carga el vehículo | constructor-negocio | high | test |
| D-1009 | Sueldo diario descontado al cierre | constructor-progresion | low | test |
| D-1010 | Despedir empleado | constructor-negocio | low | test |
| D-1011 | Navegación con navmesh y evitación entre empleados y jugadores | constructor-negocio | high | bot: 8 empleados sin trabarse 1 día |
| D-1012 | Empleados replicados en red (posición suavizada con `net_pose_smoother`) | constructor-red | xhigh | test de red; ancho de banda medido |
| D-1013 | Empleado no roba el trabajo que un jugador está haciendo (reservas en `job_board`) | constructor-negocio | high | test |
| D-1014 | Jugador puede pedirle algo puntual a un empleado (ping) | constructor-jugador | medium | test |
| D-1015 | Empleados se van al cerrar el día | constructor-negocio | low | test |
| D-1016 | Guardar empleados en el save | constructor-progresion | medium | test |
| D-1017 | Límite de empleados por etapa del galpón | constructor-progresion | low | test |
| D-1018 | Modelo del empleado base (reusa trabajadores del depósito) | modelador-blender* | medium | malla con uniforme |
| D-1019 | Animaciones básicas: caminar, cargar, armar | animador* | high | 3 clips |
| D-1020 | Rendimiento con 20 empleados | perfilador-rendimiento | high | dentro de presupuesto |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1021 | Stats: velocidad, cuidado, fuerza, resistencia | constructor-negocio | medium | afectan el trabajo (test) |
| D-1022 | Experiencia y subida de nivel | constructor-negocio | medium | test |
| D-1023 | Moral (sube con descanso, decoración, pagos a tiempo; baja con sobretrabajo) | constructor-negocio | medium | test |
| D-1024 | Renuncia por moral baja | constructor-negocio | low | test |
| D-1025 | Necesidades: comedor, vestuario (D-0923) | constructor-negocio | medium | test |
| D-1026 | Turnos (mañana/tarde) | constructor-negocio | medium | test |
| D-1027 | Empleado repartidor NPC que hace entregas fáciles solo (simulado, sin escena) | constructor-negocio | high | sim: entrega con tasa de éxito por stat |
| D-1028 | Choferes NPC para vehículos (salidas automáticas a distritos dominados) | constructor-negocio | high | sim |
| D-1029 | Supervisor que reasigna empleados según cuellos de botella | constructor-negocio | high | sim mejora throughput |
| D-1030 | Rasgos graciosos (torpe, apurado, perfeccionista) | constructor-negocio | low | 8 rasgos |
| D-1031 | Accidentes de empleados (tira una caja) con consecuencias | constructor-negocio | low | evento |
| D-1032 | Capacitación pagada | constructor-negocio | low | test |
| D-1033 | Uniformes personalizables | constructor-negocio | low | cosmético |
| D-1034 | Nombres y caras variados (reusar `face_catalog.gd`) | constructor-negocio | low | 50 combinaciones |
| D-1035 | Diálogos/burbujas de empleados | documentador | low | 80 líneas traducibles |
| D-1036 | Huelga/evento de empleados | constructor-negocio | low | evento |
| D-1037 | Empleados especializados por distrito (lanchero, piloto) | constructor-negocio | medium | test |
| D-1038 | Vista de plantilla en el portapapeles | constructor-ui | medium | captura |
| D-1039 | Empleados ayudan a un jugador caído (rescate) | constructor-negocio | low | test |
| D-1040 | LOD de empleados lejanos (animación reducida) | perfilador-rendimiento | medium | medido |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1041 | Variedad de modelos de empleados (6 cuerpos) | modelador-blender* | high | 6 variantes |
| D-1042 | Animaciones extra: descansar, saludar, quejarse | animador* | medium | 3 clips |
| D-1043 | Voces sintetizadas tipo murmullo | disenador-audio | low | SFX |
| D-1044 | Íconos de estado sobre la cabeza (zzz, !, ?) | constructor-ui | low | captura |
| D-1045 | Balance: un empleado cuesta y rinde lo esperado en D-0117 | pulidor-jugabilidad | medium | sim |
| D-1046 | Test de que empleados no atraviesan paredes tras ampliar galpón | escritor-tests | medium | test |
| D-1047 | Test de red con 20 empleados y 4 jugadores | escritor-tests | high | test |
| D-1048 | QA de empleados un día completo | probador-qa | medium | tabla |
| D-1049 | Auditoría de red de empleados | auditor-red | high | sin P0-P1 |
| D-1050 | Documentar cómo agregar un rol | documentador | low | guía |
