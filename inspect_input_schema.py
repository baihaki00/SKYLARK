from Tools.Utilities.roblox_client import RobloxStudioClient
import json

client = RobloxStudioClient()
client._send({'jsonrpc': '2.0', 'id': client._next_id(), 'method': 'tools/list'})
res = client._read()
for t in res.get('result', {}).get('tools', []):
    if t.get('name') in ['user_keyboard_input', 'start_stop_play']:
        print(t.get('name'), t.get('inputSchema'))
client.close()
