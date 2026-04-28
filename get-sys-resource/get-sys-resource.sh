#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_CSV="${SCRIPT_DIR}/packages.csv"
SYSTEMD_CSV="${SCRIPT_DIR}/systemd_enabled_services.csv"
PORT_CSV="${SCRIPT_DIR}/listening_ports.csv"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

write_packages_csv() {
    command_exists dpkg-query || return 0

    echo "Status,Name,Version,Architecture,Description" > "${PKG_CSV}"
    dpkg-query -W -f='${db:Status-Status},${Package},${Version},${Architecture},"${Description}"\n' | \
    sed ':a;N;$!ba;s/\n / /g' >> "${PKG_CSV}"
}

write_systemd_csv() {
    echo "UnitFile,EnabledState,ServiceName,Description" > "${SYSTEMD_CSV}"

    command_exists systemctl || return 0

    systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager | \
    while read -r unit_file enabled_state _; do
        [ -n "${unit_file:-}" ] || continue

        description=$(systemctl show -p Description --value "${unit_file}" 2>/dev/null || true)
        service_name="${unit_file%.service}"
        description=${description//\"/\"\"}

        printf '%s,%s,%s,"%s"\n' \
            "$unit_file" "$enabled_state" "$service_name" "$description" >> "${SYSTEMD_CSV}"
    done
}

get_port_description() {
    local port="$1"
    local process_info="$2"
    local service_name=""

    service_name=$(awk -v port="${port}" '
        $2 ~ ("^" port "/") {
            print $1
            exit
        }
    ' /etc/services 2>/dev/null || true)

    if [ -n "${process_info}" ] && [ -n "${service_name}" ]; then
        printf '%s (%s)' "${process_info}" "${service_name}"
    elif [ -n "${process_info}" ]; then
        printf '%s' "${process_info}"
    elif [ -n "${service_name}" ]; then
        printf '%s' "${service_name}"
    else
        printf 'N/A'
    fi
}

write_ports_csv() {
    echo "Protocol,Port,Address,Process,Description" > "${PORT_CSV}"

    command_exists ss || return 0

    ss -lntupH 2>/dev/null | \
    while read -r netid state recv_q send_q local_address peer_address process; do
        [ -n "${local_address:-}" ] || continue

        port="${local_address##*:}"
        address="${local_address%:*}"

        if [ "${address}" = "${port}" ]; then
            address="${local_address}"
        fi

        process_name=$(printf '%s' "${process:-}" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
        description=$(get_port_description "${port}" "${process_name}")
        description=${description//\"/\"\"}

        printf '%s,%s,%s,%s,"%s"\n' \
            "$netid" "$port" "$address" "${process_name:-N/A}" "$description" >> "${PORT_CSV}"
    done
}

write_packages_csv
write_systemd_csv
write_ports_csv

printf '软件包信息已保存: %s (%s 条)\n' "${PKG_CSV}" "$(( $(wc -l < "${PKG_CSV}") - 1 ))"
printf 'systemd 自启服务已保存: %s (%s 条)\n' "${SYSTEMD_CSV}" "$(( $(wc -l < "${SYSTEMD_CSV}") - 1 ))"
printf '监听端口信息已保存: %s (%s 条)\n' "${PORT_CSV}" "$(( $(wc -l < "${PORT_CSV}") - 1 ))"
