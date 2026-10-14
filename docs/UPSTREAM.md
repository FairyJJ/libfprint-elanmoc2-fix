# 提交上游：Depau/libfprint（elanmoc2 分支）

## 目标

- **仓库**：https://gitlab.freedesktop.org/Depau/libfprint （freedesktop GitLab，Depau 的 fork）
- **分支**：`elanmoc2`（当前 HEAD `11f0316`，与补丁基线一致，**已验证可零冲突应用**）
- 主线 `gitlab.freedesktop.org/libfprint/libfprint` **尚无 elanmoc2 分支**，驱动未收编，故唯一上游即此 fork
- GitHub 上没有 Depau 的 libfprint 镜像，**只能走 freedesktop GitLab**

## MR 标题

```
elanmoc2: Fix use-after-free and double-report on verify retry
```

## MR 描述（英文，直接粘贴）

```markdown
## Problem

Two bugs in the identify/verify error path of the elanmoc2 driver
crash fprintd (SEGV) on every finger press once a retry error is
reported (e.g. "press harder" / "sensor is dirty or wet"):

1. **Use-after-free**: `elanmoc2_identify_verify_report()` passes the
   `GError` to `fpi_device_verify_report()` *by value* while the caller
   keeps a `g_autoptr(GError)` that frees it immediately afterwards.
   fprintd later reads `error->message` in `verify_cb()`'s `g_warning()`
   and dereferences the freed error (crash in `g_strdup_vprintf`).

2. **Double report / assertion**: the retry branch jumps back into the
   SSM (`fpi_ssm_jump_to_state(ssm, IDENTIFY_IDENTIFY)`) instead of
   finishing the action. On the next press the driver reports a second
   time, tripping `fpi_device_verify_report()`'s
   `result_reported == FALSE` assertion.

## Fix

- Report an error as `FPI_MATCH_ERROR` and transfer ownership of the
  error to the core with `g_steal_pointer()` (verify and identify
  branches).
- On a retryable error, report the retry error and **complete the
  action** (`fpi_device_verify_complete()` + `fpi_ssm_mark_completed()`),
  matching the pattern already used by the older `elanmoc` driver. The
  core ends the task with the retry error and fprintd restarts verify
  with a fresh task.

## Testing

- **Real hardware** — ELAN `04f3:0c00` (`ELAN:ARM-M4`, HP Pavilion Aero
  13), patched build installed system-wide:
  - light/damp press → `verify-remove-and-retry` reported cleanly (the
    exact path that used to SEGV), no assertion, no coredump;
  - wrong finger → `verify-no-match` reported cleanly;
  - correct finger → `verify-match`, `fprintd-verify` exit code 0;
  - polkit end-to-end (`pkcheck --allow-user-interaction`): GNOME dialog
    → PAM → `Verify: finger matches` → exit code 0.
- **Deterministic replay** — umockdev pcapng replay of
  `tests/elanmoc2/custom.pcapng` under `G_DEBUG=fatal-warnings`, with an
  identify response patched to `40 fe` (NOT_ENOUGH_SURFACE) to force the
  retry path: clean retry error, fprintd-style task restart, final
  match, no assertion, no crash. Full log:
  https://github.com/FairyJJ/libfprint-elanmoc2-fix/blob/main/evidence/retry-path-test.log

## Notes

- Applies cleanly on `elanmoc2` @ `11f0316` (verified with
  `git apply --check`).
```

## 操作步骤

1. 打开 https://gitlab.freedesktop.org/users/sign_in → 点 **Sign in with GitHub** 授权 `FairyJJ`
2. 打开 https://gitlab.freedesktop.org/Depau/libfprint → 点 **Fork**（fork 到自己账号）
3. 本地执行（或直接跑本仓库的 `scripts/submit.sh`，效果相同）：
   ```bash
   git clone --depth 1 -b elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint.git
   cd libfprint
   git apply <本仓库>/patch/elanmoc2-verify-retry-fix.patch
   git checkout -b elanmoc2-fix-verify-uaf
   git -c user.name="FairyJJ" -c user.email="FairyJJ@users.noreply.github.com" \
       commit -a -F <本仓库>/docs/commit-message.txt
   git remote add mine https://gitlab.freedesktop.org/<你的gitlab用户名>/libfprint.git
   git push -o merge_request.create=true \
            -o merge_request.title="elanmoc2: Fix use-after-free and double-report on verify retry" \
            -o merge_request.target_project=Depau/libfprint \
            -o merge_request.target_branch=elanmoc2 \
            mine HEAD:elanmoc2-fix-verify-uaf
   ```
   （`merge_request.create=true` 是 GitLab push option，push 即自动建 MR）
4. 把上面的 MR 描述粘进 MR 页面，提交
