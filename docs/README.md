# Índice de docs

Todo `docs/*.md` tiene que estar listado acá: `python tools/check_docs.py` (CI y pre-push) falla si
un doc queda huérfano, si un link relativo se rompe o si un doc nombra un archivo que ya no existe.
Un doc nuevo se suma a esta tabla en el mismo commit; uno que deja de valer se borra (git guarda la historia).

## Vigentes: cómo está hecho el juego
| Doc | Qué es |
|---|---|
| [definicion-proyecto.md](definicion-proyecto.md) | Qué es el juego y qué no |
| [arquitectura.md](arquitectura.md) | Capas, autoloads, red |
| [convenciones-godot.md](convenciones-godot.md) | Reglas de código, `.tscn`, protocolo de red |
| [modulos.md](modulos.md) | Módulos portables de `do-not-drop/modules/` |
| [controles-y-ui.md](controles-y-ui.md) | Controles y flujo de UI/lobby |
| [requerimientos-tecnicos.md](requerimientos-tecnicos.md) | Requerimientos técnicos y funcionales |
| [matriz-comportamiento-cobertura.md](matriz-comportamiento-cobertura.md) | Qué comportamiento cubre qué test |
| [inventario-assets.md](inventario-assets.md) | Assets existentes y quién los genera |
| [qa-recorrido.md](qa-recorrido.md) · [rendimiento-pc.md](rendimiento-pc.md) | Recorrido de QA y FPS diarios |

## Cómo agregar cosas
[como-agregar-una-trampa.md](como-agregar-una-trampa.md) · [agregar-vehiculo.md](agregar-vehiculo.md) · [agregar-contenido-expansion.md](agregar-contenido-expansion.md) · [glosario.md](glosario.md) (una palabra por concepto en los textos)

## Diseño y contenido
| Doc | Qué es |
|---|---|
| [parametros-diseno.md](parametros-diseno.md) | Valores iniciales de diseño |
| [economia-y-contramedidas.md](economia-y-contramedidas.md) · [cartas-y-eventos-de-ruta.md](cartas-y-eventos-de-ruta.md) | Economía, cartas y eventos |
| [jugabilidad-paquetes-rescate.md](jugabilidad-paquetes-rescate.md) | Paquetes, caos y rescate |
| [deposito-rediseno.md](deposito-rediseno.md) · [mapa-pueblo.md](mapa-pueblo.md) | Depósito y ciudad |
| [narrativa.md](narrativa.md) · [diario-final.md](diario-final.md) | Premisa, tono y escena final |
| [direccion-visual.md](direccion-visual.md) · [especificaciones-visuales.md](especificaciones-visuales.md) | Dirección visual |
| [audio.md](audio.md) · [audio-mundo.md](audio-mundo.md) | Mezcla de trampas/UI y del mundo |
| [mecanicas-candidatas.md](mecanicas-candidatas.md) | Banco de mecánicas sin comprometer |

## Equipo y plan
[colaboracion-equipo.md](colaboracion-equipo.md) · [plan-desarrollo.md](plan-desarrollo.md) ·
[tareas-nacho.md](tareas-nacho.md) (portada; las tareas están en [tareas/](tareas/README.md)) ·
[tareas-nacho-archivo.md](tareas-nacho-archivo.md) · [tareas-slatex.md](tareas-slatex.md) ·
[checklist-exito.md](checklist-exito.md)

## Investigación y críticas
[investigacion-mercado.md](investigacion-mercado.md) · [investigacion-red.md](investigacion-red.md) ·
[analisis-competencia-backseat-rv.md](analisis-competencia-backseat-rv.md) ·
[critica-diseno-abogado-del-diablo.md](critica-diseno-abogado-del-diablo.md)

## Carpetas
[auditorias/](auditorias/) (una por pasada) · [avisos/](avisos/) (cambios que tocan al otro integrante) ·
[decisiones/](decisiones/) · [postmortems/](postmortems/) · [marketing/](marketing/) ·
[expansion-distritos/](expansion-distritos/) (backlog D-xxxx, no activo hasta promoverse) ·
[historial-exploracion/](historial-exploracion/)
