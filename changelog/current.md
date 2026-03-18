# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

- fix(install): remove HOST_ORIGINAL_HOME env var on Windows to fix manager-agent startup failure caused by Linux container unable to interpret Windows paths (fixes #320)
- fix(manager): normalize worker name to lowercase in create-worker.sh to match Tuwunel's username storage behavior, fixing invite failures when worker names contain uppercase letters
- feat(cloud): add Alibaba Cloud SAE deployment support with unified cloud/local abstraction layer
