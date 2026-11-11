# El workflow de release arranca la build de Linux en modo Empresa

- **Qué cambió (`.github/workflows/release.yml`, zona compartida):** paso nuevo "Smoke test (Linux build boots the
  company mode)" después del smoke al menú y antes de los zips. Corre `tools/export/smoke-company.sh builds/linux`
  (D-2019) y falla si la última línea no es `Empresa OK`; si falla, sube sus logs como artefacto
  `smoke-company-logs` (7 días).
- **Corridas manuales:** el job `publish` ahora solo corre con un tag empujado, y los zips se suben como artefacto solo
  con un tag o con la entrada nueva `keep_builds` (falsa por defecto). `gh workflow run release.yml --ref <rama>` ya no
  publica ni deja nada para bajar.
- **`tools/export/smoke-company.sh`:** acepta `SMOKE_GUARD_SECONDS` (150 por defecto; CI usa 300) y `SMOKE_LOGS`
  (carpeta donde quedan los logs), mata un arranque que no responde al guardia, arranca con `--autostart-company`
  (antes `--mode=company`, alias del mismo) y corre la sonda desde una carpeta vacía. La rutina `pc-build` lo usa igual
  que antes.
- **Ojo:** un tag nuevo ahora tarda un par de minutos más y no llega a borrador si el modo Empresa no levanta en la
  build.
