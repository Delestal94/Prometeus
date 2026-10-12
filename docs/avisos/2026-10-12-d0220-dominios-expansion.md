# Las carpetas de la expansión tienen dueño (D-0220, D-0144)

**Fecha:** 2026-10-12 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- `docs/colaboracion-equipo.md` (zona compartida): en "Nacho" se suman las carpetas del modo Empresa
  (`scripts/core/company/`, `scripts/gameplay/business/`, `districts/`, `fleet/`, `scenes/company/` y
  `data/products|zones|vehicles|boxes|suppliers|gates|order_requirements|placeables/`).
- `.claude/hooks/lib.sh` (`file_domain`): la misma lista, así los hooks avisan si las tocás. Nada tuyo cambió
  de dueño; `tools/test-file-domain.sh` (job de lint) lo comprueba.
- `docs/arquitectura.md` §10.4: qué de la expansión va a `modules/` (zona compartida) y qué queda en el juego.
