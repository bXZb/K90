#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="${ROOT}/gki/common"
STAMP="${ROOT}/gki/build/kernel/kleaf/impl/stamp.bzl"
DEFCONFIG="${COMMON}/arch/arm64/configs/gki_defconfig"

sed -i 's/^CONFIG_RFKILL=.*/CONFIG_RFKILL=y/' "${DEFCONFIG}"
sed -i '/net\/rfkill\/rfkill\.ko/d' "${COMMON}/modules.bzl"
sed -i 's/^POST_DEFCONFIG_CMDS=.*/POST_DEFCONFIG_CMDS=""/' "${COMMON}/build.config.gki"
# 工作区打过补丁后 kleaf 算不出 scmversion。用当前 HEAD 短哈希（与官方 uname 的 -g 段同宽）。
SCMVERSION_SUFFIX="${SCMVERSION_SUFFIX:-g$(git -C "${COMMON}" rev-parse --short=12 HEAD)}"
SCMVERSION_SUFFIX="${SCMVERSION_SUFFIX#-}"
sed -i "s/echo '-maybe-dirty'/echo '-${SCMVERSION_SUFFIX}'/" "${STAMP}"

python3 - "${DEFCONFIG}" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
wanted = [
    "CONFIG_IP_NF_TARGET_TTL=y",
    "CONFIG_IP6_NF_TARGET_HL=y",
    "CONFIG_IP6_NF_MATCH_HL=y",
    "CONFIG_NETFILTER_XT_TARGET_HL=y",
    "CONFIG_NETFILTER_XT_MATCH_HL=y",
]
# 曾尝试写入的 KSU_SUSFS_AUTO_ADD_* 三个键在 builtin 与 10_ 的 Kconfig 里
# 都不存在（写了被静默忽略），已删除；勿再加回。
keys = {}
for i, line in enumerate(lines):
    if not line or line.startswith("#") or "=" not in line:
        continue
    keys[line.split("=", 1)[0]] = i
changed = False
for item in wanted:
    key = item.split("=", 1)[0]
    if key in keys:
        if lines[keys[key]] != item:
            lines[keys[key]] = item
            changed = True
    else:
        lines.append(item)
        changed = True
if changed:
    p.write_text("\n".join(lines) + "\n")
PY

python3 - "${COMMON}/BUILD.bazel" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
start = text.find('"kernel_aarch64":')
end = text.find('"kernel_aarch64_16k":')
if start < 0 or end < 0 or end <= start:
    raise SystemExit("could not find kernel_aarch64 block in BUILD.bazel")
block = text[start:end]
old = block
lines = []
for line in block.splitlines(keepends=True):
    if "protected_exports_list" in line and "abi_gki_protected_exports_aarch64" in line:
        continue
    lines.append(line)
block = "".join(lines)
if block != old:
    p.write_text(text[:start] + block + text[end:])
PY

python3 "${ROOT}/scripts/lib/apply_hide_stuff.py" "${COMMON}"
