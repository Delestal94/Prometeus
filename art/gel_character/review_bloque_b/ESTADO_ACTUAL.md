# Evidencia en curso, no aprobación B

## Corrección del estado inicial, 2026-10-01

Los tres GLB y el `.blend` guardado tienen ahora los once morphs en cero
(Delgada). Antes declaraban todos en uno. El importador actual de Godot ya
cargaba cero; el error confirmado era el estado de autoría/exportación.
La API genérica del validador no cambió; el modo gel exige defaults efectivos
finitos y cero, respetando precedencia nodo/malla y el cero implícito de glTF.

Verificación actual: 44 tests Python OK (4 skips requieren Blender), 4/4 pruebas
de fuente en Blender y 4/4 tests Godot PASS. Los tres GLB pasan 53 muestras;
144 comparaciones LOD pasan, máximo 4,0143 %. La pose diagnóstica y las tres
vistas cercanas son idénticas píxel a píxel a `corrected_captures/`.
Se refrescaron las métricas dependientes de la fuente y la validación exportada.
Los resultados UV/core y las dependencias pendientes descritas abajo no cambian.

Un ensayo de suavizado de pesos del hombro introdujo pliegues visibles en las
axilas y fue retirado por completo: el algoritmo de pesos, la geometría y los
morphs finales son los anteriores. No se aprueban nuevos ajustes visuales ni
se cierran los ítems 10/13/E por esta corrección.

## Evidencia de preparación anterior

2026-10-01. Entrega de preparación B, no cierre completo ni reemplazo del jugador.
Rama sincronizada con origin/main7971e6d antes de publicar. La biblioteca añadió
Run durante la sincronización: se regeneraron los nueve clips actuales; las
huellas de geometría y morphs permanecieron idénticas.

Última regeneración independiente:4704/1176/794tri; topología y morph hashes reproducibles. Master original sin cambios.

Barrido GLB real final: los tres LOD pasan53muestras cada uno sin errores.
La reducción de LOD2 protege los vértices de planta existentes: se corrigió su
plegado sin cambiar la forma fuente ni superar800triángulos.

El validador exige un único ciclo en el enlace de cada vértice y normales de
sombreado en el hemisferio exterior de cada cara. Regresiones negativas cubren
superficies pellizcadas y normales unitarias invertidas. La revisión independiente
final de preparación pasó: `review.md`. La última corrida Godot con los nueve
clips también pasó:4/4tests (gel_body_asset,player_character,player_sprint,
character_motion), import/capturas sin SCRIPT ERROR. No confundir esta aprobación
de preparación con aprobación visual final.

`export_validation.json` y `lod_silhouette_report.json` corresponden a los GLB
actuales. Godot4.7.2/GL Compatibility, RX7800XT:216capturas de protocolo,
144comparacionesPASS; diferencia máximaLOD1=2,724%,LOD2=4,014% (límite5%).
`corrected_captures/` conserva las vistas diagnósticas actuales; `final_captures/`
y `diagnostic_failure_initial/` son iteraciones anteriores, no aprobación actual.
La pose diagnóstica muestra los brazos75°desdehorizontal; no modifica los clips.
Persisten diferencias visuales: esquina exterior del hombro, torso/extremidades
más rectos que la foto y planta inclinada en perfil animado.10/13 y aprobaciónE
siguen pendientes, sin afirmar que se haya calcado la referencia.

`geometry_metrics.json` y `core_experiment_report.json` sí se regeneraron tras la última fuente: UV61.14%escala/230.09%anisotropía falla15%; corrección lineal error máximo0.759955m; núcleo9408tri combinados fuera de presupuesto, no seleccionado.14/15/16pendientesD/E;17presetFlaca completo pendienteC.

Código41testsOK con3bpySKIP explícitos;3pruebasBlenderPASS por separado.
Godot4/4PASS tras sincronizar Run. LintGDScript/baseOK,
18módulosportablesOK. No cambios en el jugador activo, red o colisiones.
