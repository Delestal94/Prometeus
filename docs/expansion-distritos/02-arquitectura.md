# Grupo 02 — Arquitectura, datos y guardado

> Fase **F0** · Dueño: Nacho · Depende de: D-0102, D-0104, D-0119 · Aviso: sí cuando toque
> `run_manager.gd`, `network_manager.gd`, `event_bus.gd` (zona compartida) o `modules/`.
> Lo genérico va en módulos nuevos (`modules/<nombre>/` con `module.cfg` y test; `check_modules.py`).

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0201 | ✅ Documento de arquitectura de la expansión (capas: empresa persistente → día → entrega; quién es autoridad) | Plan | xhigh | sección "Expansión" en `docs/arquitectura.md` con diagrama |
| D-0202 | ✅ Autoload `CompanyState` (plata, día, reputación, desbloqueos, flota, empleados) separado de `RunManager` | constructor-progresion | xhigh | autoload compila; test `test_company_state` crea, modifica y serializa |
| D-0203 | `DayCycle`: estados del día (apertura, operación, cierre) con señales en `EventBus` | constructor-progresion | high | test `test_day_cycle` recorre los tres estados y emite las señales |
| D-0204 | ✅ Recurso `ProductDefinition` (.tres): id, malla, tamaño, peso, fragilidad, temperatura, precio | constructor-negocio | medium | 5 productos de prueba cargan; test valida campos |
| D-0205 | ✅ Recurso `DistrictDefinition` (.tres): id, escena, vehículos permitidos, peligros, condición de desbloqueo | constructor-mundo | medium | Barrio Centro y Campo definidos; test los carga |
| D-0206 | Guardado de empresa sobre `modules/persistence` con versión de esquema y migraciones | constructor-progresion | xhigh | test guarda, carga y migra un save v1 → v2 sin perder datos |
| D-0207 | Recurso `VehicleDefinition` (asientos, carga, escena, física, licencia requerida) | constructor-camion | high | la camioneta actual descrita por un `.tres` sin cambiar su manejo (`test_reference_truck` verde) |
| D-0208 | Extraer de `vehicle.gd` una base común `FleetVehicle` (asientos, carga, red, presentación) para vehículos que no son de ruedas | constructor-camion | xhigh | camioneta hereda de la base; tests de vehículo verdes; documento `agregar-vehiculo.md` actualizado |
| D-0209 | Interfaz de "movimiento" del vehículo (ruedas, casco, alas, pedal) para que asientos y carga no sepan cuál es | constructor-camion | xhigh | test con un vehículo falso de cada tipo usa la misma interfaz |
| D-0210 | ✅ `OrderBook`: pedidos activos, estado y vencimiento, autoridad en el host | constructor-progresion | high | test `test_order_book` crea, cumple y vence pedidos |
| D-0211 | ✅ `Inventory`: stock por producto y ubicación (estante, palet, caja abierta) con autoridad en el host | constructor-negocio | high | test `test_inventory` mueve unidades sin duplicar ni perder |
| D-0212 | `PackedBox`: modelo de datos de un paquete armado (caja, contenido, relleno, cinta, etiqueta, sellos, pedido) | constructor-negocio | high | test serializa y compara contra el pedido |
| D-0213 | Puente `PackedBox` → `DeliveryPackage` + trampa actual (la entrega sigue igual) | constructor-trampas | xhigh | una caja armada en el galpón aparece en la camioneta con la trampa calculada (test) |
| D-0214 | ✅ Escena raíz del modo Empresa (`company_root.tscn`) que carga galpón y distritos con `scene_loader` | constructor-mundo | high | arranca con `--autostart --mode=company` sin errores |
| D-0215 | Señales nuevas en `EventBus` para negocio (pedido_entrante, caja_armada, entrega_cobrada, empleado_contratado…) | constructor-progresion | medium | lista documentada; `test_event_bus_signals` las cubre |
| D-0216 | Registro de distritos (`DistrictRegistry`) leído de `.tres`, sin listas a mano | constructor-mundo | medium | agregar un `.tres` suma el distrito sin tocar código (test) |
| D-0217 | Registro de vehículos (`FleetRegistry`) leído de `.tres` | constructor-camion | medium | idem con vehículos |
| D-0218 | Registro de productos y proveedores leído de `.tres` | constructor-negocio | medium | idem con productos |
| D-0219 | Reloj del juego determinista desde el host (hora del día, aceleración, pausa) | constructor-red | high | test con dos peers ve la misma hora ±1 tick |
| D-0220 | Decidir dónde vive cada script nuevo (`business/`, `fleet/`, `districts/`) y qué va a módulos | Plan | medium | árbol de carpetas en `docs/arquitectura.md`; `check_modules` verde |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0221 | Módulo portable `inventory` (stock genérico sin nombrar nada del juego) | constructor-negocio | high | `modules/inventory/` con `module.cfg` y test; `portability-check.sh` verde |
| D-0222 | Módulo portable `order_queue` (cola de pedidos con prioridad y vencimiento) | constructor-progresion | high | idem |
| D-0223 | Módulo portable `day_clock` (reloj de juego con fases) | constructor-progresion | medium | idem |
| D-0224 | Módulo portable `job_board` (tareas para agentes IA: tomar, hacer, soltar) para empleados | constructor-negocio | high | idem |
| D-0225 | Módulo portable `build_grid` (colocación en grilla con validación de choque) | constructor-negocio | high | idem |
| D-0226 | Módulo portable `conveyor_graph` (cintas como grafo, avance de ítems por tick) | constructor-negocio | xhigh | idem; 1000 ítems por tick en benchmark < 1 ms |
| D-0227 | Módulo portable `buoyancy` (flotación por puntos para la lancha) | constructor-camion | high | idem |
| D-0228 | Módulo portable `simple_flight` (sustentación, arrastre, empuje para la avioneta) | constructor-camion | high | idem |
| D-0229 | Módulo portable `milestones` (condiciones y recompensas declarativas) | constructor-progresion | high | idem |
| D-0230 | Adaptadores chicos en `scripts/` que conectan cada módulo nuevo con el juego | constructor-negocio | medium | ningún módulo nombra autoloads (check verde) |
| D-0231 | Simulación del día sin escena (headless) para tests y balance: corre 1 día en < 2 s | constructor-progresion | high | `tools/sim_day.gd` imprime ingresos, entregas y fallas |
| D-0232 | Sistema de "tick de negocio" a frecuencia fija (4 Hz) separado de la física | constructor-negocio | medium | test verifica cadencia; el perfilador no lo ve en el frame |
| D-0233 | Pool de objetos para productos y cajas (evitar crear y borrar nodos) | perfilador-rendimiento | high | `bench_depot` sin picos de allocs al armar 100 cajas |
| D-0234 | Migración del save de perfil actual (`unlock_profile`) al save de empresa | constructor-progresion | high | perfil viejo carga y conserva cosméticos y récords |
| D-0235 | Varias empresas guardadas (slots) con nombre y fecha | constructor-progresion | medium | test crea, lista y borra 3 slots |
| D-0236 | Guardado automático al cerrar el día y al salir | constructor-progresion | medium | test: matar el proceso a mitad de día y recuperar el último cierre |
| D-0237 | Rutas de guardado compatibles con Steam Auto-Cloud (ver N-914) | constructor-red | medium | rutas bajo `user://saves/company/`; documentado |
| D-0238 | Flags de desarrollo: `--company-day=N`, `--district=x`, `--money=n` para tests y capturas | constructor-progresion | low | documentados en README; usados por `render_*` |
| D-0239 | Telemetría local del día (`run_log`) con eventos de negocio | constructor-progresion | medium | log del día se lee con `run_telemetry_format` |
| D-0240 | Separación simulación/presentación en todo lo nuevo (convención §) | revisor-gdscript | medium | revisión sin hallazgos de mezcla en `business/` |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0241 | Tipado estricto en todos los scripts nuevos (sin `Variant` implícitos) | revisor-gdscript | low | lint sin warnings de tipo en carpetas nuevas |
| D-0242 | Presupuesto de líneas por archivo (lint) respetado en carpetas nuevas | revisor-gdscript | low | `tools/lint` verde |
| D-0243 | Test de que ningún `--script` pierde autoloads al nombrar clases nuevas (lección de N-919) | escritor-tests | medium | `test_hud_script_loads` extendido a `CompanyState` |
| D-0244 | Documentar cómo agregar un producto, un distrito y un vehículo (3 guías cortas) | documentador | low | `docs/agregar-producto.md`, `agregar-distrito.md`, `agregar-vehiculo.md` actualizada |
| D-0245 | Validador de `.tres` de la expansión (ids únicos, rutas existentes, rangos) en CI | escritor-tests | medium | `test_expansion_resources` falla con un id repetido |
| D-0246 | Semilla de mundo compartida extendida a pedidos y proveedores (todos ven lo mismo) | auditor-red | high | auditoría sin desincronías |
| D-0247 | Ver si `DeliveryHouse` puede ser genérica para muelle, pista y casa de montaña | constructor-mundo | medium | decisión anotada y, si sí, una sola clase con variantes |
| D-0248 | Medir costo de memoria del modo Empresa con galpón grande | perfilador-rendimiento | medium | número en `docs/rendimiento-pc.md` |
| D-0249 | Revisión de arquitectura por `auditor-integral` al cerrar F0 | auditor-integral | high | hallazgos P0-P1 resueltos |
| D-0250 | Actualizar `docs/modulos.md` con el catálogo de módulos nuevos | documentador | low | catálogo al día |
