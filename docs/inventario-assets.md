# Inventario de assets — Take My Package

> Última actualización: 2026-09-23 (relevamiento de modelado pendiente, sección 10)
> Es **la lista** de assets del juego: qué existe, qué falta integrar y qué falta crear.
> Cuando se crea o se integra algo, se actualiza acá. Complementa
> `docs/especificaciones-visuales.md` (qué mejorar visualmente) y
> `docs/direccion-visual.md` (cómo tiene que verse).

**Estados:** ✅ en el juego · 🟡 creado, falta integrarlo · ⬜ falta crearlo · ⛔ no tocar por ahora

**Cómo se generan:**
- Modelos 3D: scripts de Blender 5.2 en `do-not-drop/assets/tools/` (helpers compartidos en
  `lowpoly_kit.py`). **`build_lowpoly_refined.py` es la fuente** de casas, granero, bosque,
  señales, mobiliario y jardín (grupos `houses trees plants signs props yard`). Los lotes
  viejos quedan solo para lo que no se rehizo: `build_lowpoly_glb_assets.py` (cajas por trampa,
  autos estacionados) y `build_lowpoly_glb_assets_batch2.py` (baranda de puente, molino, tanque,
  horizonte, celular, guantes). Low-poly, origen en la base, metros; frentes a −Z en Godot.
  Los materiales se llaman como la entrada de la paleta (`wood`, `roof`, `leaf`...).
- Texturas: **mapas de detalle** en gris (`assets/textures/detail/`), generados con
  `art/tools/make_detail_textures.py` (ComfyUI + Z-Image Turbo → pasa-altos → repetible sin
  costura → contraste normalizado). No cambian el color: lo multiplican. En los modelos los
  aplica `scripts/presentation/lowpoly_materials.gd` por nombre de material, con proyección
  triplanar en espacio de mundo; en el terreno, `shaders/route_terrain.gdshader`.
- Imágenes 2D: ComfyUI local + Z-Image Turbo con `art/tools/comfy_generate.py` (o el agente
  `artista-conceptual`). Estilo en `art/prompts/estilo-base.md`; cada imagen conservada se anota en
  `art/ai-registro.md` (declaración de IA de Steam).
- **Dónde aparece cada cosa:** no lo decide el asset sino las reglas de
  `scripts/gameplay/route/route_dresser.gd` (ver sección 9).

---

## 1. Interfaz 2D (`assets/ui/`, dominio Slatex salvo lo indicado)

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Fondo del menú principal | `ui/backgrounds/tx_ui_menu_background_1920.png` | ✅ | Integrado en `main_menu.gd` (2026-09-23) con tinte oscuro encima. |
| Splash de arranque | `ui/backgrounds/tx_ui_boot_splash_1920.png` | ✅ | `project.godot` → `boot_splash/*`, modo Cover. Reemplaza el logo de Godot. |
| Ícono de la app | `icon.png`, `ui/icons/tx_ui_app_icon_1024.png` | ✅ | `config/icon`. |
| Ícono del .exe | `ui/icons/app_icon.ico` | ✅ | `export_presets.cfg` → `application/icon`. |
| Íconos de trampa (×4) | `ui/icons/tx_ui_trap_{fragile,balance,growing_weight,noisy}_256.png` | ✅ | En el HUD, al lado de cada paquete de la carga (se apagan si el paquete se pierde). |
| Logo del juego (wordmark) | `UiTheme.logo()` | 🟡 | Armado con tipografía (Lilita One + cinta amarilla) en menú. Falta pasarlo a imagen para el splash, el ícono y Steam. |
| Fondo de pantalla de resultados | — | ⬜ | Ilustración: la tripulación frente a la furgoneta al terminar la ruta. |
| Cápsulas de Steam (460×215, 616×353, 231×87, 1232×706, 600×900, 3840×1240) | — | ⬜ | Necesitan el logo. Fase de lanzamiento. |
| Íconos de acción del HUD (agarrar, sentarse, timbre, foto, bocina, ping) | — | ⬜ | Hoy los prompts son solo texto. |
| Marco del celular / UI de cámara | — | ⬜ | Para `phone_camera.gd`. |

