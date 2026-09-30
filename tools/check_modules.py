#!/usr/bin/env python3
"""Static rules for the portable modules in do-not-drop/modules/ (docs/modulos.md).

A module is a folder that can be copied into another Godot project and work.
So nothing inside it may name the game: no res://scripts, scenes, data or
assets paths, no autoload, no class_name declared outside the modules, no
/root/ node paths, and no other module unless module.cfg lists it in
`depends`. Its tests (modules/<name>/tests/) follow the same rules, which is
what lets tools/portability-check.sh run them in an empty project.

    tools/check_modules.py            # check (CI, pre-push)
    tools/check_modules.py --list     # print the modules and their dependencies

Exit 1 with one line per problem.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "do-not-drop"
MODULES = PROJECT / "modules"

GAME_PATH = re.compile(r'res://(scripts|scenes|data|assets|tests|shaders|translations)/')
ROOT_PATH = re.compile(r'["^&]/root/')
COMMENT = re.compile(r'#.*')
STRING = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
CLASS_NAME = re.compile(r'^class_name\s+(\w+)', re.M)


def read_cfg(path):
    """The [module] section of a module.cfg: name, summary, depends."""
    cfg = {"name": "", "summary": "", "depends": []}
    for line in path.read_text(encoding="utf8").splitlines():
        line = line.strip()
        if "=" not in line or line.startswith(";") or line.startswith("["):
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if key == "depends":
            cfg["depends"] = re.findall(r'"([^"]+)"', value)
        elif key in cfg:
            cfg["name"] = cfg["name"] if key != "name" else value.strip('"')
            if key == "summary":
                cfg["summary"] = value.strip('"')
    return cfg


def load_modules():
    modules = {}
    for folder in sorted(MODULES.iterdir()):
        if not folder.is_dir():
            continue
        cfg_path = folder / "module.cfg"
        cfg = read_cfg(cfg_path) if cfg_path.exists() else None
        modules[folder.name] = {"path": folder, "cfg": cfg}
    return modules


def autoload_names():
    names = []
    in_section = False
    for line in (PROJECT / "project.godot").read_text(encoding="utf8").splitlines():
        if line.startswith("["):
            in_section = line.strip() == "[autoload]"
            continue
        if in_section and "=" in line:
            names.append(line.split("=", 1)[0].strip())
    return names


def game_class_names():
    names = {}
    for path in (PROJECT / "scripts").rglob("*.gd"):
        match = CLASS_NAME.search(path.read_text(encoding="utf8", errors="replace"))
        if match:
            names[match.group(1)] = path.relative_to(ROOT).as_posix()
    return names


def module_class_names(modules):
    owner = {}
    for name, module in modules.items():
        for path in module["path"].rglob("*.gd"):
            match = CLASS_NAME.search(path.read_text(encoding="utf8", errors="replace"))
            if match:
                owner[match.group(1)] = name
    return owner


def strip_comments(text):
    out = []
    for line in text.splitlines():
        # Strings first, so a "#" inside one survives; then the comment.
        placeholders = []

        def keep(match):
            placeholders.append(match.group(0))
            return "\x00%d\x00" % (len(placeholders) - 1)

        line = STRING.sub(keep, line)
        line = COMMENT.sub("", line)
        for index, text_ in enumerate(placeholders):
            line = line.replace("\x00%d\x00" % index, text_)
        out.append(line)
    return "\n".join(out)


def check(modules):
    problems = []
    autoloads = autoload_names()
    game_classes = game_class_names()
    owners = module_class_names(modules)
    for name, module in modules.items():
        cfg = module["cfg"]
        rel = module["path"].relative_to(ROOT).as_posix()
        if cfg is None:
            problems.append(f"{rel}: no module.cfg (name, summary, depends)")
            continue
        if cfg["name"] != name:
            problems.append(f"{rel}/module.cfg: name is \"{cfg['name']}\", the folder is \"{name}\"")
        if not cfg["summary"]:
            problems.append(f"{rel}/module.cfg: no summary")
        for dep in cfg["depends"]:
            if dep not in modules:
                problems.append(f"{rel}/module.cfg: depends on \"{dep}\", which is not a module")
            if dep == name:
                problems.append(f"{rel}/module.cfg: depends on itself")
        if not list((module["path"] / "tests").glob("test_*.gd")):
            problems.append(f"{rel}: no tests/test_*.gd (the portability check needs at least one)")
        allowed = set(cfg["depends"]) | {name}
        for path in sorted(module["path"].rglob("*")):
            if path.suffix not in (".gd", ".tscn", ".tres", ".gdshader", ".cfg"):
                continue
            file_rel = path.relative_to(ROOT).as_posix()
            text = path.read_text(encoding="utf8", errors="replace")
            code = strip_comments(text) if path.suffix == ".gd" else text
            for line_no, line in enumerate(code.splitlines(), 1):
                if GAME_PATH.search(line):
                    problems.append(f"{file_rel}:{line_no}: names a game path ({GAME_PATH.search(line).group(0)})")
                if ROOT_PATH.search(line):
                    problems.append(f"{file_rel}:{line_no}: looks an autoload up by /root/ path")
                for other in re.findall(r'res://modules/([A-Za-z0-9_]+)/', line):
                    if other not in allowed:
                        problems.append(f"{file_rel}:{line_no}: uses module \"{other}\" without listing it in depends")
                if path.suffix != ".gd":
                    continue
                for word in set(re.findall(r'\b[A-Z][A-Za-z0-9]*\b', line)):
                    if word in autoloads:
                        problems.append(f"{file_rel}:{line_no}: names the autoload {word}")
                    elif word in game_classes:
                        problems.append(f"{file_rel}:{line_no}: names the game class {word} ({game_classes[word]})")
                    elif word in owners and owners[word] not in allowed:
                        problems.append(f"{file_rel}:{line_no}: uses {word} from module \"{owners[word]}\" without listing it in depends")
    return problems


def main():
    modules = load_modules()
    if "--list" in sys.argv:
        for name, module in modules.items():
            cfg = module["cfg"] or {"summary": "(no module.cfg)", "depends": []}
            deps = ", ".join(cfg["depends"]) or "-"
            print(f"{name}: {cfg['summary']}  [depends: {deps}]")
        return 0
    problems = check(modules)
    if problems:
        print("check-modules: %d problem(s):" % len(problems))
        for problem in problems:
            print("  " + problem)
        return 1
    print("check-modules: OK (%d modules)" % len(modules))
    return 0


if __name__ == "__main__":
    sys.exit(main())
