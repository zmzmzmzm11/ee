# EveBox 安装部署与使用文档

## 项目简介

EveBox 是一个基于 Web 的 Suricata EVE 事件查看器和告警管理系统。它使用 Rust 编写后端，使用 SolidJS 编写前端，支持 Elasticsearch 和嵌入式 SQLite 两种数据库后端。

- **许可证**：MIT
- **版本**：0.25.0-dev
- **最低 Rust 版本**：1.85.0
- **最低 Node.js 版本**：v18+

## 目录

1. [环境要求](#环境要求)
2. [快速开始](#快速开始)
3. [从源码编译](#从源码编译)
4. [配置说明](#配置说明)
5. [运行模式](#运行模式)
6. [用户认证](#用户认证)
7. [管理功能](#管理功能)
8. [CLI 命令参考](#cli-命令参考)
9. [开发环境搭建](#开发环境搭建)
10. [常见问题](#常见问题)

---

## 环境要求

| 组件 | 要求 |
|------|------|
| Rust | 1.85.0 或更高 |
| Node.js | v18+ |
| 数据库 | Elasticsearch 7.10+ 或 嵌入式 SQLite |
| 浏览器 | 现代浏览器（Chrome/Firefox/Edge） |
| Suricata | 用于生成告警和事件数据 |
| npm | 用于构建前端 |

### 可选组件

- **Java JDK 17**：仅当需要本地运行 Elasticsearch 时
- **Python 3**：仅当需要使用 Suricata 模拟器进行开发测试时
- **Docker / Podman**：用于 EveCtl 部署方式

---

## 快速开始

### 下载预编译版本

从 GitHub 发布页面下载对应平台的二进制文件，直接运行：

```bash
# Elasticsearch 后端
./evebox server -e http://localhost:9200

# SQLite 后端
./evebox server --datastore sqlite --input /var/log/suricata/eve.json
```

然后访问 **http://localhost:5636**。

### Docker 部署

```bash
docker pull jasonish/evebox:latest
docker run -it -p 5636:5636 jasonish/evebox:latest -e http://elasticsearch:9200
```

---

## 从源码编译

### 1. 克隆仓库

```bash
git clone https://github.com/jasonish/evebox
cd evebox
```

### 2. 构建前端

```bash
cd webapp
npm ci
npm run build
cd ..
```

### 3. 构建后端

```bash
cargo build    # 开发版本（debug 模式）
cargo build --release   # 发布版本（优化模式）
```

二进制文件位于：
- Debug: `target/debug/evebox` (Linux/Mac) 或 `target/debug/evebox.exe` (Windows)
- Release: `target/release/evebox` (Linux/Mac) 或 `target/release/evebox.exe` (Windows)

### 4. 使用 Makefile 一键构建

```bash
# 构建开发版本
make

# 构建发布版本并打包
make dist
```

构建产物在 `dist/` 目录下，为 zip 格式。

---

## 配置说明

EveBox 支持三种配置方式：

1. **命令行参数**：直接在命令行中指定
2. **配置文件**：使用 YAML 配置文件
3. **环境变量**：通过环境变量设置

### 配置文件示例

创建 `evebox.yaml`：

```yaml
# 数据目录（存储数据库、证书等）
data-directory: ./data

# HTTP 服务配置
http:
  host: 127.0.0.1
  port: 5636
  tls:
    enabled: false
    # certificate: ./certs/server.pem
    # key: ./certs/server-key.pem
  reverse-proxy: false     # 如果使用反向代理则设为 true
  request-logging: false   # 是否记录 HTTP 请求日志

# 用户认证
authentication:
  required: true

# 数据库配置
database:
  type: elasticsearch      # elasticsearch 或 sqlite

  # Elasticsearch 配置
  elasticsearch:
    url: http://localhost:9200
    index: logstash
    disable-certificate-check: false
    ecs: false
    # username: elastic
    # password: changeme
    # cacert: /path/to/ca.pem

  # SQLite 配置
  retention:
    days: 7                # 事件保留天数，0 为禁用
    size: 20 GB            # 数据库最大大小

# 输入配置（SQLite 模式必备）
input:
  enabled: true
  paths:
    - /var/log/suricata/eve.json
  # rules:
  #   - /etc/suricata/rules/*.rules

# GeoIP 配置
geoip:
  disabled: false
  database: /usr/share/GeoIP/GeoLite2-City.mmdb

# 事件上下文服务（可选）
event-services:
  Scirius:
    name: Scirius
    url: https://scirius.example.com/search?q={{.src_ip}}
```

使用配置文件启动：

```bash
./evebox server -c evebox.yaml
```

### 主要环境变量

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `EVEBOX_HTTP_HOST` | 绑定的主机名/IP | `127.0.0.1` |
| `EVEBOX_HTTP_PORT` | 绑定的端口 | `5636` |
| `EVEBOX_ELASTICSEARCH_URL` | Elasticsearch URL | `http://localhost:9200` |
| `EVEBOX_ELASTICSEARCH_INDEX` | ES 索引前缀 | `logstash` |
| `EVEBOX_ELASTICSEARCH_USERNAME` | ES 用户名 | - |
| `EVEBOX_ELASTICSEARCH_PASSWORD` | ES 密码 | - |
| `EVEBOX_ELASTICSEARCH_ECS` | 开启 ECS 模式 | - |
| `EVEBOX_AUTHENTICATION_REQUIRED` | 开启认证 | - |
| `EVEBOX_HTTP_TLS_ENABLED` | 开启 TLS | - |
| `EVEBOX_DATA_DIRECTORY` | 数据目录 | - |
| `EVEBOX_CONFIG_DIRECTORY` | 配置目录 | - |

---

## 运行模式

### 模式一：EveBox Server + Elasticsearch

适用于已有 Elasticsearch 和 Logstash/Filebeat 的环境：

```bash
./evebox server -e http://elasticsearch:9200 -i logstash
```

EveBox 从 Elasticsearch 读取 Suricata 已写入的事件数据。

访问 **http://localhost:5636**。

### 模式二：EveBox Server + 嵌入式 SQLite

适用于中小规模部署，无需额外的 Elasticsearch：

```bash
./evebox server \
  --datastore sqlite \
  --data-directory /var/lib/evebox \
  --input /var/log/suricata/eve.json
```

EveBox 使用嵌入式 SQLite 存储事件数据，直接读取 Suricata 的 EVE JSON 文件。

### 模式三：Agent 模式

EveBox Agent 读取 EVE 文件并发送到 EveBox Server 或直接写入 Elasticsearch：

```bash
# 发送到 EveBox Server
./evebox agent --server http://evebox-server:5636 /var/log/suricata/eve.json

# 直接写入 Elasticsearch
./evebox agent --elasticsearch -e http://elasticsearch:9200 /var/log/suricata/eve.json
```

### 模式四：One-shot 模式

一次性导入 EVE JSON 文件进行临时分析：

```bash
./evebox oneshot /path/to/eve.json
```

此模式启动一个临时 Web 服务器，在浏览器中查看分析结果。

---

## 用户认证

### 首次启动

当 `authentication.required` 为 `true` 且数据库中没有用户时，EveBox 会自动创建一个管理员账号：

```
Created administrator username and password: username=admin, password=<随机12位密码>
```

**密码只打印一次**，请务必记录。

### 命令行管理用户

```bash
# 列出所有用户
./evebox config users ls

# 添加用户
./evebox config users add
# 交互式提示输入用户名和密码

# 或指定用户名和密码
./evebox config users add --username admin --password mypassword

# 删除用户
./evebox config users rm <用户名>

# 修改密码
./evebox config users passwd <用户名>
```

如果 CLI 报错 `--config-directory or --data-directory required`，需要指定数据目录：

```bash
# Linux/Mac
./evebox --data-directory /var/lib/evebox config users ls

# Windows（PowerShell）
.\evebox.exe --data-directory $env:LOCALAPPDATA\evebox\evebox\config config users ls
```

### Web 界面管理用户

以管理员账号登录后，进入 **Admin → Users** 页面，可以进行：

- **创建用户**：点击 "Create User" 按钮，填写用户名、密码（至少4个字符）和角色（admin/user）
- **删除用户**：点击用户行右侧的 "Delete" 按钮
- **重置密码**：点击用户行右侧的 "Reset Password" 按钮

### 角色说明

| 角色 | 权限 |
|------|------|
| **admin** | 可以创建/删除用户、管理过滤器、管理 Elasticsearch 配置、更新 JA4 数据库 |
| **user** | 查看告警、事件、仪表盘等常规功能 |

---

## 管理功能

### 管理员页面入口

以管理员账号登录后，导航栏会出现 **Admin** 菜单，包含：

1. **Users**：用户管理（创建、删除、重置密码）
2. **Filters**：自动归档过滤器管理
3. **Elasticsearch**：索引管理和状态查看

### 自动归档过滤器

在 **Admin → Filters** 页面可以添加自动归档规则。当匹配条件的事件进入系统时，会自动归档。

过滤器条件包括：
- Sensor（传感器名称）
- Source IP（源 IP）
- Destination IP（目标 IP）
- Signature ID（签名 ID）

### JA4 指纹数据库

在 **Admin** 页面可以更新 JA4 指纹数据库，用于 TLS 指纹识别。

---

## CLI 命令参考

### 全局参数

| 参数 | 短参数 | 说明 |
|------|--------|------|
| `--verbose` | `-v` | 增加日志详细程度（-v=DEBUG, -vv=TRACE） |
| `--data-directory <DIR>` | `-D` | 数据目录路径 |
| `--config-directory <DIR>` | `-C` | 配置目录路径 |

### server 子命令

| 参数 | 短参数 | 默认值 | 说明 |
|------|--------|--------|------|
| `--config <FILE>` | `-c` | - | 配置文件路径 |
| `--host <HOST>` | - | `127.0.0.1` | 绑定地址 |
| `--port <PORT>` | `-p` | `5636` | 绑定端口 |
| `--elasticsearch <URL>` | `-e` | `http://localhost:9200` | ES URL |
| `--database <TYPE>` | - | `elasticsearch` | 数据库类型 |
| `--index <NAME>` | `-i` | `logstash` | ES 索引前缀 |
| `--datastore <TYPE>` | - | - | 同上（别名） |
| `--input <FILE>` | - | - | EVE 输入文件 |
| `--no-auth` | - | - | 禁用认证 |
| `--no-tls` | - | - | 禁用 TLS |
| `--sqlite` | - | - | 使用 SQLite |

### config users 子命令

```bash
evebox config users add           # 添加用户
evebox config users ls            # 列出用户
evebox config users rm <name>     # 删除用户
evebox config users passwd <name> # 修改密码
```

### elastic 子命令

```bash
evebox elastic info                          # ES 信息
evebox elastic set-field-limit               # 设置字段限制
evebox elastic delete <index> <days>         # 删除旧索引
```

### sqlite 子命令

```bash
evebox sqlite dump <file>                           # 导出事件
evebox sqlite load --input <evt.json> <file>        # 导入 EVE 文件
evebox sqlite info <file>                           # 数据库信息
evebox sqlite fts enable <file>                     # 启用全文搜索
evebox sqlite optimize <file>                       # 优化数据库
evebox sqlite vacuum <file>                         # 清理数据库
```

---

## 开发环境搭建

### 本地完整开发环境

项目提供了一键启动脚本，用于搭建完整的本地开发环境（Elasticsearch + Suricata 模拟器 + EveBox）。

#### Windows（PowerShell）

```powershell
.\control.ps1 start
```

#### Windows（Git Bash）

```bash
./control.sh start
```

脚本会依次启动：
1. Elasticsearch 7.17.28（端口 9200）
2. Suricata EVE 事件模拟器（生成测试数据到 `data/suricata-eve.json`）
3. EveBox Server（端口 5636）

其他命令：

```powershell
.\control.ps1 stop      # 停止所有组件
.\control.ps1 restart   # 重启所有组件
.\control.ps1 status    # 查看运行状态
```

### 前端开发

```bash
cd webapp

# 安装依赖
npm ci

# 启动开发服务器（热更新，端口 3636）
npm run dev

# 构建生产版本
npm run build

# 代码格式化
npm run fmt
```

Vite 开发服务器会自动将 `/api` 请求代理到 `http://127.0.0.1:5636`。

### Suricata 模拟器

开发测试时可以使用模拟器生成 EVE 事件：

```bash
# 使用默认配置（输出到 data/suricata-eve.json，间隔 1.5 秒）
python tools/suricata_simulator.py

# 自定义配置
EVE_OUTPUT=./test-events.json EVE_INTERVAL=0.5 python tools/suricata_simulator.py
```

### 目录结构

```
evebox/
├── src/                    # Rust 后端源码
│   ├── bin/                # 入口程序
│   ├── cli/                # CLI 子命令
│   ├── server/             # HTTP 服务器
│   │   └── api/            # REST API 处理函数
│   ├── sqlite/             # SQLite 数据库操作
│   └── elastic/            # Elasticsearch 操作
├── webapp/                 # 前端源码
│   └── src/
│       ├── pages/
│       │   └── admin/      # 管理页面
│       ├── components/     # 公共组件
│       └── styles/         # 样式文件
├── resources/
│   ├── webapp/             # 编译后的前端文件（编译时嵌入二进制）
│   └── configdb/           # 数据库迁移脚本
├── examples/               # 示例配置文件
├── tools/                  # 开发工具
├── docker/                 # Docker 构建文件
└── control.ps1 / control.sh   # 开发环境控制脚本
```

---

## 常见问题

### Q: 启动后无法访问页面？

确保服务器绑定地址正确：
- `--host 127.0.0.1` 仅本机访问
- `--host 0.0.0.0` 允许外部访问（注意安全）

### Q: 忘记管理员密码怎么办？

通过 CLI 重置：

```bash
./evebox --data-directory <数据目录> config users passwd admin
```

数据目录默认位置：
- Linux: `/var/lib/evebox`
- Windows: `C:\Users\<用户名>\AppData\Local\evebox\evebox\config`

### Q: 认证开启但想创建一个新管理员？

先用 CLI 添加：

```bash
./evebox --data-directory <数据目录> config users add --username admin2 --password <密码>
```

然后登录 admin2，在 Web 界面中将其角色改为 admin（目前通过数据库直接操作）。

### Q: SQLite 模式下的性能如何？

对于中小规模部署（< 1000 events/s），SQLite 性能完全足够。SQLite 模式下不支持某些高级功能（如聚合视图），但基本的告警浏览、搜索、归档功能都可用。

### Q: 如何迁移从 Elasticsearch 到 SQLite？

目前没有直接的迁移工具。可以使用 `evebox agent` 将 EVE 文件同时写入两个后端，或者在切换后重新导入历史 EVE 文件：

```bash
./evebox sqlite load --input /var/log/suricata/eve.json /path/to/events.sqlite
```

### Q: 构建失败怎么处理？

1. 确保 Rust 版本 >= 1.85.0：`rustup update`
2. 确保 Node.js 版本 >= v18：`node --version`
3. 清理后重试：`make clean && make`
4. 如果在 Windows 上构建失败，检查是否缺少 CMake 或 OpenSSL 开发库。
