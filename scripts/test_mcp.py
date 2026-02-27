#!/usr/bin/env python3
"""
Minimal MCP test server - just to verify the protocol works
"""

import sys
import json

def main():
    # Write a test message to stderr for debugging
    print("MCP server starting...", file=sys.stderr)
    sys.stderr.flush()

    while True:
        try:
            # Read request from stdin
            line = sys.stdin.readline()
            if not line:
                break

            print(f"Received: {line.strip()}", file=sys.stderr)
            sys.stderr.flush()

            request = json.loads(line)
            method = request.get("method")
            request_id = request.get("id")

            # Simple response
            if method == "initialize":
                response = {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {
                            "tools": {}
                        },
                        "serverInfo": {
                            "name": "test-mcp-server",
                            "version": "1.0.0"
                        }
                    }
                }
            elif method == "tools/list":
                response = {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "tools": [
                            {
                                "name": "test_tool",
                                "description": "A test tool",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": {}
                                }
                            }
                        ]
                    }
                }
            else:
                response = {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {"message": "Test response"}
                }

            # Write response to stdout
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()

            print(f"Sent: {json.dumps(response)}", file=sys.stderr)
            sys.stderr.flush()

        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.stderr.flush()
            error_response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": str(e)
                }
            }
            sys.stdout.write(json.dumps(error_response) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
