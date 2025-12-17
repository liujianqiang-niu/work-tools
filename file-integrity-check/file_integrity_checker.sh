#!/bin/bash

# 文件完整性检查和对比工具
# 用于检测Linux系统文件或库文件的变更

VERSION="1.0.0"

# 默认配置
DEFAULT_DIR="/"
DEFAULT_OUTPUT="file_checksums.txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    cat << EOF
文件完整性检查和对比工具 v${VERSION}

用途:
    用于生成目录下所有文件的MD5校验和，并支持对比两个系统的差异文件

使用方法:
    $0 [选项]

选项:
    -d, --dir <目录>          指定要扫描的目录 (默认: /)
    -o, --output <文件>       指定输出文件名称 (默认: file_checksums.txt)
    -c, --compare <文件1> <文件2>  对比两个MD5校验和文件的差异
    -e, --exclude <模式>      排除匹配的目录或文件 (可多次使用)
    -h, --help               显示此帮助信息
    -v, --version            显示版本信息

示例:
    # 扫描/usr目录并生成MD5校验和文件
    $0 -d /usr -o usr_checksums.txt

    # 扫描整个系统 (排除/proc, /sys等虚拟文件系统)
    $0 -d / -o system_checksums.txt -e /proc -e /sys -e /dev

    # 对比两个系统的校验和文件
    $0 -c system1_checksums.txt system2_checksums.txt

    # 仅生成当前目录的校验和
    $0 -d . -o current_dir_checksums.txt

说明:
    - 生成校验和时会递归扫描指定目录下的所有文件
    - 对于无法读取的文件会记录错误但继续处理
    - 对比模式会输出三类差异:
      * 仅在系统1存在的文件
      * 仅在系统2存在的文件
      * 两个系统都存在但MD5值不同的文件

注意事项:
    - 扫描根目录时建议排除虚拟文件系统 (/proc, /sys, /dev等)
    - 扫描大目录可能需要较长时间
    - 确保有足够的磁盘空间存储输出文件

EOF
}

# 显示版本信息
show_version() {
    echo "文件完整性检查和对比工具 v${VERSION}"
}

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 生成MD5校验和
generate_checksums() {
    local target_dir="$1"
    local output_file="$2"
    local exclude_patterns=("${@:3}")
    
    # 检查目录是否存在
    if [ ! -d "$target_dir" ]; then
        print_error "目录不存在: $target_dir"
        return 1
    fi
    
    print_info "开始扫描目录: $target_dir"
    print_info "输出文件: $output_file"
    
    # 构建find命令的排除参数
    local find_exclude=""
    for pattern in "${exclude_patterns[@]}"; do
        if [ -n "$pattern" ]; then
            # 移除路径末尾的斜杠（如果有）
            pattern="${pattern%/}"
            find_exclude="$find_exclude -path \"$pattern\" -prune -o"
        fi
    done
    
    # 创建临时文件
    local temp_file="${output_file}.tmp"
    > "$temp_file"
    
    # 记录开始时间
    local start_time=$(date +%s)
    local file_count=0
    local error_count=0
    
    print_info "正在计算文件MD5值..."
    
    # 使用find查找所有文件并计算MD5
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            # 计算MD5并写入临时文件
            if md5sum "$file" 2>/dev/null >> "$temp_file"; then
                ((file_count++))
                if ((file_count % 100 == 0)); then
                    echo -ne "\r已处理: $file_count 个文件"
                fi
            else
                print_warning "无法计算MD5: $file"
                ((error_count++))
            fi
        fi
    done < <(eval "find '$target_dir' $find_exclude -type f -print0")
    
    echo "" # 换行
    
    # 排序并保存到最终输出文件
    print_info "正在排序结果..."
    sort -k2 "$temp_file" > "$output_file"
    rm -f "$temp_file"
    
    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 添加元数据到输出文件
    {
        echo "# 文件完整性校验报告"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# 扫描目录: $target_dir"
        echo "# 主机名: $(hostname)"
        echo "# 文件总数: $file_count"
        echo "# 错误数量: $error_count"
        echo "# 耗时: ${duration}秒"
        echo "# ----------------------------------------"
        cat "$output_file"
    } > "${output_file}.new"
    mv "${output_file}.new" "$output_file"
    
    print_success "扫描完成!"
    print_info "处理文件数: $file_count"
    if [ $error_count -gt 0 ]; then
        print_warning "错误数量: $error_count"
    fi
    print_info "耗时: ${duration}秒"
    print_info "结果已保存到: $output_file"
    
    return 0
}

