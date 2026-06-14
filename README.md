# EveBox — Suricata EVE 事件管理与告警系统

基于 [jasonish/evebox](https://github.com/jasonish/evebox) 二次开发，增加了用户角色管理、管理员控制台、一键启停脚本等功能。

> GitHub: https://github.com/zmzmzmzm11/ee

---

## 新增功能（相对 upstream）

| 功能 | 说明 |
|------|------|
| **用户角色管理** | admin/user 两种角色，基于角色的权限控制 |
| **管理员控制台** | Web 界面管理用户（创建/删除/重置密码）、自动归档过滤器、ES 索引 |
| **一键启停脚本** | `control.ps1` / `control.sh` 统一管理 ES + 模拟器 + EveBox |
| **Suricata 模拟器** | `tools/suricata_simulator.py` 生成测试 EVE 事件 |
| **修复与优化** | 表单验证提示可见性、NULL role 兼容、session 权限检查优化 |

## 原始功能

- Web 事件查看器，"收件箱"（Inbox）模式管理告警
- 事件搜索、过滤、归档、升级（Escalate）
- 支持 Elasticsearch 7.10+ 和嵌入式 SQLite 两种后端
- Agent 模式：采集 EVE 事件转发到 Server 或直接写 ES
- JA4 TLS 指纹识别、GeoIP 地理信息
- Docker 部署

---

## 环境要求

| 组件 | 要求 |
|------|------|
| Suricata | 生成 EVE 告警和事件 |
| Elasticsearch | 7.10+（外部数据库模式）或 嵌入式 SQLite |
| 浏览器 | Chrome / Firefox / Edge |

### 编译要求

| 组件 | 版本 |
|------|------|
| Rust | 1.85.0+ |
| Node.js | v18+ |

---

## 快速开始

### 下载预编译版本

```bash
./evebox server -e http://localhost:9200
```

浏览器访问 http://localhost:5636。

### Docker

```bash
docker pull jasonish/evebox:latest
docker run -it -p 5636:5636 jasonish/evebox:latest -e http://elasticsearch:9200
```

---

## 运行模式

### Server + Elasticsearch（生产环境）

```bash
evebox server -e http://elasticsearch:9200 -i logstash
```

### Server + SQLite（独立部署）

```bash
evebox server -D . --datastore sqlite --input /var/log/suricata/eve.json
```

### Agent 模式

```bash
evebox agent --server http://evebox-server:5636 /var/log/suricata/eve.json
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

### 前端开发模式

```bash
# 终端 1：启动后端
./target/debug/evebox server --datastore elasticsearch --no-auth --no-tls \
  -D ./data -e http://localhost:9200 -i evebox --input ./data/suricata-eve.json

# 终端 2：启动前端（热更新，端口 3636）
cd webapp && npm run dev
```

---

## 用户认证与角色管理

### 首次启动

认证开启且无用户时自动创建管理员：

```
Created administrator username and password: username=admin, password=<随机12位密码>
```

> ⚠ 密码仅打印一次，请务必记录！

### CLI 管理

```bash
./target/debug/evebox --data-directory ./data config users ls             # 列出用户
./target/debug/evebox --data-directory ./data config users add            # 添加用户
./target/debug/evebox --data-directory ./data config users rm <用户名>     # 删除用户
./target/debug/evebox --data-directory ./data config users passwd <用户名> # 修改密码
```

### Web 界面管理

以 admin 登录后 → **Admin → Users**：创建用户、删除用户、重置密码。

### 角色权限

| 功能 | admin | user |
|------|-------|------|
| 查看告警/事件 | ✓ | ✓ |
| 搜索过滤 | ✓ | ✓ |
| 归档/升级 | ✓ | ✓ |
| 用户管理 | ✓ | ✗ |
| 过滤器管理 | ✓ | ✗ |
| ES 索引管理 | ✓ | ✗ |

---

## CLI 命令参考

### server

| 参数 | 短 | 默认值 | 说明 |
|------|-----|--------|------|
| `--config <FILE>` | `-c` | - | YAML 配置 |
| `--host <HOST>` | - | `127.0.0.1` | 绑定地址 |
| `--port <PORT>` | `-p` | `5636` | 端口 |
| `--datastore <TYPE>` | - | `elasticsearch` | elasticsearch/sqlite |
| `--elasticsearch <URL>` | `-e` | `http://localhost:9200` | ES 地址 |
| `--index <NAME>` | `-i` | `logstash` | ES 索引前缀 |
| `--input <FILE>` | - | - | EVE 输入 |
| `-D <DIR>` | - | - | 数据目录 |
| `--no-auth` | - | - | 禁用认证 |
| `--no-tls` | - | - | 禁用 TLS |
| `-v` | - | - | 详细日志 |

### config users

```bash
evebox --data-directory <DIR> config users add|ls|rm|passwd [...]
```

### sqlite / elastic / oneshot / agent

```bash
evebox sqlite info|dump|load|fts|optimize <文件>
evebox elastic info|delete|set-field-limit
evebox oneshot <eve.json>
evebox agent --server <URL> <eve文件>
```

---

## 项目结构

```
ee/
├── src/                      # Rust 后端
│   ├── bin/evebox.rs         # 入口 + CLI
│   ├── server/api/admin.rs   # 管理员 API（用户 CRUD）
│   ├── server/main.rs        # 路由、Session、认证
│   ├── sqlite/configdb.rs    # 配置数据库
│   └── ...
├── webapp/src/               # SolidJS 前端
│   └── pages/admin/          # AdminUsers / AdminFilters / AdminElastic
├── resources/
│   ├── webapp/               # 编译后的前端（嵌入二进制）
│   └── configdb/migrations/  # 数据库迁移（含 0007_add_user_role）
├── tools/
│   └── suricata_simulator.py # Suricata EVE 事件模拟器
├── examples/                 # 配置示例
├── control.ps1               # PowerShell 统一控制脚本
├── control.sh                # Git Bash 控制脚本
├── start-all.ps1             # 启动全部组件
├── stop-all.ps1              # 停止全部组件
├── DEPLOY.md                 # 详细部署文档
└── Makefile
```

---

## 许可

MIT License. 基于 [jasonish/evebox](https://github.com/jasonish/evebox).
