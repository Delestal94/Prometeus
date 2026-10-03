# N-950 · Parcelas compactas compatibles con el plano anterior

Zona compartida: `do-not-drop/modules/town_gen/`.
`town_plan.generate(seed, generator_version=2)` agrega un argumento opcional.
La versión 1 conserva el algoritmo anterior; la 2 mantiene calles, verdes y
lotes originales y agrega parcelas compactas en los distritos 0/1.
Versiones no soportadas devuelven `{}`. No migra guardados ni protocolo.

Nuevo `town_infill.gd`: huellas rectangulares con dos metros de separación,
retirada de aceras, reserva de accesos existentes y de entradas verdes antes
de llenar los huecos. Direcciones nuevas después de las originales.
`town_walkways.green_access(plan, districts)` separa la planificación de
entradas del mallado y respeta `reserved_green_paths` cuando existe.
Pruebas ampliadas para compatibilidad, densidad, geometría y reservas.
Actualizar la rama antes de trabajar en estos módulos.
