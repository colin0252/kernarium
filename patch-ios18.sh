#!/bin/sh
# ============================================================================
# 把 Kernarium/Andarium 全仓的部署目标从 27.0 降到 18.0
# 用法：把本文件放到仓库根目录，执行   sh patch-ios18.sh
# 依赖：macOS 自带 BSD sed/awk
# 说明：本脚本只改「部署目标」这一件事，不碰 GPU 后端（MoltenVK 见
#       MOLTENVK_SWAP.md）。先跑通它，再动手换 GPU。
# ============================================================================
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"
echo "仓库根: $ROOT"

echo "== [1] 依赖构建脚本里硬编码的 DEPLOYMENT_TARGET =="
for f in dependencies/*.sh; do
  [ -f "$f" ] || continue
  if grep -q 'DEPLOYMENT_TARGET=27.0' "$f"; then
    sed -i '' 's/DEPLOYMENT_TARGET=27\.0/DEPLOYMENT_TARGET=18.0/g' "$f"
    echo "  patched $f"
  fi
done

echo "== [2] platform 契约 tsv 的 deployment_target(制表符分隔) =="
for f in dependencies/platforms/*.tsv; do
  [ -f "$f" ] || continue
  if awk -F'\t' '$1=="deployment_target"{exit 0} END{exit 1}' "$f"; then
    awk -F'\t' 'BEGIN{OFS="\t"} $1=="deployment_target"{$2="18.0"} {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "  patched $f"
  fi
done

echo "== [3] Xcode 工程 IPHONEOS_DEPLOYMENT_TARGET =="
find . -name project.pbxproj -path '*xcodeproj*' | while read -r p; do
  sed -i '' -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 18.0;/g' "$p"
  n=$(grep -c 'IPHONEOS_DEPLOYMENT_TARGET = 18.0;' "$p" || true)
  echo "  patched $p  (18.0 处数=$n)"
done

echo "== [4] 检查残留 27.0（尤其 CMake 工具链/校验脚本）=="
grep -rn '27\.0' --include='*.sh' --include='*.tsv' --include='*.cmake' --include='*.txt' \
     dependencies cmake CMakePresets.json CMakeLists.txt 2>/dev/null | head -40 || true

echo
echo "== 完成。请重点人工复查上面 [4] 列出的每一处 27.0 =="
echo "   特别注意 dependencies/cmake/VerifyAppleGpuPrefix.cmake（前缀校验会核对部署目标）"
