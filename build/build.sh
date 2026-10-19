#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_DIR/src"
BUILD_DIR="$SCRIPT_DIR"
OUTPUT_BIN="$BUILD_DIR/ram.sh"

echo "================[ 运存防线 构建脚本 ]================"

if ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
    echo "未检测到 C++ 编译器 (g++ 或 clang++)。"
    echo "正在尝试通过 apt 安装 g++..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y g++
    else
        echo "错误：无法自动安装编译器，请手动安装 g++ 或使用 Android NDK 编译。"
        exit 1
    fi
fi

COMPILER="g++"
if command -v clang++ >/dev/null 2>&1; then
    COMPILER="clang++"
fi

echo "使用编译器：$COMPILER"
echo "正在编译源码..."

$COMPILER -O2 -std=c++17 -Wall -pthread \
    "$SRC_DIR"/main.cpp \
    "$SRC_DIR"/config.cpp \
    "$SRC_DIR"/logger.cpp \
    "$SRC_DIR"/memory.cpp \
    "$SRC_DIR"/process_manager.cpp \
    "$SRC_DIR"/notification.cpp \
    "$SRC_DIR"/cleaner.cpp \
    "$SRC_DIR"/event_listener.cpp \
    -pthread -static \
    -o "$OUTPUT_BIN"

strip "$OUTPUT_BIN" 2>/dev/null || true
chmod 0755 "$OUTPUT_BIN"

echo "构建完成！输出文件：$OUTPUT_BIN"
ls -lh "$OUTPUT_BIN"

if [ "${1:-}" = "deploy" ] || [ "${1:-}" = "--deploy" ]; then
    TARGET_DIR="/proc/1/root/data/adb/modules/ram"
    if [ -d "$TARGET_DIR" ]; then
        echo "正在部署到宿主模块目录: /data/adb/modules/ram/ram.sh ..."
        cp "$TARGET_DIR/ram.sh" "$TARGET_DIR/ram.sh.bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        cp "$OUTPUT_BIN" "$TARGET_DIR/ram.sh"
        chmod 0755 "$TARGET_DIR/ram.sh"
        echo "部署成功！请通过'运存防线启动.sh'重启模块生效。"
    else
        echo "警告：未找到宿主模块目录 $TARGET_DIR，跳过自动部署。"
    fi
fi
