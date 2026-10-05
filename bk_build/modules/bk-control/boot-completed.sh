#!/system/bin/sh
# boot-completed 阶段兜底：
# 换内核后 ksud 的 services/boot-completed 阶段可能不触发，但只要任何一个阶段
# 跑到，这里就会把常驻守护拉起来，保证 AIDL 触控 HAL 在跑。

PATH=/system/bin:/system/xbin:/vendor/bin:$PATH
export PATH

MODDIR=${0%/*}
LOG=/data/local/tmp/pen_boot.log

echo "$(date) : boot-completed.sh start" >> "$LOG"

chmod 0755 "$MODDIR"/bin/touchfeature_aidl "$MODDIR"/bin/penabs \
           "$MODDIR"/supervise.sh 2>/dev/null

if pgrep -f "$MODDIR/supervise.sh" >/dev/null 2>&1; then
    echo "$(date) : supervisor already running" >> "$LOG"
else
    "$MODDIR/supervise.sh" >/dev/null 2>&1 &
    echo "$(date) : supervisor launched" >> "$LOG"
fi
