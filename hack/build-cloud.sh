#!/bin/bash
# build-cloud.sh - Build and push cloud images (cloud-manager, worker, cloud-element)
#
# Usage:
#   ./hack/build-cloud.sh                    # build + push manager & worker
#   ./hack/build-cloud.sh build              # build only
#   ./hack/build-cloud.sh push               # push only (assumes already built)
#   ./hack/build-cloud.sh all --with-element # include cloud-element
#   TAG=20260316 ./hack/build-cloud.sh       # custom tag

set -euo pipefail

TAG="${TAG:-20260316}"
REGISTRY="${REGISTRY:-registry.cn-hangzhou.aliyuncs.com/hiclaw-cloud}"
OPENCLAW_BASE="${OPENCLAW_BASE:-higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/openclaw-base:latest}"

MANAGER_IMAGE="${REGISTRY}/hiclaw-manager:${TAG}"
WORKER_IMAGE="${REGISTRY}/hiclaw-worker:${TAG}"
ELEMENT_IMAGE="${REGISTRY}/cloud-element:${TAG}"

ACTION="${1:-all}"
WITH_ELEMENT=false
for arg in "$@"; do
    [ "$arg" = "--with-element" ] && WITH_ELEMENT=true
done

log() { echo "[build-cloud] $1"; }

do_build() {
    log "Building cloud-manager: ${MANAGER_IMAGE}"
    docker build \
        --build-arg OPENCLAW_BASE_IMAGE="${OPENCLAW_BASE}" \
        -f manager/Dockerfile.aliyun \
        -t "${MANAGER_IMAGE}" \
        .

    log "Building worker: ${WORKER_IMAGE}"
    docker build \
        --build-arg OPENCLAW_BASE_IMAGE="${OPENCLAW_BASE}" \
        --build-context shared=./shared/lib \
        -t "${WORKER_IMAGE}" \
        ./worker/

    if [ "${WITH_ELEMENT}" = "true" ]; then
        log "Building cloud-element: ${ELEMENT_IMAGE}"
        docker build \
            -f cloud-element/Dockerfile \
            -t "${ELEMENT_IMAGE}" \
            .
    fi

    log "Build complete"
}

do_push() {
    log "Pushing ${MANAGER_IMAGE}"
    docker push "${MANAGER_IMAGE}"

    log "Pushing ${WORKER_IMAGE}"
    docker push "${WORKER_IMAGE}"

    if [ "${WITH_ELEMENT}" = "true" ]; then
        log "Pushing ${ELEMENT_IMAGE}"
        docker push "${ELEMENT_IMAGE}"
    fi

    log "Push complete"
}

case "${ACTION}" in
    build) do_build ;;
    push)  do_push ;;
    all)   do_build; do_push ;;
    *)     echo "Usage: $0 [build|push|all]"; exit 1 ;;
esac
