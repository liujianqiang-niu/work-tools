# Work-Tools

一套用于提高工作效率的实用工具集合。

## 工具列表

### getdepends

`getdepends` 是一个用于分析 Debian/Ubuntu 包依赖关系的脚本工具，可以查找软件包的顶层直接依赖。

#### 功能特点

- 查找单个包的顶层直接依赖包
- 考虑 Depends 和 PreDepends 依赖关系
- 当检测到顶层依赖来自推荐依赖(Recommends)时，认定被推荐的包为顶层依赖
- 支持批量处理 CSV 文件输入输出
- 自动检测循环依赖
- 识别特殊依赖情况

#### 使用方法

```bash
# 查询单个包的顶层依赖
./getdepends/getdepends.sh -p package_name

# 从CSV文件批量查询并输出到文件
./getdepends/getdepends.sh -f input.csv -o output.csv

# 显示帮助信息
./getdepends/getdepends.sh -h
```

#### 参数说明

- `-p, --package <包名>` - 查询单个包的顶层依赖
- `-f, --file <CSV文件>` - 从CSV文件读取包名列表进行批量查询
- `-o, --output <输出文件>` - 将结果输出到CSV文件（默认输出到控制台）
- `-h, --help` - 显示帮助信息

#### CSV文件格式

输入格式：每行一个包名
输出格式：查询包,顶层包,依赖链

### file-integrity-check

`file-integrity-check` 包含用于检查文件完整性的脚本 `file_integrity_checker.sh`。该脚本会扫描指定目录下的文件，计算哈希（例如 sha256），并与保存的基线记录比较，以检测新增、删除或修改的文件。

#### 功能特点

- 计算并比较文件哈希（支持 sha256）
- 支持递归扫描目录
- 可输出差异报告或更新基线文件
- 详细用法和参数请见 `file-integrity-check/README.md`

#### 使用方法（示例）

```bash
# 添加可执行权限
chmod +x file-integrity-check/file_integrity_checker.sh

# 显示帮助（如果脚本支持 -h 或 --help）
./file-integrity-check/file_integrity_checker.sh -h

# 示例：扫描 /etc 并将基线保存到 baseline.txt
./file-integrity-check/file_integrity_checker.sh -s /etc -b baseline.txt

# 示例：比较当前扫描与已有基线
./file-integrity-check/file_integrity_checker.sh -c /etc -b baseline.txt
```

请参阅 `file-integrity-check/README.md` 获取更详细的参数说明和示例。

## 系统要求

- Debian/Ubuntu Linux 系统
- bash shell
- 已安装 aptitude 和 dpkg 工具

## 安装

```bash
# 克隆仓库
git clone https://github.com/yourusername/work-tools.git

# 添加执行权限
chmod +x work-tools/getdepends/getdepends.sh
```

## 贡献指南

欢迎对本项目进行贡献！请按照以下步骤：

1. Fork 本项目
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件

## 联系方式

项目维护者 - [liujianqiang](https://github.com/liujianqiang-niu)

项目链接：[https://github.com/liujianqiang-niu/work-tools](https://github.com/liujianqiang-niu/work-tools)
