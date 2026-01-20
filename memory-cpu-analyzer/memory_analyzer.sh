#!/bin/bash
#
# memory_analyzer.sh - 分析并记录Linux系统的内存和CPU使用情况
#
# 作者: liujianqiang@uniontech.com
# 版本: 1.1
#
# 用法:
#   ./memory_analyzer.sh [选项]
#
# 描述:
#   该脚本用于收集当前Linux系统的内存和CPU使用信息，包括系统信息、
#   总体内存和CPU占用、Swap使用情况，以及占用资源最多的N个进程。
#   结果将以CSV格式输出到指定文件或标准输出。
#
#   同时，该脚本提供了一个合并功能，可以将两个独立的CSV报告
#   合并成一个文件，方便对比分析。

set -e
# set -o pipefail # 如果管道命令中任何一个失败，则整个管道失败

# --- 默认变量 ---
TOP_N=10
OUTPUT_FILE=""
MERGE_FILES=()
SORT_BY="mem" # 默认按内存排序

# --- 函数定义 ---

# 显示帮助信息
usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -n <数量>        指定要获取的内存或CPU占用最高的进程数量 (默认为 10)。"
    echo "  -o <文件名>      将结果输出到指定的CSV文件。"
    echo "  -m <文件1,文件2>   合并两个CSV文件到一个新的CSV文件中。文件名用逗号分隔。"
    echo "  -s <排序方式>    指定进程列表的排序方式: 'mem' (内存) 或 'cpu' (CPU)。默认为 'mem'。"
    echo "  -h, --help       显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  1. 按内存收集 top 10 进程并输出到 'report_mem.csv':"
    echo "     $0 -n 10 -s mem -o report_mem.csv"
    echo ""
    echo "  2. 按 CPU 收集 top 20 进程并打印到屏幕:"
    echo "     $0 -n 20 -s cpu"
    echo ""
    echo "  3. 合并 'report_boot.csv' 和 'report_used.csv' 到 'report_comparison.csv':"
    echo "     $0 -m report_boot.csv,report_used.csv -o report_comparison.csv"
}

