#!/system/bin/sh
# 常驻守护：确保 AIDL 触控 HAL 一直在跑。
# 只要进程不在就重新拉起，避免「内核/ksud 阶段没触发」「进程被杀」
# 「模块文件被还原丢了执行权限」之类情况导致笔静默失效。

PATH=/system/bin:/system/xbin:/vendor/bin:$PATH
export PATH

MODDIR=${0%/*}
if [ -x "$MODDIR/bin/touchfeature_aidl" ]; then
    BIN="$MODDIR/bin/touchfeature_aidl"
elif [ -x "$MODDIR/touchfeature_aidl" ]; then
    BIN="$MODDIR/touchfeature_aidl"
else
    BIN="/data/adb/bk-kernel/bin/touchfeature_aidl"
fi
LOG=/data/local/tmp/pen_hal.log

echo "$(date) : supervisor start" >> "$LOG"

# 准备配置文件目录
mkdir -p /data/adb/modules/touchfeature_aidl 2>/dev/null || true
if [ -f "$MODDIR/pen.conf" ] && [ ! -f /data/adb/modules/touchfeature_aidl/pen.conf ]; then
    cp -f "$MODDIR/pen.conf" /data/adb/modules/touchfeature_aidl/pen.conf 2>/dev/null || true
fi

while :; do
    if ! pidof touchfeature_aidl >/dev/null 2>&1 && ! pgrep -f "touchfeature_aidl" >/dev/null 2>&1; then
        echo "$(date) : HAL not running, starting" >> "$LOG"
        chmod 0755 "$BIN" 2>/dev/null
        "$BIN" >>"$LOG" 2>&1 &
    fi
    sleep 15
done
