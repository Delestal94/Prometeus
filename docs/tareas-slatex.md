# Tareas de Slatex (Cristian) — Personaje 2.0 de gelatina

> **Una sola tarea**, S-311, partida en 100 ítems. Pedido del usuario (2026-09-29): todas las tareas
> anteriores de Slatex (S-101 a S-907, el modelado pendiente 101-106 y lo de "para cuando haya
> playtesting") pasaron a `docs/tareas-nacho.md`, sección **"Heredadas de Slatex"**, con sus mismos IDs.
>
> Los archivos siguen siendo de tu dominio (`docs/colaboracion-equipo.md`): Nacho y las rutinas van a
> tocar jugador, paquetes y UI para cerrar las heredadas, y cada PR deja un aviso en `docs/avisos/`.

## Cómo leer esta lista

- **ID**: `S-311` (pilar 3, arte). Los ítems son `S-311.1` a `S-311.100` y se marcan `[ ]` / `[x]` con el
  hash del commit.
- **Bloques**: A-O, en orden. Se puede adelantar un ítem de un bloque posterior si no depende de otro
  pendiente, pero **el bloque E (iterar contra la imagen) se cierra antes de pasar a skins, disfraces y
  bailes**: no se viste un cuerpo que todavía no se parece a la referencia.
- **Aviso**: los ítems que tocan archivos de Nacho (volante, asientos, camión, resultados, depósito) lo
  dicen; aviso nuevo en `docs/avisos/AAAA-MM-DD-tema.md` en el mismo commit (el camión, `vehicle.tscn` /
  `vehicle.gd`, incluido: ya no está congelado).
- **Necesita PC**: modelado, render de Blender e imágenes (Blender y ComfyUI). La parte de Godot
  (shaders, física, código, tests) corre en cualquier lado.
- **Sin playtesting**: todo se verifica con capturas, mediciones y tests.

---

## Modelo recomendado (Cristian usa ChatGPT)

Datos a septiembre de 2026. Hoy conviven la generación **GPT-6** (Astra, Sol, Luna) y la
anterior **GPT-5.6** (Sol, Terra, Luna). Terra **no tiene versión GPT-6**. Todos aceptan
esfuerzo de razonamiento `none`, `low`, `medium` (por defecto), `high`, `xhigh` y `max`.

| Modelo | Cuándo usarlo en esta tarea | Esfuerzo |
|---|---|---|
| **GPT-6 Sol** (tu modelo por defecto) | Scripts de Blender, clips de animación, shaders, panel de personalización, tests. | **high**; **xhigh** si toca 4+ archivos o red. |
| **GPT-6 Astra** | Lo difícil: proporciones que no rompen animaciones ni IK (bloque C), orden de transparencias y refracción (bloque D), ragdoll activo (bloque F), replicación de apariencia y ragdoll, un test que falla y no se entiende. | **high**; **xhigh** si falló una vez. |
| **GPT-6 Luna** | Documentos del bloque A, bitácora de iteraciones, nombres y textos de presets, skins y disfraces, `.tres` de colores. | **medium**. |
| **GPT-5.6 Terra** | **No usarlo.** Solo si tu plan no ofrece GPT-6: Terra en **high** en lugar de Sol. | — |

Si tu plan no ofrece Astra, usá **Sol en xhigh** donde diga Astra. Para comparar un render con la
referencia, pasale a ChatGPT **las dos imágenes** y el reporte del ítem 39, no una descripción.

### Cómo trabajar un ítem con ChatGPT

1. **Contexto**: `CLAUDE.md`, `docs/convenciones-godot.md` §0-2, `art/gel_character/LEEME.md` (ítem 1) y
   los archivos que nombra el ítem, **enteros** (de un archivo de más de ~800 líneas, solo las funciones
   que toca más la cabecera).
2. **Pedido**:
   > Proyecto Godot 4.7, GDScript tipado, renderer GL Compatibility, red host-autoritativa. Seguí el estilo
   > de los archivos adjuntos (comentarios `##`, nombres en inglés, textos de UI en español). Ítem:
   > `<pegar ítem>`. Devolveme: (1) el diff completo por archivo, (2) el test `tests/test_<tema>.gd`
   > (`extends SceneTree` + `_expect` + `quit(_failures)`) con su descripción en el encabezado.
3. **Verificar**: `tools/run-tests.sh <filtro>` (por ejemplo `tools/run-tests.sh gel`). Si falla, pegale
   solo el resumen (`tools/run-tests.sh -v <filtro>`).
4. **Capturas** (`tests/render_*.gd`) y renders de Blender: corrélos vos y adjuntá las imágenes.
5. **Cerrar**: `[x]` acá con el hash, aviso en `docs/avisos/` si tocaste algo de Nacho o compartido,
   commit en inglés con prefijo (`feat:`, `fix:`, `test:`, `docs:`, `art:`…).

---

## S-311 · Personaje 2.0: gelatina transparente, proporciones editables, ragdoll de estudio — A · Aviso: por ítem

> **Objetivo**: un personaje jugable de gelatina translúcida que se vea **igual que la imagen de
> referencia** (`art/gel_character/referencia/referencia_frente.jpg`): figura lisa, cabeza esférica sin
> rasgos, cuerpo blanco lechoso con un tinte lavanda-azulado que deja ver el fondo, reflejos de estudio
> nítidos, bordes más densos que el centro, motas internas, manos manopla con pulgar y pies de bota
> redondeada.
>
> **Un solo cuerpo con proporciones editables** (alto, largo de piernas y brazos, tamaño de cabeza,
> grosor, panza, hombros, cadera, manos, pies…) en lugar de modelos fijos. **Delgada** (las proporciones
> de la imagen, la que se compara en el bloque E) y **Flaca** (más alta y fina) son presets; el jugador
> puede partir de uno y ajustar con sliders. Encima: varios colores, física de gelatina, ragdoll al nivel
> de Gang Beasts / Human Fall Flat, caras, pelos, skins, disfraces, animaciones base y de estudio,
> graciosas, bailes, muertes, efectos y sonidos, todo funcionando con cualquier proporción.
>
> **Punto de partida**: `art/gel_character/build_gel_character.py` y `gel_character_candidate.glb` (un
> candidato opaco y regordete sobre el rig del personaje redondeado: sirve el esqueleto, no la forma ni
> el material), `art/rounded_character/` (rig, `animation_library.py`, `head_shape.py`, validación en
> Godot), `scripts/gameplay/player/` (`player_appearance.gd`, `player_animator.gd`,
> `player_ragdoll.gd`), `scripts/ui/cosmetics_panel.gd`.
>
> **Relación con la lista de Nacho**: N-312 (personaje flaco y alto, opaco) y N-115 (correr) son de
> Nacho; el preset **Flaca** usa las mismas proporciones de fondo que N-312 y los clips de correr salen
> de N-115. Las heredadas S-305 (accesorios), S-308 (emotes), #101 (ragdoll), #102 (maniquí) y #103
> quedan en pausa en la lista de Nacho mientras esta tarea esté abierta: las cubren los ítems de acá.
>
> **Hecho cuando**: (1) el lado a lado del bloque E pasa los umbrales del ítem 40 **renderizado en
> Godot** con el preset Delgada; (2) las proporciones se pueden editar y guardar, y cualquier combinación
> dentro de los rangos se juega con todo lo de los bloques F-N sin romperse (ítem 26); (3) los otros
> jugadores ven lo mismo; (4) `test_gel_character.gd` y los tests nombrados en cada ítem pasan; (5) el
> costo medido entra en el presupuesto del ítem 7.

### A. Referencia, medidas y dirección (1-8)

- [x] **S-311.1** (`b4270c6`) `art/gel_character/LEEME.md`: qué es el personaje, de dónde parte, cómo se construye
  (comandos de Blender headless), dónde está cada archivo y la lista de rasgos **obligatorios** de la
  referencia. La imagen ya está en `art/gel_character/referencia/referencia_frente.jpg`.
- [x] **S-311.2** (`b4270c6`) Hoja de proporciones medida sobre la imagen, con la imagen anotada
  (`referencia/proporciones.png` + tabla en `LEEME.md`): alto total medido **3,68 cabezas** (corrige ≈5), ancho de hombros
  contra cabeza, largo de brazo (las manos llegan a media altura del muslo), largo de pierna (≈40 % del
  alto), ancho y largo del pie, cuello. Son los valores del preset **Delgada**.
- [x] **S-311.3** (`b4270c6`) Material objetivo medido de la foto (`referencia/material_objetivo.md`): color del
  cuerpo (muestras de píxeles en cabeza, torso y piernas; blanco lechoso con tinte lavanda-azul), color
  de las zonas densas y de las transparentes, forma y tamaño de los reflejos (ventana de estudio en la
  cabeza, línea vertical en brazos y piernas), sombra de contacto.
- [x] **S-311.4** (`b4270c6`) Los **12 criterios "igual que la imagen"** que usa el bloque E: (1) silueta, (2) cabeza
  esférica y lisa, (3) transición cuello-hombros continua, (4) reflejos tipo ventana en la cabeza, (5)
  borde más denso y claro que el centro, (6) se ve el fondo a través, (7) motas o burbujas internas
  finas, (8) manos manopla con pulgar, (9) pies de bota redondeada, (10) sombra de contacto suave, (11)
  torso un poco más opaco que las extremidades, (12) cero facetas o aristas visibles.
- [x] **S-311.5** (`b4270c6`) `art/gel_character/referencias.md`: 10-15 referencias de estudio (Fall Guys, Gang
  Beasts, Human Fall Flat, Slime Rancher, creadores de personaje con sliders, gomitas y jaleas reales,
  shaders de gelatina publicados) y qué se toma de cada una. Nada se copia: solo se describe qué funciona.
- [x] **S-311.6** (`b4270c6`) Hoja de concepto con `artista-conceptual` (ComfyUI): turnaround frente/perfil/espalda
  de los presets Delgada y Flaca, los extremos de los rangos y Delgada en 6 colores, respetando la
  referencia. Registro en `art/ai-registro.md`. Selección guiada **311071**, tres variantes revisadas;
  reservas en `concept/seleccion_comfy.md` (no aprueba el bloque E). *Necesita PC.*
- [x] **S-311.7** (`b4270c6`) Presupuesto técnico en `LEEME.md`: triángulos por LOD (LOD0 ≤ 6000, LOD1 ≤ 2500, LOD2
  ≤ 800), ≤ 16 morphs de proporción, huesos del juego + huesos de jiggle (≤ 20), texturas ≤ 1024², ≤ 3
  draw calls por personaje vestido, costo de GPU ≤ +0,5 ms con 4 personajes en pantalla contra el
  personaje de hoy.
- [x] **S-311.8** (`b4270c6`) Plan de archivos pasado por `guardian-dominios`: lo nuevo va en
  `scripts/gameplay/player/gel/`, `assets/models/characters/gel/` y `shaders/gel/`; lista de archivos de
  Nacho que se van a tocar (IK de manejo, asientos, resultados, depósito) y en qué ítems.

### B. Cuerpo base con proporciones editables, en Blender (9-18) — *Necesita PC*

- [x] **S-311.9** (`9bf1593`) `art/gel_character/build_gel_body.py`: script reproducible headless que parte del rig
  de `art/rounded_character` (mismos nombres de huesos) y genera el cuerpo base con sus morphs. Reemplaza
  al candidato (que queda como historia en git).
- [x] **S-311.10** (`3579eac`) Cuerpo base = preset **Delgada**: calca la silueta de la referencia con las medidas del
  ítem 2. Malla única cerrada (watertight), sin partes sueltas: la transparencia muestra cualquier
  costura interna.
- [x] **S-311.11** (`9bf1593`) Morphs de proporción (shape keys exportados como blend shapes del glTF), cada uno con
  rango −1…+1: grosor general (flaca ↔ rellena), panza, pecho, hombros, cadera, grosor de brazos, grosor
  de piernas, tamaño de manos, tamaño de pies, forma de cabeza (esfera ↔ ovalada), grosor de cuello. Lo
  que es **largo** (alto, piernas, brazos, torso, cuello, tamaño de cabeza) va por huesos (ítem 20), no
  por morph.
- [x] **S-311.12** (`2a5291b`) Topología para deformar y para morphs: quads, loops en hombros, codos, muñecas,
  cadera, rodillas, tobillos y cuello; densidad pareja para que la deformación por vértice (bloque F) se
  vea lisa y ninguna combinación de morphs cruce la malla consigo misma.
- [x] **S-311.13** (`face5c9`) Manos manopla con pulgar separado como en la foto (sin dedos, hueso de pulgar para
  cerrar sobre una caja), pies de bota redondeada con planta plana, y uniones cuello-hombros y
  torso-piernas como en la referencia, resueltas con forma y sombreado, no con geometría abierta.
- [ ] **S-311.14** Prueba de "núcleo": una malla interna más chica y más densa para que el torso se vea
  más opaco que las extremidades (criterio 11), con los mismos morphs. Se compara con resolverlo solo con
  el mapa de grosor (ítem 15) y se deja la opción más barata que pase el bloque E.
- [ ] **S-311.15** Normales suaves y **mapa de grosor** (thickness): la luz atraviesa más en manos y
  brazos que en el torso. El grosor tiene que seguir a los morphs (grosor horneado en el cuerpo base y
  corregido en el shader con los pesos de "grosor general"; comprobar en los extremos).
- [ ] **S-311.16** UV0 sin solapamiento y estable con cualquier morph (skins, caras, decals no se estiran
  más de un 15 %) y UV1 o color de vértice con la máscara de zonas (cabeza, torso, brazos, manos,
  piernas, pies) para skins por zona.
- [ ] **S-311.17** LOD1 y LOD2 con los mismos morphs y la misma silueta (≤ 5 % de diferencia de píxeles en
  una captura a 15 m, en Delgada, Flaca y los extremos).
- [x] **S-311.18** (`9bf1593`) `validate_glb.py` ampliado: huesos que usa el juego, pesos normalizados, ningún vértice
  sin peso, malla cerrada, triángulos y morphs dentro del presupuesto, pivote en los pies, y un barrido de
  los extremos de cada morph y de 30 combinaciones al azar sin autointersección.

> Preparación B (2026-10-01): cuerpo aislado,11morphs,20huesos,9clips y
> LOD4704/1176/794tri generados; evidencia en `art/gel_character/review_bloque_b/`.
> No reemplaza al jugador activo.10/13 conservan diferencias visuales;12 no está
> certificado para todo el continuo de morphs;14/15 esperan D/E;16 falla15%UV;
> 17 necesita el preset Flaca completo de C.9/11/18 verificados en `9bf1593`,
> con revisión independiente PASS,53muestras porLOD y4/4testsGodot. No se marca
> como terminado todo B ni se certifican combinaciones continuas no muestreadas.

> Cierre S-311.10 (2026-10-04): la silueta frontal rasterizada desde LOD0 logra
> IoU 0,849524 contra la máscara binaria reproducible de la referencia (umbral
> 0,84). Los tres GLB conservan una sola superficie cerrada y pasan 53 estados
> estáticos por LOD; 405 muestras animadas terminan sin contactos ni caras
> invertidas. No cierra material, UV, Flaca ni la comparación renderizada de E.

> Cierre S-311.12 (2026-10-05): LOD0/LOD1 mantienen 2352/1124 quads, loops
> cerrados bilaterales en las seis articulaciones de extremidades y loop de
> cuello; valencia máxima 5 en zonas de flexión y percentil 90 de aspecto
> 3,358550 ≤ 3,5 bajo los extremos individuales. Un barrido adicional de 243
> estados por LOD (Basis, extremos simples y por pares) termina sin cruces ni
> caras degeneradas/reorientadas. Es evidencia finita reproducible; LOD2 sigue
> cubierto por sus puertas derivadas y el continuo matemático no se sobredeclara.

> Corrección posterior de preparación: se guardan/exportan los once morphs a cero
> (Delgada), con regresiones de autoría, defaults GLB y carga Godot. No cambia la
> geometría ni cierra los pendientes visuales; el ensayo de hombros fue retirado
> al introducir pliegues. Ver `art/gel_character/review_bloque_b/ESTADO_ACTUAL.md`.

> Diagnóstico posterior: corregido un falso positivo de contacto en aristas
> segmentadas por redondeo del skinning, con fixtures independientes y sin
> ampliar tolerancias ni ocultar cruces reales. No cambia los assets ni aprueba
> la retopología de hombros: 10/12/13 permanecen pendientes. Aviso:
> `docs/avisos/2026-10-01-s311-contacto-numerico.md`.

> Corrección de axila (2026-10-02): loops cruzados curvos y pesos de superficie
> eliminan los pliegues de A0/A30/A60/A75 en los tres LOD. LOD2 conserva la
> transición cadera-muslo en contracciones combinadas. Exportados 4704/2248/794
> triángulos, 53 muestras por LOD válidas y 144 comparaciones de silueta bajo 5 %.
> No reemplaza al jugador ni certifica A90, todas las animaciones o el continuo;
> 10/12/13 permanecen pendientes en su alcance completo. Evidencia actual en
> `art/gel_character/review_bloque_b/ESTADO_ACTUAL.md` y aviso
> `docs/avisos/2026-10-02-s311-axila-retopologia.md`.

> Endurecimiento posterior (2026-10-03): pulgar adelantado, pesos locales de
> hombro/pecho, adaptación IK de los nueve clips y LOD2 protegido por estados
> estáticos y poses. La puerta sobre los GLB reales cubre 3 LOD × 3 estados de
> morph × 9 clips × 5 instantes = 405 muestras animadas, además de 53 estáticas
> por LOD; Godot y la revisión visual pasan, con máximo 4,373368 % frente al
> límite de 5 %. Esto incorpora A90 y todos los clips a la evidencia finita, pero
> no certifica el continuo completo, el preset Flaca/material ni resuelve núcleo,
> grosor o UV. 10/12/13/14/15/16/17 siguen pendientes en su alcance total.

### C. Proporciones en el juego (19-26)

- [x] **S-311.19** (`30e561b`) Recurso `GelBodyProportions` (`scripts/gameplay/player/gel/`): cada parámetro con
  nombre, rango y valor por defecto (el de Delgada). Largos por hueso: alto total (0,85-1,20), largo de
  piernas, de brazos, de torso y de cuello, tamaño de cabeza. Formas por morph: los del ítem 11.
- [x] **S-311.20** (`02e986a`) `gel_body_shaper.gd`: aplica los morphs y ajusta el largo de los huesos en el
  `Skeleton3D` (pose de reposo) sin romper los clips. Se calcula solo al cambiar las proporciones; costo
  por frame cero (medido).
- [x] **S-311.21** (`f4695a4`) Presets como `.tres`: **Delgada** (la de la imagen), **Flaca** (≈6 cabezas, brazos y
  piernas ~30 % más finos, cuello visible), y cuatro más para mostrar el rango (Rellena, Petisa,
  Cabezona, Larguirucha). Botón "al azar" que solo sortea combinaciones que se ven bien (límites entre
  parámetros, por ejemplo cabeza grande con cuello muy fino no).
- [x] **S-311.22** (`ebfdcd8`) Editor en la personalización: elegir preset y ajustar cada slider, con teclado, mouse
  y gamepad; maniquí de gelatina girable que se actualiza en vivo; restaurar preset y deshacer.
- [x] **S-311.23** (`0744a52`) Guardado en el perfil y replicación compacta (cada parámetro cuantizado a un byte); el
  host limita los valores a los rangos. Test de red: cada par ve las proporciones del otro.
- [x] **S-311.24** (`be6b7f7`) Juego justo: la cápsula de colisión, la altura de la cámara y el alcance **no cambian**
  con las proporciones; lo visual se acomoda (IK de pies al piso, manos a la caja, volante y pedales: estos
  dos son de Nacho, aviso).
- [x] **S-311.25** Animación con cualquier proporción: la zancada y la velocidad del clip salen del largo
  de pierna (pies sin patinar), las manos llegan a la caja con cualquier largo de brazo y la cabeza no
  atraviesa el techo del camión ni la puerta. Hecho en `e275895`.
- [x] **S-311.26** (`7d16299`) `test_gel_proportions.gd`: extremos de cada parámetro + 50 combinaciones al azar (semilla
  fija) — pies en el piso (±2 cm), manos en la caja al cargar, cara ni enterrada ni flotando, ragdoll
  estable, ropa y pelo sin atravesar el cuerpo (cuando existan los bloques H y J).

### D. Material de gelatina en Godot (27-37)

- [x] **S-311.27** (`15cf4c9`) `shaders/gel/gel_body.gdshader` (con `artista-shaders`) para GL Compatibility:
  transparencia con fresnel, bordes más densos y centro más transparente (criterios 5 y 6).
- [x] **S-311.28** (`8bea552`) Refracción del fondo desplazada por la normal (`hint_screen_texture`),
  comprobada en GL Compatibility. Quedó la lectura real de pantalla; no fue necesario el reflejo falso.
- [x] **S-311.29** (`a05dafc`) Reflejos de estudio nítidos como los de la foto (criterio 4): especular
  de rugosidad baja + matcap procedural chico de ventana y cinta, visibles aunque el cielo sea oscuro.
- [x] **S-311.30** (`33d459a`) Absorción por grosor (Beer-Lambert aproximado con el mapa base del ítem
  15): más color y menos transparencia donde hay más gelatina. La corrección del mapa para morphs sigue
  pendiente en S-311.15 y no se da por cerrada aquí.
- [ ] **S-311.31** Luz trasera / subsurface falso: a contraluz la gelatina brilla (wrap lighting +
  back-light), sin pasadas extra.
- [ ] **S-311.32** Motas y burbujas internas (criterio 7): ruido 3D en espacio del objeto, que se mueve
  con el cuerpo y no con la cámara; densidad y tamaño como en la foto, sin estirarse con las proporciones.
- [ ] **S-311.33** Orden de transparencia y sombras: sin brazos que desaparecen detrás del torso ni
  agujeros al girar (prepasada de profundidad o dos pasadas cara trasera / delantera); proyecta sombra
  suave, un poco más clara que la de un opaco, y recibe sombra. Captura girando 360°.
- [ ] **S-311.34** Color, opacidad y brillo por jugador con `instance uniform`: un solo material para
  todos, sin duplicarlo por instancia.
- [ ] **S-311.35** Variante "opaca lechosa" para la calidad baja de las opciones y para quien la elija en
  accesibilidad: mismo look sin transparencia ni lectura de pantalla.
- [ ] **S-311.36** Capturas en todos los contextos con `revisor-visual`: día, atardecer, noche con
  linternas, lluvia, niebla, interior del camión, depósito, pantalla de resultados.
- [ ] **S-311.37** Costo medido con `perfilador-rendimiento`: 4 personajes con proporciones distintas en
  pantalla contra el personaje de hoy; dentro del presupuesto del ítem 7.

### E. Iterar hasta que se vea igual que la imagen (38-43)

- [ ] **S-311.38** `tests/render_gel_reference.gd`: preset Delgada, fondo blanco, luz de estudio suave de
  arriba a la izquierda, cámara de frente con el encuadre y el campo de visión de la foto, pose A
  relajada como la referencia; guarda el PNG. Otra escena igual en Blender para iterar rápido.
- [ ] **S-311.39** `art/gel_character/compare_reference.py`: lado a lado render / referencia, IoU de la
  silueta (máscara por umbral sobre el fondo blanco), diferencia de color media (ΔE) por zona (cabeza,
  torso, brazos, piernas) y un PNG de diferencias. Guarda el reporte de cada ronda.
- [ ] **S-311.40** Umbrales para aprobar: **IoU de silueta ≥ 0,92**, **ΔE medio ≤ 8 por zona**, y los 12
  criterios del ítem 4 marcados "sí" en la revisión visual.
- [ ] **S-311.41** Bitácora `art/gel_character/iteraciones.md`: por ronda, el lado a lado, los números,
  qué se cambió y qué falta. **Mínimo 5 rondas**, y se sigue iterando hasta pasar los umbrales: no hay
  tope de rondas. Si falla la silueta, se corrigen los valores del preset (ítem 21) antes que la malla.
- [ ] **S-311.42** La comparación que cuenta es la del **render de Godot** (ítem 38), no solo la de
  Blender: lo que ve el jugador.
- [ ] **S-311.43** Revisión final del lado a lado con `director-arte` y con el usuario. Si marcan algo,
  se hace otra ronda y se anota en la bitácora.

### F. Física de gelatina y ragdoll (44-56)

- [ ] **S-311.44** Huesos de jiggle secundarios (cabeza, panza, antebrazos, pantorrillas) con
  `SpringBoneSimulator3D`: rebote al frenar, girar, saltar y aterrizar, y un temblor en reposo muy suave
  con fase distinta por jugador. Rigidez y amplitud escaladas con las proporciones (más panza, más
  rebote).
- [ ] **S-311.45** Squash & stretch con volumen constante en el shader, a partir de la aceleración del
  cuerpo: se aplasta al aterrizar y se estira al saltar.
- [ ] **S-311.46** Ondas de impacto: un golpe (caja, pared, otro jugador, trampa) manda una onda por la
  malla desde el punto de contacto; hasta 4 simultáneas por uniforms.
- [ ] **S-311.47** Arrastre: los vértices lejos del hueso se atrasan un poco en brazos y cabeza al
  moverse (inercia de gelatina).
- [ ] **S-311.48** Ragdoll sobre el rig real con `PhysicalBoneSimulator3D` y límites de articulación
  (cono en hombros y caderas, bisagra en codos y rodillas), en lugar de las cápsulas sueltas de
  `player_ragdoll.gd`. Formas y masas de cada hueso físico se recalculan con las proporciones.
- [ ] **S-311.49** Ragdoll activo: mezcla animación ↔ física con motores hacia la pose animada y fuerza
  variable, para tropezar, ser empujado y recuperarse sin saltos (estilo Gang Beasts / Human Fall Flat).
- [ ] **S-311.50** Levantarse: detecta boca arriba / boca abajo y mezcla con uno de dos clips de
  levantarse, sin teletransporte.
- [ ] **S-311.51** La gelatina sigue temblando durante el ragdoll (jiggle + ondas al tocar el piso).
- [ ] **S-311.52** Solo visual y en red: la cápsula y la autoridad del host no cambian; el host replica
  impulso y semilla y cada cliente simula su ragdoll. Test de dos pares: el ragdoll arranca en todos y
  el cuerpo termina a < 0,5 m de la cápsula.
- [ ] **S-311.53** El ragdoll choca con cajas y con la caja del camión en movimiento y hereda su velocidad
  (como hoy `player_ragdoll.gd`). Aviso si toca algo del camión.
- [ ] **S-311.54** Estabilidad: test headless que suelta el ragdoll 100 veces desde poses, impulsos y
  proporciones aleatorias; se duerme en < 4 s, sin NaN, sin huesos estirados más de lo permitido.
- [ ] **S-311.55** Contacto entre gelatinas: dos jugadores que chocan se aplastan uno contra otro un
  instante (deformación de contacto, solo visual).
- [ ] **S-311.56** Entorno: la lluvia hace ondas chicas, el viento lo mece, mojado brilla más.

### G. Caras (57-61)

- [ ] **S-311.57** Sistema de caras: dibujo "flotando" dentro de la cabeza (se ve a través de la
  gelatina) o en la superficie; probar las dos, elegir con el bloque E y documentarlo. Sigue el tamaño y
  la forma de la cabeza. La cara por defecto es **ninguna**, como la referencia.
- [ ] **S-311.58** 12 caras: sin cara, feliz, preocupada, dormida, enojada, sorpresa, guiño, bizca, lengua
  afuera, llorando, enamorada y "X X".
- [ ] **S-311.59** Expresión por estado del juego: caja por romperse → preocupada, entrega perfecta →
  feliz, caída → sorpresa, ragdoll → mareada, knockout → "X X".
- [ ] **S-311.60** Parpadeo, mirada que sigue al jugador más cercano o a la caja que se lleva, y boca que
  se abre con el chat de voz de proximidad (amplitud → apertura).
- [ ] **S-311.61** Caras elegibles en la personalización, guardadas en el perfil y replicadas (test).

### H. Pelos (62-64)

- [ ] **S-311.62** 10 peinados de gelatina, con su propio color: pelado (defecto), jopo, rulos, colitas,
  mohicano, afro, flequillo, trenza, rodete y pelo largo; más 5 cejas y 5 bigotes opcionales. Cada pelo
  ≤ 1500 triángulos.
- [ ] **S-311.63** Mechones, colitas y trenza con huesos de resorte.
- [ ] **S-311.64** Pelo que sigue a la cabeza: se engancha al hueso de la cabeza y copia sus morphs de
  forma y tamaño; reglas pelo ↔ sombrero (el sombrero aplasta o esconde el pelo, nunca se atraviesan).
  Test con cada combinación y los extremos de cabeza.

### I. Skins y colores (65-70)

- [ ] **S-311.65** 16 colores de gelatina como `.tres` (color, absorción, brillo): leche (el de la
  referencia, por defecto), frutilla, lima, uva, naranja, menta, limón, arándano, cereza, cola, sandía,
  mora, durazno, cielo, carbón translúcido y arcoíris.
- [ ] **S-311.66** Skins con interior: bicolor en capas (gomita), degradé vertical, trocitos de fruta
  flotando adentro, brillantina, burbujas grandes.
- [ ] **S-311.67** Skins animadas: arcoíris que cicla, neón que brilla de noche, lava con burbujas lentas,
  holográfica.
- [ ] **S-311.68** Color del equipo sin romper la skin: acento en el borde o en el núcleo con el color que
  hoy tiñe la camiseta.
- [ ] **S-311.69** Legibilidad: cada jugador distinguible a 20 m, de día y de noche, y con los filtros
  de daltonismo (S-502, ahora en la lista de Nacho). Capturas.
- [ ] **S-311.70** Vista previa, guardado en el perfil y replicación en `player_appearance.gd` (test de
  red: cada par ve la skin del otro).

### J. Disfraces y accesorios (71-76)

- [ ] **S-311.71** 12 disfraces: repartidor (uniforme del juego), cartero, bombero, astronauta, pirata,
  chef, dinosaurio, abeja, momia, robot, superhéroe con capa y esqueleto (los huesos se ven dentro de la
  gelatina).
- [ ] **S-311.72** 15 accesorios sueltos: gorra, casco, lentes, bufanda, mochila, moño, corona,
  auriculares, bigote postizo, etc.
- [ ] **S-311.73** Partes con física: capa, cola del dinosaurio, antenas de abeja, vendas de la momia.
- [ ] **S-311.74** Ropa que sigue las proporciones: cada prenda lleva los mismos morphs que el cuerpo
  (transferidos por script desde el cuerpo base) y los mismos pesos de hueso, así calza con cualquier
  combinación. La ropa opaca no rompe el orden de transparencia y el cuerpo se ve a través donde no hay
  ropa.
- [ ] **S-311.75** Matriz automática disfraz × pelo × proporciones (presets y extremos): ninguna
  combinación se atraviesa (test).
- [ ] **S-311.76** Desbloqueos en la progresión existente (`UnlockManager`) y panel de cosméticos con el
  maniquí de gelatina del ítem 22 en vez de cápsula + esfera.

### K. Animaciones base y de estudio (77-85)

- [ ] **S-311.77** Clips base con `animation_library.py`: idle, caminar, trotar, correr (N-115), salto
  (impulso, aire, aterrizaje), girar en el lugar.
- [ ] **S-311.78** Clips de juego: levantar caja baja y alta, caminar cargando, lanzar, dejar, sentarse,
  manejar (IK de volante y pedales de Nacho: aviso), subir y bajar del camión, tocar timbre.
- [ ] **S-311.79** Reacciones: tropezar, resbalar, empujado, golpe de caja, susto (explosiva), mareo,
  sacudirse el agua.
- [ ] **S-311.80** Máquina de estados y mezclas en `PlayerAnimator` con tiempos pulidos; pies sin
  patinar con cualquier largo de pierna (medido: desplazamiento del pie apoyado < 2 cm por paso).
- [ ] **S-311.81** Los clips quedan limpios y la física (bloque F) pone el "jelly" encima: sin bamboleo
  dibujado a mano que choque con la simulación.
- [ ] **S-311.82** Anticipación, squash & stretch y follow-through en los clips clave (salto, lanzar,
  aterrizar, levantar), con los 12 principios de animación.
- [ ] **S-311.83** Pulido de estudio: curvas revisadas (arcos, overlap, sin interpolaciones lineales
  duras), turntable y capturas en movimiento por clip en `art/gel_character/review/`, con Delgada, Flaca
  y un extremo.
- [ ] **S-311.84** Los clips dependen solo del estado replicado: los otros ven la misma animación (test
  de dos pares).
- [ ] **S-311.85** Los mismos clips funcionan con cualquier proporción y en los NPC del depósito sin
  retoque a mano (retarget por nombres de huesos; test de clips presentes).

### L. Emotes graciosos y bailes (86-91)

- [ ] **S-311.86** 8 emotes: saludar, aplaudir, facepalm, encogerse de hombros, señalar, pulgar arriba,
  derretirse al piso y volver, sacudirse como un perro.
- [ ] **S-311.87** 6 animaciones de gelatina pura: panqueque, chicle estirado, rebote de pelota,
  dividirse en dos y juntarse, temblar de frío, inflarse.
- [ ] **S-311.88** 8 bailes originales (sin copiar coreografías de otros juegos): paso simple, robot,
  disco, gusano en el piso, headbang, baile de la victoria, "flan" (todo el cuerpo ondulando) y conga
  que se sincroniza con quien esté cerca.
- [ ] **S-311.89** Rueda de emotes con teclado y gamepad (junto a la rueda de pings S-505 o aparte),
  replicada.
- [ ] **S-311.90** Idles largos si el jugador no toca nada: mirarse la mano transparente, hacer una
  burbuja, rebotar en el lugar.
- [ ] **S-311.91** Celebración al entregar y derrota en resultados (`hud_results.gd` y S-508 están en la
  lista de Nacho: aviso).

### M. Muerte, distorsión y efectos (92-95)

- [ ] **S-311.92** Knockout de gelatina: se derrite en un charco (shader + partículas) y se rearma al
  reaparecer con animación de reensamble.
- [ ] **S-311.93** Variantes por causa: aplastado (panqueque), explosión (gotas que vuelven al centro),
  caída al agua (se disuelve), atropellado.
- [ ] **S-311.94** Distorsión extrema al chocar fuerte: se estira más allá de lo normal y vuelve con
  rebote, con tope para que la malla nunca se rompa ni se invierta.
- [ ] **S-311.95** VFX con `artista-vfx` del color de la skin: gotas, salpicaduras, burbujas al aterrizar,
  estela corta al correr, y manchas en piso y paredes que se desvanecen en segundos, con tope de
  cantidad (test de que no crecen sin límite).

### N. Sonido (96-98)

- [ ] **S-311.96** Sonidos sintetizados en `SynthAudio` con `disenador-audio`: pasos "squish" por
  superficie, salto, aterrizaje, rebote, golpe, estirarse, derretirse, rearmarse.
- [ ] **S-311.97** Voz sin palabras gelatinosa (base: S-402) y música corta propia para cada baile.
- [ ] **S-311.98** Mezcla en los buses Interior/Exterior; tono según el jugador y el tamaño del cuerpo
  (más grande, más grave); nunca tapan los sonidos de las trampas (medido como en S-404).

### O. Integración y entrega (99-100)

- [ ] **S-311.99** Todo junto en la personalización (preset, proporciones, color, skin, cara, pelo,
  disfraz), guardado y replicado. `tests/test_gel_character.gd`: huesos, clips, morphs, materiales,
  presupuesto, ragdoll estable, red de dos pares. Capturas finales con `revisor-visual`.
- [ ] **S-311.100** Presentación de estudio en `art/gel_character/review/`: turntable de los seis presets
  en 6 colores, un video del editor moviendo los sliders, reel de animaciones (base, graciosas, bailes,
  muertes) y `LEEME.md` final. Pasa a ser el personaje por defecto solo con el visto bueno del usuario.