# 对比两个校验和文件
compare_checksums() {
    local file1="$1"
    local file2="$2"
    
    # 检查文件是否存在
    if [ ! -f "$file1" ]; then
        print_error "文件不存在: $file1"
        return 1
    fi
    
    if [ ! -f "$file2" ]; then
        print_error "文件不存在: $file2"
        return 1
    fi
    
    print_info "开始对比文件..."
    print_info "系统1: $file1"
    print_info "系统2: $file2"
    echo ""
    
    # 创建临时文件用于存储处理后的数据
    local temp1=$(mktemp)
    local temp2=$(mktemp)
    
    # 过滤掉注释行和空行，提取MD5和文件路径（MD5是第一列32字符，其余是路径）
    grep -v '^#' "$file1" | grep -v '^$' | sed 's/^\([a-f0-9]\{32\}\)  /\1|/' | sort -t'|' -k2 > "$temp1"
    grep -v '^#' "$file2" | grep -v '^$' | sed 's/^\([a-f0-9]\{32\}\)  /\1|/' | sort -t'|' -k2 > "$temp2"
    
    # 统计变量
    local only_in_file1=0
    local only_in_file2=0
    local different_md5=0
    local identical=0
    
    # 创建输出文件
    local output_report="comparison_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "================================================================"
        echo "文件完整性对比报告"
        echo "================================================================"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "系统1文件: $file1"
        echo "系统2文件: $file2"
        echo ""
        
        # 查找仅在文件1中存在的文件
        echo "----------------------------------------------------------------"
        echo "1. 仅在系统1中存在的文件:"
        echo "----------------------------------------------------------------"
        while IFS='|' read -r md5 filepath; do
            if ! grep -qF "|$filepath" "$temp2"; then
                echo "  $filepath"
                ((only_in_file1++))
            fi
        done < "$temp1"
        
        if [ $only_in_file1 -eq 0 ]; then
            echo "  (无)"
        fi
        echo ""
        
        # 查找仅在文件2中存在的文件
        echo "----------------------------------------------------------------"
        echo "2. 仅在系统2中存在的文件:"
        echo "----------------------------------------------------------------"
        while IFS='|' read -r md5 filepath; do
            if ! grep -qF "|$filepath" "$temp1"; then
                echo "  $filepath"
                ((only_in_file2++))
            fi
        done < "$temp2"
        
        if [ $only_in_file2 -eq 0 ]; then
            echo "  (无)"
        fi
        echo ""
        
        # 查找MD5值不同的文件
        echo "----------------------------------------------------------------"
        echo "3. 两个系统都存在但MD5值不同的文件:"
        echo "----------------------------------------------------------------"
        while IFS='|' read -r md5_1 filepath; do
            # 在文件2中查找相同路径的文件（使用精确匹配）
            md5_2=$(grep -F "|$filepath" "$temp2" 2>/dev/null | head -1 | cut -d'|' -f1)
            
            if [ -n "$md5_2" ] && [ "$md5_1" != "$md5_2" ]; then
                echo "  $filepath"
                echo "    系统1 MD5: $md5_1"
                echo "    系统2 MD5: $md5_2"
                echo ""
                ((different_md5++))
            elif [ -n "$md5_2" ]; then
                ((identical++))
            fi
        done < "$temp1"
        
        if [ $different_md5 -eq 0 ]; then
            echo "  (无)"
        fi
        echo ""
        
        # 汇总统计
        echo "================================================================"
        echo "对比统计汇总:"
        echo "================================================================"
        echo "仅在系统1存在: $only_in_file1 个文件"
        echo "仅在系统2存在: $only_in_file2 个文件"
        echo "MD5值不同: $different_md5 个文件"
        echo "完全相同: $identical 个文件"
        echo "总差异数: $((only_in_file1 + only_in_file2 + different_md5))"
        echo "================================================================"
        
    } | tee "$output_report"
    
    # 从输出文件中提取统计数据
    local total_diff=$(grep "^总差异数:" "$output_report" | awk '{print $2}')
    
    # 清理临时文件
    rm -f "$temp1" "$temp2"
    
    # 输出汇总信息
    echo ""
    print_success "对比完成!"
    print_info "详细报告已保存到: $output_report"
    
    # 根据差异数量返回不同的退出码
    if [ "$total_diff" -eq 0 ]; then
        print_success "两个系统的文件完全一致"
        return 0
    else
        print_warning "检测到 $total_diff 处文件差异"
        return 2
    fi
}

# 主函数
main() {
    local mode=""
    local target_dir=""
    local output_file=""
    local compare_file1=""
    local compare_file2=""
    local exclude_patterns=()
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -d|--dir)
                target_dir="$2"
                mode="generate"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -c|--compare)
                compare_file1="$2"
                compare_file2="$3"
                mode="compare"
                shift 3
                ;;
            -e|--exclude)
                exclude_patterns+=("$2")
                shift 2
                ;;
            *)
                print_error "未知选项: $1"
                echo "使用 -h 或 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # 根据模式执行相应操作
    case $mode in
        generate)
            target_dir="${target_dir:-$DEFAULT_DIR}"
            output_file="${output_file:-$DEFAULT_OUTPUT}"
            generate_checksums "$target_dir" "$output_file" "${exclude_patterns[@]}"
            ;;
        compare)
            if [ -z "$compare_file1" ] || [ -z "$compare_file2" ]; then
                print_error "对比模式需要指定两个文件"
                echo "使用方法: $0 -c <文件1> <文件2>"
                exit 1
            fi
            compare_checksums "$compare_file1" "$compare_file2"
            ;;
        *)
            print_error "请指定操作模式"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
