# Grupo 19 — UI, tutorial, audio y efectos

> Fase **F1-F5** · Dueño: Nacho · Depende de: D-0130, D-0131.
> Aviso: sí (`scripts/ui/` es de Slatex). Todo texto por `tr()` (N-805); todo navegable con mando.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1901 | Tutorial de la primera semana (D-0130): un objetivo por vez | constructor-ui | high | bot completa el tutorial sin errores |
| D-1902 | Portapapeles: objeto en la mano con pestañas (pedidos, stock, empleados, flota, plata) | constructor-ui | xhigh | test de navegación con mando y teclado |
| D-1903 | HUD del día: hora, plata, pedidos pendientes | constructor-ui | medium | captura |
| D-1904 | Menú principal con modo Empresa y slots de guardado | constructor-ui | high | test de flujo |
| D-1905 | Pantalla de cierre del día (resumen, hitos, sueldos) | constructor-ui | high | captura |
| D-1906 | Pantalla de despacho (D-0303) con estilo final | constructor-ui | medium | captura |
| D-1907 | Indicadores en el mundo (flecha a la estación que necesita algo) | constructor-ui | medium | captura |
| D-1908 | Tooltips de productos y requisitos | constructor-ui | low | test |
| D-1909 | Menú de pausa con opciones de la empresa | constructor-ui | low | test |
| D-1910 | Escalado de UI y Steam Deck | constructor-ui | medium | captura a 800p |
| D-1911 | Música del galpón (loop de trabajo, sube con la actividad) | disenador-audio | medium | loop adaptativo |
| D-1912 | Mezcla: buses para galpón, máquinas y distritos | disenador-audio | medium | niveles medidos |
| D-1913 | SFX de UI del portapapeles | disenador-audio | low | SFX |
| D-1914 | Efecto de pedido completado | artista-vfx | low | partículas |
| D-1915 | Efecto de error de armado | artista-vfx | low | efecto |
| D-1916 | Fuente y estilo visual unificado de la expansión | constructor-ui | medium | tema de Godot |
| D-1917 | Traducción al inglés de todo lo nuevo | constructor-ui | medium | `loc_text` completo |
| D-1918 | Accesibilidad: daltonismo en requisitos y estados | constructor-ui | medium | captura con filtros |
| D-1919 | Opciones de dificultad visibles (D-0127) | constructor-ui | low | test |
| D-1920 | Test de que todo texto nuevo pasa por `tr()` | escritor-tests | low | test N-805 extendido |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1921 | Radio del galpón con estaciones (música, noticias graciosas) | disenador-audio | medium | 3 estaciones |
| D-1922 | Noticias del diario del día siguiente con eventos de la empresa (N-606) | constructor-ui | medium | diario con titulares de negocio |
| D-1923 | Celular del jugador con app de pedidos y mapa | constructor-ui | high | test |
| D-1924 | Pantalla de estadísticas (D-0431) | constructor-ui | medium | captura |
| D-1925 | Pantalla de personalización de la empresa | constructor-ui | medium | captura |
| D-1926 | Tutoriales por sistema (empleados, automatización, lancha, vuelo) | constructor-ui | high | 4 flujos |
| D-1927 | Consejos en pantalla de carga según distrito | constructor-ui | low | 40 consejos |
| D-1928 | Voces del jefe y NPC como murmullos de `SynthAudio` + burbujas (decidido 2026-10-04: sin ElevenLabs) | disenador-audio | medium | murmullos por personaje en `SynthAudio`; test de que no hay archivos de voz |
| D-1929 | Música por distrito (9 temas compuestos por código) | disenador-audio | high | 9 loops |
| D-1930 | SFX de vehículos nuevos revisados juntos | disenador-audio | medium | mezcla |
| D-1931 | Efectos de clima por distrito (lluvia, nieve, ceniza) unificados | artista-vfx | medium | presupuesto medido |
| D-1932 | Efecto de "nivel subido" de empleado | artista-vfx | low | efecto |
| D-1933 | Efecto de desbloqueo de distrito | artista-vfx | medium | efecto |
| D-1934 | Transiciones animadas entre pantallas | constructor-ui | low | tweens |
| D-1935 | Feed de eventos del galpón (quién hizo qué) | constructor-ui | medium | captura |
| D-1936 | Voz de proximidad en el galpón grande (alcance ajustado) | constructor-red | low | parámetros |
| D-1937 | Chat de pings con íconos de negocio | constructor-ui | low | test |
| D-1938 | Atajos de teclado configurables para gestión | constructor-ui | medium | test |
| D-1939 | Texto a voz de pedidos para accesibilidad (opcional) | critico-diseno | low | decisión |
| D-1940 | Créditos actualizados | constructor-ui | low | pantalla |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-1941 | Pasada de pulido de UI completa | pulidor-jugabilidad | high | lista cerrada |
| D-1942 | Pasada de mezcla de audio completa | disenador-audio | medium | niveles en doc |
| D-1943 | Pasada de VFX para no tapar visión | artista-vfx | medium | capturas |
| D-1944 | Revisión de UX copy de la expansión (skill ux-copy) | constructor-ui | low | textos revisados |
| D-1945 | Capturas de cada pantalla nueva | revisor-visual | low | set |
| D-1946 | Revisión de accesibilidad | revisor-visual | medium | informe |
| D-1947 | Rendimiento de la UI (portapapeles sin picos) | perfilador-rendimiento | low | medido |
| D-1948 | Test de navegación con mando de todas las pantallas nuevas | escritor-tests | high | test |
| D-1949 | Documentar controles nuevos en `controles-y-ui.md` | documentador | low | doc |
| D-1950 | QA de UI | probador-qa | medium | tabla |
