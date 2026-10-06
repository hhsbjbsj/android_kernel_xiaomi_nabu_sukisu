#!/system/bin/sh

MODDIR=${0%/*}
export BK_CONTROL_DIR=$MODDIR

setup_miui_keyboard()
{
	BK_FEATURE_SOURCE=/product/etc/device_features/nabu.xml
	BK_FEATURE_DIR=/data/adb/bk-kernel/device_features
	BK_FEATURE_FILE=$BK_FEATURE_DIR/nabu.xml
	BK_FEATURE_TMP=$BK_FEATURE_FILE.tmp

	[ -f "$BK_FEATURE_SOURCE" ] || return 0
	grep -q '<bool name="support_usb_keyboard">true</bool>' \
		"$BK_FEATURE_SOURCE" 2>/dev/null && return 0
	mkdir -p "$BK_FEATURE_DIR" || return 0
	cp -f "$BK_FEATURE_SOURCE" "$BK_FEATURE_TMP" || return 0
	if grep -q 'name="support_usb_keyboard"' "$BK_FEATURE_TMP"; then
		sed -i 's#<bool name="support_usb_keyboard">false</bool>#<bool name="support_usb_keyboard">true</bool>#' \
			"$BK_FEATURE_TMP"
	else
		sed -i '/<bool name="support_iic_keyboard">/i\    <bool name="support_usb_keyboard">true</bool>' \
			"$BK_FEATURE_TMP"
	fi
	mv -f "$BK_FEATURE_TMP" "$BK_FEATURE_FILE" || return 0
	chown 0:0 "$BK_FEATURE_FILE"
	chmod 0644 "$BK_FEATURE_FILE"
	chcon u:object_r:system_file:s0 "$BK_FEATURE_FILE" 2>/dev/null || true
	mount --bind "$BK_FEATURE_FILE" "$BK_FEATURE_SOURCE"
}

setup_ufs_io()
{
	BK_UFS_SCHEDULER=/sys/block/sda/queue/scheduler
	if [ -w "$BK_UFS_SCHEDULER" ] && grep -qw noop "$BK_UFS_SCHEDULER" 2>/dev/null; then
		printf '%s\n' noop > "$BK_UFS_SCHEDULER" 2>/dev/null || true
	fi
	for BK_UFS_LUN in /sys/block/sd[a-f]/queue; do
		[ -d "$BK_UFS_LUN" ] || continue
		if [ -w "$BK_UFS_LUN/scheduler" ] && grep -qw noop "$BK_UFS_LUN/scheduler" 2>/dev/null; then
			printf '%s\n' noop > "$BK_UFS_LUN/scheduler" 2>/dev/null || true
		fi
		printf '%s\n' 512 > "$BK_UFS_LUN/read_ahead_kb" 2>/dev/null || true
		printf '%s\n' 256 > "$BK_UFS_LUN/nr_requests" 2>/dev/null || true
		printf '%s\n' 0 > "$BK_UFS_LUN/iostats" 2>/dev/null || true
		printf '%s\n' 0 > "$BK_UFS_LUN/nomerges" 2>/dev/null || true
		printf '%s\n' 2 > "$BK_UFS_LUN/rq_affinity" 2>/dev/null || true
	done
	for BK_DM_QUEUE in /sys/block/dm-*/queue; do
		[ -d "$BK_DM_QUEUE" ] || continue
		printf '%s\n' 512 > "$BK_DM_QUEUE/read_ahead_kb" 2>/dev/null || true
		printf '%s\n' 0 > "$BK_DM_QUEUE/iostats" 2>/dev/null || true
		printf '%s\n' 2 > "$BK_DM_QUEUE/rq_affinity" 2>/dev/null || true
	done
}

setup_extphone_stub()
{
	BK_EXTPHONE_JAR=$MODDIR/telephony/extphonelib.jar
	BK_EXTPHONE_EMPTY=$MODDIR/telephony/empty
	[ -f "$BK_EXTPHONE_JAR" ] || return 0
	[ -f "$BK_EXTPHONE_EMPTY" ] || return 0
	mount -o bind "$BK_EXTPHONE_JAR" /system_ext/framework/extphonelib.jar
	for BK_EXTPHONE_ODEX in \
		/system_ext/framework/oat/arm64/extphonelib.odex \
		/system_ext/framework/oat/arm64/extphonelib.vdex \
		/system_ext/framework/oat/arm/extphonelib.odex \
		/system_ext/framework/oat/arm/extphonelib.vdex
	do
		[ -e "$BK_EXTPHONE_ODEX" ] || continue
		mount -o bind "$BK_EXTPHONE_EMPTY" "$BK_EXTPHONE_ODEX"
	done
}

setup_cpu_boost()
{
	BK_CPU_BOOST=/sys/module/cpu_boost/parameters
	[ -d "$BK_CPU_BOOST" ] || return 0
	printf '%s\n' "0:1113600 4:1286400 7:1286400" > "$BK_CPU_BOOST/input_boost_freq" 2>/dev/null || true
	printf '%s\n' 75 > "$BK_CPU_BOOST/input_boost_ms" 2>/dev/null || true
	printf '%s\n' 1 > "$BK_CPU_BOOST/sched_boost_on_input" 2>/dev/null || true
}

setup_pen_support()
{
	BK_PEN_DIR=/data/adb/modules/touchfeature_aidl
	mkdir -p "$BK_PEN_DIR" 2>/dev/null || true
	if [ -f "$MODDIR/pen.conf" ]; then
		if [ ! -f "$BK_PEN_DIR/pen.conf" ] || ! grep -q 'candidates=' "$BK_PEN_DIR/pen.conf" 2>/dev/null; then
			cp -f "$MODDIR/pen.conf" "$BK_PEN_DIR/pen.conf" 2>/dev/null || true
			chmod 0644 "$BK_PEN_DIR/pen.conf" 2>/dev/null || true
		fi
	fi
	chmod 0755 "$MODDIR/bin/touchfeature_aidl" "$MODDIR/bin/penabs" \
		"$MODDIR/supervise.sh" "$MODDIR/boot-completed.sh" 2>/dev/null || true
	if [ -x "$MODDIR/bin/penabs" ]; then
		"$MODDIR/bin/penabs" >/dev/null 2>&1 || true
	fi
}

rm -f /data/adb/post-fs-data.d/bk-zram-writeback.sh
setup_miui_keyboard
setup_ufs_io
setup_cpu_boost
setup_pen_support
setup_extphone_stub
"$MODDIR/scripts/bk-zram-writeback.sh"

