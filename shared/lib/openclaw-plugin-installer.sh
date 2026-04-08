#!/bin/bash
# openclaw-plugin-installer.sh - Helpers for installing standalone OpenClaw plugins

install_openclaw_npm_plugin_from_pack() {
    local package_name="$1"
    local plugin_dir="$2"
    local log_prefix="${3:-openclaw-plugin}"
    local tmp_dir pack_name pack_err install_log

    pack_err="/tmp/${log_prefix}-pack.err"
    install_log="/tmp/${log_prefix}-install.log"
    tmp_dir="$(mktemp -d)"

    pack_name="$(cd "${tmp_dir}" && npm pack "${package_name}" --silent 2>"${pack_err}" | tail -n 1)"
    if [ -z "${pack_name}" ] || [ ! -f "${tmp_dir}/${pack_name}" ]; then
        rm -rf "${tmp_dir}"
        return 1
    fi

    rm -rf "${plugin_dir}"
    mkdir -p "${plugin_dir}"

    if ! tar -xzf "${tmp_dir}/${pack_name}" -C "${tmp_dir}"; then
        rm -rf "${tmp_dir}"
        return 1
    fi

    if [ ! -d "${tmp_dir}/package" ]; then
        rm -rf "${tmp_dir}"
        return 1
    fi

    cp -rf "${tmp_dir}/package/." "${plugin_dir}/"
    rm -rf "${tmp_dir}"

    if ! (cd "${plugin_dir}" && npm install --omit=dev --ignore-scripts >"${install_log}" 2>&1); then
        return 1
    fi

    [ -f "${plugin_dir}/openclaw.plugin.json" ]
}
