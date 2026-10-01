# Pantalla "Hacé tu personaje" nueva, caras rubber hose y vestuario del depósito (N-506)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

**Caras** (`art/rounded_character/build_faces.py` → `assets/textures/characters/faces/`): estilo rubber hose
(ojos altos y juntos con pupila en cuña, cejas cortas, paréntesis en las comisuras, bocas oscuras con lengua),
ojos un 15 % y bocas un 22 % más grandes. Ocho ojos y ocho bocas: se suman `determined` ("Decididos") y `smirk` ("Pícara").
Los IDs viejos siguen valiendo, así que los perfiles guardados no cambian. "Dormilones" pasa a llamarse "Con
sueño" y "Preocupados", "Nerviosos", para que entren en una línea.

- `scripts/core/face_catalog.gd`: `texture()` acepta también `"brows"` (por id de ojos; devuelve null si no
  hay, como con `none`). Entran `THUMB_EYES`, `THUMB_MOUTH` y `THUMB_FACE`, el recorte que muestran las
  tarjetas, y `PRESETS` / `preset(id)`: ocho caras armadas (un par ojos + boca cada una; no se guardan, se
  guardan los dos rasgos).
- `scripts/presentation/character_face.gd`: tercera capa `Brows` sobre la misma malla. El parpadeo aplasta solo
  `Eyes`: antes las cejas de "Preocupados" estaban en la textura de los ojos y bajaban en cada parpadeo.
  `EYE_LINE_V` está medido sobre los SVG nuevos. **La cara ya no sale espejada**: `_patch_point()` llevaba
  la `u` hacia +X, que en un modelo que mira a -Z es la izquierda de quien lo mira. El guiño, la gota de
  sudor y el brillo de las pupilas caían del lado contrario al del dibujo. Umbral de recorte alfa 0,22 (era
  0,35), para que de lejos los trazos finos no se rompan en puntos.

**Pantalla** (`scripts/ui/cosmetics_panel.gd`, tu dominio; reescrita):
- A la izquierda va el personaje 3D en un estudio con luz propia (`scripts/ui/customize/character_preview.gd`):
  primer plano de la cara en la pestaña Rostro y cuerpo entero en las demás. Se gira arrastrando o con el stick
  derecho (`look_left` / `look_right`), y rebota cuando cambiás algo. Debajo están el apodo y "Sorprendeme".
- A la derecha, las pestañas (subrayado de tinta) con tarjetas con dibujo
  (`scripts/ui/customize/customize_swatch.gd`): la piel con los ojos o la boca, la cara entera de cada cara
  armada, la remera del uniforme y la furgoneta en su pintura. En Rostro entran sin scroll, a 720p, las
  caras armadas, los 8 ojos y las 8 bocas, en filas de 8. Las de Uniforme son altas, como un perchero. La
  elegida tiene tinte menta, borde de tinta y un tilde. Las bloqueadas aparecen deshabilitadas, con un
  candado, y dicen con qué se ganan.
- Las tarjetas se actualizan en el lugar (`_sync()`): el escenario no se reconstruye en cada clic.
- Ahora hay `mode` (`Mode.MENU` / `Mode.DEPOT`) y `page` (`Page.FACE` / `UNIFORM` / `TRUCK`), que se fijan
  antes de entrar al árbol, y `focus_first()`. `open()`, `close()` y la señal `closed` no cambian.
- Foco: el apodo queda a la **izquierda** de las tarjetas (antes estaba arriba), las pestañas arriba y Listo
  abajo.
- La remera de la vista previa se tiñe con `PlayerAppearance.tint_shirt`, la del juego. Con "Color de equipo"
  muestra el color de tu slot (`PlayerColorSlot`), no el amarillo genérico.
- Se borró `scripts/ui/face_preview.gd` (la cara 2D plana).

**Depósito** (`scripts/ui/depot_panel.gd`, tu dominio): la estación `wardrobe` ya no arma su tarjeta de
uniformes. Abre `CosmeticsPanel` en `Mode.DEPOT` (Rostro y Uniforme, sin Camión) como hijo "Wardrobe". Cerrarla
cierra el panel del depósito. Lo que elegís llega en vivo a tu jugador y, por la réplica que ya existía
(`face_eyes`, `face_mouth`, `cosmetic_id`, `PlayerNickname`), al resto. `progress_changed` ya no reconstruye
el panel en el vestuario.

**Textos** (`strings_ui.csv`): entran `UI_COSM_RANDOM`, `UI_COSM_RANDOM_HINT`, `UI_COSM_ROTATE_HINT`,
`UI_COSM_UNLOCK_AT`, `UI_COSM_PRESETS`, `UI_COSM_PRESETS_HINT`, `UI_FACE_PRESET_*`, `UI_FACE_EYES_DETERMINED` y
`UI_FACE_MOUTH_SMIRK`; cambian los textos de `UI_FACE_EYES_SLEEPY` y `UI_FACE_EYES_WORRIED`. Salen
`UI_COSM_PREVIEW_HINT`, `UI_COSM_LOCKED_SUFFIX` y `UI_DEPOT_UNIFORM_TAG`, que no quedaron en uso.

**Tests:** `test_customization_screen` (nuevo). También se adaptaron `test_character_faces` (cejas y vista 3D),
`test_nickname` (foco a la izquierda) y `test_gamepad_focus` (grilla nueva y vestuario).

## Qué tiene que hacer Slatex

Nada obligatorio. Si agregás un cosmético nuevo, sumalo a `UnlockManager` y aparece solo como tarjeta: una
remera si tiene `color`. Para un gorro haría falta un dibujo nuevo en `customize_swatch.gd`.
