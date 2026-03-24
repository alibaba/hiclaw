# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

- **fix(cloud): auto-refresh STS credentials for all mc invocations** — wrap mc binary with `mc-wrapper.sh` that calls `ensure_mc_credentials` before every invocation, preventing token expiry after ~50 minutes in cloud mode. Affects: manager, worker, copaw.
- **fix(copaw): refresh STS credentials in Python sync loops to prevent MinIO sync failure after token expiry

