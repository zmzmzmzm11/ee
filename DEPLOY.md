# EveBox 安装部署与使用文档

> 版本 0.25.0-dev | 2026年6月
>
> GitHub: https://github.com/zmzmzmzm11/ee
>
> 基于 [jasonish/evebox](https://github.com/jasonish/evebox) 二次开发

---

## 1. 项目简介

EveBox 是一个基于 Web 的 Suricata EVE 事件查看器和告警管理系统，使用 Rust 编写后端，SolidJS 编写前端。本项目在 upstream 基础上增加了用户角色管理（admin/user）、管理员控制台等功能。

| 属性 | 值 |
|------|-----|
| 仓库 | https://github.com/zmzmzmzm11/ee |
| 许可证 | MIT |
| 后端 | Rust 1.85.0+ (Axum 0.8) |
| 前端 | SolidJS + Vite + Bootstrap 5 |
| 数据库 | Elasticsearch 7.10+ 或 SQLite |

### 核心功能

- Web 事件查看器，"收件箱"（Inbox）模式管理告警
- 事件搜索、过滤、归档、升级（Escalate）
- 嵌入式 SQLite 支持，可单机运行
- **用户认证 + 角色权限管理（admin/user）**
- **管理员控制台：用户管理、过滤器、ES 管理**
- JA4 TLS 指纹识别、GeoIP 地理信息
- 多种部署模式：Server / Agent / One-shot / Docker

---

## 2. 本地开发环境

本项目在 Windows 10 上开发，组件布局：

| 组件 | 路径/版本 | 端口 |
|------|----------|------|
| Elasticsearch | elasticsearch/elasticsearch-7.17.28/ | 9200 |
| Suricata 模拟器 | tools/suricata_simulator.py | - |
| EveBox Server | target/debug/evebox.exe | 5636+ |
| Java JDK | C:\Program Files\Java\jdk-17.0.18 | - |
| Python 3 | 系统安装 | - |
| Node.js | v18+ | 3636 (dev) |

### 安装依赖

```bash
# 1) Rust
curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2) Node.js v18+ LTS
# 从 https://nodejs.org 下载安装

# 3) Java JDK 17 (运行 ES 需要)
# 从 https://adoptium.net 下载，安装到 C:\Program Files\Java\jdk-17.0.18

# 4) Python 3 (运行模拟器需要)
# 从 https://python.org 下载安装
```

### 克隆项目

```bash
git clone git@github.com:zmzmzmzm11/ee.git
cd ee
```

如 GitHub SSH 被墙，配置 `~/.ssh/config` 使用 443 端口：

```
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
```

---

## 3. 快速启动

### 一键启动（PowerShell，推荐）

```powershell
.\control.ps1 start       # 启动全部组件
.\control.ps1 stop        # 停止全部组件
.\control.ps1 restart     # 重启
.\control.ps1 status      # 查看状态
.\control.ps1             # 交互式菜单
```

脚本自动：检查前置条件 → 启动 ES → 启动模拟器 → 启动 EveBox → 打开浏览器。

### Git Bash

```bash
./control.sh start
./control.sh stop
./control.sh status
```

### 独立脚本

```powershell
.\start-all.ps1           # 仅启动
.\stop-all.ps1            # 仅停止
```

### 验证

```bash
curl http://localhost:9200/_cat/indices/evebox*?format=json
curl http://127.0.0.1:5636/api/version
curl http://127.0.0.1:5636/api/alerts | python -m json.tool
```

浏览器访问 **http://127.0.0.1:5636**。

---

## 4. 从源码编译

### 前端

```bash
cd webapp
npm ci
echo "export const GIT_REV = \"$(git rev-parse --short HEAD)\";" > src/gitrev.ts
npm run build
cd ..
```

### 后端

```bash
rm -rf resources/webapp
cp -a webapp/dist resources/webapp
cargo build              # Debug: target/debug/evebox.exe
cargo build --release    # Release: target/release/evebox.exe
```

### Makefile

```bash
make          # 一键构建 debug 版本
make dist     # 构建 release + 打包 zip
```

### 前端开发模式

```bash
# 终端 1: 启动后端
./target/debug/evebox server --datastore elasticsearch --no-auth --no-tls \
  -D ./data -e http://localhost:9200 -i evebox --input ./data/suricata-eve.json

# 终端 2: 启动前端（热更新）
cd webapp && npm run dev

# 访问 http://localhost:3636
```

---

## 5. 配置说明

### 本项目的启动命令

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
| --datastore | elasticsearch | 事件存储类型 |
| --no-auth | - | 禁用认证（开发） |
| --no-tls | - | 禁用 TLS |
| -D | ./data | 数据目录 |
| -e | http://localhost:9200 | ES 地址 |
| -i | evebox | 索引前缀 |
| --input | ./data/suricata-eve.json | EVE 输入 |
| -p | 5636 | 端口 |

### 配置文件方式

```yaml
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
./target/debug/evebox server -c evebox.yaml
```

---

## 6. 运行模式

### 开发模式：ES + 模拟器 + EveBox

```
Suricata 模拟器 → Elasticsearch ← EveBox Web Server
     (EVE 生成)   (localhost:9200)    (Web :5636)
```

模拟器以 ~1 条/1.5 秒的速率生成事件。

### 生产模式：Server + Elasticsearch

```bash
./evebox server -e http://elasticsearch:9200 -i logstash
```

### SQLite 独立模式

```bash
./evebox server --datastore sqlite -D ./data --input /var/log/suricata/eve.json
```

### Agent 模式

```bash
./evebox agent --server http://evebox-server:5636 /var/log/suricata/eve.json
```

### One-shot 临时分析

```bash
./evebox oneshot /path/to/eve.json
```

---

## 7. 用户认证与角色管理

本项目在 upstream 基础上增加了完整的角色管理功能。

### 首次启动

认证开启且无用户时自动创建管理员，控制台输出：

```
Created administrator username and password: username=admin, password=<随机12位密码>
```

**密码仅打印一次！**

### CLI 管理用户

```bash
# 列出用户
./target/debug/evebox --data-directory ./data config users ls

# 添加用户
./target/debug/evebox --data-directory ./data config users add

# 删除用户
./target/debug/evebox --data-directory ./data config users rm <用户名>

# 修改密码
./target/debug/evebox --data-directory ./data config users passwd <用户名>
```

### Web 界面管理

以 admin 登录 → **Admin → Users**：

| 操作 | 步骤 |
|------|------|
| 创建用户 | Create User → 填用户名+密码(≥4字符)+角色 → Create |
| 删除用户 | 点击 Delete → 确认 |
| 重置密码 | Reset Password → 输新密码 → 确认 |

验证错误信息会显示在弹窗内部（已修复 previous 的隐藏问题）。

### 角色权限

| 功能 | admin | user |
|------|-------|------|
| 查看告警/事件 | ✓ | ✓ |
| 搜索过滤 | ✓ | ✓ |
| 归档/升级 | ✓ | ✓ |
| 用户管理 | ✓ | ✗ |
| 过滤器管理 | ✓ | ✗ |
| ES 管理 | ✓ | ✗ |

---

## 8. 管理员功能

Admin 菜单包含：

- **Users** — 用户 CRUD、密码重置
- **Filters** — 自动归档规则管理（Sensor/IP/Signature）
- **Elasticsearch** — 索引查看、删除、JA4 数据库更新

---

## 9. CLI 命令参考

### server 参数

| 参数 | 短 | 默认值 | 说明 |
|------|-----|--------|------|
| --config | -c | - | YAML 配置文件 |
| --host | - | 127.0.0.1 | 绑定地址 |
| --port | -p | 5636 | 绑定端口 |
| --datastore | - | elasticsearch | elasticsearch/sqlite |
| --elasticsearch | -e | http://localhost:9200 | ES URL |
| --index | -i | logstash | ES 索引前缀 |
| --input | - | - | EVE 输入文件 |
| -D | - | - | 数据目录 |
| --no-auth | - | - | 禁用认证 |
| --no-tls | - | - | 禁用 TLS |
| -v | - | - | 详细日志 |

### config users

```bash
./evebox --data-directory <DIR> config users add|ls|rm|passwd
```

### sqlite

```bash
./evebox sqlite info|dump|load|fts|optimize <文件>
```

---

## 10. 项目目录结构

```
evebox/
├── src/                      # Rust 后端
│   ├── bin/evebox.rs         # 入口 + CLI
│   ├── server/api/admin.rs   # 管理员 API
│   ├── server/main.rs        # 路由、Session
│   ├── sqlite/configdb.rs    # 配置数据库
│   └── ...
├── webapp/src/               # 前端 SolidJS
│   └── pages/admin/          # AdminUsers, AdminFilters, AdminElastic
├── resources/
│   ├── webapp/               # 编译后的前端（嵌入二进制）
│   └── configdb/migrations/  # DB 迁移
├── tools/suricata_simulator.py
├── data/                     # 运行数据（gitignore）
├── control.ps1               # 统一控制脚本
├── control.sh                # Git Bash 控制
├── start-all.ps1 / stop-all.ps1
└── examples/                 # 配置示例
```

---

## 11. 常见问题

### Q1: "Failed to fetch" 错误

检查后端是否运行：`curl http://127.0.0.1:5636/api/version`。如使用 `npm run dev`（3636 端口），确保后端也在 5636 端口运行。

### Q2: "admin role required"

当前用户无管理员权限。用 admin 账号登录，或通过 CLI 重置密码：
```bash
./target/debug/evebox --data-directory ./data config users passwd admin
```

### Q3: 点击 Create 无反应

已在最新版本修复——错误提示现在显示在弹窗内部。如仍发生，强制刷新浏览器（Ctrl+Shift+R）。

### Q4: 忘记管理员密码

```bash
./target/debug/evebox --data-directory ./data config users passwd admin
```

### Q5: 端口被占用

control.ps1 自动查找空闲端口。手动指定：`-p 15637`。

### Q6: ES 启动失败

- 检查 JDK 17: `java -version`
- 确认路径: `C:\Program Files\Java\jdk-17.0.18`
- 查看日志: `elasticsearch/elasticsearch-7.17.28/logs/`

### Q7: 构建失败

- Rust ≥ 1.85.0: `rustup update`
- Node.js ≥ v18: `node --version`
- 先创建 `webapp/src/gitrev.ts`
- `cargo clean && make`

### Q8: 查看数据库

```bash
sqlite3 data/config.sqlite
SELECT uuid, username, role FROM users WHERE username != '__system__';
```
