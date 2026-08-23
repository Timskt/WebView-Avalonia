from __future__ import annotations

import pathlib
import re
import sys


def patch(path: pathlib.Path) -> None:
    source = path.read_text(encoding="utf-8")
    newline = "\r\n" if "\r\n" in source else "\n"

    if "import ntpath" not in source:
        source = source.replace(
            "import os" + newline,
            "import os" + newline + "import ntpath" + newline,
            1,
        )
    if "import re" not in source:
        source = source.replace(
            "import ntpath" + newline,
            "import ntpath" + newline + "import re" + newline,
            1,
        )
    if "import subprocess" not in source:
        source = source.replace(
            "import re" + newline,
            "import re" + newline + "import subprocess" + newline,
            1,
        )

    helper = r'''

def _resolve_subst_path(path):
  """Resolve a Windows subst drive to its physical directory."""
  if os.name != 'nt':
    return path
  drive, tail = ntpath.splitdrive(path.replace('/', '\\'))
  if not drive:
    return path
  try:
    output = subprocess.check_output(['subst'], stderr=subprocess.STDOUT)
    output = output.decode('mbcs', errors='replace')
  except Exception:
    return path
  pattern = re.compile(r'^([A-Za-z]):\\: => (.+)$')
  for line in output.splitlines():
    match = pattern.match(line.strip())
    if match and match.group(1).lower() == drive[0].lower():
      return match.group(2).rstrip('\\') + tail
  return path
'''
    if "def _resolve_subst_path(path):" not in source:
        source = source.replace(
            newline + "def get_files_for_variable(",
            helper.replace("\n", newline) + newline + "def get_files_for_variable(",
            1,
        )

    loop_pattern = re.compile(
        r"(?m)^(?P<indent>[ \t]+)for path in paths:\r?\n"
        r"[ \t]+abspath = os\.path\.join\(cef_dir, path\)\r?\n"
        r"(?:[ \t]+resolved_abspath = _resolve_subst_path\(abspath\)\r?\n)?"
        r"(?:[ \t]+relative_base = _resolve_subst_path\(cmake_dirname\)\r?\n)?"
        r"[ \t]+newpath = normalize_path\(os\.path\.relpath\("
        r"(?:abspath|resolved_abspath), (?:cmake_dirname|relative_base)\)\)\r?\n"
        r"[ \t]+new_paths\.append\(newpath\)$"
    )
    match = loop_pattern.search(source)
    if not match:
        raise RuntimeError("Unable to patch CEF make_cmake.py relative path handling")

    indent = match.group("indent")
    child_indent = indent + "  "
    replacement = newline.join((
        indent + "for path in paths:",
        child_indent + "abspath = os.path.join(cef_dir, path)",
        child_indent + "resolved_abspath = _resolve_subst_path(abspath)",
        child_indent + "relative_base = _resolve_subst_path(cmake_dirname)",
        child_indent + "newpath = normalize_path(os.path.relpath(resolved_abspath, relative_base))",
        child_indent + "new_paths.append(newpath)",
    ))
    path.write_text(
        source[:match.start()] + replacement + source[match.end():],
        encoding="utf-8",
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-cef-cmake-paths.py MAKE_CMAKE_PY")
    patch(pathlib.Path(sys.argv[1]))
