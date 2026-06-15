# EveBox — Suricata EVE 事件管理与告警系统

EveBox 是一个基于 Web 的 Suricata EVE 事件查看器和告警管理系统，支持 Elasticsearch 和嵌入式 SQLite 两种后端。

> GitHub: https://github.com/zmzmzmzm11/ee

---

## 功能特性

- **事件管理**：Web 事件查看器，"收件箱"（Inbox）模式管理告警，支持归档、升级、评论
- **搜索过滤**：强大的事件搜索、过滤、聚合功能
- **双后端支持**：Elasticsearch 7.10+ 或嵌入式 SQLite，无需外部依赖即可运行
- **用户认证**：用户登录认证，admin/user 两种角色，基于角色的权限控制
- **管理员控制台**：Web 界面管理用户（创建/删除/重置密码）、自动归档过滤器、ES 索引管理
- **JA4 指纹识别**：TLS 指纹识别与数据库查询
- **GeoIP 支持**：MaxMind GeoLite2 地理信息集成
- **多种部署模式**：Server、Agent、One-shot、Docker
- **Agent 采集**：独立 Agent 进程采集 EVE 事件转发到 Server 或直接写入 ES

---

## 环境要求

| 组件 | 要求 |
|------|------|
| Suricata | 生成 EVE 告警和事件 |
| 数据库 | Elasticsearch 7.10+ 或 嵌入式 SQLite |
| 浏览器 | Chrome / Firefox / Edge 等现代浏览器 |

### 编译要求

| 组件 | 版本 |
|------|------|
| Rust | 1.85.0+ |
| Node.js | v18+ |

---

## 快速开始

### 直接运行

```bash
# Elasticsearch 后端
evebox server -e http://localhost:9200

# SQLite 后端
evebox server -D . --datastore sqlite --input /var/log/suricata/eve.json
```

浏览器访问 **http://localhost:5636**。

### Docker

```bash
docker pull ghcr.io/zmzmzmzm11/evebox:latest
docker run -it -p 5636:5636 ghcr.io/zmzmzmzm11/evebox:latest -e http://elasticsearch:9200
```

---

## 运行模式

### Server + Elasticsearch

适用于已有 Elasticsearch 和 Logstash/Filebeat 的生产环境：

```bash
evebox server -e http://elasticsearch:9200 -i logstash
```

### Server + SQLite

适用于中小规模部署，无需外部数据库：

```bash
evebox server -D /var/lib/evebox --datastore sqlite --input /var/log/suricata/eve.json
```

### Agent 模式

Agent 读取 EVE 文件并转发到 Server 或直接写入 ES：

```bash
# 转发到 EveBox Server
evebox agent --server http://evebox-server:5636 /var/log/suricata/eve.json

# 直接写入 Elasticsearch
evebox agent --elasticsearch -e http://es:9200 /var/log/suricata/eve.json
```

### One-shot 临时分析

```bash
evebox oneshot /path/to/eve.json
```

---

## 从源码编译

```bash
git clone https://github.com/zmzmzmzm11/ee.git
cd ee

# 构建前端
cd webapp
echo "export const GIT_REV = \"$(git rev-parse --short HEAD)\";" > src/gitrev.ts
npm ci && npm run build
cd ..

# 复制前端产物
rm -rf resources/webapp && cp -a webapp/dist resources/webapp

# 构建后端
cargo build              # Debug: target/debug/evebox (evebox.exe)
cargo build --release    # Release: target/release/evebox (evebox.exe)

# 或使用 Makefile 一键构建
make          # debug 版本
make dist     # release + 打包
```

---

## 本地开发环境

本项目 Windows 10 开发环境组件：

| 组件 | 路径/版本 | 端口 |
|------|----------|------|
| Elasticsearch | `elasticsearch/elasticsearch-7.17.28/` | 9200 |
| Suricata 模拟器 | `tools/suricata_simulator.py` | - |
| EveBox Server | `target/debug/evebox.exe` | 5636+ |
| Java JDK | `C:\Program Files\Java\jdk-17.0.18` | - |

### 一键启动

```powershell
.\control.ps1 start       # 启动 ES + 模拟器 + EveBox
.\control.ps1 stop        # 停止全部
.\control.ps1 status      # 查看状态
.\control.ps1             # 交互式菜单
```

```bash
./control.sh start        # Git Bash 环境
```

脚本自动检查前置条件、启动 Elasticsearch、启动 Suricata 模拟器、启动 EveBox Server 并打开浏览器。

### 前端开发模式

```bash
# 终端 1：启动后端
./target/debug/evebox server --datastore elasticsearch --no-auth --no-tls \
  -D ./data -e http://localhost:9200 -i evebox --input ./data/suricata-eve.json

# 终端 2：启动前端（热更新，端口 3636）
cd webapp && npm run dev

# 访问 http://localhost:3636
```

Vite 开发服务器自动将 `/api` 请求代理到后端 `http://127.0.0.1:5636`。

---

## 用户认证与角色管理

### 首次启动

认证开启且无用户时自动创建管理员账号，控制台打印：

```
Created administrator username and password: username=admin, password=<随机12位密码>
```

> ⚠ 密码仅打印一次，务必记录！

### CLI 管理

```bash
# 列出用户
./target/debug/evebox --data-directory ./data config users ls

# 添加用户
./target/debug/evebox --data-directory ./data config users add

# 指定用户名密码
./target/debug/evebox --data-directory ./data config users add --username admin --password mypass

# 删除用户
./target/debug/evebox --data-directory ./data config users rm <用户名>

# 修改密码
./target/debug/evebox --data-directory ./data config users passwd <用户名>
```

