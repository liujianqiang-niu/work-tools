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
    # 使用 AWK 处理 CSV 格式，正确转义描述中的双引号
    # dpkg-query 输出中，描述可能包含换行符（以空格开头的续行）
    dpkg-query -W -f='${db:Status-Status},${Package},${Version},${Architecture},${Description}\n' | \
    awk '
    BEGIN { FS=","; OFS="," }
    # 正确格式的行：以状态开头（installed, not-installed 等）
    /^(installed|not-installed|half-configured|half-installed|config-files|post-inst-failed|removal-failed|absent),/ {
        # 如果有上一条未完成的记录，先输出
        if (NR > 1 && status != "") {
            gsub(/"/, "\"\"", desc)
            print status","name","version","arch",\""desc"\""
        }
        # 解析新记录的前4个字段
        status = $1
        name = $2
        version = $3
        arch = $4
        # 第5个字段开始是描述（可能包含逗号）
        desc = ""
        for (i=5; i<=NF; i++) {
            if (desc != "") desc = desc ","
            desc = desc $i
        }
        # 移除描述开头的空格
        gsub(/^[ \t]+/, "", desc)
        next
    }
    # 续行：描述中的换行，以空格开头
    /^[ \t]/ {
        # 追加到描述
        desc = desc " " $0
        next
    }
    # 处理其他情况
    {
        desc = desc " " $0
    }
    END {
        # 输出最后一条记录
        if (status != "") {
            gsub(/"/, "\"\"", desc)
            print status","name","version","arch",\""desc"\""
        }
    }' >> "${PKG_CSV}"
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
        # IPv6 地址包含多个冒号，端口是最后一个冒号后面的数字
        # IPv4 地址只有一个冒号分隔地址和端口
        # IPv6 格式示例: "::1:631", ":::22", "fe80::1:80"
        # IPv4 格式示例: "127.0.0.1:80", "0.0.0.0:22"
        
        port="${local_addr##*:}"      # 提取最后一个冒号后的内容作为端口
        address="${local_addr%:*}"    # 提取最后一个冒号前的内容作为地址
        
        # 如果地址为空（如 "::1:631" 的情况），说明是 IPv6 地址
        # 需要重新处理：地址应该是去掉最后一个 :端口 后的完整部分
        if [ -z "${address}" ]; then
            # 对于 "::1:631" 这种情况，local_addr 是 "::1:631"
            # port="631", address=""，需要重新提取
            # 实际上地址应该是 "::1"
            address="${local_addr%:${port}}"
        fi
        
        # 如果端口不是纯数字，说明解析有问题（可能是 IPv6 地址的一部分）
        # 这种情况下整个 local_addr 应该被视为地址，端口可能需要从其他地方获取
        if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
            # 端口不是数字，跳过此行
            continue
        fi

        # 解析 PID 和进程名 (格式: PID/Program name 或 PID/Program name: extra)
        # netstat 的 PID/Program name 可能在行尾且包含空格
        pid=""
        process_name=""
        
        # 使用正则从整行中提取 PID/Program name 部分
        # 匹配格式: 数字/进程名（进程名可包含字母、数字、下划线、连字符、点号等）
        # 进程名后面可能有空格和其他参数
        if [[ "${line}" =~ ([0-9]+)/([a-zA-Z0-9_.:-]+)[[:space:]]*$ ]]; then
            pid="${BASH_REMATCH[1]}"
            process_name="${BASH_REMATCH[2]}"
        elif [[ "${line}" =~ ([0-9]+)/([a-zA-Z0-9_.:-]+)[[:space:]] ]]; then
            # 进程名后有空格（如 "1234/chrome --type"）
            pid="${BASH_REMATCH[1]}"
            process_name="${BASH_REMATCH[2]}"
        fi

        # 获取包名
        pkg_name=$(get_process_package_info "${pid}" "${process_name:-}")

        # 获取描述
        description=$(get_port_description "${pid}" "${port}" "${process_name:-N/A}" "${pkg_name}")
        description=${description//\"/\"\"}
        pkg_name=${pkg_name//\"/\"\"}

        # 保留原始协议名（tcp/tcp6/udp/udp6）

        printf '%s,%s,%s,%s,%s,"%s"\n' \
            "$proto" "$port" "$address" "${process_name:-N/A}" "${pkg_name}" "$description" >> "${PORT_CSV}"
    done
}

write_packages_csv
write_systemd_csv
write_ports_csv

printf '软件包信息已保存: %s (%s 条)\n' "${PKG_CSV}" "$(( $(wc -l < "${PKG_CSV}") - 1 ))"
printf 'systemd 自启服务已保存: %s (%s 条)\n' "${SYSTEMD_CSV}" "$(( $(wc -l < "${SYSTEMD_CSV}") - 1 ))"
printf '监听端口信息已保存: %s (%s 条)\n' "${PORT_CSV}" "$(( $(wc -l < "${PORT_CSV}") - 1 ))"
