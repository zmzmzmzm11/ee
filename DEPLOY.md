# EveBox 安装部署与使用文档

> 版本 0.25.0-dev | 2026年6月
>
> GitHub: https://github.com/zmzmzmzm11/ee

---

## 1. 项目简介

EveBox 是一个基于 Web 的 Suricata EVE 事件查看器和告警管理系统，使用 Rust 编写后端，SolidJS 编写前端，支持 Elasticsearch 和嵌入式 SQLite 两种数据库后端。

### 核心功能

- Web 事件查看器，"收件箱"（Inbox）模式管理告警
- 事件搜索、过滤、归档、升级（Escalate）、评论
- 嵌入式 SQLite 支持，可单机运行，无需外部数据库
- 用户认证与基于角色的权限管理（admin / user）
- 管理员控制台：用户管理、自动归档过滤器、ES 索引管理
- JA4 TLS 指纹识别、GeoIP 地理信息
- 多种部署模式：Server、Agent、One-shot、Docker

### 技术栈

| 属性 | 值 |
|------|-----|
| 许可证 | MIT |
| 当前版本 | 0.25.0-dev |
| 后端语言 | Rust (edition 2024，最低 1.85.0) |
| 前端框架 | SolidJS + Vite + Bootstrap 5 |
| Web 框架 | Axum 0.8 |
| 数据库 | Elasticsearch 7.10+ / 嵌入式 SQLite |

---

## 2. 环境要求

| 组件 | 要求 | 说明 |
|------|------|------|
| Rust | 1.85.0+ | 编译后端 |
| Node.js | v18+ | 构建前端 |
| Elasticsearch | 7.10+ | 外部数据库模式（可选） |
| SQLite | 嵌入式 | 内嵌模式（无需安装） |
| Suricata | 任意版本 | 生成 EVE 事件数据 |
| 浏览器 | Chrome / Firefox / Edge | 访问 Web 界面 |

### 可选依赖

- **Java JDK 17**：仅当需要本地运行 Elasticsearch 时
- **Python 3**：仅当使用 Suricata 模拟器进行开发测试时
- **Docker / Podman**：用于容器化部署

---

## 3. 快速开始

### 3.1 预编译版本

从 GitHub Releases 下载对应平台的二进制文件：

```bash
# Elasticsearch 后端
./evebox server -e http://localhost:9200

# SQLite 后端
./evebox server --datastore sqlite --input /var/log/suricata/eve.json
```

浏览器访问 **http://localhost:5636**。

### 3.2 Docker 部署

```bash
docker pull jasonish/evebox:latest
docker run -it -p 5636:5636 jasonish/evebox:latest -e http://elasticsearch:9200
```

### 3.3 Windows 开发环境一键启动

项目提供 PowerShell 脚本一键启动全部组件：

```powershell
.\control.ps1 start       # 启动 ES + 模拟器 + EveBox
.\control.ps1 stop        # 停止全部
.\control.ps1 status      # 查看状态
.\control.ps1             # 交互式菜单
```

```bash
./control.sh start        # Git Bash
```

### 3.4 验证数据流

```bash
curl http://localhost:9200/_cat/indices/evebox*?format=json
curl http://127.0.0.1:5636/api/version
curl http://127.0.0.1:5636/api/alerts | python -m json.tool
curl http://127.0.0.1:5636/api/sensors
curl http://127.0.0.1:5636/api/event_types
```

---

## 4. 从源码编译

### 4.1 克隆仓库

```bash
git clone https://github.com/zmzmzmzm11/ee.git
cd ee
```

### 4.2 构建前端

```bash
cd webapp
echo "export const GIT_REV = \"$(git rev-parse --short HEAD)\";" > src/gitrev.ts
npm ci
npm run build
cd ..
```

前端资源编译到 `webapp/dist/`，复制到 `resources/webapp/` 后由 Rust 编译时通过 rust-embed 嵌入二进制。

### 4.3 构建后端

```bash
rm -rf resources/webapp
cp -a webapp/dist resources/webapp
cargo build              # Debug: target/debug/evebox.exe
cargo build --release    # Release: target/release/evebox.exe
```

### 4.4 使用 Makefile

```bash
make          # 构建 debug 版本
make dist     # 构建 release + 打包 zip
```

### 4.5 前端开发模式

前端支持热更新（修改代码后浏览器自动刷新）：

```bash
# 终端 1：启动后端
./target/debug/evebox server --datastore elasticsearch --no-auth --no-tls \
  -D ./data -e http://localhost:9200 -i evebox --input ./data/suricata-eve.json

# 终端 2：启动前端（端口 3636）
cd webapp && npm run dev

# 访问 http://localhost:3636
```

