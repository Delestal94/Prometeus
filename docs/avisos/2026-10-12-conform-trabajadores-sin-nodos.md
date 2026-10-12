# conform_all(): los hilos ya no le piden nada al nodo del terreno (2026-10-12)

Lo hizo Nacho (con Claude), rama `nacho/ci-flaky-route-golden-crash` (issue #404). Zona compartida:
`modules/route_gen/terrain_field.gd`.

- `_conform_warp()` (corre en el `WorkerThreadPool` desde `conform_all()`) leía `global_transform` del
  terreno en cada malla. Leer ese valor puede refrescar el transform cacheado del nodo y de sus
  ancestros mientras el hilo principal sigue trabajando en el mismo árbol. Ahora `_conform_prepare()`
  (hilo principal) guarda `terrain_global` y `terrain_inverse` en el trabajo y el hilo solo lee eso.
- Mismos números: el golden de la ruta no cambia. Ninguna firma pública cambia.
- Para quien toque el trabajo de `conform_all()`: dentro de `_conform_warp()` y lo que llama no se le
  pregunta nada a un `Node` (ni `global_transform`, ni `to_local`, ni metas); todo entra por el trabajo.
