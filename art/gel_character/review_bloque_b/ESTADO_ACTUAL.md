# Evidencia en curso, no aprobación B

## S-311.13: manoplas, botas y uniones cerradas, 2026-10-07

La forma neutral exportada tiene manoplas sin dedos con pulgar anterior separado
y deformable. LOD0/LOD1 miden 0,1777/0,1772 m de largo; el ancho frontal queda en
0,1450/0,1722 m, dentro del margen de 15 % respecto a 0,39 D × 0,35 D. El pulgar
sobresale al menos 0,0222 m hacia delante y las cinco muestras de cierre entre
−45° y +45° terminan sin contactos ni caras invertidas.

Las botas miden 0,2615/0,2585 m de ancho y 0,2408 m de alto frente a las bandas
de referencia 0,2411–0,2979 m y 0,1844–0,2411 m. Conservan 39/12 vértices por
lado en la planta plana; el LOD distante conserva 12. La compresión vertical no
mueve el hueso del tobillo ni ensancha el borde interior: la regresión de `Run`
con `leg_thickness=+1` pasa en los tres LOD.

Las superficies siguen cerradas, manifold y de una sola pieza, con todas las
caras suaves. Los percentiles 95 de ángulo entre caras son 26,83°/40,93° en
cuello-hombros y 26,91°/51,35° en torso-piernas para LOD0/LOD1; los máximos son
53,08°/62,49° y 39,95°/58,66°. La puerta limita p95 a 30°/55° y el máximo a 65°.

Verificación: 16 pruebas Blender PASS; 84 pruebas Python PASS (20 skips que
requieren Blender se ejecutaron aparte); 486 estados de topología/morph PASS;
53 estados por cada GLB y 405 muestras animadas PASS, sin contactos ni inversión.
Silueta Delgada IoU 0,841324 ≥ 0,84. Se mantienen 4704/2248/794 triángulos,
20 huesos, 11 morphs y 9 clips. Esto cierra S-311.13, no material, UV, núcleo,
Flaca completo ni la aprobación visual final del bloque E.

## S-311.12: topología de autoría medible, 2026-10-05

LOD0 y LOD1 conservan respectivamente 2352/1124 quads. La nueva puerta
`validate_gel_topology.py` detecta loops cerrados bilaterales alrededor de
hombros, codos, muñecas, caderas, rodillas y tobillos, además del loop de cuello.
Dentro de esas zonas la valencia máxima es 5. Al recorrer Basis y los 22 extremos
individuales, el peor percentil 90 de relación entre aristas es 3,358550 frente
al límite 3,5; los outliers de puntas y ramificaciones siguen cubiertos por las
pruebas de contacto y orientación.

El informe `topology_report.json` valida además 243 estados por LOD: Basis, cada
extremo individual y las 220 combinaciones de extremos por pares. Las 486
muestras terminan sin caras degeneradas/reorientadas ni autointersecciones. Esto
es una compuerta finita reproducible, no una afirmación matemática sobre cada
punto del continuo de once morphs. LOD2 sigue siendo la simplificación triangular
derivada y queda bajo sus puertas de morfología, pose y silueta existentes.

## S-311.10: silueta Delgada cerrada, 2026-10-04

El preset base ahora sigue las medidas frontales de la referencia: cuello y
hombros más estrechos, cadera y piernas ajustadas, brazos algo más cortos y
botas separadas hacia afuera. La comparación geométrica reproducible proyecta
LOD0 en la pose frontal medida y obtiene IoU 0,849524 contra
`referencia/silueta_mascara.png`, por encima de la puerta 0,84. El reporte y la
superposición están en `delgada_silhouette_report.json` y
`delgada_silhouette_overlay.png`.

Los tres GLB siguen siendo una sola superficie cerrada, con 4704/2248/794
triángulos y 53 estados estáticos válidos por LOD. La puerta animada recorrió
405 combinaciones de LOD, clip, instante y grosor: cero contactos y cero caras
invertidas. La regresion de fuente del caso Run/grosor que motivo el ultimo
ajuste también pasa. El master conserva SHA256
`14763003da303779d38725530d78bc7a71baa83318d5b892ed5c5e610e3bb178`.

Esto cierra solamente S-311.10. No aprueba material, UV, el preset Flaca ni la
comparación final renderizada en Godot del bloque E.

