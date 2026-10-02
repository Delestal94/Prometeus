# N-917: el terreno por rebanadas deja un hilo libre a Jolt (2026-10-01)

Lo hizo Nacho (con Claude), rama `nacho/N-917-jolt-jobs`. Zona compartida: `modules/route_gen/terrain_field.gd`.

- `TerrainField.build_async()` y `conform_all()` ya no piden todos los hilos del `WorkerThreadPool`
  (`tasks_needed = -1`): usan `TerrainField.worker_tasks()` = núcleos − 1 (mínimo 1).
- Por qué: Jolt corre sus jobs de física en el mismo pool y solo los libera cuando un hilo del pool los
  ejecuta. Con el pool entero ocupado 1,5–3 s, los jobs se acumulaban hasta agotar los 2048 fijos
  ("Jolt Physics job system exceeded the maximum number of jobs") y el paso de física quedaba esperando
  en el hilo principal (cuadros de 0,4–1,8 s bajo la pantalla de carga). Lo trajo #191 (N-408).
- Para quien use el pool: un `add_group_task` largo con `-1` y prioridad alta vuelve a provocarlo. Dejá
  al menos un hilo libre (`TerrainField.worker_tasks()` o equivalente).
- Ninguna firma cambia. Test: `tests/test_jolt_job_budget.gd`.
