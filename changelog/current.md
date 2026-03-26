# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

- feat(shared/manager): **ACK/ACS cloud Workers** — `HICLAW_RUNTIME=aliyun`, `HICLAW_ALIYUN_WORKER_BACKEND=k8s` (aligned with Helm); under `HICLAW_CLOUD_COORDINATOR`, skip local Higress/MinIO and use OSS pull/sync; `kubernetes.sh` / `kubernetes-api.py` create Worker Pods in-cluster (SAE-equivalent env, no fake MinIO on `:9000`); `create-worker` / `lifecycle-worker` / `k8s-worker-env.sh`; RRSA with `gateway-api.sh`, `hiclaw-env.sh`, `start-manager-agent.sh`, `container-api.sh`, `Dockerfile.aliyun`, etc.
- feat(helm): **ACK/ACS Helm deploy** — **Manager**, **Tuwunel**, and **Element Web** in one namespace; **`global.platform`** `ack` | `acs` (Tuwunel NAS: **ACK** static PV+PVC / **ACS** annotated PVC); **`tuwunel.persistence.nas.server`**; RRSA (manual default or webhook + optional namespace injection); **`HICLAW_REGISTRATION_TOKEN`** shared with Tuwunel via Secret; dedicated **Worker ServiceAccount** and `HICLAW_K8S_WORKER_SERVICE_ACCOUNT`; Manager probes **18799**; install docs merged into **`helm/hiclaw/README.md`**

### Security

- fix(security): `oss-credentials.sh` — `HICLAW_WORKER_NAME` 时令 STS 仅限 `agents/{worker}/*`、`shared/*`

### Cloud Runtime

- fix(cloud): `Dockerfile.aliyun` 安装 `kubernetes`；mc/copaw STS 刷新；`HICLAW_RUNTIME` 显式或尊重预置；Matrix 欢迎语前入房重试