## Estado actual: deformación A90 y exportación endurecidas, 2026-10-03

Esta sección sustituye los estados históricos de abajo. El pulgar descansa ahora
por delante de la mano y conserva separación respecto al muslo en A90. Un campo
local de pesos, limitado a hombro/pecho superior, corrige los seis contactos
dirigidos que quedaban sin mover la piel más de 0,948 mm ni cambiar los demás
propietarios. La adaptación de los nueve clips usa objetivos finitos de manos y
tobillos; no modifica nombres ni duraciones y mantiene cada objetivo por debajo
de 1e-5 m.

LOD2 se genera con QEM protegido por 53 estados estáticos y 52 poses, heredando
exactamente posiciones, pesos y morphs de los vértices retenidos. Una cara cuyo
promedio suave cruzaba su hemisferio geométrico se deja plana de forma local;
las demás siguen suaves. Los tres GLB quedan en 4704/2248/794 triángulos y el
master original conserva SHA256
`14763003da303779d38725530d78bc7a71baa83318d5b892ed5c5e610e3bb178`.

La puerta de producto recorre cada LOD en base, grosor general +1 y grosor de
piernas +1, para los nueve clips y cinco instantes: 405 muestras animadas, además
de 53 estados estáticos por export. Comprueba también la lista y duración exactas
de los clips. Los tests de fuente cubren A90, cierre del pulgar, objetivos IK,
pesos, LOD y normales; Godot pasa gel_body_asset, player_character,
player_sprint y character_motion. La revisión visual comprende 216 capturas de
protocolo y cuatro diagnósticas: no se observan aberturas ni pliegues invertidos;
la peor diferencia medida de perfil es 4,373368 %, bajo el límite de 5 %.

Esto endurece la evidencia finita de 10/12/13/17, pero no certifica el continuo
infinito de morphs+poses ni sustituye la comparación completa de Flaca y material.
El núcleo continúa descartado por presupuesto; UV sigue excediendo 15 % y la
corrección lineal de grosor no está aprobada. Por eso 10/12/13/14/15/16/17 se
mantienen pendientes en su alcance total. No cambia el jugador activo, red ni
colisiones.

## Estado actual: axila reconstruida, 2026-10-02

Esta sección sustituye los estados históricos de abajo. Se corrigieron los
pliegues de axila en A0/A30/A60/A75 con pesos de superficie normalizados a cuatro
influencias y loops cruzados curvos en LOD1. El dihedro problemático de A75 pasa
de 143,17° a 72,80°. LOD2 deriva esa superficie y protege la transición
cadera-muslo: la regresión de muestra 30/cara 9 pasó de RED a GREEN.

Fuente: siete tests Blender PASS, incluida la regresión de poses que falla en
13 subpruebas con el builder anterior. Python: 50 tests OK, siete skips que
requieren Blender y que se ejecutaron aparte. Los tres GLB reales pasan las
53 muestras cada uno sin errores; límites 4704/2248/794 triángulos. Se conservan
los once morphs, sus rangos y defaults cero, veinte huesos y nueve clips.
Reposos, inverse binds y datos de animación decodificados son idénticos a main
`e383ed5`; master original SHA256 `14763003da303779d38725530d78bc7a71baa83318d5b892ed5c5e610e3bb178`.

Godot 4.7.2/GL Compatibility, RX7800XT: cuatro tests relacionados PASS, lint
PASS, 216 capturas nuevas y 144 comparaciones bajo el 5 %. Con el denominador
más estricto de área de LOD0, máximos LOD1=3,1003 % y LOD2=4,4195 %.
`lod_silhouette_report.json` usa la métrica original XOR/unión.
Las 18 vistas cercanas opacas A60/A75 no muestran aberturas ni pliegues
transversales invertidos; persiste el facetado propio de LOD2 distante.
Las hojas actuales están en `axilla_captures/`; las demás carpetas de capturas
son históricas y no certifican estos archivos.

`export_validation.json`, métricas y experimento de núcleo fueron regenerados.
El núcleo sigue fuera de presupuesto y no seleccionado; UV sigue fallando 15 %,
y la corrección lineal de grosor no está aprobada. No cambia el jugador activo.
No se certifican A90, todas las animaciones ni el continuo de morphs+poses.
10/12/13 siguen pendientes en su alcance total; C/D/E y Flaca completo también.

## Historial (no evidencia del export actual)

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
