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
import threading
import time
import zipfile  # For auto-extracting downloaded zip files

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

    # Create file handler
    file_handler = logging.FileHandler(log_file, encoding='utf-8', delay=False)

    # Create formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    file_handler.setFormatter(formatter)

    # Configure logger
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.DEBUG)

    # Add handlers
    logger.handlers.clear()
    logger.addHandler(file_handler)
    logger.addHandler(logging.StreamHandler(sys.stderr))

    # Start background thread to flush logs every 3 seconds
    def flush_logs_periodically():
        """Flush log handlers every 3 seconds to ensure logs are written to disk immediately"""
        while True:
            time.sleep(3)
            try:
                for handler in logger.handlers:
                    handler.flush()
            except:
                pass

    flush_thread = threading.Thread(target=flush_logs_periodically, daemon=True)
    flush_thread.start()

    return logger

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
            # Increase timeout for large file compression (10 minutes)
            logger.debug(f"Calling RPC method: {method} with timeout=600s")
            with urllib.request.urlopen(req, timeout=600) as response:
                result = json.loads(response.read().decode('utf-8'))

                if "error" in result:
                    raise Exception(f"RPC error: {result['error']}")

                return result.get("result")
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            raise Exception(f"HTTP {e.code}: {error_body}")
        except urllib.error.URLError as e:
            raise Exception(f"URL error: {e.reason}")

    def list_devices(self, device_name_filter: Optional[str] = None) -> List[Dict[str, Any]]:
        """List all online devices, optionally filtered by device name"""
        devices = self._call_rpc("list_devices", {})

        # Apply client-side filtering if filter is provided
        if device_name_filter:
            filtered = [d for d in devices if device_name_filter in d.get("device_name", "")]
            return filtered

        return devices

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

    def __init__(self, mcp_url: str, mcp_token: str, download_dir: str = r"C:\logs\device-logs"):
        self.client = RemoteFileClient(mcp_url, mcp_token)
        self.download_dir = download_dir
        # Extract the real host from MCP_URL to fix 0.0.0.0 URLs returned by the Go server
        from urllib.parse import urlparse
        parsed = urlparse(mcp_url)
        self._mcp_host = parsed.hostname or "localhost"
        self._mcp_port = parsed.port
        logger.debug(f"LogDownloaderMCP initialized with mcp_url: {mcp_url}")
        logger.debug(f"Extracted _mcp_host: {self._mcp_host}, _mcp_port: {self._mcp_port}")

    def _fix_download_url(self, url: str) -> str:
        """Replace 0.0.0.0 with the real host from MCP_URL"""
        logger.debug(f"_fix_download_url called with url: {url}")
        logger.debug(f"_mcp_host: {self._mcp_host}, _mcp_port: {self._mcp_port}")

        if "0.0.0.0" in url:
            url = url.replace("0.0.0.0", self._mcp_host)
            logger.debug(f"Replaced 0.0.0.0 with {self._mcp_host}, new url: {url}")

        return url

    def _download_file_locally(self, download_url: str, save_dir: str, filename: str) -> str:
        """Download a file from URL and save to local directory. Returns the local file path."""
        os.makedirs(save_dir, exist_ok=True)
        save_path = os.path.join(save_dir, filename)

        fixed_url = self._fix_download_url(download_url)
        logger.info(f"Downloading {fixed_url} -> {save_path}")

        headers = {"Authorization": f"Bearer {self.client.token}"}
        req = urllib.request.Request(fixed_url, headers=headers)

        try:
            # Increase timeout for large file downloads (10 minutes)
            logger.debug(f"Starting download with timeout=600s")
            with urllib.request.urlopen(req, timeout=600) as response:
                with open(save_path, "wb") as f:
                    f.write(response.read())

            logger.info(f"Downloaded successfully: {save_path}")

            # Auto-extract if it's a zip file
            if save_path.lower().endswith('.zip'):
                extract_dir = self._extract_zip(save_path, save_dir)
                if extract_dir:
                    logger.info(f"Auto-extracted to: {extract_dir}")

            return save_path
        except urllib.error.HTTPError as http_err:
            logger.error(f"HTTP Error downloading {fixed_url}: {http_err.code} {http_err.reason}")
            logger.error(f"HTTP Error response: {http_err.read().decode('utf-8')}")
            raise
        except Exception as e:
            logger.error(f"Error downloading {fixed_url}: {str(e)}", exc_info=True)
            raise

    def _extract_zip(self, zip_path: str, extract_to: str) -> Optional[str]:
        """Extract a zip file to the specified directory. Returns the extraction directory path."""
        try:
            # Create extraction directory name (remove .zip extension)
            base_name = os.path.splitext(os.path.basename(zip_path))[0]
            extract_dir = os.path.join(extract_to, base_name)

            logger.info(f"Extracting {zip_path} to {extract_dir}")

            # Extract the zip file
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)

            # Count extracted files
            file_count = sum(len(files) for _, _, files in os.walk(extract_dir))
            logger.info(f"Extracted {file_count} files to {extract_dir}")

            return extract_dir
        except zipfile.BadZipFile:
            logger.error(f"Bad zip file: {zip_path}")
            return None
        except Exception as e:
            logger.error(f"Error extracting {zip_path}: {str(e)}", exc_info=True)
            return None

    def download_daily_logs(
        self,
        device_name: str,
        days_ago: int = 0,
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
                    # For backend logs, mark as skipped instead of error
                    if log_type == "backend":
                        logger.warning(f"Backend log path does NOT exist: {path}")
                        results.append({
                            "log_type": log_type,
                            "date": date_str,
                            "path": path,
                            "exists": False,
                            "skipped": True,
                            "message": "Backend log does not exist, skipped"
                        })
                        continue
                    else:
                        # For client logs, report as error
                        logger.error(f"Client log path does NOT exist: {path}")
                        results.append({
                            "log_type": log_type,
                            "date": date_str,
                            "path": path,
                            "exists": False,
                            "error": "Path does not exist"
                        })
                        continue

                # Get download link
                logger.info(f"[{log_type}] Getting download link for: {path}")
                link_info = self.client.get_download_link(
                    paths=[path],
                    description=f"{log_type}-logs-{date_str}"
                )
                logger.debug(f"[{log_type}] Got download link info: {link_info}")
                original_download_url = link_info["download_url"]
                logger.debug(f"[{log_type}] Download URL: {original_download_url}")
                logger.info(f"[{log_type}] File info - size: {link_info.get('file_size')} bytes, compressed: {link_info.get('compressed')}, expires: {link_info.get('expires_at')}")

                # Check if file size is 0 (empty directory)
                if link_info.get("file_size", 0) == 0:
                    logger.error(f"[{log_type}] SKIP DOWNLOAD: Directory exists but contains NO log files (file_size=0). Path: {path}")
                    results.append({
                        "log_type": log_type,
                        "date": date_str,
                        "path": path,
                        "exists": True,
                        "error": "Directory exists but has no log files (file_size=0)",
                        "file_size": 0
                    })
                    continue

                # Fix 0.0.0.0 in URL
                download_url = self._fix_download_url(original_download_url)
                logger.debug(f"[{log_type}] Fixed URL: {download_url}")

                # Auto-download file to local logs directory
                safe_device = device_name.replace("/", "_").replace("\\", "_")
                local_dir = os.path.join(self.download_dir, safe_device, date_str)
                try:
                    logger.info(f"[{log_type}] Starting download -> {local_dir}/{link_info['file_name']}")
                    local_path = self._download_file_locally(
                        download_url, local_dir, link_info["file_name"]
                    )
                    logger.info(f"[{log_type}] Download SUCCESS: {local_path}")

                    # Check if extracted directory exists
                    extracted_dir = None
                    if local_path and local_path.lower().endswith('.zip'):
                        base_name = os.path.splitext(os.path.basename(local_path))[0]
                        potential_extract_dir = os.path.join(local_dir, base_name)
                        if os.path.isdir(potential_extract_dir):
                            extracted_dir = potential_extract_dir
                except Exception as dl_err:
                    logger.error(f"[{log_type}] Download FAILED: {dl_err}", exc_info=True)
                    local_path = None
                    extracted_dir = None

                results.append({
                    "log_type": log_type,
                    "date": date_str,
                    "path": path,
                    "exists": True,
                    "download_url": download_url,
                    "file_name": link_info["file_name"],
                    "file_size": link_info["file_size"],
                    "compressed": link_info["compressed"],
                    "expires_at": link_info["expires_at"],
                    "local_path": local_path,
                    "extracted_dir": extracted_dir
                })
            except Exception as e:
                # For backend logs, mark as skipped on error
                if log_type == "backend":
                    logger.error(f"[{log_type}] Backend log error (skipping): {e}", exc_info=True)
                    results.append({
                        "log_type": log_type,
                        "date": date_str,
                        "path": path,
                        "skipped": True,
                        "message": f"Backend log error, skipped: {str(e)}"
                    })
                    continue
                else:
                    # For client logs, report error
                    logger.error(f"[{log_type}] Client log error: {e}", exc_info=True)
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
                                "properties": {
                                    "device_name_filter": {
                                        "type": "string",
                                        "description": "Optional device name filter (fuzzy matching, e.g., '扬州')"
                                    }
                                }
                            }
                        },
                        {
                            "name": "download_daily_logs",
                            "description": "Download device logs for a specific date. Files are saved locally and local_path is returned so the AI can read them directly.",
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
                                        "default": 0
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
                    device_name_filter = tool_params.get("device_name_filter")
                    tool_result = self.client.list_devices(device_name_filter)
                elif tool_name == "download_daily_logs":
                    tool_result = self.download_daily_logs(
                        device_name=tool_params["device_name"],
                        days_ago=tool_params.get("days_ago", 0),
                        log_types=tool_params.get("log_types")
                    )
                else:
                    raise Exception(f"Unknown tool: {tool_name}")

                # Format result according to MCP spec
                result = {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(tool_result, ensure_ascii=False, indent=2)
                        }
                    ]
                }

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
        logger.info(f"stdin isatty: {sys.stdin.isatty()}")
        logger.info(f"stdout isatty: {sys.stdout.isatty()}")

        while True:
            try:
                # Read request from stdin
                logger.debug("Waiting for input from stdin...")
                line = sys.stdin.readline()
                logger.debug(f"Read line: {repr(line[:100]) if line else 'None'}")

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
    download_dir = os.getenv("DOWNLOAD_DIR", r"C:\logs\device-logs")
    server = LogDownloaderMCP(mcp_url, mcp_token, download_dir=download_dir)

    logger.info("MCP server initialized, waiting for requests...")

    server.run_stdio_server()


if __name__ == "__main__":
    main()
