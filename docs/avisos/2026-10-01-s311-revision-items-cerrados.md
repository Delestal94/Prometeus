# S-311: revisión de los ítems cerrados (.1–.9, .11, .18) y retoques

Para Slatex, de Nacho. Se revisó solo lo marcado `[x]` en S-311; nada de lo abierto
(.10, .12–.17 y los bloques C–O) se tocó, y `build_gel_body.py` y `review_bloque_b/`
quedan como estaban. **Hacé pull antes de seguir con el bloque B.**

## Lo que está muy bien

- Las medidas se pueden reproducir (`measure_reference.py` con asserts de caja y
  colores), y los 12 criterios del bloque E tienen umbrales numéricos, no adjetivos.
- El presupuesto técnico es concreto y está escrito como compuerta.
- El cuerpo se regenera con un comando, el validador `--gel-body` es estricto (malla
  cerrada por ciclo de enlace, normales hacia afuera, 53 poses de morphs) y no
  rompe el validador genérico.
- La honestidad de los cierres: lo pendiente está dicho con cifras (UV 61 %, núcleo
  fuera de presupuesto) en vez de marcado como hecho.

## Lo que se cambió en este PR

1. **S-311.2, la imagen anotada era generada con IA.** Redibujaba la figura en otra
   resolución, así que no se podía medir sobre ella. Ahora `annotate_reference.py`
   dibuja las cotas de la tabla sobre la foto original sin reescalarla y regenera
   `referencia/proporciones.png`. Se borró `proporciones_prompt.md` y se anotó el
   reemplazo en `art/ai-registro.md`.
2. **S-311.7, el cupo de huesos no dejaba lugar para el bloque F.** Era ≤ 20 en total
   con jiggle incluido, y el cuerpo ya exporta 20 de juego, mientras S-311.44 pide
   jiggle en cabeza, panza, antebrazos y pantorrillas. Decisión de Nacho: **≤ 26 =
   20 de juego + hasta 6 de jiggle** (`LEEME.md`, tabla de presupuesto). Falta que
   cambies la cifra en el texto de S-311.7 de tu lista; esa lista no la tocamos.
3. **S-311.9, el candidato seguía en el árbol.** El ítem dice que el cuerpo nuevo lo
   reemplaza y que queda como historia en git. Se quitaron `build_gel_character.py`,
   `gel_character_candidate.glb` y `.png` (2,7 MB); ningún test los usaba. Para verlo:
   `git show 7a3e211:art/gel_character/gel_character_candidate.glb`.
4. **S-311.18, test más legible.** `test_gel_body_asset.gd` informaba un error por cada
   vértice o UV no finito (miles si falla una exportación); ahora informa una vez por
   LOD con la cantidad. Pasa 1/1.

## Sugerencias para cuando sigas con B

- Los tres `.import` de `assets/models/characters/gel/` tienen `meshes/generate_lods=true`:
  Godot arma LODs automáticos encima de los tuyos. Apagalo desde el panel Import del
  editor (no se edita a mano).
- `review_bloque_b/` pesa: `geometry_metrics.json` (1,1 MB) y las rondas viejas
  (`final_captures/`, `diagnostic_failure_initial/`) que el propio `ESTADO_ACTUAL.md`
  marca como no vigentes. Si no las necesitás, conviene sacarlas; el repo no usa LFS.
- En `ESTADO_ACTUAL.md`, `review.md` y la nota de B de tu lista hay números pegados a
  las palabras ("aislado,11morphs,20huesos"); cuesta leerlos.
- La forma todavía se aleja de la foto en cuello (largo y fino), torso (rectangular) y
  botas (de bloque): ya lo tenés anotado para .10/.13. La hoja nueva de proporciones
  sirve para comparar sobre la foto real.