| Tipografías | `assets/fonts/LilitaOne-Regular.ttf`, `Nunito-Variable.ttf` | ✅ | OFL (licencias al lado). Sistema de UI en `docs/direccion-visual.md` §3. |

## 2. Personajes y viewmodel (dominio Slatex)

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Jugador low-poly con 5 animaciones | `models/characters/sm_char_player_lowpoly.glb` | ✅ | |
| Guantes del viewmodel (izq./der.) | `models/characters/sm_char_viewmodel_glove_{left,right}.glb` | ✅ | Espec. #20. Origen en la muñeca, dedos a +Z. La manga usa el material `PlayerTint` para teñirla por jugador. Los carga `player.gd` (`_build_viewmodel_gloves`). |
| Celular en la mano | `models/props/handheld/sm_prop_phone.glb` | 🟡 | Pantalla hacia −Z en Godot, lente atrás. Para `phone_camera.gd`, que todavía no lo carga. Es de los más simples (92 triángulos) y se ve en primer plano: rehacerlo antes de integrarlo (sección 10). |
| Accesorios/cosméticos (gorras, chalecos) | — | ⬜ | Fase 5 (progresión). |

## 3. Paquetes (dominio Slatex)

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Cajas abribles por trampa: cubo (frágil), ventilada (ruidoso), alta (equilibrio), plana (peso creciente) | `models/cargo/sm_cargo_box_{cube,vented,tall,flat}.glb` | ✅ | Espec. #17 (2026-09-23). Cuerpo + 4 solapas con pivote en la bisagra, cinta de marca cortada en la unión. Las usa `package_feedback.gd` vía `data/contents/*.tres`. Las viejas `sm_cargo_package_*.glb` quedan sin uso. |
| Impresión del cartón (logo, "este lado arriba", copa, paraguas, código de barras, sello del fondo, cinta) | `art/cargo/tx_cargo_box_*_2048.png` (embebidas en los GLB) | ✅ | Espec. #18. Dibujadas con PIL por `art/tools/make_cargo_textures.py`. |
| Etiqueta de envío | `textures/cargo/tx_cargo_shipping_label_512.png` | ✅ | En el dorso de la caja; el contenido declarado va encima como `Label3D`. |
| Contenidos: jarrón de porcelana, gallina, torta de bodas, masa madre | `models/cargo/contents/sm_cargo_content_*.glb` | ✅ | Cada uno con `Filler`, `Intact`, `Damage` (en riesgo) y `Ruined` (piezas sueltas que salen como cuerpos rígidos si se derrama). `assets/tools/build_cargo_packages.py`. |

## 4. Ruta: señales y mobiliario (dominio Nacho)

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Señal de curva | `models/environment/signs/sm_env_sign_curve.glb` | ✅ | Antes de `CurveSegment` / `SCurveSegment`. Se espeja sola en las curvas a la izquierda. |
| Señal de lomo de burro | `…/sm_env_sign_speed_bump.glb` | ✅ | Antes de `SpeedBumpSegment`. |
| Señal de puente angosto | `…/sm_env_sign_narrow_bridge.glb` | ✅ | Antes de `NarrowBridgeSegment` / `ChicaneSegment`. |
| Señal de ripio | `…/sm_env_sign_gravel.glb` | ✅ | Antes de `GravelSegment`. |
| Señal de obras | `…/sm_env_sign_roadworks.glb` | ✅ | Antes de `ConstructionZoneSegment`. |
| Cartel "entrega adelante" | `…/sm_env_sign_delivery_ahead.glb` | ✅ | ~80 m antes de cada casa, del lado de la casa. |
| Guardarraíl (4 m) | `models/environment/props/sm_env_prop_guardrail.glb` | ✅ | Del lado de afuera de cada `CurveSegment`, cada 4 m. |
| Baranda de puente (6 m) | `…/sm_env_prop_bridge_railing.glb` | 🟡 | Opcional: el puente ya tiene barandas con colisión hechas en código. |
| Conos, barrera, farol, banco, buzón | `…/props/sm_env_prop_*.glb` | ✅ | Lote 1. |
| Fardo, cajón de madera, pallet, hidrante, parada de colectivo, mojón | `…/props/sm_env_prop_{hay_bale,wooden_crate,pallet,fire_hydrant,bus_stop,milestone}.glb` | ✅ | En la rotación de mobiliario de banquina; pallet y cajón además detrás de la valla de obras. |
| Cables entre postes | — | ⬜ | Espec. #53. Se genera en código (curva entre postes), no como GLB. |
| Poste eléctrico, cerca, tacho, señal genérica | `models/environment/sm_env_*.tscn` | ✅ | Lote 0 (escenas nativas). |

