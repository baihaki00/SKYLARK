---
name: studio-git-export
description: How to export QUIN_COMBAT.rbxl scripts into the QUINCORE_BACKUP git repo and push to GitHub
metadata:
  node_type: memory
  type: reference
  originSessionId: aab93d9f-4a24-4c2a-9a6e-34e1919e40d6
  modified: 2026-10-01T04:05:43.341Z
---

Repo: `D:\SKYLARK\SKYLARK LOCAL REPO\QUINCORE_BACKUP` (remote `origin` = github.com/baihaki00/SKYLARK). Audit work lives on branch `audit/16v16-baseline-20261001`; structured export is under `studio_snapshot/<Service>/...` with `.server.lua` / `.client.lua` / `.lua` suffixes; audit write-ups go in `audits/`. The flat `.lua` files at the repo root are an older layout and are not updated by the audit commits. The place file itself (rigs, templates) is not in the repo.

Export recipe (Studio MCP cannot write to disk, tool output caps at ~100k chars):
1. In Edit mode, build `HttpService:JSONEncode({{p=path, s=Source}, ...})` for ReplicatedStorage, ServerScriptService, StarterGui, StarterPlayer; escape `~` and bytes >127 as `~HH`; store in `_G.__export`.
2. Return it in 90,000-char slices prefixed `SLICEnn|` (pad the last slice past the cap and add `|END|` so it is also saved to a file). Each oversized result is saved under the session's `tool-results` folder.
3. A small Python script globs those files, orders by slice number, un-escapes, JSON-parses and writes the files (`newline=""` to keep line endings). `git diff --stat` then shows the real changes.

The Studio session id changes when Studio is reopened; call `list_roblox_studios` again.

Cheaper variant (pass 12): first return `path|len|hash` per script from Studio (`h=(h*31+byte)%2147483647`), hash the local `studio_snapshot` files the same way in Python, and export only the differing scripts (about 5 slices instead of 20). `LocalScript` IsA `Script`, so pick the suffix by `ClassName`. Saved slices can come back either plain or wrapped in a JSON `[{"text":...}]`; handle both. The Bash heredoc mangles `'\'`, so use `os.sep`.

**Large scripts (2026-10-03):** the MCP result is cut at ~100,015 chars and the tool appends a few chars, so stripping padding pipes fails. Slice the JSON in 90,000-char chunks and take exactly t[8:8+90000] from each non-final slice (helper `$TEMP/unslice_multi.py <id> <id,id,id>`); check the unpacked byte count against `#Source` in Studio. AnimationLabController is ~197 KB = 3 slices.

**Publishing (2026-10-03):** owner publishes with Studio 'Save to Roblox with Notes'. `QUINCORE_BACKUP/scripts/publish-notes.ps1` (commit 215f65b) builds title+details from git since the last `roblox-published-*` tag, fills the dialog (Ctrl+Alt+S + paste), owner clicks Save, then it tags+pushes. First run needs `-Since 28b9fd4` (last publish before any tag). MCP cannot drive Studio's own dialogs; after each pass offer the owner to run it (or paste ready notes).

**Creating scripts (2026-10-03):** `execute_luau` can't parent a new Script/ModuleScript into ServerScriptService, ServerStorage or QuinCore; its sandboxed thread lacks those containers' Capabilities. Use the MCP `multi_edit` tool with `className` and an empty first `old_string`: it creates the script anywhere. Never ask the owner to create scripts.

**Local -> Studio push (found 2026-10-04, much cheaper than sending source through a tool call):**
- In `QUINCORE_BACKUP/studio_snapshot`: `python -m http.server 58917 --bind 127.0.0.1` (background).
- Edit the file on disk with ordinary tools.
- Edit-mode `execute_luau`: `local src = game:GetService("HttpService"):GetAsync("http://127.0.0.1:58917/<path>?v="..os.clock(), true)`, then `assert(loadstring(src))`, then `script.Source = src`.
- Only safe when the disk copy equals Studio's first (check `GetAsync(...) == script.Source` before editing). Studio -> disk still needs the export recipe.
- Stop the server when done.

**Studio -> disk, cheapest (2026-10-26):** `QUINCORE_BACKUP/scripts/snapshot_receiver.py <studio_snapshot dir> 58918` (background). Edit-mode execute_luau walks the 6 services, GETs `/hash?p=` and POSTs `/put?p=` only for changed scripts (same hash formula), then POSTs a `__manifest.txt` to spot files deleted in Studio (delete the manifest before committing). Duplicate script names are skipped (the old `_2` files stay). Stop the receiver when done.
