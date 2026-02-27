# Remote Log Downloader MCP Server

这是一个 MCP (Model Context Protocol) 服务器，用于通过 AI 助手（如 Claude）下载远程设备的日志文件。

## 功能

提供 `download_daily_logs` 工具，可以：
- 根据设备名称选择设备（支持模糊匹配）
- 下载指定日期的日志（Client 和 Backend）
- 自动处理日志路径（今天/昨天/更早）
- 返回下载链接供 AI 下载和分析

## 配置

### 1. 服务器端配置

编辑 `remote-file-agent-server/config.yaml`：

```yaml
mcp:
  enabled: true
  auth_token: "uMkeLj8m+6HYmldwdYkqBIA9fYfeBUdgPdIfOLDKBlw="
  session_timeout_minutes: 30
  endpoint: "/mcp"
```

### 2. MCP 配置

编辑 `.mcp.json`（项目根目录）：

```json
{
  "mcpServers": {
    "remote-log-downloader": {
      "command": "C:\Program Files\Python314\python.exe",
      "args": ["C:\Users\Administrator\Documents\canxingjian2025\packages\remote-file-agent\scripts\log_downloader_mcp.py"],
      "env": {
        "MCP_URL": "http://112.84.176.170:18120/mcp",
        "MCP_TOKEN": "uMkeLj8m+6HYmldwdYkqBIA9fYfeBUdgPdIfOLDKBlw="
      }
    }
  }
}
```

**重要**：确保 `MCP_TOKEN` 与服务器配置中的 `auth_token` 一致！

## 使用方法

### 启动服务器

```bash
cd remote-file-agent-server
./bin/server.exe
```

### 使用 Claude

直接向 Claude 提问：

```
"帮我下载西小口店昨天的日志"
```

Claude 会自动：
1. 调用 `download_daily_logs` 工具
2. 选择设备（模糊匹配"西小口店"）
3. 获取昨天的 Client 和 Backend 日志下载链接
4. 下载并分析日志内容

### 其他示例

```
"下载西小口店今天的 Client 日志"
"获取西小口店 3 天前的日志"
"下载西小口店 2026-02-26 的所有日志"
```

## 工具参数

### download_daily_logs

- `device_name` (必需): 设备名称，支持模糊匹配
  - 例如："西小口店"、"西小口"、"xixiaokou"
  
- `days_ago` (可选，默认=1): 几天前的日志
  - 0 = 今天
  - 1 = 昨天
  - 2 = 前天
  - ...

- `log_types` (可选，默认=["client", "backend"]): 日志类型
  - "client" - Client 日志
  - "backend" - Backend 日志

## 返回格式

```json
[
  {
    "log_type": "client",
    "date": "2026-02-26",
    "path": "Client/logs/2026-02-26",
    "exists": true,
    "download_url": "http://112.84.176.170:18120/api/objects/download/abc123",
    "file_name": "Windows_西小口店_10.1.23.120-client-logs-2026-02-26.zip",
    "file_size": 2621440,
    "compressed": true,
    "expires_at": "2026-02-27T10:40:00Z"
  },
  {
    "log_type": "backend",
    "date": "2026-02-26",
    "path": "Backend/log/2026-02-26.zip",
    "exists": true,
    "download_url": "http://112.84.176.170:18120/api/objects/download/def456",
    "file_name": "Windows_西小口店_10.1.23.120-backend-logs-2026-02-26.zip",
    "file_size": 1048576,
    "compressed": false,
    "expires_at": "2026-02-27T10:40:00Z"
  }
]
```

## 日志路径规则

### Client 日志
- 路径：`Client/logs/YYYY-MM-DD/`
- 格式：每小时一个文件 `raw-YYYY-MM-DD-HH-0001.log`

### Backend 日志
- 今天：`Backend/log/YYYY-MM-DD/`（文件夹）
- 昨天及更早：`Backend/log/YYYY-MM-DD.zip`（压缩文件）

## 故障排除

### "MCP_URL and MCP_TOKEN environment variables are required"
- 检查 `.mcp.json` 中的 `env` 配置
- 确保 `MCP_URL` 和 `MCP_TOKEN` 都已设置

### "RPC error: Unauthorized"
- 检查 `MCP_TOKEN` 是否与服务器的 `auth_token` 一致
- 确保 token 没有多余的空格或换行

### "Device not found"
- 使用 `list_devices` 查看可用设备
- 检查设备名称拼写
- 尝试使用部分名称（模糊匹配）

### "Path does not exist"
- 检查日期是否正确
- 确认设备上确实有该日期的日志
- 查看日志路径规则

## 依赖

- Python 3.14+
- requests 库：`pip install requests`

## 安全注意事项

- 不要将 `MCP_TOKEN` 提交到版本控制
- 定期更换 token
- 使用 HTTPS（生产环境）
- 限制 MCP 端点的访问权限
