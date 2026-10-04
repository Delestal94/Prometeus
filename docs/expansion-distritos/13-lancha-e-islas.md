# Grupo 13 — Lancha, agua, Puerto e Islas

> Fase **F3** · Dueño: Nacho · Depende de: D-0227 (`buoyancy`), D-0208, D-0415.
> Islas: casas en islotes, muelles y caminos de arena; la lancha cruza, el carrito recorre la isla.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1301 | Agua: plano con olas por shader (GL Compatibility) y altura consultable desde CPU | artista-shaders | xhigh | la altura de la ola en CPU coincide con el shader ±5 cm (test) |
| D-1302 | Lancha: flotación por puntos, empuje, timón, deriva | constructor-camion | xhigh | bot cruza a la isla en 10 corridas sin volcar |
| D-1303 | Oleaje que mueve la carga (fuente de riesgo como los baches) | constructor-camion | high | medición de impactos en la carga como N-105 |
| D-1304 | Lancha en red (suavizado y predicción) | constructor-red | xhigh | test de red con oleaje |
| D-1305 | Muelle de carga en Puerto (anexo del galpón) | constructor-mundo | high | cargar la lancha desde el muelle |
| D-1306 | Atracar en un muelle de isla (zona de amarre) | constructor-camion | high | test: amarrar frena la lancha |
| D-1307 | Bajar con la carga al muelle y caminar/carrito a la casa | constructor-jugador | high | test |
| D-1308 | Caer al agua: jugador nada, paquete flota o se hunde según embalaje | constructor-jugador | high | test de los dos casos |
| D-1309 | Rescate de paquete en el agua (bichero, red) | constructor-jugador | medium | test |
| D-1310 | Generación del archipiélago por semilla (islas, muelles, casas) | constructor-tramos | xhigh | 3 semillas distintas con capturas |
| D-1311 | Navegación: boyas y faros como guía (como el GPS) | constructor-mundo | medium | test |
| D-1312 | Límite del mapa en agua (corriente que devuelve) | constructor-mundo | medium | test |
| D-1313 | Distrito Puerto en tierra (grúas, contenedores) — ver D-1535 | constructor-mundo | high | escena cargable |
| D-1314 | Islas: casas sobre pilotes, cabañas, faro | constructor-mundo | high | 4 tipos de casa de entrega |
| D-1315 | Marea (sube y baja; algunos muelles quedan inaccesibles) | constructor-mundo | medium | test por hora |
| D-1316 | Modelo 3D de la lancha de reparto | modelador-blender* | high | modelo con asientos y cámaras |
| D-1317 | Asientos de la lancha (timonel + 3-5 pasajeros con carga) | constructor-camion | medium | test |
| D-1318 | Sonido de motor fuera de borda y agua | disenador-audio | medium | SFX |
| D-1319 | Salpicaduras y estela | artista-vfx | medium | partículas medidas en FPS |
| D-1320 | Test de referencia de la lancha | escritor-tests | high | `test_reference_boat` |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1321 | Mal tiempo en el mar (olas grandes, lluvia) | constructor-mundo | medium | perfil de clima |
| D-1322 | Gaviotas que roban (reusa `cargo_gull.gd`) | constructor-mundo | low | variante |
| D-1323 | Rocas y bajíos que golpean el casco | constructor-tramos | medium | test de daño |
| D-1324 | Delfines/ballena que asustan (peligro gracioso) | constructor-mundo | low | evento |
| D-1325 | Lancha grande (mejora) | constructor-camion | medium | test |
| D-1326 | Kayak/bote a remo para islas cercanas (2 remeros coordinados) | constructor-camion | high | test de red |
| D-1327 | Ferry que lleva vehículos (carrito) a la isla | constructor-mundo | high | test |
| D-1328 | Puente colgante entre islas a pie | constructor-tramos | medium | test |
| D-1329 | Combustible de la lancha (si D-0505) | constructor-camion | low | test |
| D-1330 | Productos de Islas (pescado, cocos) como proveedor | constructor-negocio | low | `.tres` |
| D-1331 | Clientes de Islas con pedidos raros (faro, náufrago) | constructor-progresion | low | 6 pedidos |
| D-1332 | Entrega directo en un barco anclado | constructor-progresion | medium | test |
| D-1333 | Hidroavión (puente a F4) | critico-diseno | low | decisión |
| D-1334 | Arena: carrito se entierra si va lento | constructor-camion | medium | test |
| D-1335 | Palmeras y vegetación con viento | constructor-mundo | low | shader de viento reusado |
| D-1336 | Noche en el mar con faros y bioluminiscencia | constructor-mundo | low | captura |
| D-1337 | Grúa del puerto para cargar contenedores | constructor-mundo | medium | test |
| D-1338 | Tormenta que cierra el distrito ese día | constructor-progresion | low | evento |
| D-1339 | Pesca de paquetes perdidos (mini-objetivo) | critico-diseno | low | decisión |
| D-1340 | Trampa "Mojable" en contexto (D-0739) | constructor-trampas | medium | test en Islas |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1341 | Modelos de islas, muelles, pilotes, faro | modelador-blender* | high | kit modular |
| D-1342 | Textura de arena y roca húmeda | artista-shaders | medium | material |
| D-1343 | Color del agua por profundidad | artista-shaders | medium | captura |
| D-1344 | Ambiente sonoro de Islas (olas, gaviotas) | disenador-audio | low | loop |
| D-1345 | Mareo en primera persona: ajustar cámara de la lancha | constructor-jugador | medium | parámetros |
| D-1346 | Rendimiento del agua en GPU baja | perfilador-rendimiento | high | presets de calidad |
| D-1347 | Capturas de Islas para Steam | revisor-visual | low | 5 capturas |
| D-1348 | Auditoría de red de la lancha | auditor-red | high | sin P0-P1 |
| D-1349 | QA de Islas | probador-qa | medium | tabla |
| D-1350 | Test de humo de Islas en CI | escritor-tests | medium | test |
