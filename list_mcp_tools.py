from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
client._send({'jsonrpc': '2.0', 'id': client._next_id(), 'method': 'tools/list'})
res = client._read()
tools = res.get('result', {}).get('tools', [])
for t in tools:
    print(t.get('name'))
client.close()
