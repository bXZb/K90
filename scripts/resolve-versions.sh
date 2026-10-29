#!/usr/bin/env bash
# 解析最终构建的 KernelSU ref 与 susfs commit。被 workflow 预览步骤与 02 共用（单点逻辑）。
#
# 用法：bash scripts/resolve-versions.sh --env-file <输出文件>
#   把 KSU_REF_FINAL / SUSFS_REF_FINAL / KSU_RESOLVE_MODE 写入 <输出文件>（export 行），
#   人类可读说明打到 stdout。调用方 source 该文件即得三个变量。
#
# 环境输入（全可空）：
#   KSU_TAG / KSU_COMMIT —— 手动指定 tiann/KernelSU 的 tag 或 commit
#   SUSFS_COMMIT         —— 手动 pin ShirkNeko/susfs4ksu 的 commit
#
# 解析规则：
#   1. KSU_COMMIT 显式指定 → 直接用（susfs 未显式指定时告警并跟随 HEAD，配对未验证）
#   2. KSU_TAG 显式指定   → 直接用；命中下方已验证配对表时自动补全 susfs commit
#   3. 均为空             → 联动解析：susfs 跟 HEAD，KSU checkout 到 susfs 最新
#                           "Sync with the official KernelSU main repo" 提交消息
#                           里声明的 tiann commit（10_ 与驱动按构造对齐）
set -euo pipefail

ENV_FILE=""
if [ "${1:-}" = "--env-file" ]; then
  ENV_FILE="${2:?--env-file needs a path}"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android15-6.6}"
SUSFS_REPO="${SUSFS_REPO:-https://github.com/ShirkNeko/susfs4ksu.git}"
KSU_REPO="${KSU_REPO:-https://github.com/tiann/KernelSU.git}"

KSU_TAG="${KSU_TAG:-}"
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_COMMIT="${SUSFS_COMMIT:-}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# 已验证的 ksu↔susfs 配对（CI 全绿 + System.map/K 真机背书）。ksu_tag 命中且
# susfs 未显式指定时自动补全，避免"钉驱动忘配 susfs"的隐性错误。
paired_susfs() {
  case "${1}" in
    v3.3.1) printf '%s' "bd7d199ac87808001127e8a6d076832e2938cf0d" ;;  # run #44/#47/#64
    *) return 1 ;;
  esac
}

mode=""
ksu_ref=""
susfs_ref="HEAD"
susfs_note=""

if [ -n "${KSU_COMMIT}" ]; then
  mode="manual-commit"
  ksu_ref="${KSU_COMMIT}"
elif [ -n "${KSU_TAG}" ]; then
  mode="manual-tag"
  ksu_ref="${KSU_TAG}"
  if [ -z "${SUSFS_COMMIT}" ] && paired_susfs "${KSU_TAG}" >/dev/null 2>&1; then
    SUSFS_COMMIT="$(paired_susfs "${KSU_TAG}")"
    susfs_note="（已验证配对表自动补全）"
  elif [ -z "${SUSFS_COMMIT}" ]; then
    echo "WARNING: ksu_tag=${KSU_TAG} 不在已验证配对表且未指定 susfs_commit——" \
         "susfs 将跟随 HEAD，配对未经校验。" >&2
  fi
else
  mode="linked"
  git clone --depth=30 --branch "${SUSFS_BRANCH}" "${SUSFS_REPO}" "${TMP}/susfs" >/dev/null 2>&1
  if [ -n "${SUSFS_COMMIT}" ]; then
    # 只 pin susfs 侧：KSU 仍联动到该 susfs 历史声明的 sync 点。
    git -C "${TMP}/susfs" fetch --depth=30 origin "${SUSFS_COMMIT}"
    git -C "${TMP}/susfs" checkout -q --detach FETCH_HEAD
    susfs_ref="${SUSFS_COMMIT}"
    susfs_note="（手动 pin）"
  fi
  ksu_ref="$(git -C "${TMP}/susfs" log -30 --format=%B \
    | grep -oE 'tiann/KernelSU/commit/[0-9a-f]{40}' \
    | head -n1 | cut -d/ -f4)"
  if [ -z "${ksu_ref}" ]; then
    echo "ERROR: susfs 最近 30 条提交里没有 tiann/KernelSU/commit/<sha> 同步点，" \
         "上游消息格式可能变了。用 ksu_tag / KSU_COMMIT / susfs_commit 手动指定。" >&2
    exit 1
  fi
fi

if [ -n "${KSU_COMMIT}" ] && [ -z "${SUSFS_COMMIT}" ]; then
  echo "WARNING: 指定了 KSU_COMMIT 但未指定 susfs_commit——两者配对未经校验，" \
       "susfs 将跟随 HEAD。如构建在 10_/50_ 补丁或链接期失败，大概率是配对不匹配。" >&2
fi

if [ -n "${ENV_FILE}" ]; then
  {
    echo "KSU_REF_FINAL=${ksu_ref}"
    echo "SUSFS_REF_FINAL=${susfs_ref}"
    echo "SUSFS_COMMIT_FINAL=${SUSFS_COMMIT}"
    echo "KSU_RESOLVE_MODE=${mode}"
  } > "${ENV_FILE}"
fi

echo "[resolve] mode=${mode}"
echo "[resolve] KSU  ref : ${ksu_ref} $([ "${mode}" = "linked" ] && echo '(susfs sync point)')"
echo "[resolve] susfs    : ${SUSFS_COMMIT:-HEAD} ${susfs_note}"
