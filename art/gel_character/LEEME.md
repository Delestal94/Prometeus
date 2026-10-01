# Personaje 2.0 de gelatina

> Fuente de verdad visual: `referencia/referencia_frente.jpg`.
>
> Este directorio contiene la referencia, las mediciones, la dirección material y
> los artefactos reproducibles para reemplazar el candidato histórico por un único
> cuerpo editable. Cuando un valor escrito contradice una medición reproducible de
> la imagen, se conserva el valor medido y se documenta la discrepancia.

## Qué es

El personaje es una figura jugable sin género ni rasgos faciales por defecto,
formada por gelatina blanca lechosa con un tinte lavanda-azulado. Debe seguir siendo
legible desde primera persona, para los otros jugadores y durante animación, IK,
deformación y ragdoll. **Delgada** es el preset que se compara contra la referencia;
**Flaca** y los demás presets son configuraciones del mismo cuerpo, no modelos
independientes.

## Punto de partida real

| Archivo | Estado y uso |
|---|---|
| `referencia/referencia_frente.jpg` | Fuente de verdad de silueta, material y luz. |
| `referencia/proporciones.png` | Copia anotada; las cifras vienen del análisis reproducible de la imagen original. |
| `referencia/material_objetivo.md` | Muestras sRGB, reflejos, motas, sombra y tolerancias. |
| `build_gel_character.py` | Genera el candidato histórico sobre el rig redondeado. Sirve como prueba de pipeline, no como forma final. |
| `gel_character_candidate.glb` | Candidato opaco y regordete. Conserva valor histórico; no es el objetivo. |
| `gel_character_candidate.png` | Render del candidato para comparar por qué debe reemplazarse. |
| `validate_glb.py` | Validador glTF actual; el bloque B lo amplía para morphs, malla cerrada y barridos. |
| `../rounded_character/` | Fuente del rig, nombres de huesos, animaciones y validaciones ya probadas. |
| `concept/concept_sheet_imagegen_draft.png` | Borrador exploratorio; no reemplaza la hoja final exigida con ComfyUI. |
| `concept/concept_sheet_guidance_v3.png` | Guía editada con imagegen para conservar manoplas y vistas posteriores; procedencia en `concept/guidance_prompt.md`. |
| `concept/comfy/guidance_v3/` | Variaciones ComfyUI de la guía, con PNG y workflow JSON por semilla; selección en `concept/seleccion_comfy.md`. |
| `concept/generate_guided.py` | Reproduce el estudio img2img local; no genera ni modifica modelos del juego. |
| `referencias.md` | Referencias externas y límites de qué se estudia sin copiar. |
| `measure_reference.py` | Reproduce máscara, caja corporal y muestras RGB; requiere Pillow y NumPy. |

## Construcción reproducible actual

Antes de comenzar cada bloque, actualizar la rama con la última `main` remota
mediante pull, preservando cualquier cambio local. Volver a sincronizar antes de
actualizar el PR y antes de integrarlo: hay dos desarrolladores trabajando en paralelo.
Si cambió un contrato usado por el bloque, revisarlo y verificar otra vez.
Al cerrar cada bloque: verificar, subir la rama, abrir un PR hacia `main` y resolver
los checks antes de integrarlo. Nunca forzar un push sobre el trabajo del otro.

Desde la raíz del repositorio, con Blender disponible en `PATH`:

```powershell
python art/gel_character/measure_reference.py
blender --background --python art/gel_character/build_gel_character.py
python art/gel_character/validate_glb.py art/gel_character/gel_character_candidate.glb
python art/gel_character/validate_glb.py art/gel_character/gel_character_candidate.glb --max-triangles 6000
```

El primer comando reproduce las medidas de la referencia. El segundo vuelve a
escribir `gel_character_candidate.glb` y `gel_character_candidate.png`.
El tercero comprueba la estructura actual sin abrir Blender y pasa.
El cuarto aplica ya el presupuesto final y **falla de forma esperada**:
el candidato tiene 46.552 triángulos, frente al límite LOD0 de 6.000. En el bloque B,
`build_gel_body.py` reemplaza este generador y produce el cuerpo Delgada con morphs,
LOD y mapas de grosor/zonas; recién ese resultado debe pasar el cuarto comando.

## Rasgos visuales obligatorios

1. Silueta del preset Delgada alineada con la referencia.
2. Cabeza esférica, lisa y sin cara por defecto.
3. Cuello corto con transición continua hacia los hombros.
4. Reflejo rectangular de ventana arriba a la izquierda de la cabeza.
5. Borde más denso y claro que el centro.
6. Fondo visible a través de cabeza y extremidades.
7. Motas o burbujas internas finas y poco contrastadas.
8. Manos manopla, sin dedos, con un pulgar legible.
9. Pies de bota redondeada con planta plana.
10. Sombra de contacto suave, sin borde duro.
11. Torso un poco más opaco que brazos y piernas.
12. Contorno y reflejos continuos, sin facetas ni aristas visibles.