## 5. Casas de entrega y jardines (dominio Nacho)

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Casas cottage, cabin, bungalow | `models/architecture/sm_arch_delivery_house_*.glb` | ✅ | |
| Casa de dos pisos, casa de campo con galería | `…/sm_arch_delivery_house_{two_story,farmhouse}.glb` | ✅ | Las cinco casas se reparten como un mazo con la semilla de la sesión (no se repiten hasta usarlas todas). Colisión propia por modelo en `delivery_house.gd`. |
| Granero | `…/sm_arch_barn.glb` | ✅ | Aparece al lado de la casa de campo. |
| Cerca de estacas, maceta, enano de jardín, cucha, felpudo | `models/environment/yard/sm_env_yard_*.glb` | ✅ | `route.gd::_build_yard()`: felpudo y macetas sobre el porche; cerca a los costados, enano, cucha (una de cada dos). Cada pieza del lote pasa por las reglas y se descarta si no entra. Sin colisión. |
| Timbre / panel de puerta | — | ⬜ | Hoy `doorbell_point.gd` es una caja. |

## 6. Mundo lejano y cielo (dominio Nacho)

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Anillo de montañas en el horizonte | `models/environment/sky/sm_env_horizon_mountains.glb` | ✅ | Espec. #59. `route_sky.gd` (ruta y endless): a ~280 m, sigue a la cámara, sin niebla y con el tinte de la niebla de cada nivel. |
| Nubes | `shaders/stylized_sky.gdshader` | ✅ | Espec. #58. Pintadas en el cielo: planas, dos tonos, se mueven despacio; `route_sky.gd` convierte el `ProceduralSkyMaterial` de cada nivel conservando sus colores. Las nubes 3D (`sm_env_sky_cloud_*`) se retiraron el 2026-09-23: con luz se veían como piedras flotando. |
| Tanque de agua, molino | `models/environment/landmarks/sm_env_landmark_{water_tower,windmill}.glb` | ✅ | Regla `landmark`: sobre todo en zona de campo, a 42-56 m, nunca dos a menos de 170 m. El nodo `WindmillRotor` gira sobre su eje local **Z** en Godot. |
| Bosque (6 árboles + 13 piezas de sotobosque) | `models/environment/forest/` | ✅ | |
| Fauna: ciervo (con rig), conejo, rana, pájaro | `models/environment/wildlife/sm_env_animal_*.glb` | ✅ | Reglas de fauna en `route_dresser.gd`; el ciervo además cruza la ruta (`wildlife_crossing.gd`). |
| Señal de cruce de animales | `models/environment/signs/sm_env_sign_animal_crossing.glb` | ✅ | Antes del cruce de fauna. |
| Texturas de terreno | `textures/detail/tx_detail_{asphalt,earth,grass,gravel}_512.png` | ✅ | Reemplazan a `textures/terrain/*` (rayas procedurales con grilla visible, nunca se usaron). |
| Texturas de modelos | `textures/detail/tx_detail_{wood_planks,roof_shingles,plaster,bark,foliage,stone}_512.png` | ✅ | Vía `LowpolyMaterials`; vidrios, pintura y señales quedan lisos a propósito. |

## 7. Vehículos

