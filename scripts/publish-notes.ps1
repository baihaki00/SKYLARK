<#
.SYNOPSIS
  Fill Roblox Studio's "Save to Roblox with Notes" dialog from git history, then tag the
  published commit so the next notes start from there.

.DESCRIPTION
  1. Collects the commits since the last tag named roblox-published-* (or -Since <ref>).
  2. Builds a version title ("Pass 22F-23c: <latest change>") and details (one line per
     commit, plus branch and commit id).
  3. Brings Roblox Studio to the front, presses Ctrl+Alt+S (Save to Roblox with Notes) and
     pastes the title and details into the dialog. YOU review and click Save.
  4. Asks whether you saved; on yes it creates the tag roblox-published-<date-time> on the
     commit and pushes it, so each Roblox version maps to a git commit.

  The clipboard is used for pasting and restored afterwards.

.EXAMPLE
  .\scripts\publish-notes.ps1 -DryRun
  Print the notes only.

.EXAMPLE
  .\scripts\publish-notes.ps1 -Since 28b9fd4
  First run (no publish tag yet): notes for everything after 28b9fd4.

.EXAMPLE
  .\scripts\publish-notes.ps1 -Title "Hotfix: arena ring" -Note "Tested in FFA 32"
#>
param(
	[string]$Since,              # start ref (exclusive); default = latest roblox-published-* tag
	[string]$Title,              # override the generated title
	[string]$Note,               # extra line placed first in the details
	[string]$Window = "QUIN_COMBAT", # part of the Studio window title (several Studios open)
	[switch]$DryRun,             # print the notes, touch nothing
	[switch]$NoTag,              # fill the dialog but never tag
	[int]$MaxTitle = 100,
	[int]$MaxDetails = 1500
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$repo = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
	# (Windows PowerShell turns git's stderr progress lines into errors under "Stop"; the exit
	# code is what counts)
	$saved = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$out = & git.exe -C $repo @args 2>&1 | ForEach-Object { "$_" }
	$code = $LASTEXITCODE
	$ErrorActionPreference = $saved
	if ($code -ne 0) { throw "git $($args -join ' ') failed: $($out -join ' ')" }
	return $out
}

# --- 1. Range -----------------------------------------------------------------------------
if (-not $Since) {
	$tags = @(Invoke-Git tag --list "roblox-published-*" --sort=-creatordate)
	if ($tags.Count -gt 0 -and $tags[0]) {
		$Since = $tags[0]
	} else {
		Write-Host "No roblox-published-* tag yet. Run once with -Since <commit> (the commit you last published)." -ForegroundColor Yellow
		exit 1
	}
}
$head = (Invoke-Git rev-parse --short HEAD).Trim()
$branch = (Invoke-Git rev-parse --abbrev-ref HEAD).Trim()
$subjects = @(Invoke-Git -c i18n.logOutputEncoding=UTF-8 log --reverse --format=%s "$Since..HEAD")
if ($subjects.Count -eq 0 -or -not $subjects[0]) {
	Write-Host "Nothing new since $Since." -ForegroundColor Yellow
	exit 0
}
$dirty = @(Invoke-Git status --porcelain --untracked-files=no)
if ($dirty.Count -gt 0 -and $dirty[0]) {
	Write-Host "Note: the repo has uncommitted changes; they are not in these notes." -ForegroundColor Yellow
}

# --- 2. Notes -----------------------------------------------------------------------------
function Shorten([string]$text, [int]$max) {
	# drop a trailing "(...)" explanation, then cut at a word boundary
	$t = ($text -replace '\s*\([^)]*\)\s*$', '').Trim()
	if ($t.Length -le $max) { return $t }
	$cut = $t.Substring(0, $max - 3)
	$space = $cut.LastIndexOf(' ')
	if ($space -gt $max / 2) { $cut = $cut.Substring(0, $space) }
	return $cut.TrimEnd(',', ';', ' ', '-') + "..."
}

$passes = @()
$lines = @()
foreach ($s in $subjects) {
	if ($s -match '^Pass (\d+[A-Za-z]?)\b') { $passes += $Matches[1] }
	$lines += "- " + (Shorten $s 140)
}

if (-not $Title) {
	$latest = $subjects[-1] -replace '^Pass [^:]+:\s*', ''
	$latest = ($latest -split '\s+\(|,|;| - ')[0].Trim()
	$prefix = ""
	if ($passes.Count -gt 0) {
		$prefix = if ($passes[0] -eq $passes[-1]) { "Pass $($passes[0]): " } else { "Pass $($passes[0])-$($passes[-1]): " }
	}
	$Title = Shorten ($prefix + $latest) $MaxTitle
}

$footer = "Git: $branch @ $head ($($subjects.Count) commit(s) since $Since)"
$body = @()
if ($Note) { $body += $Note; $body += "" }
$body += $lines
# keep within the limit: drop the oldest lines first
while ((($body + "" + $footer) -join "`r`n").Length -gt $MaxDetails -and $lines.Count -gt 1) {
	$lines = $lines[1..($lines.Count - 1)]
	$body = @()
	if ($Note) { $body += $Note; $body += "" }
	$body += "- (older changes in git)"
	$body += $lines
}
$Details = (($body + "" + $footer) -join "`r`n")

Write-Host "`n=== Version title ===" -ForegroundColor Cyan
Write-Host $Title
Write-Host "`n=== Version details ===" -ForegroundColor Cyan
Write-Host $Details
Write-Host ""
if ($DryRun) { exit 0 }

# --- 3. Fill the Studio dialog --------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
$studio = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue |
	Where-Object { $_.MainWindowTitle -like "*$Window*" } | Select-Object -First 1
if (-not $studio) {
	$studio = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue |
		Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}
if (-not $studio) { throw "Roblox Studio is not running." }
Write-Host "Studio window: $($studio.MainWindowTitle)"

$previousClipboard = $null
try { $previousClipboard = Get-Clipboard -Raw } catch {}

$shell = New-Object -ComObject WScript.Shell
if (-not $shell.AppActivate($studio.Id)) { throw "Could not bring Studio to the front." }
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("^%s")   # Ctrl+Alt+S: Save to Roblox with Notes
Start-Sleep -Milliseconds 1800                       # the dialog opens with the title box focused

Set-Clipboard -Value $Title
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
Start-Sleep -Milliseconds 200
Set-Clipboard -Value $Details
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 300

if ($null -ne $previousClipboard) { Set-Clipboard -Value $previousClipboard }

Write-Host "`nThe dialog is filled. Check it in Studio and click Save (or Cancel)." -ForegroundColor Green

# --- 4. Tag what was published ----------------------------------------------------------------
if ($NoTag) { exit 0 }
$answer = Read-Host "Did you click Save? Tag $head as published and push the tag (y/N)"
if ($answer -notmatch '^[Yy]') { Write-Host "Not tagged."; exit 0 }
$tag = "roblox-published-" + (Get-Date -Format "yyyyMMdd-HHmm")
$msgFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($msgFile, "$Title`n`n$Details", (New-Object System.Text.UTF8Encoding($false)))
Invoke-Git tag -a $tag -F $msgFile HEAD | Out-Null
Remove-Item $msgFile
Invoke-Git push origin $tag | Out-Null
Write-Host "Tagged and pushed $tag -> $head. Next run starts from here." -ForegroundColor Green
