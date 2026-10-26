#!/usr/bin/env python3
"""把 module/ 打包成可直接刷入的 Magisk 模块 zip。

    python3 scripts/build_module.py

产物：dist/groupguard-magisk-v<version>.zip
zip 根目录必须直接是 module.prop，不能带 module/ 这一层，否则 Magisk 认不出来。
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE_DIR = os.path.join(ROOT, "module")
DIST_DIR = os.path.join(ROOT, "dist")

# 模块运行时文件需保留可执行位，zip 里用 external_attr 表达
EXEC_SUFFIXES = (".sh",)


def read_version():
    with open(os.path.join(MODULE_DIR, "module.prop"), encoding="utf-8") as f:
        prop = f.read()
    ver = re.search(r"^version=(.+)$", prop, re.M)
    code = re.search(r"^versionCode=(\d+)$", prop, re.M)
    if not ver or not code:
        raise SystemExit("module.prop 缺少 version 或 versionCode")
    return ver.group(1).strip(), int(code.group(1))


def main():
    if not os.path.isdir(MODULE_DIR):
        raise SystemExit("找不到 module/ 目录")
    if not os.path.isfile(os.path.join(MODULE_DIR, "module.prop")):
        raise SystemExit("module/ 下缺少 module.prop")

    version, code = read_version()
    os.makedirs(DIST_DIR, exist_ok=True)
    out = os.path.join(DIST_DIR, "groupguard-magisk-v%s.zip" % version)

    files = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for base, _dirs, names in os.walk(MODULE_DIR):
            for name in sorted(names):
                if name.startswith(".") or name.endswith(".swp"):
                    continue
                src = os.path.join(base, name)
                rel = os.path.relpath(src, MODULE_DIR).replace(os.sep, "/")
                info = zipfile.ZipInfo(rel)
                info.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if rel.endswith(EXEC_SUFFIXES) else 0o644
                info.external_attr = (0o100000 | mode) << 16
                with open(src, "rb") as f:
                    zf.writestr(info, f.read())
                files += 1

    size = os.path.getsize(out)
    print("版本    : %s (versionCode=%d)" % (version, code))
    print("文件数  : %d" % files)
    print("产物    : %s" % out)
    print("大小    : %.1f KB" % (size / 1024))
    print()
    print("提示：发布 release 时把这个 zip 作为附件上传，")
    print("      并把 update.json 里的 version/versionCode/zipUrl 一起改掉。")


if __name__ == "__main__":
    sys.exit(main())