| Asset | Archivo | Estado | Notas |
|---|---|---|---|
| Furgoneta de reparto (exterior, interior, puertas, espejos, tablero, asientos) | `vehicle.tscn`, `truck_reference_lowpoly.glb` | ✅ | Modelo de Slatex, en uso vía `reference_truck.gd`. Espec. #5-#12, #14-#16 hechas salvo líneas de paneles (#8). No regenerarlo desde los scripts de lote. |
| Autos estacionados: hatchback, pickup | `models/vehicles/sm_vehicle_parked_*.glb` | ✅ | |
| Más autos estacionados (sedán, camioneta de reparto de la competencia), tractor | — | ⬜ | Espec. #55. |

## 8. Audio (hoy todo sintetizado en `synth_audio.gd`)

| Asset | Estado | Notas |
|---|---|---|
| Motor, golpes, neumáticos, trampas, bocina, viento, obturador | ✅ | Sintetizados en código. |
| Música de tensión según el riesgo | ⬜ | Espec. #47. |
| Pájaros y ruido lejano de ruta | ⬜ | Espec. #45 (parcial). |

---

## 9. Reglas de generación del mundo (`route_dresser.gd`)

Equivalente a la colocación de "features" de Minecraft. Cada tipo de objeto tiene una regla:
franja lateral, separación a lo largo de la ruta, densidad por zona, huella que ocupa,
distancia mínima al asfalto, pendiente máxima, hacia dónde mira, escala, y distancia mínima a
otro de su misma clase. Todo pasa por los mismos cinco chequeos (ruta, zona despejada,
ocupación, misma clase, pendiente) y lo que no entra **se descarta**: nunca se empuja a un
lugar que no le corresponde. `dresser.rejected_counts` dice por qué se rechazó cada cosa.

| Zona | Dónde | Qué aparece |
|---|---|---|
| Pueblo | a menos de 110 m de una casa de entrega | faroles, bancos, buzones, hidrantes, parada de colectivo, autos, árboles ralos |
| Campo | tramos abiertos elegidos por ruido a lo largo de la ruta | fardos, cajones, pallets, molino/tanque, árboles sueltos, autos |
| Bosque | el resto | el corredor de árboles denso |

Prioridad: primero lo explícito (jardines, señales, guardarraíles, obra), después las reglas en
orden (hitos, autos, mobiliario de pueblo, parada, mojones, cosas de campo, árboles, plantas).
Determinista con la semilla de la sesión: todos los jugadores ven lo mismo. Test:
`tests/test_route_placement_rules.gd`.

## 10. Modelado pendiente y modelos a mejorar (relevamiento 2026-09-23)

Salió de revisar qué geometría del juego se sigue armando en código con primitivas
(`BoxMesh`, `CylinderMesh`, `CapsuleMesh`…) y de contar triángulos de cada GLB. Las tareas
correspondientes están en `docs/tareas-nacho.md` §128-139 y `docs/tareas-slatex.md` §101-106.

### 10.1 Falta modelar (hoy son primitivas en código)

