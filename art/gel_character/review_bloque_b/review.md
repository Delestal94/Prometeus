# Revisión independiente — preparación B, 2026-10-01

## Corrección de axila, 2026-10-02

Revisión independiente de código/assets y ejecución Godot: PASS para el alcance
A0/A30/A60/A75. Cuatro tests PASS y lint PASS después del import final, 216
capturas de silueta, 144 comparaciones bajo 5 %, dieciocho vistas cercanas A60/A75
sin aberturas ni pliegue transversal invertido. LOD2 mantiene facetado distante.

Verificados independientemente en los GLB finales los veinte reposos e inverse
binds y los nueve clips: sus valores decodificados son idénticos a `e383ed5`.
El master original no cambió. Root comprobó por separado los siete tests fuente
y el barrido estricto de 53 muestras por LOD. Regresiones RED→GREEN cubren el
pliegue de hombro y la pérdida de transición cadera-muslo al simplificar LOD2.

No hay aprobación de todo B: A90, todas las animaciones y el continuo combinado
siguen sin certificar, igual que los ítems completos 10/12/13 y el material E.
El resultado actual y sus métricas están en `ESTADO_ACTUAL.md`.

Una revisión final nueva, sin acceso al historial de revisiones, también dio
PASS: ejecutó siete tests fuente en Blender, validación genérica de los tres
GLB y las 53 muestras estrictas de LOD2, comparó reposos/binds/clips contra
`f0a8a94` e inspeccionó ambas hojas de hombros. No volvió a correr Godot ni el
barrido estricto LOD0/1; éstos corresponden a las comprobaciones separadas de
ejecución y root. Tras el último pull, los cuatro tests Godot volvieron a pasar.

## Historial de entregas anteriores

Veredicto **PASS** del revisor nuevo `gel_preparation_fresh_gate`, sin acceso a
revisiones anteriores. Aprobación de la preparación, no cierre completo de B/E.

| Condición | Evidencia independiente |
|---|---|
| Reproducibilidad y presupuestos | Tres huellas de geometría/morph reproducidas; 4704/1176/794tri;3testsBlenderPASS; master intacto. |
| Contrato de cuerpo |11morphs[-1,+1],20huesos exportados,35deautoría,9clips actuales incluidoRun. |
| API y geometría exportada | Genérico preservado; costuras exactas crudas/evaluadas, enlaces manifold, orientación exterior y normales de sombreado; negativos reales. |
| Barrido | Tres LOD53muestras cada unoPASS, incluidos22extremos y30combinaciones seed311018; no prueba del continuo. |
| Medición |4704rayos por23estados, cero faltantes, mapaRGBA1024²; hash fuente verificado. |
| LOD en Godot |216capturas,144comparacionesPASS; máximos2,724%/4,014% frente a5%; mismo protocolo y pesos. |
| Tests |41PythonOK,3SKIP requierenBlender;3sourceBlenderPASS. |
| Documentación | Preparación aislada y pendientes explícitos, sin aprobación de material ni reemplazo del jugador. |

Sin hallazgos bloqueantes. El revisor no ejecutó Godot; la última corrida con los
nueve clips pasó4/4tests y144comparaciones, registrada en `ESTADO_ACTUAL.md`.
La verificación de archivos modificados y los hooks/CI son responsabilidad del cierre.

Pendientes:10/12/13 visual/continuo;14/15D/E;16distorsiónUV excede15%;17Flaca
completo dependeC. Corrección lineal error0,759955m y núcleo9408tri se rechazan.
El shader, la apariencia final y costeGPU de cuatro personajes no están certificados.

## Revisión independiente: defaults Delgada, 2026-10-01

Dictamen: PASS, sin bloqueos ni advertencias, limitado a esta corrección.
Base sincronizada con main `c29a526`; el cambio de tipado del otro desarrollador
se conservó y se repitieron los cuatro tests Godot relacionados después del pull.

El revisor ejecutó independientemente los 30 tests de fixtures, cuatro pruebas
Blender y la suite Python de 44 tests (cuatro skips requieren Blender). Leyó el
`.blend` guardado y los tres GLB: once defaults efectivos cero y rangos −1…+1.
Comparó los payloads binarios con la base: posiciones, índices, todos los morphs,
atributos, pesos del rig, skins y samplers de los nueve clips permanecen iguales.
Comprobó el SHA del master y de las métricas, y repitió los barridos GLB de
53 muestras por LOD sin errores. La API genérica del validador sigue intacta.

Comparó los siete PNG de referencia conservados con las capturas actuales:
idénticos píxel a píxel. Repitió 144 comparaciones LOD: todas pasan, máximo
4,0143 %. El ejecutor independiente reportó Godot 4/4 PASS después del pull;
el revisor no ejecutó Godot. La documentación distingue correctamente los
defaults incorrectos de autoría/exportación de la carga anterior de Godot a cero.

El ensayo de hombros fue retirado completamente. La revisión no aprueba nuevos
ajustes visuales ni cierra 10/13/E, UV, núcleo o preset Flaca completo.
