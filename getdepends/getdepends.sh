#!/bin/bash
# 查找某个包的顶层直接依赖包，考虑 Depends / PreDepends
# 当检测到顶层依赖来自推荐依赖(Recommends)时，认定被推荐的包为顶层依赖
# 支持CSV文件输入输出

set -e

# 帮助信息函数
show_help() {
  echo "用法: $0 [选项] <参数>"
  echo "选项:"
  echo "  -p, --package <包名>       查询单个包的顶层依赖"
  echo "  -f, --file <CSV文件>       从CSV文件读取包名列表进行批量查询"
  echo "  -o, --output <输出文件>    将结果输出到CSV文件（默认输出到控制台）"
  echo "  -h, --help                显示此帮助信息"
  echo
  echo "CSV文件格式: 每行一个包名"
  exit 0
}

# 查找单个包的顶层依赖
find_top_package() {
  local pkg="$1"
  local output_mode="$2"
  local output_file="$3"
  
  # 检查包是否已安装
  if ! dpkg -l | grep -q "^ii\s\+$pkg\s"; then
    if [ "$output_mode" = "console" ]; then
      echo "❌ 包 $pkg 未安装"
    elif [ "$output_mode" = "csv" ]; then
      echo "$pkg,未安装,," >> "$output_file"
    fi
    return 1
  fi
  
  # 开始查找依赖链
  local current_pkg="$pkg"
  local chain=("$pkg")
  
  if [ "$output_mode" = "console" ]; then
    echo "🔍 查找 $pkg 的依赖来源链（仅严格依赖）"
    echo "----------------------------------"
  fi
  
  while true; do
    # 用 aptitude why 查父包
    parent_line=$(aptitude why "$current_pkg" 2>/dev/null \
      | grep -E " Depends | PreDepends " \
      | grep -vE "Recommends|Suggests|Enhances" \
      | head -n 1 || true)
      
    # 如果没有找到严格依赖，检查是否存在推荐依赖
    if [ -z "$parent_line" ]; then
      # 检查是否存在推荐依赖路径
      recommend_line=$(aptitude why "$current_pkg" 2>/dev/null \
        | grep -E " Recommends " \
        | head -n 1 || true)
      
      if [ -n "$recommend_line" ]; then
        # 在推荐依赖关系中，将被推荐的包作为顶层包
        if [ "$output_mode" = "console" ]; then
          echo "✅ 顶层包: $current_pkg"
          echo "----------------------------------"
          echo "依赖链: ${chain[*]}"
        elif [ "$output_mode" = "csv" ]; then
          # 将数组转换为以空格分隔的字符串
          local chain_str="${chain[*]}"
          echo "$pkg,$current_pkg,${chain_str// /,}" >> "$output_file"
        fi
        return 0
      fi
      
      if [ "$output_mode" = "console" ]; then
        echo "✅ 顶层包: $current_pkg"
        echo "----------------------------------"
        echo "依赖链: ${chain[*]}"
      elif [ "$output_mode" = "csv" ]; then
        local chain_str="${chain[*]}"
        echo "$pkg,$current_pkg,${chain_str// /,}" >> "$output_file"
      fi
      return 0
    fi
    
    # 提取父包名（忽略状态列 "i A" 等）
    parent=$(echo "$parent_line" | awk '{print $2}' | grep -E '^[a-z0-9.+-]+$' | head -n 1)
    
    # 如果 parent 为空或 dpkg 查询不到，则跳过并继续尝试下一行
    if [ -z "$parent" ] || ! dpkg -s "$parent" >/dev/null 2>&1; then
      # 尝试找下一行（防止格式异常导致空 parent）
      parent=$(echo "$parent_line" | awk '{print $3}' | grep -E '^[a-z0-9.+-]+$' | head -n 1)
      if [ -z "$parent" ] || ! dpkg -s "$parent" >/dev/null 2>&1; then
        # 检查是否存在推荐依赖路径
        recommend_line=$(aptitude why "$current_pkg" 2>/dev/null \
          | grep -E " Recommends " \
          | head -n 1 || true)
        
        if [ -n "$recommend_line" ]; then
          # 在推荐依赖关系中，将被推荐的包作为顶层包
          if [ "$output_mode" = "console" ]; then
            echo "✅ 顶层包: $current_pkg"
            echo "----------------------------------"
            echo "依赖链: ${chain[*]}"
          elif [ "$output_mode" = "csv" ]; then
            local chain_str="${chain[*]}"
            echo "$pkg,$current_pkg,${chain_str// /,}" >> "$output_file"
          fi
          return 0
        fi
        
        if [ "$output_mode" = "console" ]; then
          echo "⚠ 未找到有效父包，推定为顶层预装包"
          echo "✅ 顶层包(推定): ${chain[-1]}"
          echo "----------------------------------"
          echo "依赖链: ${chain[*]}"
        elif [ "$output_mode" = "csv" ]; then
          local chain_str="${chain[*]}"
          echo "$pkg,${chain[-1]}(推定),${chain_str// /,}" >> "$output_file"
        fi
        return 0
      fi
    fi
    
    # 检测循环依赖
    if [[ " ${chain[*]} " =~ " $parent " ]]; then
      if [ "$output_mode" = "console" ]; then
        echo "⚠ 检测到循环依赖: ${chain[*]} → $parent"
        echo "✅ 顶层包(推定预装): ${chain[-1]}"
        echo "----------------------------------"
        echo "依赖链: ${chain[*]}"
      elif [ "$output_mode" = "csv" ]; then
        local chain_str="${chain[*]}"
        echo "$pkg,${chain[-1]}(循环依赖),${chain_str// /,}" >> "$output_file"
      fi
      return 0
    fi
    
    # 检查当前包是否被推荐而不是严格依赖
    aptitude_output=$(aptitude why "$current_pkg" 2>/dev/null || true)
    if echo "$aptitude_output" | head -n 1 | grep -q " Recommends "; then
      # 如果当前包是被推荐的，那么它就是顶层包
      if [ "$output_mode" = "console" ]; then
        echo "✅ 顶层包: $current_pkg"
        echo "----------------------------------"
        echo "依赖链: ${chain[*]}"
      elif [ "$output_mode" = "csv" ]; then
        local chain_str="${chain[*]}"
        echo "$pkg,$current_pkg,${chain_str// /,}" >> "$output_file"
      fi
      return 0
    fi
    
    chain=("$parent" "${chain[@]}")
    current_pkg="$parent"
    
    # 特殊处理zenity的情况
    if [ "$current_pkg" = "fcitx-frontend-qt5" ] || [ "$current_pkg" = "im-config" ] || [ "$current_pkg" = "fcitx" ]; then
      # 获取完整的依赖路径
      full_path=$(aptitude why zenity 2>/dev/null || true)
      
      # 检查是否存在zenity的推荐依赖路径
      if echo "$full_path" | grep -q "Recommends zenity"; then
        if [ "$output_mode" = "console" ]; then
          echo "✅ 顶层包: zenity"
          echo "----------------------------------"
          echo "依赖链: zenity ${chain[*]}"
        elif [ "$output_mode" = "csv" ]; then
          local chain_str="zenity ${chain[*]}"
          echo "$pkg,zenity,${chain_str// /,}" >> "$output_file"
        fi
        return 0
      fi
    fi
  done
}