## Proporciones medidas del preset Delgada

La imagen es de 832 × 1248 px. La máscara reproducible usa `B-R >= 3` y
`255-min(R,G,B) >= 8`, conserva el mayor componente 8-conectado y produce una caja
del cuerpo de `x=148..676`, `y=98..1135`: **529 × 1038 px**. Se normaliza con
`H=1038 px` y `D=282 px`, el diámetro medio de cabeza.

| Medida | Resultado | Uso de modelado |
|---|---:|---|
| Alto total | **3,68 D** | Valor medido; corrige la expectativa previa de ≈5 cabezas. |
| Cabeza | 284 × 280 px; aspecto 1,014 | Esfera visual, tolerancia de aspecto 0,97–1,05. |
| Hombros exteriores | 305 px = **1,08 D** = 29,4 % H | Ancho en `y≈425`. |
| Brazo por línea central | 405,5 px = **1,44 D** = 39,1 % H | La mano termina casi en la mitad del muslo. |
| Pierna, bifurcación a apoyo | 392 px = **1,39 D** = 37,8 % H | Confirma el objetivo de ≈40 % del alto. |
| Mano | ≈0,35 D × 0,39 D | Una masa de manopla y un lóbulo de pulgar. |
| Pie en vista frontal | **0,57 D** ancho × **0,45 D** alto | La profundidad 3D queda para el perfil/turnaround. |
| Cuello visible | **0,55 D** ancho × **0,11 D** alto | Puente corto, sin cilindro marcado. |

La foto frontal no permite medir la longitud anteroposterior del pie ni recuperar
alpha o albedo. Esos valores se fijan con el turnaround y capturas sobre fondo de
checker; no se inventan a partir del JPG.

## Los 12 criterios de aprobación del bloque E

1. **Silueta:** IoU ≥ 0,92; hombros, manos, bifurcación, tobillos y planta dentro de
   ±0,02 H; ratios de la tabla dentro de ±5 %.
2. **Cabeza:** aspecto 0,97–1,05, RMS de ajuste circular ≤2,5 % D y sin rasgos.
3. **Cuello/hombros:** una sola componente, cuello `0,55 D ±0,05 D` por
   `0,11 D ±0,04 D`, curva tangente sin esquina visible al 200 %.
4. **Reflejos:** ventana de cabeza con centro local `(0,21, 0,28) ±0,05` y caja
   `0,22 D × 0,24 D ±0,05 D`; glare blando abajo-derecha y cinta longitudinal en
   cada extremidad.
5. **Borde denso:** rim de cabeza/pies 8–18 niveles sRGB más oscuro que el centro
   transmisivo sobre blanco, con highlight claro continuo; no outline plano.
6. **Fondo visible:** un checker sigue identificable a través de cabeza y
   extremidades y queda más atenuado en el torso.
7. **Motas:** predominantemente 1–4 px a escala de referencia, contraste local de
   3–8 niveles, distribución irregular en espacio de objeto.
8. **Manoplas:** masa sin dedos más lóbulo/muesca de pulgar; `0,35 D × 0,39 D` y
   simetría de tamaño dentro de ±5 %.
9. **Botas:** ancho `0,57 D ±0,06 D`, alto frontal `0,45 D ±0,06 D`, puntera
   redonda y plantas alineadas dentro de 3 px a escala de referencia.
10. **Sombra:** envolvente aproximada `0,42 H × 0,043 H`, centro `0,057 H` a la
    derecha del cuerpo, déficit de luma mediano 3–6 y p90 6–10 sobre blanco.
11. **Torso más opaco:** mediana del torso 6–12 niveles de luma por debajo de
    brazo/pierna en regiones equivalentes; objetivo observado ≈9.
12. **Cero facetas:** a 100 % y 200 % no hay quiebres rectos repetidos atribuibles
    a caras en cabeza, hombros, brazos o botas.

## Presupuesto técnico bloqueado

| Recurso | Límite |
|---|---:|
| LOD0 | ≤ 6000 triángulos |
| LOD1 | ≤ 2500 triángulos |
| LOD2 | ≤ 800 triángulos |
| Morphs de proporción | ≤ 16 |
| Huesos de juego + jiggle | ≤ 20 huesos exportados en total, incluidos los de jiggle |
| Texturas | ≤ 1024 × 1024 por mapa |
| Personaje vestido | ≤ 3 draw calls |
| GPU, 4 personajes | ≤ +0,5 ms frente al personaje actual, misma escena/cámara/calidad |

