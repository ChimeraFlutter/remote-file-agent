#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MCP Server for Remote Log Downloader
Provides high-level tools for downloading device logs through the remote-file-agent MCP server.
Uses only standard library (urllib instead of requests).
"""

import sys
import json
import os
import urllib.request
import urllib.error
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
import ntpath  # For Windows path handling
import logging

# Ensure UTF-8 encoding for stdin/stdout on Windows
if sys.platform == 'win32':
    import io
    sys.stdin = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8')
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', line_buffering=True)
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', line_buffering=True)

# Configure logging
def setup_logging():
    """Setup logging to file with date/time based naming"""
    log_dir = r"C:\logs\remote-file-logs"
    now = datetime.now()
    # Windows compatible date format
    date_dir = now.strftime("%Y-%m-%d").replace("-0", "-").lstrip("0")
    if date_dir.startswith("-"):
        date_dir = "0" + date_dir
    # Simpler: just use the format that matches Golang
    date_dir = f"{now.year}-{now.month}-{now.day}"
    full_log_dir = os.path.join(log_dir, date_dir)
    os.makedirs(full_log_dir, exist_ok=True)

    hour = now.strftime("%H-00")
    log_file = os.path.join(full_log_dir, f"Python-{hour}.log")

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stderr)
        ]
    )
    return logging.getLogger(__name__)

logger = setup_logging()


class RemoteFileClient:
    """Client for calling the Go MCP server"""

    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip('/')
        self.token = token
        self.session_id = f"python-mcp-{datetime.now().timestamp()}"

    def _call_rpc(self, method: str, params: Dict[str, Any]) -> Any:
        """Call JSON-RPC method"""
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params
        }

        # Create request
        url = f"{self.base_url}/messages"
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "X-Session-ID": self.session_id
        }

        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(url, data=data, headers=headers, method='POST')

        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                result = json.loads(response.read().decode('utf-8'))

                if "error" in result:
                    raise Exception(f"RPC error: {result['error']}")

                return result.get("result")
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            raise Exception(f"HTTP {e.code}: {error_body}")
        except urllib.error.URLError as e:
            raise Exception(f"URL error: {e.reason}")

    def list_devices(self) -> List[Dict[str, Any]]:
        """List all online devices"""
        return self._call_rpc("list_devices", {})

    def select_device(self, device_name: str) -> Dict[str, Any]:
        """Select device by name"""
        return self._call_rpc("select_device", {"device_name": device_name})

    def check_path(self, path: str) -> Dict[str, Any]:
        """Check if path exists"""
        return self._call_rpc("check_path", {"path": path})

    def get_download_link(self, paths: List[str], description: str = "") -> Dict[str, Any]:
        """Get download link for paths"""
        return self._call_rpc("get_download_link", {
            "paths": paths,
            "description": description
        })


class LogDownloaderMCP:
    """MCP Server for log downloading"""

    def __init__(self, mcp_url: str, mcp_token: str):
        self.client = RemoteFileClient(mcp_url, mcp_token)

    def download_daily_logs(
        self,
        device_name: str,
        days_ago: int = 1,
        log_types: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """
        Download logs for a specific date

        Args:
            device_name: Device name (supports fuzzy matching)
            days_ago: Number of days ago (0=today, 1=yesterday, etc.)
            log_types: List of log types to download (default: ["client", "backend"])

        Returns:
            List of download link info for each log type
        """
        if log_types is None:
            log_types = ["client", "backend"]

        # Select device
        device = self.client.select_device(device_name)

        # Get the base path from device's allowed_roots
        # Assume the first allowed root is the CXJPos directory
        allowed_roots = device.get("allowed_roots", [])
        if not allowed_roots:
            raise Exception("Device has no allowed_roots configured")

        base_path = allowed_roots[0].rstrip("/\\")

        # Calculate date
        target_date = datetime.now() - timedelta(days=days_ago)
        date_str = target_date.strftime("%Y-%m-%d")

        results = []

        for log_type in log_types:
            # Determine path based on log type
            if log_type == "client":
                # Use ntpath.join for Windows paths
                path = ntpath.join(base_path, "Client", "logs", date_str)
            elif log_type == "backend":
                # Yesterday or earlier: .zip file
                if days_ago >= 1:
                    path = ntpath.join(base_path, "Backend", "log", f"{date_str}.zip")
                else:
                    path = ntpath.join(base_path, "Backend", "log", date_str)
            else:
                continue

            # Check if path exists
            try:
                path_info = self.client.check_path(path)
                if not path_info.get("exists"):
                    results.append({
                        "log_type": log_type,
                        "date": date_str,
                        "path": path,
                        "exists": False,
                        "error": "Path does not exist"
                    })
                    continue

                # Get download link
                link_info = self.client.get_download_link(
                    paths=[path],
                    description=f"{log_type}-logs-{date_str}"
                )

                results.append({
                    "log_type": log_type,
                    "date": date_str,
                    "path": path,
                    "exists": True,
                    "download_url": link_info["download_url"],
                    "file_name": link_info["file_name"],
                    "file_size": link_info["file_size"],
                    "compressed": link_info["compressed"],
                    "expires_at": link_info["expires_at"]
                })
            except Exception as e:
                results.append({
                    "log_type": log_type,
                    "date": date_str,
                    "path": path,
                    "error": str(e)
                })

        return results

    def handle_mcp_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle MCP JSON-RPC request"""
        method = request.get("method")
        params = request.get("params", {})
        request_id = request.get("id")

        try:
            if method == "initialize":
                # Handle MCP initialization
                result = {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {}
                    },
                    "serverInfo": {
                        "name": "remote-log-downloader",
                        "version": "1.0.0"
                    }
                }

            elif method == "tools/list":
                # List available tools
                result = {
                    "tools": [
                        {
                            "name": "list_devices",
                            "description": "列出所有在线设备",
                            "inputSchema": {
                                "type": "object",
                                "properties": {}
                            }
                        },
                        {
                            "name": "download_daily_logs",
                            "description": "Download device logs for a specific date",
                            "inputSchema": {
                                "type": "object",
                                "properties": {
                                    "device_name": {
                                        "type": "string",
                                        "description": "Device name (supports fuzzy matching, e.g., '西小口店')"
                                    },
                                    "days_ago": {
                                        "type": "integer",
                                        "description": "Number of days ago (0=today, 1=yesterday, 2=day before yesterday, etc.)",
                                        "default": 1
                                    },
                                    "log_types": {
                                        "type": "array",
                                        "items": {"type": "string", "enum": ["client", "backend"]},
                                        "description": "Types of logs to download",
                                        "default": ["client", "backend"]
                                    }
                                },
                                "required": ["device_name"]
                            }
                        }
                    ]
                }

            elif method == "tools/call":
                # Call a tool
                tool_name = params.get("name")
                tool_params = params.get("arguments", {})

                if tool_name == "list_devices":
                    result = self.client.list_devices()
                elif tool_name == "download_daily_logs":
                    result = self.download_daily_logs(
                        device_name=tool_params["device_name"],
                        days_ago=tool_params.get("days_ago", 1),
                        log_types=tool_params.get("log_types")
                    )
                else:
                    raise Exception(f"Unknown tool: {tool_name}")

            else:
                raise Exception(f"Unknown method: {method}")

            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": result
            }

        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {
                    "code": -32603,
                    "message": str(e)
                }
            }

    def run_stdio_server(self):
        """Run MCP server using stdio transport"""
        logger.info("Entering stdio server loop...")

        while True:
            try:
                # Read request from stdin
                line = sys.stdin.readline()
                if not line:
                    logger.info("EOF received, exiting...")
                    break

                logger.debug(f"Received request: {line.strip()[:100]}...")

                request = json.loads(line)
                response = self.handle_mcp_request(request)

                # Write response to stdout
                sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
                sys.stdout.flush()

                logger.debug(f"Sent response for method: {request.get('method')}")

            except Exception as e:
                logger.error(f"Error in stdio server: {e}", exc_info=True)
                error_response = {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {
                        "code": -32700,
                        "message": f"Parse error: {str(e)}"
                    }
                }
                sys.stdout.write(json.dumps(error_response, ensure_ascii=False) + "\n")
                sys.stdout.flush()


def main():
    # Get configuration from environment variables
    mcp_url = os.getenv("MCP_URL")
    mcp_token = os.getenv("MCP_TOKEN")

    if not mcp_url or not mcp_token:
        logger.error("MCP_URL and MCP_TOKEN environment variables are required")
        sys.exit(1)

    # Debug output
    logger.info(f"Starting remote-log-downloader MCP server")
    logger.info(f"MCP_URL: {mcp_url}")

    # Create and run MCP server
    server = LogDownloaderMCP(mcp_url, mcp_token)

    logger.info("MCP server initialized, waiting for requests...")

    server.run_stdio_server()


if __name__ == "__main__":
    main()
