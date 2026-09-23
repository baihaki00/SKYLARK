import subprocess
import time
import json
import os
import glob

class RobloxStudioClient:
    """
    Robust MCP client interface for interacting with Roblox Studio.
    Dynamically discovers StudioMCP.exe in LocalAppData and handles JSON-RPC communication.
    """
    def __init__(self):
        mcp_path = self._find_mcp_binary()
        if not mcp_path:
            raise FileNotFoundError("StudioMCP.exe could not be located in Roblox Versions directories.")

        self.proc = subprocess.Popen(
            [mcp_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding='utf-8',
            errors='replace',
            bufsize=1
        )
        self.msg_id = 1
        self._send({
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "QuinPersistentClient", "version": "2.0"}
            }
        })
        self._read()
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.studio_id = self.get_active_studio_id()

    def _find_mcp_binary(self):
        # 1. Check known fixed path
        fixed_path = r"C:\Users\User\AppData\Local\Roblox\Versions\version-574ecee7ee2b4e60\StudioMCP.exe"
        if os.path.exists(fixed_path):
            return fixed_path

        # 2. Glob across all version folders
        base_dir = r"C:\Users\User\AppData\Local\Roblox\Versions"
        matches = glob.glob(os.path.join(base_dir, "*", "StudioMCP.exe"))
        if matches:
            # Pick latest modified
            matches.sort(key=os.path.getmtime, reverse=True)
            return matches[0]
        return None

    def _next_id(self):
        mid = self.msg_id
        self.msg_id += 1
        return mid

    def _send(self, msg):
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def _read(self):
        line = self.proc.stdout.readline()
        if not line:
            return None
        return json.loads(line)

    def call_tool(self, name, arguments):
        self._send({
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": "tools/call",
            "params": {
                "name": name,
                "arguments": arguments
            }
        })
        return self._read()

    def get_active_studio_id(self):
        for _ in range(15):
            time.sleep(0.5)
            res = self.call_tool("list_roblox_studios", {})
            if res and not res.get("isError", False):
                content = res.get("result", {}).get("content", [{}])[0].get("text", "")
                try:
                    data = json.loads(content)
                    studios = data.get("studios", [])
                    if studios:
                        return studios[0]["id"]
                except Exception:
                    pass
        raise RuntimeError("No active Roblox Studio session found after timeout.")

    def execute_luau(self, code, datamodel_type="Edit"):
        """
        Executes Luau code in Studio.
        datamodel_type options: 'Edit', 'Server', 'Client'.
        """
        return self.call_tool("execute_luau", {
            "studio_id": self.studio_id,
            "datamodel_type": datamodel_type,
            "code": code
        })

    def get_studio_state(self):
        return self.call_tool("get_studio_state", {"studio_id": self.studio_id})

    def set_play_mode(self, is_start=True):
        return self.call_tool("start_stop_play", {
            "studio_id": self.studio_id,
            "is_start": is_start
        })

    def screen_capture(self, capture_id=None, camera_position=None, look_at_position=None):
        capture_id = capture_id or f"Capture_{int(time.time()*1000)}"
        args = {
            "studio_id": self.studio_id,
            "capture_id": capture_id
        }
        if camera_position:
            args["camera_position"] = camera_position
        if look_at_position:
            args["look_at_position"] = look_at_position
        return self.call_tool("screen_capture", args)

    def close(self):
        if self.proc:
            self.proc.terminate()

if __name__ == "__main__":
    client = RobloxStudioClient()
    print("Successfully connected to Roblox Studio MCP. Studio ID:", client.studio_id)
    st = client.get_studio_state()
    print("Current State:", st.get("result", {}).get("content", [{}])[0].get("text", ""))
    client.close()
