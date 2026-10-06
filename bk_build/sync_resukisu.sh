#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$KERNEL_DIR"

echo "=========================================================="
echo "== Syncing BakaSU (formerly ReSukiSU) upstream at build =="
echo "=========================================================="

BAKASU_REPO="https://github.com/Baka-SU/BakaSU.git"
RESUKISU_REPO="${BAKASU_REPO}"
UPSTREAM_DIR="${KERNELSU_UPSTREAM_DIR:-/tmp/BakaSU-upstream}"

# 1. Fetch / Clone BakaSU main with full tags and commit history
if [ -d "$UPSTREAM_DIR/.git" ]; then
    echo "[+] Updating existing BakaSU clone..."
    git -C "$UPSTREAM_DIR" fetch --depth=2000 --tags origin main
    git -C "$UPSTREAM_DIR" checkout -f origin/main
else
    echo "[+] Cloning latest BakaSU main branch with tags..."
    rm -rf "$UPSTREAM_DIR"
    git clone --depth=2000 --tags -b main "$BAKASU_REPO" "$UPSTREAM_DIR"
fi

# 2. Extract authentic BakaSU metadata from upstream git
KSU_COMMIT=$(git -C "$UPSTREAM_DIR" rev-parse --short=8 HEAD)
KSU_COMMIT_FULL=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)
KSU_TAG=$(git -C "$UPSTREAM_DIR" describe --abbrev=0 --tags 2>/dev/null || echo "v4.2.0-rc3")
KSU_COUNT=$(git -C "$UPSTREAM_DIR" rev-list --count HEAD 2>/dev/null || echo 1551)
KSU_VERCODE=$((30000 + KSU_COUNT + 700))
KSU_VERNAME="${KSU_TAG}-${KSU_COMMIT}@BakaSU"

echo "[+] Resolved Upstream BakaSU Metadata:"
echo "    Tag:         $KSU_TAG"
echo "    Commit:      $KSU_COMMIT ($KSU_COMMIT_FULL)"
echo "    CommitCount: $KSU_COUNT"
echo "    VersionCode: $KSU_VERCODE"
echo "    VersionName: $KSU_VERNAME"

# 3. Synchronize drivers/kernelsu
DEST_DIR="$KERNEL_DIR/drivers/kernelsu"
echo "[+] Syncing upstream kernel and uapi headers to drivers/kernelsu..."
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -r "$UPSTREAM_DIR/kernel/"* "$DEST_DIR/"
rm -rf "$DEST_DIR/include/uapi"
mkdir -p "$DEST_DIR/include/uapi"
cp -r "$UPSTREAM_DIR/uapi/"* "$DEST_DIR/include/uapi/"

# 4. Patch Makefile
echo 'include $(srctree)/$(src)/Kbuild' > "$DEST_DIR/Makefile"

# 5. Patch Kbuild with exact resolved version numbers and Custom Manager signature
echo "[+] Injected upstream version numbers and Custom Manager flags into Kbuild..."
sed -i 's/LOCAL_GIT_EXISTS\s*:=.*/LOCAL_GIT_EXISTS := 1/g' "$DEST_DIR/Kbuild"
sed -i "s/KSU_LOCAL_VERSION\s*:=.*/KSU_LOCAL_VERSION := $KSU_COUNT/g" "$DEST_DIR/Kbuild"
sed -i "s/KSU_VERSION\s*:=.*/KSU_VERSION := $KSU_VERCODE/g" "$DEST_DIR/Kbuild"
sed -i "s/KSU_TAG_NAME\s*:=.*/KSU_TAG_NAME := $KSU_TAG/g" "$DEST_DIR/Kbuild"
sed -i "s/KSU_COMMIT_SHA\s*:=.*/KSU_COMMIT_SHA := $KSU_COMMIT/g" "$DEST_DIR/Kbuild"
sed -i "s/KSU_BRANCH_NAME\s*:=.*/KSU_BRANCH_NAME := main/g" "$DEST_DIR/Kbuild"
sed -i 's/REPO_NAME := .*/REPO_NAME := BakaSU/g' "$DEST_DIR/Kbuild"
echo 'ccflags-y += -DEXPECTED_SIZE=0x039a -DEXPECTED_HASH=\"366aa724f4ed84d589fb47077cee4dc6aac45c37c4a50a6e1eaed4446bb3bc03\"' >> "$DEST_DIR/Kbuild"