# 收集数据并生成报告
generate_report() {
    local output_target=${1:-/dev/stdout}
    local top_n_processes=${2:-10}
    local sort_by=${3:-"mem"}

    # --- 1. 收集系统信息 ---
    # 使用 lsb_release 或 /etc/os-release 获取发行版信息
    if command -v lsb_release &> /dev/null; then
        distro_info=$(lsb_release -ds)
    else
        distro_info=$(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
    fi
    kernel_version=$(uname -r)
    capture_time=$(date "+%Y-%m-%d %H:%M:%S")

    # --- 2. 收集内存和Swap信息 ---
    # 从 'free -m' 命令获取内存数据 (以MB为单位)
    mem_info=$(LC_ALL=C free -m | awk '
        /Mem:/ {
            total=$2; used=$3; shared=$5;
            used_percent=sprintf("%.2f", used/total*100);
            print total","used","used_percent","shared;
        }
    ')
    swap_info=$(LC_ALL=C free -m | awk '
        /Swap:/ {
            total=$2; used=$3;
            if (total > 0) {
                used_percent=sprintf("%.2f", used/total*100);
            } else {
                used_percent=0;
            }
            print total","used","used_percent;
        }
    ')
    total_mem=$(echo "$mem_info" | cut -d',' -f1)
    used_mem=$(echo "$mem_info" | cut -d',' -f2)
    used_mem_percent=$(echo "$mem_info" | cut -d',' -f3)
    shared_mem=$(echo "$mem_info" | cut -d',' -f4)
    
    total_swap=$(echo "$swap_info" | cut -d',' -f1)
    used_swap=$(echo "$swap_info" | cut -d',' -f2)
    used_swap_percent=$(echo "$swap_info" | cut -d',' -f3)

    # --- 3. 收集CPU信息 ---
    cpu_info=$(LC_ALL=C top -bn1 | grep "Cpu(s)" | awk '{print $2+$4","$2","$4","$8}')
    cpu_total_used=$(echo "$cpu_info" | cut -d',' -f1)
    cpu_user=$(echo "$cpu_info" | cut -d',' -f2)
    cpu_system=$(echo "$cpu_info" | cut -d',' -f3)
    cpu_idle=$(echo "$cpu_info" | cut -d',' -f4)

    # --- 4. 格式化并输出CSV ---
    # 写入CSV头部
    echo "类别,指标,值,单位/描述" > "$output_target"
    echo "--- 系统信息 ---,---,---,---" >> "$output_target"
    echo "数据捕获时间,$capture_time,," >> "$output_target"
    echo "操作系统,\"$distro_info\",," >> "$output_target"
    echo "内核版本,$kernel_version,," >> "$output_target"
    
    # 写入内存汇总信息
    echo "--- 内存概览 ---,---,---,---" >> "$output_target"
    echo "总内存,$total_mem,MB," >> "$output_target"
    echo "已用内存,$used_mem,MB," >> "$output_target"
    echo "共享内存 (SHR),$shared_mem,MB," >> "$output_target"
    echo "内存使用率,$used_mem_percent,%,(已用/总共)" >> "$output_target"

    # 写入Swap使用情况
    echo "--- Swap 使用情况 ---,---,---,---" >> "$output_target"
    echo "Swap总计,$total_swap,MB," >> "$output_target"
    echo "Swap已用,$used_swap,MB," >> "$output_target"
    echo "Swap使用率,$used_swap_percent,%,(已用/总计)" >> "$output_target"

    # 写入CPU使用情况
    echo "--- CPU 概览 ---,---,---,---" >> "$output_target"
    echo "CPU总使用率,$cpu_total_used,%,(用户+系统)" >> "$output_target"
    echo "用户空间使用率,$cpu_user,%,us" >> "$output_target"
    echo "系统空间使用率,$cpu_system,%,sy" >> "$output_target"
    echo "CPU空闲率,$cpu_idle,%,id" >> "$output_target"

    # 写入Top N进程信息
    sort_col_name=$([ "$sort_by" == "cpu" ] && echo "CPU" || echo "内存")
    echo "--- Top $top_n_processes 按${sort_col_name}占用排序的进程 ---,---,---,---,---,---,---,---,---" >> "$output_target"
    echo "排名,PPID,PID,用户,CPU使用率 (%),内存使用量 (MB),共享内存 (MB),内存使用率 (%),启动命令" >> "$output_target"
    
    # 根据排序选择确定 ps 的 --sort 参数
    sort_key=$([ "$sort_by" == "cpu" ] && echo "-pcpu" || echo "-rss")

    # 使用 ps 命令获取进程信息
    # ppid: 父进程ID
    # user: 启动进程的用户
    # pid:  进程ID
    # pcpu: CPU使用率 (%)
    # pmem: 内存使用率 (%)
    # rss:  实际使用的物理内存 (Resident Set Size)，单位是KB
    # cmd:  完整的命令行
    LC_ALL=C ps -eo ppid,user:20,pid,pcpu,pmem,rss,cmd --sort=$sort_key | head -n $((top_n_processes + 1)) | tail -n +2 | awk -v total_mem_mb="$total_mem" '
    BEGIN { rank=1; }
    {
        ppid = $1;
        user = $2;
        pid = $3;
        cpu_percent = $4;
        mem_percent = $5;
        mem_mb = sprintf("%.2f", $6 / 1024);
        
        # 从第七个字段开始的所有内容都属于 command
        command = "";
        for (i = 7; i <= NF; i++) {
            command = command (i == 7 ? "" : " ") $i;
        }

        # 读取 /proc/{pid}/status 获取共享内存 (RssShmem)
        shr_kb = 0;
        proc_status_file = "/proc/" pid "/status";
        while ((getline line < proc_status_file) > 0) {
            if (line ~ /^RssShmem:/) {
                split(line, parts);
                shr_kb = parts[2];
                break;
            }
        }
        close(proc_status_file);
        shr_mb = sprintf("%.2f", shr_kb / 1024);
        
        # 为了安全，处理一下可能包含逗号和引号的命令名
        gsub("\"", "\"\"", command); # Escape double quotes
        gsub(",", ";", command);

        print rank "," ppid "," pid "," user "," cpu_percent "," mem_mb "," shr_mb "," mem_percent ",\"" command "\"";
        rank++;
    }' >> "$output_target"

    # 如果输出到文件，则在屏幕上提示
    if [ "$output_target" != "/dev/stdout" ]; then
        echo "报告已成功生成到: $output_target"
    fi
}

# 合并两个报告
merge_reports() {
    local file1=$1
    local file2=$2
    local output_target=${3:-/dev/stdout}

    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo "错误: 无法找到要合并的文件。请检查文件名是否正确。" >&2
        exit 1
    fi

    # 使用 paste 命令按行合并文件，以逗号作为分隔符
    paste -d, "$file1" "$file2" > "$output_target"

    if [ "$output_target" != "/dev/stdout" ]; then
        echo "文件 '$file1' 和 '$file2' 已成功合并到: $output_target"
    fi
}


# --- 主逻辑 ---

# 解析命令行参数
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

while getopts ":n:o:m:s:h-:" opt; do
    case ${opt} in
        n )
            TOP_N=$OPTARG
            ;;
        o )
            OUTPUT_FILE=$OPTARG
            ;;
        m )
            # 将逗号分隔的字符串转换为数组
            IFS=',' read -r -a MERGE_FILES <<< "$OPTARG"
            ;;
        s )
            SORT_BY=$OPTARG
            if [[ "$SORT_BY" != "mem" && "$SORT_BY" != "cpu" ]]; then
                echo "错误: -s 的参数必须是 'mem' 或 'cpu'。" >&2
                exit 1
            fi
            ;;
        h )
            usage
            exit 0
            ;;
        - )
            [ "$OPTARG" == "help" ] && { usage; exit 0; }
            ;;
        \? )
            echo "无效的选项: -$OPTARG" >&2
            usage
            exit 1
            ;;
        : )
            echo "选项 -$OPTARG 需要一个参数。" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# --- 执行操作 ---

# 检查是执行合并还是生成报告
if [ ${#MERGE_FILES[@]} -ne 0 ]; then
    # 执行合并操作
    if [ ${#MERGE_FILES[@]} -ne 2 ]; then
        echo "错误: 合并功能需要且仅需要两个文件名，用逗号分隔。" >&2
        echo "例如: -m file1.csv,file2.csv" >&2
        exit 1
    fi
    if [ -z "$OUTPUT_FILE" ]; then
        echo "错误: 使用 -m 进行合并时，必须使用 -o 指定输出文件名。" >&2
        exit 1
    fi
    merge_reports "${MERGE_FILES[0]}" "${MERGE_FILES[1]}" "$OUTPUT_FILE"
else
    # 执行生成报告操作
    generate_report "$OUTPUT_FILE" "$TOP_N" "$SORT_BY"
fi

exit 0
