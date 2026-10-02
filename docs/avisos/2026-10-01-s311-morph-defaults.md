# S-311: estado inicial Delgada consistente

Se corrigió `art/gel_character/build_gel_body.py` para guardar y exportar los
once morphs con valor inicial cero. Blender los creaba en uno; los tres GLB
anteriores también declaraban once valores uno. Sus rangos −1…+1 no cambian.

`gel_body_validation.py` exige cero en los pesos iniciales efectivos del modo
estricto gel, con precedencia nodo/malla y cero implícito si no se declaran.
La API genérica de `validate_glb.py` permanece igual. Las regresiones cubren
defaults de malla/nodo incorrectos, valores no finitos, longitud incorrecta y
override válido; `test_gel_body_asset.gd` comprueba carga a cero en Godot.
El importador actual ya cargaba cero antes del arreglo: no se afirma un fallo
visual de carga en Godot, sino una inconsistencia de autoría y exportación.

Los pesos del rig, geometría, morphs, presupuesto y nueve clips siguen iguales.
Se regeneraron `.blend`, los tres GLB y la evidencia dependiente de la fuente.
No se reemplaza al jugador activo ni se cambia red, colisiones o animaciones.
Los ítems visuales 10/13 y las dependencias C/D/E continúan pendientes.

Hacer pull antes de seguir y antes de integrar cambios, como acordamos entre
los dos desarrolladores. No hay firmas ni protocolo de red nuevos.