# 6. Enable allow_shell = true for ADB root
echo "[+] Enabling allow_shell = true in core/init.c..."
sed -i 's/bool allow_shell = false;/bool allow_shell = true;/g' "$DEST_DIR/core/init.c"

# 7. Adapt Linux 4.14 user-pointer ABI, hide su for unauthorized UIDs, and disable KPM
echo "[+] Adapting sucompat and apatch for Linux 4.14 + SUSFS..."
python3 -u - <<'PY'
from pathlib import Path

# 1. sucompat.h
h_path = Path("drivers/kernelsu/feature/sucompat.h")
if h_path.exists():
    h = h_path.read_text(encoding="utf-8")
    target_h = "#ifdef CONFIG_KSU_SUSFS\nint ksu_handle_faccessat(int *dfd, struct filename **filename, int *mode, int *__unused_flags);"
    replace_h = "#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)) && defined(CONFIG_KSU_SUSFS)\nint ksu_handle_faccessat(int *dfd, struct filename **filename, int *mode, int *__unused_flags);"
    if target_h in h:
        h = h.replace(target_h, replace_h, 1)
        h_path.write_text(h, encoding="utf-8")
        print("  - Updated sucompat.h: 4.14 user-pointer ABI guard installed")

# 2. sucompat.c
c_path = Path("drivers/kernelsu/feature/sucompat.c")
if c_path.exists():
    c = c_path.read_text(encoding="utf-8")
    fa_target = "#ifdef CONFIG_KSU_SUSFS\nint ksu_handle_faccessat(int *dfd, struct filename **filename, int *mode, int *__unused_flags)"
    fa_replace = "#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)) && defined(CONFIG_KSU_SUSFS)\nint ksu_handle_faccessat(int *dfd, struct filename **filename, int *mode, int *__unused_flags)"
    stat_target = "#ifdef CONFIG_KSU_SUSFS\nint ksu_handle_stat(int *dfd, struct filename **filename, int *flags)"
    stat_replace = "#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)) && defined(CONFIG_KSU_SUSFS)\nint ksu_handle_stat(int *dfd, struct filename **filename, int *flags)"
    if fa_target in c:
        c = c.replace(fa_target, fa_replace, 1)
    if stat_target in c:
        c = c.replace(stat_target, stat_replace, 1)

    # Restrict faccessat and stat redirects to authorized UIDs
    target_fa = 'int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *__unused_flags)'
    idx_fa = c.find(target_fa)
    if idx_fa != -1:
        check = 'if (!ksu_is_allow_uid_for_current'
        next_brace = c.find('{', idx_fa)
        if check not in c[idx_fa:idx_fa+350]:
            c = c[:next_brace+1] + '\n    if (!ksu_is_allow_uid_for_current(ksu_get_uid_t(current_uid()))) {\n        return 0;\n    }\n' + c[next_brace+1:]

    target_st = 'int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags)'
    idx_st = c.find(target_st)
    if idx_st != -1:
        check = 'if (!ksu_is_allow_uid_for_current'
        next_brace = c.find('{', idx_st)
        if check not in c[idx_st:idx_st+350]:
            c = c[:next_brace+1] + '\n    if (!ksu_is_allow_uid_for_current(ksu_get_uid_t(current_uid()))) {\n        return 0;\n    }\n' + c[next_brace+1:]

    c_path.write_text(c, encoding="utf-8")
    print("  - Updated sucompat.c: 4.14 user-pointer ABI & authorized UID filter installed")

# 3. Disable KPM conflict check to prevent kernel crash when clicking KPM in Manager
ap_path = Path("drivers/kernelsu/compat/apatch_conflict.c")
if ap_path.exists():
    ap = ap_path.read_text(encoding="utf-8")
    target_start = "ksu_start_apatch_conflict_check"
    idx = ap.find(target_start)
    if idx != -1:
        next_brace = ap.find("{", idx)
        close_brace = ap.find("}", next_brace)
        if next_brace != -1 and close_brace != -1:
            ap = ap[:next_brace+1] + '\n    pr_info("KernelPatch KPM is disabled on built-in kernel\\n");\n    kernel_patch_type = KERNEL_PATCH_NOT_FOUND;\n' + ap[close_brace:]
            ap_path.write_text(ap, encoding="utf-8")
            print("  - Updated apatch_conflict.c: KPM disabled safely")

