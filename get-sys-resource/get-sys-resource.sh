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
    local pid="$1"
    local port="$2"
    local process_info="$3"
    local binary_path=""
    local pkg_name=""
    local pkg_desc=""
    local service_name=""

    # 通过 PID 获取二进制路径
    if [ -n "${pid}" ] && [ "${pid}" != "0" ] && [ "${pid}" != "-" ]; then
        binary_path=$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)
        
        # 通过二进制路径查询所属包
        if [ -n "${binary_path}" ]; then
            pkg_name=$(dpkg -S "${binary_path}" 2>/dev/null | cut -d: -f1 | head -1 || true)
            
            # 通过包名获取包描述
            if [ -n "${pkg_name}" ]; then
                pkg_desc=$(dpkg-query -W -f='${Description}' "${pkg_name}" 2>/dev/null | head -1 || true)
            fi
        fi
    fi

    # 从 /etc/services 获取服务名作为补充
    service_name=$(awk -v port="${port}" '
        $2 ~ ("^" port "/") {
            print $1
            exit
        }
    ' /etc/services 2>/dev/null || true)

    # 组合描述信息：优先使用包描述，其次进程名+服务名
    if [ -n "${pkg_desc}" ]; then
        if [ -n "${service_name}" ]; then
            printf '%s (%s)' "${pkg_desc}" "${service_name}"
        else
            printf '%s' "${pkg_desc}"
        fi
    elif [ -n "${process_info}" ] && [ -n "${service_name}" ]; then
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

    command_exists netstat || return 0

    netstat -lntup 2>/dev/null | \
    while read -r proto recv_q send_q local_addr foreign_addr state pid_program; do
        # 跳过标题行和空行
        [ -n "${local_addr:-}" ] || continue
        [[ "${proto}" =~ ^(tcp|tcp6|udp|udp6)$ ]] || continue

        # 解析端口和地址
        port="${local_addr##*:}"
        address="${local_addr%:*}"

        if [ "${address}" = "${port}" ]; then
            address="${local_addr}"
        fi

        # 解析 PID 和进程名 (格式: PID/Program name)
        pid=""
        process_name=""
        if [ -n "${pid_program:-}" ]; then
            pid=$(echo "${pid_program}" | cut -d'/' -f1 2>/dev/null || true)
            process_name=$(echo "${pid_program}" | cut -d'/' -f2 2>/dev/null || true)
        fi

        description=$(get_port_description "${pid}" "${port}" "${process_name}")
        description=${description//\"/\"\"}

        # 处理协议名（去除数字后缀，如 tcp6 -> tcp）
        proto_clean="${proto%%[0-9]*}"

        printf '%s,%s,%s,%s,"%s"\n' \
            "$proto_clean" "$port" "$address" "${process_name:-N/A}" "$description" >> "${PORT_CSV}"
    done
}

write_packages_csv
write_systemd_csv
write_ports_csv

printf '软件包信息已保存: %s (%s 条)\n' "${PKG_CSV}" "$(( $(wc -l < "${PKG_CSV}") - 1 ))"
printf 'systemd 自启服务已保存: %s (%s 条)\n' "${SYSTEMD_CSV}" "$(( $(wc -l < "${SYSTEMD_CSV}") - 1 ))"
printf '监听端口信息已保存: %s (%s 条)\n' "${PORT_CSV}" "$(( $(wc -l < "${PORT_CSV}") - 1 ))"
