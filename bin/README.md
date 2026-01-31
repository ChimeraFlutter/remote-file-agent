# Server 启动指南

本目录包含预编译的 Remote File Agent Server。

## 文件说明

```
bin/
├── server                  # 服务器可执行文件 (macOS)
├── config.yaml.example     # 配置文件模板
├── migrations/             # 数据库迁移文件
└── web/                    # Web 管理台静态文件
```

## 快速启动

### 1. 创建配置文件

```bash
cd bin
cp config.yaml.example config.yaml
```

### 2. 修改配置（可选）

编辑 `config.yaml`：

```yaml
server:
  host: "0.0.0.0"
  port: 18120
  admin_password: "Acewill2025"              # 修改管理台密码
  agent_enroll_token: "your-secret-token"    # 修改 Agent 注册令牌
```

**重要**: 请修改 `agent_enroll_token`，并确保 Flutter Agent 使用相同的令牌。

### 3. 启动服务器

```bash
./server
```

服务器将在 `http://localhost:18120` 启动。

### 4. 验证运行状态

```bash
curl http://localhost:18120/health
```

预期输出：
```json
{"status":"ok","version":"1.0.0"}
```

## Web 管理台

启动服务器后，访问：

- **登录页面**: http://localhost:18120/admin/login.html
- **密码**: 配置文件中的 `admin_password`（默认 `Acewill2025`）

## 配合 Flutter Agent 使用

1. 确保 Server 的 `agent_enroll_token` 与 Agent 配置一致
2. Agent 连接地址: `ws://localhost:18120/ws/agent`

示例 Agent 配置：

```dart
final agent = await RemoteFileAgent.create(
  serverUrl: 'ws://localhost:18120/ws/agent',
  enrollToken: 'your-secret-token',  // 与 Server 配置一致
  allowedPaths: ['/Users/mac/Desktop'],
);
```

## 数据存储

服务器运行后会自动创建：

- `data/meta.sqlite` - SQLite 数据库
- `data/objects/` - 上传文件存储目录

## 停止服务器

按 `Ctrl+C` 停止服务器。

## 故障排除

### 端口被占用

```bash
# 查看占用端口的进程
lsof -i :18120

# 终止进程
kill -9 <PID>
```

### 权限问题

```bash
chmod +x ./server
```

### 数据库错误

删除 `data/` 目录重新启动，将自动重建数据库。
