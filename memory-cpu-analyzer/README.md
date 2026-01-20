# Memory and CPU Analyzer - 内存与CPU分析脚本

这是一个用于分析和记录 Debian/Ubuntu 等 Linux 系统内存和CPU使用情况的 Shell 脚本。

## 功能特性

- **系统信息**: 捕获操作系统版本、内核版本和数据收集时间。
- **内存概览**: 显示总内存、已用内存、共享内存(SHR)和使用率。
- **Swap使用情况**: 统计Swap空间的总量、已用量和使用率。
- **CPU概览**: 展示CPU的总体使用率，包括用户空间、系统空间和空闲百分比。
- **Top-N 进程**: 列出当前消耗资源最多的 N 个进程，包含CPU和内存的详细占用情况。
- **灵活排序**: 用户可以选择按内存（`mem`）或CPU（`cpu`）使用率对进程列表进行排序。
- **CSV 格式输出**: 将所有收集到的信息格式化为 CSV 文件，便于后续处理和分析。
- **灵活配置**: 通过命令行参数指定 Top-N 的数量、排序方式和输出文件。
- **报告合并**: 支持将两个独立的报告文件合并为一个，方便进行前后对比。

## 依赖

此脚本依赖一些标准的 Linux 命令。在大多数 Debian 发行版中，这些工具都是预装的。如果您的系统是最小化安装，请确保以下软件包已安装：

- `procps`: 提供 `free`, `ps`, `top` 命令，用于获取内存、进程和CPU信息。
- `coreutils`: 提供 `cat`, `head`, `tail`, `cut` 等基础工具。
- `gawk` (或 `mawk`): 提供 `awk` 命令，用于处理文本。
- `lsb-release`: (可选) 提供 `lsb_release` 命令，用于更精确地获取发行版信息。如果未安装，脚本会尝试从 `/etc/os-release` 文件中获取。

您可以使用以下命令安装它们：

```bash
sudo apt-get update
sudo apt-get install procps coreutils gawk lsb-release
```

## 使用方法

### 1. 授予执行权限

在使用脚本之前，您需要为其添加可执行权限。

```bash
chmod +x memory_analyzer.sh
```

### 2. 查看帮助信息

您可以随时运行 `-h` 或 `--help` 选项来查看所有可用的命令和示例。

```bash
./memory_analyzer.sh -h
```

### 3. 示例

#### 示例 1: 按内存占用生成报告并输出到屏幕

运行脚本，查看内存占用最高的 15 个进程。

```bash
# 查看内存占用最高的 15 个进程
./memory_analyzer.sh -n 15 -s mem
```

#### 示例 2: 按CPU占用生成报告并保存到文件

使用 `-s cpu` 指定按CPU使用率排序，并用 `-o` 参数将分析结果保存到一个 CSV 文件中。

```bash
# 记录CPU占用最高的 10 个进程到 report_cpu_usage.csv
./memory_analyzer.sh -n 10 -s cpu -o report_cpu_usage.csv

# 记录内存占用最高的 10 个进程到 report_mem_usage.csv
./memory_analyzer.sh -n 10 -s mem -o report_mem_usage.csv
```

#### 示例 3: 合并两个报告进行对比

当您有两个或多个报告文件时，可以使用 `-m` 参数将它们合并。这会在一个新的 CSV 文件中并排显示两个报告的内容，非常便于对比分析。

**注意**: 使用 `-m` 时，必须同时使用 `-o` 指定合并后的输出文件名。

```bash
# 将CPU和内存报告合并
./memory_analyzer.sh -m report_cpu_usage.csv,report_mem_usage.csv -o report_comparison.csv
```

生成的 `report_comparison.csv` 文件会包含两份报告的数据，左右并列，方便您在电子表格软件（如 LibreOffice Calc, Microsoft Excel）中查看和分析差异。

## 作者

- liujianqiang@uniontech.com