Vite 开发服务器将 `/api` 请求代理到 `http://127.0.0.1:5636`。

---

## 5. 配置说明

### 5.1 命令行参数方式

这是本项目开发环境使用的启动命令：

```bash
./target/debug/evebox.exe server \
  --datastore elasticsearch \
  --no-auth --no-tls \
  -D ./data \
  -e http://localhost:9200 \
  -i evebox \
  --input ./data/suricata-eve.json \
  -p 5636
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `--datastore` | elasticsearch | 事件存储类型（elasticsearch / sqlite） |
| `--no-auth` | - | 禁用用户认证（开发模式） |
| `--no-tls` | - | 禁用 TLS（本地开发） |
| `-D` | ./data | 数据目录（存储配置、bookmark 等） |
| `-e` | http://localhost:9200 | Elasticsearch 地址 |
| `-i` | evebox | ES 索引前缀 |
| `--input` | ./data/suricata-eve.json | Suricata EVE 输入文件 |
| `-p` | 5636 | Web 服务端口 |

### 5.2 配置文件方式

创建 `evebox.yaml`：

```yaml
data-directory: ./data

http:
  host: 127.0.0.1
  port: 5636
  tls:
    enabled: false
  reverse-proxy: false
  request-logging: false

authentication:
  required: true

database:
  type: elasticsearch
  elasticsearch:
    url: http://localhost:9200
    index: evebox
    disable-certificate-check: false
    ecs: false

input:
  enabled: true
  paths:
    - ./data/suricata-eve.json

geoip:
  disabled: false
  database: /usr/share/GeoIP/GeoLite2-City.mmdb
```

```bash
./target/debug/evebox server -c evebox.yaml
```

### 5.3 主要环境变量

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `EVEBOX_HTTP_HOST` | 绑定的主机名/IP | `127.0.0.1` |
| `EVEBOX_HTTP_PORT` | 绑定的端口 | `5636` |
| `EVEBOX_DATA_DIRECTORY` | 数据目录 | - |
| `EVEBOX_ELASTICSEARCH_URL` | ES URL | `http://localhost:9200` |
| `EVEBOX_ELASTICSEARCH_INDEX` | ES 索引前缀 | `logstash` |
| `EVEBOX_AUTHENTICATION_REQUIRED` | 开启用户认证 | - |
| `EVEBOX_HTTP_TLS_ENABLED` | 开启 TLS | - |

---

## 6. 运行模式

### 6.1 开发模式：ES + Suricata 模拟器 + EveBox

本项目的默认开发运行模式，三组件联动：

```
Suricata 模拟器 ──▶ Elasticsearch ◀── EveBox Web Server
 (EVE 事件生成)    (localhost:9200)    (Web :5636)
```

- Suricata 模拟器持续生成 EVE 事件（约 1 条/1.5 秒）
- EveBox 读取 EVE 文件写入 ES（索引前缀 `evebox`）
- EveBox 提供 Web 界面读取 ES 中的事件数据

### 6.2 生产模式：Server + Elasticsearch

适用于已有 Suricata + ES + Filebeat/Logstash 的环境：

```bash
./evebox server -e http://elasticsearch:9200 -i logstash
```

### 6.3 独立模式：Server + SQLite

适用于中小规模部署，无需外部数据库：

```bash
./evebox server --datastore sqlite -D /var/lib/evebox --input /var/log/suricata/eve.json
```

### 6.4 Agent 模式

```bash
# 转发到 EveBox Server
./evebox agent --server http://evebox-server:5636 /var/log/suricata/eve.json

# 直接写入 Elasticsearch
./evebox agent --elasticsearch -e http://es:9200 /var/log/suricata/eve.json
```

### 6.5 One-shot 临时分析

```bash
./evebox oneshot /path/to/eve.json
```

---

## 7. 用户认证与角色管理

### 7.1 首次启动自动创建管理员

当认证开启且数据库无用户时，服务器自动创建管理员账号：

```
Created administrator username and password: username=admin, password=<随机12位密码>
```

> ⚠ 密码仅打印一次，务必记录！

### 7.2 CLI 管理用户

```bash
# 列出所有用户
./target/debug/evebox --data-directory ./data config users ls

# 交互式添加用户
./target/debug/evebox --data-directory ./data config users add

# 指定用户名密码
./target/debug/evebox --data-directory ./data config users add --username admin --password mypass

# 删除用户
./target/debug/evebox --data-directory ./data config users rm <用户名>

# 修改密码
./target/debug/evebox --data-directory ./data config users passwd <用户名>
```

如果 CLI 报错 `--config-directory or --data-directory required`，需手动指定数据目录：

