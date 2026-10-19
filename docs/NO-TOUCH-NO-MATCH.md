# ELAN `elanmoc2`: immediate no-match without touching the reader

## Scope

This field report documents an ELAN `04f3:0c00` / Match-on-Chip 2 case observed on 2026-10-16 with libfprint 1.94.100 and fprintd 1.94.5. It is separate from the retry-path use-after-free and double-report bug fixed by this repository's patch.

## Symptom

The GNOME lock screen displayed “Fingerprint match failed” immediately after wake, before the user touched the reader. A direct `fprintd-verify` call reproduced an immediate `verify-no-match`, so the false result was below GNOME/PAM.

## Evidence and cause

`fprintd-list` initially showed three host-side records. With `G_MESSAGES_DEBUG=all` enabled for fprintd, a verify operation logged:

```text
file_storage_discover_prints() ... loaded ...
Querying number of enrolled fingers
No fingers enrolled, no need to identify finger
Device reported verify result (result: FPI_MATCH_FAIL, print: (nil), error: none)
report_verify_status: result verify-no-match
```

The ELAN device's own enrollment-count response was zero even though stale per-user print records existed on the host. The driver therefore short-circuited verification before asking for a finger. The GNOME extension was not the cause in this case.

## Recovery used

1. Preserve a backup of `/var/lib/fprint/<user>/` before changing enrollment data.
2. Confirm the device itself reports zero stored prints in the fprintd debug log. Do not clear records when the device reports a nonzero count.
3. Remove the stale host-side enrollment records and confirm `fprintd-list <user>` reports no prints. In this case, `fprintd-delete <user>` returned a device-deletion error but the host-side list was empty afterward, so always re-check the list rather than relying on the command's summary alone.
4. Run `fprintd-enroll -f <finger-name> <user>` in a visible terminal and follow the repeated touch/lift prompts until enrollment completes. A transfer timeout means the reader did not receive a sample within its roughly 10-second command window; it is not a successful enrollment.
5. Confirm the new finger appears in `fprintd-list`. Run a short no-touch verification check: it should remain pending until timeout, rather than immediately return `verify-no-match`. Then verify with the enrolled finger and test the lock screen.

After this recovery, a no-touch `fprintd-verify` remained active for a three-second timeout, and the user subsequently confirmed successful lock-screen fingerprint unlock.

## Diagnostic distinction

- A crash/assertion after a retry is the driver bug addressed by `elanmoc2-verify-retry-fix.patch`.
- An immediate no-match with a zero device enrollment count and stale host-side records is a host/device enrollment mismatch.
- A transfer timeout during enrollment indicates no sample arrived in time; make the enrollment prompt visible and perform each touch/lift cycle before the next timeout.

This is a case-specific field diagnosis, not a claim that all immediate no-match reports have the same cause.
