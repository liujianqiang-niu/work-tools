#!/bin/bash

PID=${1:-2338}

echo "=== 进程 $PID 加载的SO文件映射到软件包和调试包 ==="

declare -A PKGS_SEEN
DBG_PKGS=""

while read so_path; do
    [ ! -f "$so_path" ] && continue
    
    pkg=$(dpkg -S "$so_path" 2>/dev/null | cut -d: -f1)
    [ -z "$pkg" ] && continue
    
    if [ -z "${PKGS_SEEN[$pkg]}" ]; then
        PKGS_SEEN[$pkg]=1
        
        dbgsym_pkg="${pkg}-dbgsym"
        dbg_pkg="${pkg}-dbg"
        
        if apt-cache show "$dbgsym_pkg" &>/dev/null; then
            dbg_info="$dbgsym_pkg"
            DBG_PKGS="$DBG_PKGS $dbgsym_pkg"
        elif apt-cache show "$dbg_pkg" &>/dev/null; then
            dbg_info="$dbg_pkg"
            DBG_PKGS="$DBG_PKGS $dbg_pkg"
        else
            dbg_info="N/A"
        fi
        
        printf "%-30s -> Debug: %-30s\n" "$pkg" "$dbg_info"
    fi
done < <(cat /proc/$PID/maps | grep -i "\.so" | awk '{print $6}' | sort -u)

echo ""
echo "=== 一键安装命令 ==="
if [ -n "$DBG_PKGS" ]; then
    echo "sudo apt install$(echo "$DBG_PKGS" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
else
    echo "# 未找到可用的调试包"
fi
