# 文件完整性检查和对比工具使用说明

## 概述

`file_integrity_checker.sh` 是一个用于生成文件MD5校验和并对比两个Linux系统文件差异的工具。主要用于系统文件或库文件的变更检测。

## 功能特性

✅ 生成目录下所有文件的MD5校验和  
✅ 支持自定义扫描目录和输出文件名  
✅ 对比两个系统的差异文件列表  
✅ 完整的帮助信息和参数说明  
✅ 排除特定目录（如虚拟文件系统）  
✅ 彩色输出和进度显示  
✅ 详细的对比报告生成  

## 快速开始

### 1. 查看帮助信息

```bash
./file_integrity_checker.sh --help
```

### 2. 扫描指定目录

在**系统1**上执行：
```bash
./file_integrity_checker.sh -d /usr -o system1_usr.txt
```

在**系统2**上执行：
```bash
./file_integrity_checker.sh -d /usr -o system2_usr.txt
```

### 3. 对比两个系统的差异

```bash
./file_integrity_checker.sh -c system1_usr.txt system2_usr.txt
```

## 使用场景

### 场景1：检测系统关键目录变更

扫描 `/usr`、`/lib`、`/bin` 等系统目录，对比升级前后的变化：

```bash
# 升级前
./file_integrity_checker.sh -d /usr -o before_upgrade.txt

# 升级后
./file_integrity_checker.sh -d /usr -o after_upgrade.txt

# 对比差异
./file_integrity_checker.sh -c before_upgrade.txt after_upgrade.txt
```

### 场景2：扫描整个系统（排除虚拟文件系统）

```bash
./file_integrity_checker.sh \
  -d / \
  -o full_system.txt \
  -e /proc \
  -e /sys \
  -e /dev \
  -e /run \
  -e /tmp
```

### 场景3：对比两台服务器的文件一致性

在服务器A上：
```bash
./file_integrity_checker.sh -d /opt/application -o serverA.txt
```

在服务器B上：
```bash
./file_integrity_checker.sh -d /opt/application -o serverB.txt
```

将两个文件传输到同一台机器上对比：
```bash
./file_integrity_checker.sh -c serverA.txt serverB.txt
```

## 参数说明

| 参数 | 长选项 | 说明 | 示例 |
|-----|--------|------|------|
| -d | --dir | 指定扫描目录（默认: /） | `-d /usr` |
| -o | --output | 指定输出文件名（默认: file_checksums.txt） | `-o my_checksums.txt` |
| -c | --compare | 对比两个MD5文件 | `-c file1.txt file2.txt` |
| -e | --exclude | 排除匹配的目录（可多次使用） | `-e /proc -e /sys` |
| -h | --help | 显示帮助信息 | `--help` |
| -v | --version | 显示版本信息 | `--version` |

## 输出示例

### 生成MD5校验和输出

```
[INFO] 开始扫描目录: /usr
[INFO] 输出文件: usr_checksums.txt
[INFO] 正在计算文件MD5值...
已处理: 12500 个文件
[INFO] 正在排序结果...
[SUCCESS] 扫描完成!
[INFO] 处理文件数: 12543
[INFO] 耗时: 45秒
[INFO] 结果已保存到: usr_checksums.txt
```

### 对比差异输出

```
================================================================
文件完整性对比报告
================================================================
生成时间: 2025-12-17 13:40:40
系统1文件: system1.txt
系统2文件: system2.txt

----------------------------------------------------------------
1. 仅在系统1中存在的文件:
----------------------------------------------------------------
  /usr/lib/example1.so
  /usr/bin/deprecated-tool

----------------------------------------------------------------
2. 仅在系统2中存在的文件:
----------------------------------------------------------------
  /usr/lib/example2.so
  /usr/bin/new-feature

----------------------------------------------------------------
3. 两个系统都存在但MD5值不同的文件:
----------------------------------------------------------------
  /usr/bin/updated-app
    系统1 MD5: abc123...
    系统2 MD5: def456...

================================================================
对比统计汇总:
================================================================
仅在系统1存在: 2 个文件
仅在系统2存在: 2 个文件
MD5值不同: 1 个文件
完全相同: 12538 个文件
总差异数: 5
================================================================

[SUCCESS] 对比完成!
[INFO] 详细报告已保存到: comparison_report_20251217_134040.txt
[WARNING] 检测到 5 处文件差异
```