```bash
# Linux / Mac
./evebox --data-directory /var/lib/evebox config users ls

# Windows
.\evebox.exe --data-directory "%LOCALAPPDATA%\evebox\evebox\config" config users ls
```

### 7.3 Web 界面管理用户

以管理员身份登录 → **Admin → Users**：

| 操作 | 步骤 |
|------|------|
| 创建用户 | "Create User" → 填用户名、密码（≥4字符）、角色 → Create |
| 删除用户 | 点击 "Delete" → 确认删除（不可撤销） |
| 重置密码 | "Reset Password" → 输入新密码 → 确认 |

创建用户验证规则：
- 用户名不能为空
- 密码至少 4 个字符
- 角色必须选择 admin 或 user
- 验证失败时错误信息显示在弹窗内部

### 7.4 角色权限说明

| 功能 | admin | user |
|------|-------|------|
| 查看告警/事件 | ✓ | ✓ |
| 搜索过滤 | ✓ | ✓ |
| 归档/升级/评论 | ✓ | ✓ |
| 仪表盘 | ✓ | ✓ |
| 用户管理（增删改） | ✓ | ✗ |
| 自动归档过滤器 | ✓ | ✗ |
| ES 索引管理 | ✓ | ✗ |
| JA4 数据库更新 | ✓ | ✗ |

---

## 8. 管理员功能

以管理员登录后，导航栏出现 **Admin** 菜单：

### 8.1 Users（用户管理）

- 用户列表：显示用户名、角色标签（admin=红色、user=蓝色）
- 创建用户：弹窗表单，设置用户名、密码、角色
- 删除用户：点击删除按钮确认
- 重置密码：在弹窗中输入新密码

### 8.2 Filters（自动归档过滤器）

- 添加自动归档规则，匹配条件的事件自动归档
- 条件：Sensor / Source IP / Destination IP / Signature ID
- 支持 `*` 通配符匹配所有
- 过滤器存储在 `config.sqlite` 的 `filters` 表中

### 8.3 Elasticsearch（ES 管理）

- 查看 ES 索引信息和状态
- 删除指定天数之前的旧索引
- 更新 JA4 指纹数据库

---

## 9. CLI 命令参考

### 9.1 全局参数

| 参数 | 短参数 | 说明 |
|------|--------|------|
| `--verbose` | `-v` | 详细日志（`-v`=DEBUG，`-vv`=TRACE） |
| `--data-directory <DIR>` | `-D` | 数据目录路径 |
| `--config-directory <DIR>` | `-C` | 配置目录路径 |

### 9.2 server 子命令

| 参数 | 短 | 默认值 | 说明 |
|------|-----|--------|------|
| `--config <FILE>` | `-c` | - | YAML 配置文件 |
| `--host <HOST>` | - | `127.0.0.1` | 绑定地址 |
| `--port <PORT>` | `-p` | `5636` | 绑定端口 |
| `--datastore <TYPE>` | - | `elasticsearch` | elasticsearch / sqlite |
| `--elasticsearch <URL>` | `-e` | `http://localhost:9200` | ES URL |
| `--index <NAME>` | `-i` | `logstash` | ES 索引前缀 |
| `--input <FILE>` | - | - | EVE 输入文件 |
| `--no-auth` | - | - | 禁用认证 |
| `--no-tls` | - | - | 禁用 TLS |
| `--sqlite` | - | - | SQLite 快捷方式 |

### 9.3 config users 子命令

```bash
./evebox --data-directory <DIR> config users add       # 添加用户
./evebox --data-directory <DIR> config users ls        # 列出用户
./evebox --data-directory <DIR> config users rm <用户名> # 删除用户
./evebox --data-directory <DIR> config users passwd <用户名> # 修改密码
```

### 9.4 sqlite 常用命令

```bash
./evebox sqlite dump <文件>                            # 导出事件
./evebox sqlite load --input <evt.json> <文件>         # 导入 EVE 文件
./evebox sqlite info <文件>                            # 数据库信息
./evebox sqlite fts enable <文件>                      # 启用全文搜索
./evebox sqlite optimize <文件>                        # 优化数据库
./evebox sqlite vacuum <文件>                          # 清理数据库
```

### 9.5 elastic 子命令

```bash
./evebox elastic info                                  # ES 信息
./evebox elastic set-field-limit                       # 设置字段限制
./evebox elastic delete <index> <days>                 # 删除旧索引
```

### 9.6 其他子命令

```bash
./evebox oneshot <eve.json>                            # 临时分析
./evebox agent --server <URL> <eve文件>                 # Agent 采集
./evebox update ja4db                                  # 更新 JA4 指纹库
./evebox util eve2pcap --output <file> <inputs>         # EVE 转 PCAP
```