La medición de GPU se hace en una GPU real, no con render por software. Cada cifra
es una compuerta: el bloque que la exceda debe simplificar antes de integrarse.
El rig histórico exporta 35 joints (incluye controles) y tampoco cumple este
objetivo. El bloque B debe definir la reducción/retarget sin prometer que conservar
todos los huesos históricos entra en veinte; cualquier cambio de presupuesto
requiere una decisión explícita, no reinterpretar el límite como veinte adicionales.

## Plan de archivos y dominios

La implementación nueva se concentra en:

- `do-not-drop/scripts/gameplay/player/gel/`
- `do-not-drop/assets/models/characters/gel/`
- `do-not-drop/shaders/gel/`

### Rutas previstas por bloque

| Bloque | Ítems | Rutas principales |
|---|---:|---|
| B | 9–18 | `art/gel_character/build_gel_body.py`, `gel_body.blend`, `validate_glb.py`; modelo, LOD y mapas en `do-not-drop/assets/models/characters/gel/`. |
| C | 19–26 | `gel_body_proportions.gd`, `gel_body_shaper.gd`, presets; integración en jugador, cosméticos, perfil, red y anclas del camión. |
| D | 27–37 | `do-not-drop/shaders/gel/gel_body.gdshader`, variante opaca y controlador material. |
| E | 38–43 | `tests/render_gel_reference.gd`, `compare_reference.py`, `iteraciones.md` y `review/`. |
| F | 44–56 | Jiggle, deformación y ragdoll activo dentro de `scripts/gameplay/player/gel/`; consumir contratos del camión sin modificarlo. |
| G–J | 57–76 | Cara, pelo, colores, skins y disfraces dentro del árbol `gel/`; integración propia en apariencia, cosméticos y perfil. |
| K | 77–85 | Librería de animación, `player_animator.gd`, anclas de manejo y NPC del depósito. |
| L | 86–91 | Emotes, input aditivo, replicación y celebración/derrota de resultados. |
| M | 92–95 | Efectos y partículas dentro del dominio de jugador y shaders gel. |
| N | 96–98 | Audio gel, voz y extensión aditiva del módulo SynthAudio. |
| O | 99–100 | Integración, `test_gel_character.gd` y entrega final en `review/`. |

### Archivos de Nacho o compartidos previstos

| Archivo | Ítems | Contrato y aviso futuro |
|---|---:|---|
| `do-not-drop/scenes/gameplay/vehicle/vehicle.tscn` | 24, 25, 78 | Marcadores de manos/pedales y validación de extremos. Aviso del bloque C; reutilizar en K. |
| `do-not-drop/scripts/gameplay/depot/depot_worker.gd` | 85 | Cambiar modelo/retarget de NPC. Aviso del bloque K. |
| `do-not-drop/scripts/core/network_manager.gd` | 23, 61, 70, 84, 89, 99 | Subir `PROTOCOL_VERSION` solo si cambia el esquema replicado. Aviso del bloque que lo haga. |
| `do-not-drop/project.godot` | 89 | Nueva acción de rueda de emotes, cambio aditivo. Aviso del bloque L. |
| `do-not-drop/modules/synth_audio/` | 96–98 | API aditiva; aviso del bloque N. |

`vehicle.gd` no se toca en el plan normal: S-311.53 puede consumir `carries(point)` y
`point_velocity(point)`. El ragdoll portable tampoco se modifica: el rig real vive en
`gel_active_ragdoll.gd`. `hud_results.gd` pertenece a Slatex aunque S-508 esté en la
lista de Nacho. Los avisos se crean en el bloque que efectivamente toque cada frontera,
no en este bloque documental.

Las integraciones propias de asientos se ubican en
`do-not-drop/scripts/gameplay/player/player_seat_pose.gd` y
`do-not-drop/scripts/gameplay/interaction/seat_point.gd` (ítems 25 y 78).
La celebración/derrota usa `do-not-drop/scripts/ui/hud/hud_results.gd` (ítem 91).
Son de Slatex; se coordinan con las anclas del camión sin cambiar su contrato a ciegas.
`interaction/seat_point.gd` es adaptador del módulo `modules/interaction/seat_point.gd`:
ocupación, volante y liberación no se duplican en el controlador de poses.
Los colores consumen `PlayerColorSlot.slot()` y respetan reconexiones, sin derivarse
del ID del jugador. SynthAudio conserva su API; sonidos nuevos se agregan en el
generador responsable y mediante un accesor en `modules/synth_audio/synth_audio.gd`.
