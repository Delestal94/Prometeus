# Grupo 20 — Red, rendimiento, QA, tests, Steam y lanzamiento

> Fase **F0** (núcleo de red y CI) / F5 · Dueño: Nacho · Depende de: todo.
> Aviso: sí (`network_manager.gd`, zona compartida). Cada cambio de RPC elige `PROTOCOL_VERSION` como
> dice `convenciones-godot.md` §6.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-2001 | ✅ Modelo de autoridad de la expansión (host dueño de empresa, stock, pedidos, empleados) | auditor-red | xhigh | doc en `docs/arquitectura.md` |
| D-2002 | Presupuesto de ancho de banda del galpón (objetos, empleados, cintas) | constructor-red | high | número medido con 8 jugadores |
| D-2003 | ✅ Sincronización por eventos en vez de por tick para stock y pedidos | constructor-red | xhigh | test de red |
| D-2004 | ✅ Join tardío al galpón: el que entra recibe el estado completo | constructor-red | xhigh | test de join tardío a mitad de día |
| D-2005 | Desconexión del host a mitad de día: guarda y vuelve al menú con resultados (N-222) | constructor-red | high | test |
| D-2006 | Cliente desconectado vuelve y recupera su lugar | constructor-red | high | test |
| D-2007 | `RpcGuard` en todos los RPC nuevos | constructor-red | medium | test N-238 extendido |
| D-2008 | `PROTOCOL_VERSION` nuevo para la expansión | constructor-red | low | número subido según §6 |
| D-2009 | Steam: lobby con nombre de empresa y día | constructor-red | medium | test en build |
| D-2010 | Guardado en la nube del save de empresa (D-0237) | constructor-red | medium | probado en build |
| D-2011 | Benchmark del modo Empresa (`bench_company`) en CI | perfilador-rendimiento | high | paso de CI con número |
| D-2012 | Presupuesto de FPS por distrito y galpón | perfilador-rendimiento | medium | tabla en `rendimiento-pc.md` |
| D-2013 | Leak check de un día completo y de 10 días | perfilador-rendimiento | high | sin huérfanos (como S-908) |
| D-2014 | ✅ Tests de la expansión entran en `run-tests.sh` por filtro (`company`, `district`, `fleet`) | escritor-tests | low | filtros funcionan |
| D-2015 | ✅ Tests afectados en el hook `pre-push` para carpetas nuevas | escritor-tests | low | hook los detecta |
| D-2016 | Recorrido de QA del día completo para `probador-qa` | probador-qa | medium | guion en `docs/qa-recorrido.md` |
| D-2017 | Recorrido de QA de red par y trío en modo Empresa | probador-qa | high | guion |
| D-2018 | `portability-check.sh` incluye los módulos nuevos | escritor-tests | low | CI verde |
| D-2019 | Build de Windows con la expansión | empaquetador-release | medium | build y smoke test |
| D-2020 | Smoke test del ejecutable arrancando en modo Empresa | empaquetador-release | medium | paso en `release.yml` |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-2021 | Simulación de mala conexión con galpón lleno (N-216) | constructor-red | medium | test |
| D-2022 | Interest management: solo se replica lo cercano | constructor-red | xhigh | ancho de banda baja medido |
| D-2023 | Bot de 8 jugadores simulados para pruebas de carga | constructor-red | high | corre en CI nocturno |
| D-2024 | Bot de jugador solo que juega 20 días (D-0126) | constructor-progresion | high | termina sin quiebra ni bloqueos |
| D-2025 | Bot que juega la campaña completa acelerada | constructor-progresion | high | llega al Volcán en sim |
| D-2026 | Test de save de 50 días (tamaño y tiempo de carga) | escritor-tests | medium | < 2 s de carga |
| D-2027 | Fuzz de acciones en red (agarrar/soltar al mismo tiempo) | escritor-tests | high | test sin duplicados |
| D-2028 | Steam: logros (D-0440) | constructor-red | medium | logros en build |
| D-2029 | Steam: Remote Play Together en el galpón | constructor-red | medium | probado |
| D-2030 | Steam Deck: rendimiento y controles | perfilador-rendimiento | high | preset Deck medido |
| D-2031 | Página de Steam actualizada con la expansión | estratega-steam | medium | textos en `docs/marketing/` |
| D-2032 | Tráiler: lista de planos de la expansión | estratega-steam | medium | plan de planos |
| D-2033 | Demo para Next Fest (¿hasta qué distrito?) | estratega-steam | medium | decisión documentada |
| D-2034 | Notas de versión de la expansión | empaquetador-release | low | notas |
| D-2035 | Plan de actualización post-lanzamiento (distritos extra) | estratega-steam | low | plan |
| D-2036 | Sin telemetría remota (decidido 2026-10-04): revisar que la expansión solo escriba el log local | revisor-gdscript | low | grep sin `HTTPRequest` en carpetas nuevas |
| D-2037 | Reporte de errores desde el juego (log al portapapeles) | constructor-ui | low | test |
| D-2038 | Calidad mínima: preset bajo con galpón grande jugable | perfilador-rendimiento | high | FPS medido |
| D-2039 | Auditoría integral al cerrar cada fase | auditor-integral | high | informe por fase |
| D-2040 | Revisión de `abogado-del-diablo` al cerrar F2 y F4 | abogado-del-diablo | high | informes |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-2041 | Pasada de `revisor-gdscript` a todas las carpetas nuevas | revisor-gdscript | medium | sin hallazgos |
| D-2042 | `matriz-comportamiento-cobertura.md` con la expansión | documentador | medium | matriz al día |
| D-2043 | README "cómo probar" con el modo Empresa | documentador | low | README |
| D-2044 | `docs/arquitectura.md` final de la expansión | documentador | medium | doc |
| D-2045 | Limpieza de flags de desarrollo en release | empaquetador-release | low | test |
| D-2046 | Revisión de licencias de todo lo nuevo antes de lanzar | documentador | low | tabla |
| D-2047 | Prueba de 4 horas sin cerrar (estabilidad) | probador-qa | medium | sin leaks ni cuelgues |
| D-2048 | Prueba con 8 jugadores por Steam (⏸ playtesting, al final) | — | — | ⏸ con amigos, cuando toque |
| D-2049 | Checklist de lanzamiento de la expansión | estratega-steam | low | checklist |
| D-2050 | Cierre: marcar esta carpeta como terminada y archivar | documentador | low | README con estado final |