---

## 10. 开发环境搭建

### 10.1 一键启动

```powershell
.\control.ps1 start       # 启动全部组件
.\control.ps1 stop        # 停止全部组件
.\control.ps1 restart     # 重启全部组件
.\control.ps1 status      # 查看运行状态
```

脚本执行流程：
1. 检查前置条件（evebox.exe、模拟器脚本、Java）
2. 启动 Elasticsearch（如未运行）并等待就绪
3. 启动 Suricata EVE 事件模拟器
4. 启动 EveBox Server 并自动打开浏览器

### 10.2 Suricata 模拟器

开发测试时使用模拟器生成 EVE 事件：

```bash
# 默认配置
python tools/suricata_simulator.py

# 自定义输出路径和速度
EVE_OUTPUT=./test-events.json EVE_INTERVAL=0.5 python tools/suricata_simulator.py
```

### 10.3 项目目录结构

```
ee/
├── src/                      # Rust 后端源码
│   ├── bin/evebox.rs         # 程序入口，CLI 定义
│   ├── cli/                  # CLI 子命令
│   ├── server/               # HTTP 服务器
│   │   ├── main.rs           # Axum 路由、Session、中间件
│   │   ├── session.rs        # Session 管理
│   │   └── api/              # REST API
│   │       ├── mod.rs        # 路由注册
│   │       ├── admin.rs      # 管理员 API（用户CRUD、过滤器）
│   │       ├── login.rs      # 登录/登出
│   │       └── ...
│   ├── sqlite/               # SQLite 操作
│   │   ├── configdb.rs       # 配置数据库
│   │   └── eventrepo.rs      # 事件存储
│   └── elastic/              # ES 客户端
├── webapp/                   # 前端 SolidJS 源码
│   ├── src/
│   │   ├── App.tsx           # 路由 + 认证守卫
│   │   └── pages/admin/      # 管理页面组件
│   └── vite.config.ts        # Vite 配置
├── resources/
│   ├── webapp/               # 编译后的前端（嵌入二进制）
│   └── configdb/migrations/  # 数据库迁移（含 0007_add_user_role）
├── tools/suricata_simulator.py
├── examples/                 # 示例配置
├── control.ps1 / control.sh  # 控制脚本
├── start-all.ps1 / stop-all.ps1
└── Makefile
```

---

## 11. 常见问题

### Q1: "Failed to fetch" 错误

后端未运行或不可达：

```bash
curl http://127.0.0.1:5636/api/version
```

如果使用 `npm run dev`（3636 端口），确保后端也在 5636 端口运行。

### Q2: "admin role required"

当前用户无管理员权限。使用 admin 账号登录，或通过 CLI 重置密码：

```bash
./target/debug/evebox --data-directory ./data config users passwd admin
```

### Q3: 点击 Create 按钮无反应

验证错误现在显示在弹窗内部。如仍无反应，强制刷新浏览器（Ctrl+Shift+R）清除 JS 缓存。

### Q4: 忘记管理员密码

```bash
./target/debug/evebox --data-directory ./data config users passwd admin
```

输入新密码（至少 4 个字符）即可。

### Q5: 端口 5636 被占用

`control.ps1` 自动查找 5636-5649 范围内的空闲端口。手动指定：

```bash
./target/debug/evebox server -p 15637 ...
```

### Q6: Elasticsearch 启动失败

- 检查 JDK 17：`java -version`
- 确认路径：`C:\Program Files\Java\jdk-17.0.18`
- 查看日志：`elasticsearch/elasticsearch-7.17.28/logs/`

### Q7: 构建失败

- Rust 版本 ≥ 1.85.0：`rustup update`
- Node.js 版本 ≥ v18：`node --version`
- 先创建 `webapp/src/gitrev.ts`
- 清理重试：`cargo clean && make`

### Q8: 查看数据库内容

```bash
sqlite3 data/config.sqlite

-- 查看用户
SELECT uuid, username, role FROM users WHERE username != '__system__';

-- 查看过滤器
SELECT * FROM filters;

-- 查看会话
SELECT * FROM sessions;
```

### Q9: 如何开启/关闭用户认证？

- 命令行：加 `--no-auth` 禁用，不加则默认启用
- 配置文件：`authentication.required: true/false`
- 环境变量：`EVEBOX_AUTHENTICATION_REQUIRED=true`

### Q10: 反向代理部署

在配置文件中设置 `http.reverse-proxy: true`，确保反向代理转发 `X-Forwarded-For` 头部和 WebSocket 连接（SSE 实时更新需要）。
