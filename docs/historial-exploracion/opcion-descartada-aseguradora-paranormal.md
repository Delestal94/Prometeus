# Definición de proyecto — Tema y mecánica central (DESCARTADO)

> ⚠️ **ARCHIVADO — este concepto fue descartado.** Este documento define un juego de
> puzzle/narrativa ("aseguradora de lo paranormal") que **no es el proyecto actual**.
> El proyecto pivoteó a un delivery cooperativo con paquetes-trampa, propuesto
> directamente por el usuario. La definición vigente del proyecto está en
> `docs/definicion-proyecto.md` (en la raíz de `docs/`, no en este archivo). Se
> conserva este documento como registro del proceso de decisión.
>
> Basado en: `docs/mvp-candidatos.md` (Candidato 3 elegido: puzzle/narrativa de autor,
> con rejugabilidad ligera).
> Última actualización: 2026-09-20
> Estado: eligiendo tema + mecánica central (la "lente") antes de pasar a requerimientos.

## Contexto de búsqueda

Revisé el estado actual del género (deducción/verificación narrativa) para no proponer
algo ya saturado. Encontré casos recientes como *Clues by Sam* (deducción por
constraints, 50k jugadores diarios) y *TR-49* (explorar una base de datos tipo
"Wikipedia rabbit hole" para investigar) — el espacio sigue activo pero sin un patrón
de clones masivos como los otros géneros. Buena señal para el Candidato 3.

## Opciones propuestas (tema + mecánica)

### Opción A — Aseguradora de lo paranormal ⭐ (recomendada)
- **Tema**: trabajás como perito de una aseguradora que cubre eventos "imposibles"
  (algo se comió el auto, la casa cambió de lugar, un familiar juró que lo secuestraron
  ovnis). Tenés que decidir si el reclamo es legítimo según la póliza y la evidencia.
- **Mecánica/lente**: cruzar testimonios contradictorios, fotos, recibos y cláusulas de
  la póliza para aprobar, rechazar o investigar más un reclamo. La dificultad escala
  agregando cláusulas nuevas, testigos que mienten, o reclamos con capas de fraude
  encubierto (igual que Papers Please escala reglas de frontera).
- **Por qué es fuerte**: el contenido es absurdo por diseño → genera **momentos
  clipeables** naturalmente (la debilidad típica del género), sin necesitar sistemas
  emergentes. Además permite un **modo "endless" con reclamos generados combinando
  piezas** (testigo + objeto + causa) para sumar la rejugabilidad ligera que
  recomendamos — barato de producir, ya que son combinaciones de texto/ítems, no arte
  nuevo por caso.
- **Riesgo**: hay que escribir bien el humor/tono para que no se sienta repetitivo.

### Opción B — Restaurador/tasador de objetos falsificados
- **Tema**: trabajás en una casa de subastas o anticuario, autenticando piezas antes de
  la venta.
- **Mecánica/lente**: comparar la pieza con el catálogo/procedencia, detectar
  inconsistencias de estilo, época o material, decidir si es auténtica, falsificada, o
  robada.
- **Por qué podría funcionar**: apela a fans de "detective visual" (como Obra Dinn), con
  fuerte componente de observación.
- **Riesgo**: más difícil de generar contenido variado sin arte nuevo por caso (cada
  objeto necesita diseño único) — mayor carga de producción visual que la Opción A.

### Opción C — Curador de mensajes/cartas de un pueblo aislado
- **Tema**: sos el/la encargado/a de la oficina de correos (o de una radio) de un pueblo
  remoto con secretos, decidiendo qué correspondencia dejar pasar.
- **Mecánica/lente**: similar en estructura a Papers Please (revisar documento contra
  reglas), aplicado a cartas/mensajes en vez de pasaportes.
- **Por qué podría funcionar**: tono íntimo, dilemas morales fuertes.
- **Riesgo**: estructuralmente muy cercano a Papers Please — menos diferenciado, mayor
  riesgo de sentirse "clon con skin nueva" (el mismo problema que detectamos en el
  género roguelike saturado).

### Opción D — Investigador/a de reclamos de seguros médicos imposibles (variante de A)
- Similar a la A pero con tono más oscuro/serio (bioética en vez de humor paranormal).
- Se descarta como primera opción: mismo esqueleto que A pero con tono más pesado y
  menos "clipeable", que es justo lo que buscamos reforzar en este candidato.

## Comparación rápida

| | A: Seguros paranormales | B: Tasador de falsificaciones | C: Correo de pueblo aislado |
|---|---|---|---|
| Diferenciación vs. referentes | Alta | Media | Baja (muy cerca de Papers Please) |
| Carga de producción visual | Baja (documentos/texto + iconos) | Alta (arte único por objeto) | Baja-media |
| Potencial de humor/viralidad | Alto | Bajo-medio | Bajo |
| Facilidad de generar rejugabilidad ligera | Alta (combinatoria de reclamos) | Media | Media |

## Recomendación

**Opción A (Aseguradora de lo paranormal)** es la que mejor cumple los criterios del
Candidato 3 reforzado: bajo costo de producción, mayor diferenciación, y resuelve la
debilidad estructural del género (poca viralidad) con humor absurdo integrado al propio
tema, no como añadido artificial.

## Próximo paso
Si se confirma la Opción A, pasar a definir en `docs/requerimientos.md`:
- Estructura exacta de un "caso" (qué piezas de evidencia, cuántas por caso, cómo se
  presentan).
- Reglas de la "póliza" inicial y cómo escalan de complejidad.
- Diseño del modo endless/rejugable.
- Tono narrativo y referencia visual (paleta, estilo de documentos).