# 4. Support additional init.rc paths in is_init_rc
ksud_path = Path("drivers/kernelsu/runtime/ksud_integration.c")
if ksud_path.exists():
    ksud = ksud_path.read_text(encoding="utf-8")
    old_cmp = 'if (!!strcmp(dpath, "/init.rc") && !!strcmp(dpath, "/system/etc/init/hw/init.rc"))'
    new_cmp = 'if (!!strcmp(dpath, "/init.rc") && !!strcmp(dpath, "/system/etc/init/hw/init.rc") && !!strcmp(dpath, "/system/etc/init/init.rc"))'
    if old_cmp in ksud:
        ksud = ksud.replace(old_cmp, new_cmp, 1)
        ksud_path.write_text(ksud, encoding="utf-8")
        print("  - Updated ksud_integration.c: added /system/etc/init/init.rc support")

# 5. Inject custom manager credentials into manager_sign.h and apk_sign.c
ms_path = Path("drivers/kernelsu/manager/manager_sign.h")
if ms_path.exists():
    ms = ms_path.read_text(encoding="utf-8")
    if "0x039a" not in ms:
        custom_def = (
            "\n// Custom Manager (User Customized)\n"
            "#ifndef EXPECTED_SIZE\n"
            "#define EXPECTED_SIZE 0x039a\n"
            "#endif\n"
            "#ifndef EXPECTED_HASH\n"
            '#define EXPECTED_HASH "366aa724f4ed84d589fb47077cee4dc6aac45c37c4a50a6e1eaed4446bb3bc03"\n'
            "#endif\n"
            "#ifndef EXPECTED_SIZE_CUSTOM_V1\n"
            "#define EXPECTED_SIZE_CUSTOM_V1 0x38b\n"
            "#endif\n"
            "#ifndef EXPECTED_HASH_CUSTOM_V1\n"
            '#define EXPECTED_HASH_CUSTOM_V1 "aaf4f7590df8e55068503e29c58f7e9d5699f0c72bd31a7561cc36c0d044af11"\n'
            "#endif\n"
        )
        guard = "#endif /* MANAGER_SIGN_H */"
        if guard in ms:
            ms = ms.replace(guard, custom_def + "\n" + guard, 1)
        else:
            ms += custom_def
        ms_path.write_text(ms, encoding="utf-8")
        print("  - Updated manager_sign.h: injected custom manager credentials (0x039a)")

as_path = Path("drivers/kernelsu/manager/apk_sign.c")
if as_path.exists():
    as_code = as_path.read_text(encoding="utf-8")
    old_block = """static apk_sign_key_t apk_sign_keys[] = {
    { EXPECTED_SIZE_BAKASU, EXPECTED_HASH_BAKASU }, /* Baka-SU/BakaSU */
#ifdef CONFIG_KSU_MULTI_MANAGER_SUPPORT"""
    new_block = """static apk_sign_key_t apk_sign_keys[] = {
    { EXPECTED_SIZE_BAKASU, EXPECTED_HASH_BAKASU }, /* Baka-SU/BakaSU */
#ifdef EXPECTED_SIZE
    { EXPECTED_SIZE, EXPECTED_HASH }, // Custom (0x039a)
#endif
#ifdef EXPECTED_SIZE_CUSTOM_V1
    { EXPECTED_SIZE_CUSTOM_V1, EXPECTED_HASH_CUSTOM_V1 }, // Custom (0x38b)
#endif
#ifdef CONFIG_KSU_MULTI_MANAGER_SUPPORT"""
    if old_block in as_code and "#ifdef EXPECTED_SIZE" not in as_code[:as_code.find(old_block) + 200]:
        as_code = as_code.replace(old_block, new_block, 1)
        as_path.write_text(as_code, encoding="utf-8")
        print("  - Updated apk_sign.c: unconditional custom manager matching enabled")
PY

# 8. Record resolved metadata
echo "$KSU_TAG" > "$DEST_DIR/.resukisu_tag"
echo "$KSU_COMMIT" > "$DEST_DIR/.resukisu_commit"
echo "$KSU_VERCODE" > "$DEST_DIR/.resukisu_version"
echo "$KSU_VERNAME" > "$DEST_DIR/.resukisu_version_full"

echo "[PASS] BakaSU (formerly ReSukiSU) successfully synchronized, adapted for Linux 4.14 + SUSFS, and custom manager credentials configured."
