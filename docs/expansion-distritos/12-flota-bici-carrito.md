# Grupo 12 — Flota: base común, garaje, bici y carrito

> Fase **F2** · Dueño: Nacho · Depende de: D-0103, D-0207, D-0208, D-0209.
> La camioneta deja de ser "el vehículo" y pasa a ser uno de la flota. Bici para Barrio Centro y zonas
> peatonales; carrito para Suburbio e Islas (ver D-0103).

## Núcleo — base y bici

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1201 | Flota de la empresa en `CompanyState` (qué vehículos hay, estado, mejoras) | constructor-progresion | medium | test |
| D-1202 | Elegir vehículo en el despacho (D-0303) | constructor-ui | medium | test |
| D-1203 | Capacidad de carga por vehículo (cajas y peso) | constructor-camion | medium | test: no entra la caja 7 en la bici |
| D-1204 | Asientos variables por vehículo (1 a 8) con la cámara de asiento actual | constructor-camion | high | test con 2 y 6 asientos |
| D-1205 | Garaje en el galpón donde se ven y eligen los vehículos | constructor-mundo | high | captura |
| D-1206 | Daño persistente del vehículo entre salidas y reparación en el garaje | constructor-camion | medium | test |
| D-1207 | Bici: física de dos ruedas estable (equilibrio asistido) | constructor-camion | xhigh | bot recorre Barrio Centro sin caerse en 10 corridas |
| D-1208 | Bici: pedaleo (input), cambios, freno, derrape | constructor-camion | high | test de velocidades |
| D-1209 | Bici: canasto delantero y caja trasera (2-3 paquetes) | constructor-camion | high | carga viaja y sufre los baches |
| D-1210 | Bici tándem para 2 jugadores (uno pedalea, otro cuida carga) | constructor-camion | high | test de red con 2 |
| D-1211 | Bici con trailer de carga (más cajas, peor manejo) | constructor-camion | medium | test |
| D-1212 | Caída de la bici con ragdoll (reusa `modules/ragdoll`) | constructor-jugador | high | test |
| D-1213 | Bici en red (suavizado como la camioneta) | constructor-red | xhigh | test de red |
| D-1214 | Presentación de la bici (pedales giran, cadena, timbre) | constructor-camion | medium | captura |
| D-1215 | Timbre de la bici como bocina con función (N-107) | constructor-camion | low | test |
| D-1216 | Estacionar la bici y bajar a pie para entregar | constructor-jugador | medium | test |
| D-1217 | Modelo 3D de la bici de reparto | modelador-blender* | high | modelo con pivotes según `agregar-vehiculo.md` |
| D-1218 | Modelo de la tándem y del trailer | modelador-blender* | medium | modelos |
| D-1219 | Sonidos de bici (cadena, frenos, timbre) | disenador-audio | low | SFX |
| D-1220 | Test de referencia de manejo de la bici (como `test_reference_truck`) | escritor-tests | high | `test_reference_bike` |

## Ampliación — carrito y garaje

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1221 | Carrito (según D-0103): física y manejo | constructor-camion | high | bot recorre Suburbio |
| D-1222 | Carrito: 2-4 asientos y caja de carga abierta | constructor-camion | medium | test |
| D-1223 | Carrito: batería que se carga en el galpón o en enchufes del distrito | constructor-camion | medium | test |
| D-1224 | Carrito en caminos de tierra y arena (Islas) | constructor-camion | medium | test de tracción |
| D-1225 | Carrito en red | constructor-red | high | test de red |
| D-1226 | Presentación del carrito (techito que vibra, luces) | constructor-camion | low | captura |
| D-1227 | Modelo 3D del carrito | modelador-blender* | high | modelo |
| D-1228 | Sonido del carrito (motor eléctrico, bocina chiquita) | disenador-audio | low | SFX |
| D-1229 | Test de referencia del carrito | escritor-tests | medium | `test_reference_cart` |
| D-1230 | (Si D-0103 incluye zorra) carrito de mano empujado a pie con cajas apiladas | constructor-jugador | high | test de equilibrio |
| D-1231 | Camioneta 4x4 (variante de la actual con más tracción y suspensión) | constructor-camion | high | `test_reference_truck_4x4` |
| D-1232 | Camión grande (mejora tardía: más carga, peor en curvas) | constructor-camion | high | test |
| D-1233 | Mejoras de vehículo (suspensión, motor, frenos, estantes internos) | constructor-camion | medium | efecto medido |
| D-1234 | Pintura y logo de la empresa en la flota | constructor-camion | medium | cosmético |
| D-1235 | Remolcar un vehículo roto (gancho de rescate actual) | constructor-camion | medium | test |
| D-1236 | Cambio de vehículo en un hub (dejar la camioneta y seguir en bici) | constructor-mundo | high | test |
| D-1237 | Vehículo llevado en otro (bici en la caja de la camioneta) | constructor-camion | high | test de física |
| D-1238 | Seguro y costo de reparación por vehículo | constructor-progresion | low | test |
| D-1239 | Vehículos manejados por NPC en salidas automáticas (D-1028) | constructor-negocio | medium | sim |
| D-1240 | Pantalla de flota en el portapapeles | constructor-ui | medium | captura |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1241 | Balance de cada vehículo (velocidad, carga, riesgo) vs. D-0115 | pulidor-jugabilidad | high | tabla medida con bots |
| D-1242 | Cámara de primera persona en la bici sin mareo (head bob) | constructor-jugador | medium | parámetros medidos |
| D-1243 | Partículas de polvo y agua para bici y carrito | artista-vfx | low | partículas |
| D-1244 | Marcas de frenada de bici | artista-vfx | low | decal |
| D-1245 | Animación del jugador pedaleando | animador* | high | clip |
| D-1246 | Mandos: manejo de bici con gatillos | constructor-ui | medium | test de input |
| D-1247 | Rendimiento con 4 vehículos en el garaje | perfilador-rendimiento | low | medido |
| D-1248 | Auditoría de red de la flota | auditor-red | high | sin P0-P1 |
| D-1249 | QA de cada vehículo | probador-qa | medium | tabla |
| D-1250 | `agregar-vehiculo.md` con bici y carrito como ejemplos | documentador | low | doc actualizado |