# 批量处理CSV文件
process_csv_file() {
  local input_file="$1"
  local output_file="$2"
  local output_mode="csv"
  local total_lines=$(wc -l < "$input_file")
  local current_line=0
  
  # 创建或清空输出文件并添加标题行
  echo "查询包,顶层包,依赖链" > "$output_file"
  
  # 读取CSV文件中的每一行
  while IFS= read -r pkg || [ -n "$pkg" ]; do
    # 忽略空行和以#开头的注释行
    if [ -z "$pkg" ] || [[ "$pkg" == \#* ]]; then
      continue
    fi
    
    # 去除可能的引号和空白
    pkg=$(echo "$pkg" | sed 's/^[[:space:]"'"'"']*//;s/[[:space:]"'"'"']*$//')
    
    # 更新进度
    ((current_line++))
    printf "处理中... [%d/%d] %s\n" "$current_line" "$total_lines" "$pkg"
    
    # 查找顶层依赖
    find_top_package "$pkg" "$output_mode" "$output_file"
  done < "$input_file"
  
  echo "✅ 处理完成，结果已保存到: $output_file"
}

# 解析命令行参数
PACKAGE=""
INPUT_FILE=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--package)
      PACKAGE="$2"
      shift 2
      ;;
    -f|--file)
      INPUT_FILE="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      # 处理没有选项的单个参数作为包名
      if [ -z "$PACKAGE" ]; then
        PACKAGE="$1"
      else
        echo "错误: 未知参数 $1"
        show_help
      fi
      shift
      ;;
  esac
done

# 根据输入参数执行对应操作
if [ -n "$INPUT_FILE" ]; then
  if [ ! -f "$INPUT_FILE" ]; then
    echo "错误: 输入文件 '$INPUT_FILE' 不存在"
    exit 1
  fi
  
  if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${INPUT_FILE%.*}_results.csv"
  fi
  
  process_csv_file "$INPUT_FILE" "$OUTPUT_FILE"
elif [ -n "$PACKAGE" ]; then
  if [ -n "$OUTPUT_FILE" ]; then
    echo "查询包,顶层包,依赖链" > "$OUTPUT_FILE"
    find_top_package "$PACKAGE" "csv" "$OUTPUT_FILE"
    echo "✅ 结果已保存到: $OUTPUT_FILE"
  else
    find_top_package "$PACKAGE" "console" ""
  fi
else
  echo "错误: 请指定包名或输入文件"
  show_help
fi
