#!/usr/bin/env python3
"""Checks for tools/pc/rutina-pc.ps1 (N-973): python3 tools/pc/test_rutina_pc.py

Static checks (they run anywhere): one issue per routine, closing filtered by routine, quota pattern,
body through a UTF-8 file, skips logged, BOM kept. Then, if `pwsh` is installed (GitHub's ubuntu runners
have it), the behaviour test tools/pc/test-rutina-pc.ps1 with a fake `gh`. Only the standard library.
"""
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "rutina-pc.ps1"
raw = SCRIPT.read_bytes()
text = raw.decode("utf-8-sig")
failures = 0


def check(cond, msg):
    global failures
    if not cond:
        print("FAIL:", msg)
        failures += 1


check(raw.startswith(b"\xef\xbb\xbf"), "rutina-pc.ps1 keeps its UTF-8 BOM (Windows PowerShell 5.1 needs it for accents)")
check('--title "Rutina de PC caída: $Rutina"' in text, "the issue title carries the routine")
check("'^Rutina de PC .*: {0}$' -f $Rutina" in text, "the issue is looked up by title and routine")
check("--title 'Rutina de PC caída'" not in text, "no single shared title left")
check("--jq '.[0].number'" not in text, "no 'first open issue' lookup (it closed the other routine's issue)")
check("usage limit" in text and "rate.?limit" in text and "quota" in text, "quota pattern exists")
check("Cupo del plan agotado (regla 13)" in text, "quota is reported as such")
check("Select-Object -Last 10" in text, "the last 10 log lines go to the issue")
check("Substring(0, 300)" in text, "lines are cut to 300 characters")
check("$OutputEncoding = $utf8" in text and "[Console]::OutputEncoding = $utf8" in text, "console and pipe encoding are UTF-8")
check("UTF8Encoding $false" in text and "WriteAllText($tmp, $text, $utf8)" in text, "bodies are written as UTF-8 without BOM")
check("--body-file -" not in text, "no body through the pipe (ASCII in 5.1)")
check("--body-file $tmp" in text, "gh reads the body from the file")
check("saltos.log" in text, "skips go to saltos.log")
check(text.count("Add-Skip '") == 4, "the four skips (lock, PAUSA, PRESUPUESTO x2) use Add-Skip")
check("Write-Log 'another PC routine" not in text and "Write-Log 'PAUSA" not in text, "no skip left that only writes the run log")

pwsh = shutil.which("pwsh")
if pwsh:
    r = subprocess.run([pwsh, "-NoProfile", "-File", str(HERE / "test-rutina-pc.ps1")], text=True, capture_output=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    check(r.returncode == 0, "tools/pc/test-rutina-pc.ps1 (fake gh) passes")
else:
    print("pwsh not installed: behaviour test tools/pc/test-rutina-pc.ps1 skipped")

if failures:
    print(f"{failures} check(s) failed")
    sys.exit(1)
print("rutina-pc static checks: OK")
