# libfprint-elanmoc2-fix

修复 libfprint `elanmoc2` 驱动（ELAN Match-on-Chip 2 指纹读头，USB ID `04f3:0c00` / `ELAN:ARM-M4` 等）在 verify/identify **重试路径**上的 use-after-free 与重复上报崩溃。

> 一句话：装上 Depau 的 elanmoc2 分支后**一按指纹 fprintd 就 SEGV**——根因在驱动的重试错误处理，不在 PAM、不在 fprintd 本身。本仓库提供修复补丁、完整验证证据和上游提交材料。

## 症状

- 按压指纹 → `fprintd` 立即崩溃（`g_strdup_vprintf` 内 SEGV，或 `result_reported` 断言失败），journal 里刷 coredump
- 波及所有走 fprintd 的认证入口：GDM 登录/解锁、`sudo`、`su`、polkit（GNOME 设置里改个设置都弹不出认证对话框）
- 只在**上报过一次 retry 之后**崩溃（"Press your finger slightly harder on the sensor" / "Sensor is dirty or wet"）

## 根因

`elanmoc2_identify_verify_report()` 与 `elanmoc2_identify_run_state()` 两个 bug 叠加：

1. **Use-after-free**：`fpi_device_verify_report(device, result, print, *error)` 把 `GError` **按值**传进 core，而调用方持有 `g_autoptr(GError)`，函数返回即释放。fprintd 的 `verify_cb()` 随后在 `g_warning()` 里读 `error->message` → 解引用已释放内存（SEGV）。
2. **重复上报**：重试分支用 `fpi_ssm_jump_to_state(ssm, IDENTIFY_IDENTIFY)` 跳回 SSM 而不是结束动作。下次按压时驱动第二次上报，触发 `fpi_device_verify_report()` 的 `result_reported == FALSE` 断言。

## 修复（3 处，+21 −4）

| # | 位置 | 改动 |
|---|---|---|
| 1 | verify 分支 | 有 error 时 `result` 置 `FPI_MATCH_ERROR`，并用 `g_steal_pointer(error)` 把 error 所有权移交给 core |
| 2 | retry 分支 | 不再跳回 SSM；改为 `fpi_device_verify_complete()` + `fpi_ssm_mark_completed()` 结束动作，core 以 retry error 结束任务，fprintd 用**全新 task** 重启 verify |
| 3 | identify 分支 | 同样 `g_steal_pointer(error)` 转移所有权 |

第 2 处与更老的 `elanmoc`（v1）驱动写法一致——那是这个驱动家族里一直正确的模式。

## 验证

| 层 | 方法 | 结果 |
|---|---|---|
| 确定性回放 | umockdev pcapng 回放 `tests/elanmoc2/custom.pcapng`，把 identify 响应改成 `40 fe`（NOT_ENOUGH_SURFACE）强制走重试路径；`G_DEBUG=fatal-warnings` | 干净 retry → 新 task 重启 → match，无 assertion / SEGV，全量日志见 `evidence/retry-path-test.log` |
| 真实硬件 | ELAN `04f3:0c00`（HP Pavilion Aero 13），补丁版装到系统 | 轻压/湿手 → `verify-remove-and-retry` 干净上报（正是以前崩溃那条路径）；错指纹 → `verify-no-match`；正确指纹 → **`verify-match`，`fprintd-verify` 退出码 0** |
| polkit 端到端 | `pkcheck --allow-user-interaction` | GNOME 对话框 → PAM → `Verify: finger matches` → **退出码 0** |

## 应用

补丁基线：Depau/libfprint `elanmoc2` 分支 HEAD `11f0316`（`git apply --check` 实测零冲突）：

```bash
git clone --depth 1 -b elanmoc2 https://gitlab.freedesktop.org/Depau/libfprint.git
cd libfprint
git apply /path/to/patch/elanmoc2-verify-retry-fix.patch
```

Arch 用户可直接使用本地重建的 `libfprint-elanmoc2-git 1.94.0+372+g11f0316-2`（已含本补丁）。

一键脚本：`bash scripts/submit.sh`（clone → apply → commit，只动本地 `/tmp`，不推送）。

## 上游提交

- 实际托管上游：**https://gitlab.freedesktop.org/Depau/libfprint** 的 `elanmoc2` 分支（主线 freedesktop libfprint 尚未收编 elanmoc2；GitHub 上也没有 Depau 的 libfprint 镜像）
- 英文 MR 描述与操作步骤：**[docs/UPSTREAM.md](docs/UPSTREAM.md)**（freedesktop GitLab 支持 GitHub OAuth 登录，fork 后 push 即自动建 MR）

## 文件

| 路径 | 说明 |
|---|---|
| `patch/elanmoc2-verify-retry-fix.patch` | 原始 diff，`git apply` 直接用 |
| `patch/0001-elanmoc2-fix-verify-retry-uaf.patch` | format-patch（含 commit message） |
| `docs/commit-message.txt` | commit message（`elanmoc2:` 前缀，与分支历史风格一致） |
| `docs/UPSTREAM.md` | 上游 MR 描述（英文）+ 提交步骤 |
| `evidence/retry-path-test.log` | 重试路径确定性回放全量日志 |
| `scripts/submit.sh` | 一键 apply + commit |

## License

补丁衍生于 [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint)（LGPL-2.1-or-later），以相同许可提供。

---

## English summary

Fix for a use-after-free + double-report crash in the libfprint `elanmoc2` driver (ELAN Match-on-Chip 2 readers, e.g. `04f3:0c00`): pressing a finger crashed fprintd (SEGV) whenever a retry error had been reported. Root cause: the driver passed the `GError` *by value* to `fpi_device_verify_report()` while a `g_autoptr` freed it (UAF), and the retry branch jumped back into the SSM instead of completing the action (assertion on re-report). The patch transfers error ownership with `g_steal_pointer()` and completes the action on retry, matching the older `elanmoc` driver pattern. Verified on real hardware (`verify-match`, exit code 0) and deterministically via umockdev pcapng replay under `G_DEBUG=fatal-warnings`. Upstream target: Depau/libfprint `elanmoc2` branch @ `11f0316` (applies cleanly) — see `docs/UPSTREAM.md`.
