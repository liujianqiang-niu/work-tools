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

# 通过进程名或 PID 获取包名和描述
get_process_package_info() {
    local pid="$1"
    local process_name="$2"
    local binary_path=""
    local pkg_name=""

    # 优先通过 PID 获取二进制路径
    if [ -n "${pid}" ] && [ "${pid}" != "0" ] && [ "${pid}" != "-" ]; then
        binary_path=$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)
    fi

    # 如果通过 PID 获取失败，尝试通过进程名查找
    if [ -z "${binary_path}" ] && [ -n "${process_name}" ] && [ "${process_name}" != "-" ] && [ "${process_name}" != "N/A" ]; then
        # 尝试通过 which 查找二进制路径
        binary_path=$(which "${process_name}" 2>/dev/null || true)
        
        # 如果 which 找不到，尝试在常见路径查找
        if [ -z "${binary_path}" ]; then
            for dir in /usr/sbin /usr/bin /sbin /bin /usr/lib /usr/libexec; do
                if [ -x "${dir}/${process_name}" ]; then
                    binary_path="${dir}/${process_name}"
                    break
                fi
            done
        fi
    fi

    # 通过二进制路径查询所属包
    if [ -n "${binary_path}" ]; then
        pkg_name=$(dpkg -S "${binary_path}" 2>/dev/null | cut -d: -f1 | head -1 || true)
    fi

    printf '%s' "${pkg_name:-N/A}"
}

get_port_description() {
    local pid="$1"
    local port="$2"
    local process_info="$3"
    local pkg_name="$4"
    local pkg_desc=""
    local service_name=""

    # 通过包名获取包描述
    if [ -n "${pkg_name}" ] && [ "${pkg_name}" != "N/A" ]; then
        pkg_desc=$(dpkg-query -W -f='${Description}' "${pkg_name}" 2>/dev/null | head -1 || true)
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
    elif [ -n "${process_info}" ] && [ "${process_info}" != "N/A" ] && [ -n "${service_name}" ]; then
        printf '%s (%s)' "${process_info}" "${service_name}"
    elif [ -n "${process_info}" ] && [ "${process_info}" != "N/A" ]; then
        printf '%s' "${process_info}"
    elif [ -n "${service_name}" ]; then
        printf '%s' "${service_name}"
    else
        printf 'N/A'
    fi
}

write_ports_csv() {
    echo "Protocol,Port,Address,Process,Package,Description" > "${PORT_CSV}"

    command_exists netstat || return 0

    netstat -lntup 2>/dev/null | \
    while IFS= read -r line; do
        # 跳过标题行
        [[ "${line}" =~ ^Proto ]] && continue
        # 跳过空行
        [ -z "${line}" ] && continue

        # 解析行内容，netstat 输出格式可能包含多列
        proto=$(echo "${line}" | awk '{print $1}')
        
        # 跳过非协议行
        [[ "${proto}" =~ ^(tcp|tcp6|udp|udp6)$ ]] || continue

        local_addr=$(echo "${line}" | awk '{print $4}')
        [ -n "${local_addr:-}" ] || continue

        # 解析端口和地址
        port="${local_addr##*:}"
        address="${local_addr%:*}"

        if [ "${address}" = "${port}" ]; then
            address="${local_addr}"
        fi

        # 解析 PID 和进程名 (格式: PID/Program name 或 PID/Program name: extra)
        # netstat 的最后一列可能是 PID/Program 或 state (对于 UDP)
        pid=""
        process_name=""
        
        # 提取最后一列（PID/Program name）
        last_col=$(echo "${line}" | awk '{print $NF}')
        
        # 使用正则提取 PID（连续数字）
        if [[ "${last_col}" =~ ^([0-9]+)/ ]]; then
            pid="${BASH_REMATCH[1]}"
            # 提取进程名，去除斜杠前的 PID，然后取第一个字段（去除冒号后的额外信息）
            process_name_raw="${last_col#*/}"
            # 进程名可能在冒号后有额外信息，只取冒号前的部分
            process_name=$(echo "${process_name_raw}" | cut -d':' -f1 | awk '{print $1}')
        fi

        # 获取包名
        pkg_name=$(get_process_package_info "${pid}" "${process_name:-}")

        # 获取描述
        description=$(get_port_description "${pid}" "${port}" "${process_name:-N/A}" "${pkg_name}")
        description=${description//\"/\"\"}
        pkg_name=${pkg_name//\"/\"\"}

        # 处理协议名（去除数字后缀，如 tcp6 -> tcp）
        proto_clean="${proto%%[0-9]*}"

        printf '%s,%s,%s,%s,%s,"%s"\n' \
            "$proto_clean" "$port" "$address" "${process_name:-N/A}" "${pkg_name}" "$description" >> "${PORT_CSV}"
    done
}

write_packages_csv
write_systemd_csv
write_ports_csv

printf '软件包信息已保存: %s (%s 条)\n' "${PKG_CSV}" "$(( $(wc -l < "${PKG_CSV}") - 1 ))"
printf 'systemd 自启服务已保存: %s (%s 条)\n' "${SYSTEMD_CSV}" "$(( $(wc -l < "${SYSTEMD_CSV}") - 1 ))"
printf '监听端口信息已保存: %s (%s 条)\n' "${PORT_CSV}" "$(( $(wc -l < "${PORT_CSV}") - 1 ))"
