#!/system/bin/sh

for file in bkctl service.sh post-fs-data.sh action.sh uninstall.sh \
  scripts/bk-reburnout.sh scripts/bk-zram-writeback.sh \
  scripts/bk-wake-guard.sh bin/bk-zram-setup bin/bk-keyboard-monitor \
  bin/touchfeature_aidl; do
  [ -f "$MODPATH/$file" ] || {
    echo "Missing bkk-control file: $file" >&2
    exit 1
  }
  chmod 0755 "$MODPATH/$file" || exit 1
done

if [ -d /data/adb/service.d ]; then
  mkdir -p /data/adb/bk-kernel/bin
  cp -f "$MODPATH/bin/touchfeature_aidl" /data/adb/bk-kernel/bin/touchfeature_aidl
  chmod 0755 /data/adb/bk-kernel/bin/touchfeature_aidl
  cat << 'EOF' > /data/adb/service.d/bk-touchfeature.sh
#!/system/bin/sh
PATH=/system/bin:/system/xbin:/vendor/bin:$PATH
export PATH
DAEMON=/data/adb/bk-kernel/bin/touchfeature_aidl
[ -x "$DAEMON" ] || exit 0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
  sleep 1
done
while true; do
  if ! pidof touchfeature_aidl >/dev/null 2>&1; then
    log -t TouchFeatureAIDL "Starting touchfeature_aidl from service.d"
    "$DAEMON" </dev/null >/dev/null 2>&1 &
  fi
  sleep 5
done
EOF
  chmod 0755 /data/adb/service.d/bk-touchfeature.sh
fi
