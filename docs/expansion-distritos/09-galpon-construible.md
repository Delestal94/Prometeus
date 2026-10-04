# Grupo 09 — Galpón construible

> Fase **F1** (núcleo mínimo: colocar mesas y estantes) / F2 · Dueño: Nacho · Depende de: D-0225, D-0620.
> Modo construcción estilo *Schedule I*: comprar y colocar estaciones, estantes, cintas y máquinas en
> una grilla; ampliar el galpón por etapas. Parte del depósito actual (N-319).

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0901 | Modo construcción: activar, cámara elevada, grilla visible | constructor-negocio | high | test de entrada/salida del modo |
| D-0902 | Colocar un objeto comprado con previsualización verde/roja | constructor-negocio | high | test: choque bloquea la colocación |
| D-0903 | Rotar, mover y vender objetos colocados | constructor-negocio | medium | test de las 3 acciones |
| D-0904 | Objetos colocables iniciales: mesa de armado, estante, heladera, zona de despacho | constructor-negocio | medium | 4 objetos `.tres` |
| D-0905 | Etapas del galpón (chico → mediano → grande → centro logístico) que amplían la grilla | constructor-mundo | xhigh | ampliar cambia paredes y grilla sin recargar el nivel |
| D-0906 | Paredes y portones fijos que no se pueden tapar (dársena, salida) | constructor-negocio | medium | test |
| D-0907 | Caminos libres: validación de que se puede llegar a cada estación | constructor-negocio | high | test de conectividad (navmesh) |
| D-0908 | Navmesh que se rehornea al colocar objetos (para empleados) | constructor-negocio | high | test: empleado esquiva objeto nuevo |
| D-0909 | Guardar el layout en el save de empresa | constructor-progresion | medium | test |
| D-0910 | Layout replicado en red; solo host o voto coloca | constructor-red | xhigh | test de red |
| D-0911 | Layout por defecto que ya funciona sin tocar nada | constructor-mundo | medium | corte vertical juega con él |
| D-0912 | Electricidad/enchufes como restricción de máquinas (sí/no) | critico-diseno | low | decisión |
| D-0913 | Iluminación que se adapta al layout (sin rincones oscuros) | constructor-mundo | medium | captura |
| D-0914 | Interacción con objetos colocados igual que con los fijos | constructor-jugador | medium | test |
| D-0915 | Límite de objetos por etapa (presupuesto de rendimiento) | perfilador-rendimiento | medium | número fijado y medido |
| D-0916 | Deshacer la última colocación | constructor-negocio | low | test |
| D-0917 | Modo construcción con mando | constructor-ui | high | test de input |
| D-0918 | Reusar `depot_layout.gd`/`depot_zones.gd` como base de las zonas | constructor-mundo | high | sin duplicar lógica (revisión) |
| D-0919 | Etiquetas de zona pintadas en el piso (recepción, armado, despacho) | constructor-mundo | low | captura |
| D-0920 | Precio y venta con devolución parcial | constructor-progresion | low | test |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0921 | Planos guardables (copiar una configuración) | constructor-negocio | medium | test |
| D-0922 | Decoración (plantas, carteles, máquina de café) con efecto en moral | constructor-negocio | low | ver D-1025 |
| D-0923 | Vestuario y comedor para empleados (como Schedule I: camas/lockers) | constructor-negocio | medium | requisito de empleados |
| D-0924 | Oficina del jefe con escritorio de gestión | constructor-mundo | medium | escena |
| D-0925 | Garaje de la flota dentro del galpón | constructor-mundo | high | ver D-1205 |
| D-0926 | Pista de aterrizaje anexa (con F4) | constructor-mundo | high | ver D-1405 |
| D-0927 | Muelle anexo en Puerto | constructor-mundo | high | ver D-1305 |
| D-0928 | Pisos y paredes pintables con la marca de la empresa | constructor-negocio | low | cosmético |
| D-0929 | Segundo piso/mezanine construible (D-0631) | constructor-mundo | high | test |
| D-0930 | Ventanas y techo con claraboyas (día/noche) | constructor-mundo | low | captura |
| D-0931 | Zona de carga para varios vehículos a la vez | constructor-mundo | medium | test |
| D-0932 | Estacionamiento de camiones de proveedores ampliado | constructor-mundo | medium | ver D-0640 |
| D-0933 | Alarma de incendio/evento (caja explosiva en el galpón) | constructor-trampas | medium | evento |
| D-0934 | Mapa de calor de tránsito de empleados (para optimizar) | constructor-ui | medium | overlay |
| D-0935 | Herramienta de medir tiempos por estación (cuello de botella) | constructor-ui | medium | overlay |
| D-0936 | Exterior del galpón que cambia con la etapa (cartel, playón) | constructor-mundo | medium | 4 variantes |
| D-0937 | Galpones secundarios en otros distritos (D-0330) | constructor-mundo | high | test |
| D-0938 | Ajuste fino sin grilla (modo libre) para decoración | constructor-negocio | low | test |
| D-0939 | Colisiones de objetos colocados livianas (cajas simples) | perfilador-rendimiento | medium | física medida |
| D-0940 | Reubicar objetos con productos adentro sin perderlos | constructor-negocio | medium | test |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0941 | Sonido y polvo al colocar | disenador-audio | low | SFX |
| D-0942 | Animación de "pop" al colocar | animador | low | tween |
| D-0943 | Cámara de construcción cómoda (zoom, paneo) | constructor-ui | medium | test de input |
| D-0944 | Shader de previsualización (holograma) | artista-shaders | low | material |
| D-0945 | Iconos del catálogo de construcción | artista-conceptual* | medium | íconos |
| D-0946 | Captura del galpón en cada etapa | revisor-visual | low | 4 capturas |
| D-0947 | `bench_depot` con galpón grande lleno | perfilador-rendimiento | high | FPS ≥ objetivo |
| D-0948 | Test de layouts inválidos (estación encerrada) | escritor-tests | medium | test |
| D-0949 | QA del modo construcción | probador-qa | medium | tabla |
| D-0950 | Documentar cómo agregar un objeto colocable | documentador | low | guía |