| Qué | Dónde se arma hoy | Dominio | Tarea |
|---|---|---|---|
| Barrera de hormigón y conos de la zona de obras | `construction_zone_segment.gd` (caja de 5 m y cubos de 0,5 m) | Nacho | N-128. **Solo código:** ya existen `sm_env_prop_road_barrier.glb` y `sm_env_prop_traffic_cone.glb`. |
| Tren del paso a nivel (locomotora + vagones) | `rail_crossing_segment.gd` `_build_train()` (cajas de 7,5×3×2,6 m) | Nacho | N-129 |
| Paso a nivel: poste, cruz de San Andrés, luces, barrera, vías y durmientes | `rail_crossing_segment.gd` | Nacho | N-130 |
| Túnel: paredes, techo, portal, pilares, lámparas | `tunnel_segment.gd` | Nacho | N-131 |
| Puente angosto: tablero, postes, agua | `narrow_bridge_segment.gd` | Nacho | N-132 (la baranda GLB ya existe, sin integrar) |
| Bloques de la chicana | `chicane_segment.gd` | Nacho | N-133 |
| Poste eléctrico | `route_dresser.gd` (cilindro de 6 lados + caja) | Nacho | N-134 |
| Depósito: autoelevador, cinta transportadora, portón enrollable, estanterías, lámparas, ventiladores, reloj, insumos | `depot*.gd` (~160 primitivas horneadas con `depot_kit.gd`) | Nacho | N-135 |
| Autos estacionados nuevos: sedán, camioneta de la competencia, tractor | — | Nacho | N-136 (espec. #55) |
| Residente que abre la puerta | `delivery_house.gd` (cápsula) | Nacho | N-137 (puede reusar el modelo del jugador) |
| Timbre / panel de puerta | `doorbell_point.gd` | Nacho | N-137 |
| Ragdoll del jugador | `player_ragdoll.gd` (cápsulas) | Slatex | S-101 |
| Maniquí del panel de cosméticos | `cosmetics_panel.gd` (cápsula + esfera) | Slatex | S-102 |
| Manos del conductor en el volante | `vehicle_presentation.gd` (cápsulas) | Nacho | N-138 (usar los guantes GLB) |
| Objetos sueltos de la zona de carga (caja de herramientas, termo) | `cargo_clutter.gd` | Nacho | N-139 |
| Accesorios cosméticos (gorras, chalecos) | — | Slatex | S-103 |

### 10.2 Modelos existentes demasiado simples

Ordenados por cuánto se ven de cerca, no solo por triángulos. Low-poly es el estilo, así que
pocos triángulos no es un defecto en sí: importa en lo que queda cerca de la cámara.

| Prio | Modelo | Triángulos | Motivo | Tarea |
|---|---|---|---|---|
| Alta | Celular (`sm_prop_phone`) | 92 | Primer plano, en la mano | S-104 |
| Alta | Autos estacionados hatchback / pickup | 320 / 364 | Lote viejo sin refinar; en ruta y depósito | N-136 |
| Alta | Farol (`sm_env_prop_street_lamp`) | 132 | Muy repetido en pueblo y depósito | N-140 |
| Media | Molino / tanque de agua | 192 / 204 | Lote viejo; hitos que se leen por silueta | N-140 |
| Media | Buzón, mojón, cajón de madera, cono | 120–176 | Mobiliario que pasa cerca del camión | N-140 |
| Media | Enano de jardín, felpudo | 164 / 68 | En el porche, donde se entrega | N-140 |
| Baja | Roca, arbusto redondo, rama caída, tocón, mata de pasto | 80–192 | Variantes rinden más que detalle | N-141 |
| Baja | Baranda de puente | 352 | Lote viejo, sin integrar | N-132 |

Referencia: árboles 240–376, casas 2.300–3.400, contenidos de paquete 1.000–2.000 y el
jugador 1.568 triángulos están bien para el estilo.

### 10.3 Para limpiar

- `models/cargo/sm_cargo_package_{balance,fragile,heavy,vented}.glb`: sin uso desde las cajas
  por trampa (S-105).
- Lote 0 en escenas nativas, sin referencias en código ni escenas:
  `models/environment/sm_env_{fence_segment,trash_bin,tree_pine,utility_pole,warning_sign}.tscn`
  y `models/architecture/sm_arch_delivery_house_small.tscn` (N-142).

## Próximo paso sugerido

1. ~~Integrar lo 🟡 del dominio de Nacho~~ **Hecho (2026-09-23)**: tests en
   `tests/test_route_dressing_assets.gd`, capturas con `tests/render_route_dressing.gd`.
2. ~~Refinar casas, árboles, señales y mobiliario; texturas sutiles; nubes pintadas~~ **Hecho
   (2026-09-23)**.
3. **Avisar a Slatex** de lo 🟡 de su dominio (guantes, celular, cajas por trampa, íconos de
   trampa): los assets ya están, solo falta enchufarlos.
4. **Crear los ⬜ de mayor impacto:** el logo (lo necesitan menú, splash y Steam), los íconos
   de acción del HUD y el timbre.
5. **Modelado (sección 10):** primero N-128 (conos y barrera de obras, solo código), después
   el tren y el paso a nivel (N-129/N-130), el celular (S-104) y los autos (N-136).