### Web 界面管理

以 admin 登录 → **Admin → Users**：

- **创建用户**：填写用户名、密码（≥4 字符）、选择角色（admin/user）
- **删除用户**：点击 Delete 按钮，确认后删除
- **重置密码**：点击 Reset Password，输入新密码

### 角色权限

| 功能 | admin | user |
|------|-------|------|
| 查看告警/事件 | ✓ | ✓ |
| 搜索过滤 | ✓ | ✓ |
| 归档/升级 | ✓ | ✓ |
| 仪表盘 | ✓ | ✓ |
| 用户管理 | ✓ | ✗ |
| 过滤器管理 | ✓ | ✗ |
| ES 索引管理 | ✓ | ✗ |
| JA4 数据库更新 | ✓ | ✗ |

---

## CLI 命令参考

### server 参数

| 参数 | 短 | 默认值 | 说明 |
|------|-----|--------|------|
| `--config <FILE>` | `-c` | - | YAML 配置文件 |
| `--host <HOST>` | - | `127.0.0.1` | 绑定地址 |
| `--port <PORT>` | `-p` | `5636` | 绑定端口 |
| `--datastore <TYPE>` | - | `elasticsearch` | elasticsearch / sqlite |
| `--elasticsearch <URL>` | `-e` | `http://localhost:9200` | ES URL |
| `--index <NAME>` | `-i` | `logstash` | ES 索引前缀 |
| `--input <FILE>` | - | - | EVE 输入文件 |
| `-D <DIR>` | - | - | 数据目录 |
| `--no-auth` | - | - | 禁用认证 |
| `--no-tls` | - | - | 禁用 TLS |
| `-v` / `-vv` | - | - | 详细日志 / 追踪日志 |

### config users

```bash
evebox --data-directory <DIR> config users add       # 添加用户
evebox --data-directory <DIR> config users ls        # 列出用户
evebox --data-directory <DIR> config users rm <用户名> # 删除用户
evebox --data-directory <DIR> config users passwd <用户名> # 修改密码
```

### 其他子命令

```bash
evebox sqlite info|dump|load|fts|optimize <文件>     # SQLite 管理
evebox elastic info|delete|set-field-limit            # ES 管理
evebox oneshot <eve.json>                             # 临时分析
evebox agent --server <URL> <eve文件>                 # Agent 采集
evebox update ja4db                                   # 更新 JA4 指纹库
evebox util eve2pcap --output <file> <inputs>         # EVE 转 PCAP
```

---

## 项目结构

```
ee/
├── src/                      # Rust 后端源码
│   ├── bin/evebox.rs         # 程序入口 + CLI 定义
│   ├── cli/                  # CLI 子命令（agent/config/elastic/sqlite）
│   ├── server/               # HTTP 服务器
│   │   ├── main.rs           # Axum 路由、Session、中间件
│   │   ├── session.rs        # Session 管理
│   │   └── api/              # REST API
│   │       ├── mod.rs        # 路由注册
│   │       ├── admin.rs      # 管理员 API（用户 CRUD、过滤器）
│   │       ├── login.rs      # 登录/登出
│   │       ├── alerts.rs     # 告警查询
│   │       └── ...
│   ├── sqlite/               # SQLite 操作
│   │   ├── configdb.rs       # 配置数据库（用户、过滤器、会话）
│   │   └── eventrepo.rs      # 事件存储
│   └── elastic/              # Elasticsearch 客户端
├── webapp/                   # 前端 SolidJS 源码
│   ├── src/
│   │   ├── App.tsx           # 路由 + 认证守卫
│   │   ├── Login.tsx         # 登录页面
│   │   ├── pages/admin/      # 管理页面
│   │   │   ├── AdminUsers.tsx     # 用户管理
│   │   │   ├── AdminFilters.tsx   # 过滤器管理
│   │   │   └── AdminElastic.tsx   # ES 管理
│   │   └── ...
│   └── vite.config.ts        # Vite 配置（含 API 代理）
├── resources/
│   ├── webapp/               # 编译后的前端（嵌入二进制）
│   └── configdb/migrations/  # 数据库迁移
├── tools/
│   └── suricata_simulator.py # Suricata EVE 事件模拟器
├── examples/                 # 示例配置
├── control.ps1               # PowerShell 控制脚本
├── control.sh                # Git Bash 控制脚本
├── start-all.ps1             # 一键启动
├── stop-all.ps1              # 一键停止
├── DEPLOY.md                 # 详细部署文档
└── Makefile
```

---

## 配置示例

```yaml
# evebox.yaml
data-directory: ./data

http:
  host: 127.0.0.1
  port: 5636

authentication:
  required: true

database:
  type: elasticsearch
  elasticsearch:
    url: http://localhost:9200
    index: evebox

input:
  enabled: true
  paths:
    - ./data/suricata-eve.json
```

```bash
evebox server -c evebox.yaml
```

---

## 常见问题

**Q: 忘记管理员密码？**

```bash
./target/debug/evebox --data-directory ./data config users passwd admin
```

**Q: "admin role required" 错误？**

当前用户无管理员权限，需使用 admin 账号登录。

**Q: "Failed to fetch" 错误？**

后端未运行或不可达。检查 `curl http://127.0.0.1:5636/api/version`。

**Q: 端口被占用？**

control.ps1 自动查找空闲端口。手动指定：`-p 15637`。

**Q: 查看数据库内容？**

```bash
sqlite3 data/config.sqlite
SELECT uuid, username, role FROM users WHERE username != '__system__';
```

---

## 许可

MIT License.