## 输出文件格式

生成的MD5校验和文件格式：

```
# 文件完整性校验报告
# 生成时间: 2025-12-17 13:40:40
# 扫描目录: /usr
# 主机名: server1
# 文件总数: 12543
# 错误数量: 0
# 耗时: 45秒
# ----------------------------------------
abc123def456...  /usr/bin/example1
def456abc123...  /usr/bin/example2
...
```

## 注意事项

1. **权限要求**：扫描系统目录需要root权限
   ```bash
   sudo ./file_integrity_checker.sh -d /usr -o usr.txt
   ```

2. **虚拟文件系统**：扫描根目录时务必排除虚拟文件系统
   - `/proc` - 进程信息
   - `/sys` - 系统信息
   - `/dev` - 设备文件
   - `/run` - 运行时数据

3. **磁盘空间**：确保有足够空间存储输出文件
   - 大型目录扫描可能生成较大的输出文件
   - 每10万个文件约需10-20MB存储空间

4. **执行时间**：扫描时间取决于文件数量和磁盘性能
   - 10万文件约需5-15分钟
   - SSD比HDD快3-5倍

5. **特殊文件**：工具会跳过无法读取的文件并记录警告

## 常见问题

### Q1: 如何只对比特定类型的文件？

可以先用grep过滤输出文件：

```bash
grep "\.so$" system1.txt > system1_libs.txt
grep "\.so$" system2.txt > system2_libs.txt
./file_integrity_checker.sh -c system1_libs.txt system2_libs.txt
```

### Q2: 扫描速度太慢怎么办？

1. 排除不需要的大目录
2. 只扫描关键目录而不是整个系统
3. 使用SSD存储临时文件

### Q3: 如何定期自动检测？

可以配合cron定时任务：

```bash
# 每天凌晨2点扫描一次
0 2 * * * /path/to/file_integrity_checker.sh -d /usr -o /backup/daily_$(date +\%Y\%m\%d).txt
```

### Q4: 对比报告太大如何处理？

报告保存为文本文件，可以：
- 使用less/more查看：`less comparison_report_*.txt`
- 只查看差异部分：`grep -A2 "系统1 MD5" comparison_report_*.txt`
- 压缩保存：`gzip comparison_report_*.txt`

## 高级用法

### 批量对比多个目录

```bash
#!/bin/bash
dirs=("/usr" "/lib" "/bin" "/sbin")
for dir in "${dirs[@]}"; do
    dirname=$(echo $dir | tr '/' '_')
    ./file_integrity_checker.sh -d "$dir" -o "system1${dirname}.txt"
done
```

### 集成到监控系统

脚本的退出码：
- `0` - 对比完全一致
- `2` - 检测到差异
- `1` - 执行错误

可以在监控脚本中检查退出码：

```bash
./file_integrity_checker.sh -c sys1.txt sys2.txt
if [ $? -eq 2 ]; then
    echo "警告：检测到系统文件差异！" | mail -s "系统完整性告警" admin@example.com
fi
```

## 版本信息

当前版本：1.0.0

查看版本：
```bash
./file_integrity_checker.sh --version
```

## 许可证

本工具为开源软件，可自由使用和修改。

## 技术支持

如遇问题，请检查：
1. 脚本是否有执行权限：`chmod +x file_integrity_checker.sh`
2. 系统是否安装了必要工具：`md5sum`, `find`, `sort`
3. 是否有足够的磁盘空间
4. 扫描目录的访问权限

---

**提示**：首次使用建议先在小目录上测试，熟悉工具后再扫描大型目录。
