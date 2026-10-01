<#
.SYNOPSIS
  Launch one worker session for one task and track its process state.

.EXAMPLE
  tools\run-task.ps1 T-007 codex          # launch (developer or tester task)
  tools\run-task.ps1 -Status              # process state of all tasks
  tools\run-task.ps1 T-007 -Stop          # kill a hung worker (whole process tree), release the lock
  tools\run-task.ps1 T-007 -MarkFinished  # tool was started by hand (Antigravity IDE) and has finished

.DESCRIPTION
  Process state lives in tasks\.runtime\T-NNN.json, written only by this script:
    running   - worker process started and has not reported an end
    completed - tool process exited with code 0
    failed    - non-zero exit, launch error, or stopped with -Stop
  -Status also shows "dead": state is "running" but the process is gone (window closed).
  Process state says nothing about the task itself: done / blocked / rework come from the
  Task File "## Result" and the ledger (protocol: Runtime state).

  One task = one live worker. A "running" state with a live pid is the lock: a second launch of
  the same task (re-issue, fallback to another tool) is refused until the lock is released.

  Developer: an existing worktree must be on the task's Branch, otherwise the launch stops.
  Tester: always runs before merge, in the worktree of the task named in "Checks: T-xxx"; no worktree = stop.
  Each new attempt starts with a clean log.

  The launcher reads tasks\T-NNN-*.md: Role, Branch, Worktree, and lines in "## Environment setup"
  (link/copy sources are required: missing in the main folder = stop before anything is created):
    - link: node_modules        (junction from the main folder into the worktree)
    - copy: viewers\gs\dist     (copied once)
    - env: FOO=bar              (set for the worker process)
  and PORT=NNNN in "## Port". The worker runs in a visible window: this script again with -Worker.

  Tool command lines in $Tools are defaults: verify them once against your installed versions.
  Developer gets a full-access mode, tester does not (protocol: Launching workers, rule 4).
  Deployer is never started here: it runs only in the session the human designated.
#>
param(
  [Parameter(Position = 0)][string]$TaskId,
  [Parameter(Position = 1)][ValidateSet('codex', 'claude', 'agy')][string]$Tool,
  [switch]$Status,
  [switch]$Stop,
  [switch]$MarkFinished,
  [switch]$Worker
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtDir = Join-Path $root 'tasks\.runtime'
New-Item -ItemType Directory -Force $rtDir | Out-Null

# Defaults, verify once. pipe = output goes through Tee into the log (non-interactive mode).
# Interactive tools (pipe = $false) keep the window until a human exits them; the log is a transcript.
$Tools = @{
  codex  = @{ exe = 'codex'; pipe = $true
              args = { param($p, $r) $s = if ($r -eq 'developer') { 'danger-full-access' } else { 'read-only' }; @('exec', '--sandbox', $s, $p) } }
  claude = @{ exe = 'claude'; pipe = $true   # -p prints the answer only at the end
              args = { param($p, $r) if ($r -eq 'developer') { @('-p', $p, '--dangerously-skip-permissions') } else { @('-p', $p, '--allowedTools', 'Read,Grep,Glob,Bash') } } }
  agy    = @{ exe = 'agy'; pipe = $false       # -i only: -p prints nothing until the end
              args = { param($p, $r) @('-i', $p) } }
}

function Now { [DateTime]::UtcNow.ToString('s') + 'Z' }
function Get-RtPath([string]$id) { Join-Path $rtDir "$id.json" }
function Read-Rt([string]$id) {
  $p = Get-RtPath $id
  if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json } else { $null }
}
function Write-Rt([string]$id, $obj) {
  $p = Get-RtPath $id; $tmp = "$p.tmp"
  [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  Move-Item -Force $tmp $p
}
function Test-Alive($rt) {
  if (-not $rt -or $rt.status -ne 'running' -or -not $rt.pid) { return $false }
  $p = Get-Process -Id $rt.pid -ErrorAction SilentlyContinue
  return [bool]($p -and [long]$p.StartTime.ToUniversalTime().Ticks -eq [long]$rt.pidStart)   # pid reuse guard
}

function Get-Task([string]$id, [switch]$Prepare) {
  $f = Get-ChildItem (Join-Path $root 'tasks') -Filter "$id-*.md" | Select-Object -First 1
  if (-not $f) { throw "Task File tasks\$id-*.md not found" }
  $text = Get-Content $f.FullName -Raw -Encoding utf8
  $field = { param($n) if ($text -match "(?m)^$n\s*:\s*(.+?)\s*(<!--.*)?$") { $Matches[1].Trim() } }
  $section = { param($n) if ($text -match "(?ms)^## $n\s*\r?\n(.*?)(?=^## |\z)") { $Matches[1] } else { '' } }

  $t = @{ file = $f.FullName; rel = "tasks/$($f.Name)"; role = & $field 'Role'
          branch = & $field 'Branch'; worktree = & $field 'Worktree'; env = @{} }
  $t.prompt = "Your role: roles/$($t.role).md. Your task: $($t.rel). Follow docs/ai-handoff-protocol.md, section 'Starting a role session'."

  if ($t.role -eq 'tester') {
    # tester always runs pre-merge, in the worktree of the task it checks (field "Checks: T-xxx, commit <SHA>")
    $checks = & $field 'Checks'
    if ($checks -notmatch '(T-\d+)') { throw 'tester task needs "Checks: T-xxx, commit <SHA>"' }
    $target = Get-ChildItem (Join-Path $root 'tasks') -Filter "$($Matches[1])-*.md" | Select-Object -First 1
    if (-not $target) { throw "checked task $($Matches[1]) has no Task File" }
    $tt = Get-Content $target.FullName -Raw -Encoding utf8
    if ($tt -notmatch '(?m)^Worktree\s*:\s*(.+?)\s*(<!--.*)?$') { throw "checked task $($target.Name) has no Worktree" }
    $t.worktree = $Matches[1].Trim()
    $tb = if ($tt -match '(?m)^Branch\s*:\s*(\S+)') { $Matches[1] } else { throw "checked task $($target.Name) has no Branch" }
    $cur = if (Test-Path $t.worktree) { git -C $t.worktree rev-parse --abbrev-ref HEAD 2>$null }
    if ($cur -ne $tb) { throw "no worktree of checked task on branch '$tb' at $($t.worktree) (tester runs before merge)" }
  }
  $setup = (& $section 'Environment setup') + "`n" + (& $section 'Port')
  $items = [regex]::Matches($setup, '(?m)^\s*-\s*(link|copy|env)\s*:\s*(.+?)\s*$')
  if ($Prepare) {   # check required environment before creating anything
    foreach ($m in $items) {
      if ($m.Groups[1].Value -ne 'env' -and -not (Test-Path (Join-Path $root $m.Groups[2].Value))) {
        throw "required environment missing: $($m.Groups[1].Value) $($m.Groups[2].Value) is not in the main folder. Build it there first."
      }
    }
  }

  if ($Prepare -and $t.role -eq 'developer') {
    if (-not $t.branch -or -not $t.worktree) { throw 'developer task needs Branch and Worktree' }
    if (Test-Path $t.worktree) {
      $cur = (git -C $t.worktree rev-parse --abbrev-ref HEAD 2>$null)
      if ($cur -ne $t.branch) { throw "worktree $($t.worktree) is on branch '$cur', task needs '$($t.branch)'. Not this task's: stop." }
      Write-Host "worktree exists on $($t.branch): resume"
    } else {
      git -C $root worktree add $t.worktree -b $t.branch
      if ($LASTEXITCODE) { throw 'git worktree add failed' }
    }
  }
  $t.workdir = if ($t.worktree) { $t.worktree } else { $root }

  foreach ($m in $items) {
    $kind = $m.Groups[1].Value; $val = $m.Groups[2].Value
    if ($kind -eq 'env') { $k, $v = $val -split '=', 2; $t.env[$k.Trim()] = $v.Trim(); continue }
    if (-not $Prepare) { continue }
    $src = Join-Path $root $val; $dst = Join-Path $t.workdir $val
    if (Test-Path $dst) { continue }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    if ($kind -eq 'link') { New-Item -ItemType Junction -Path $dst -Target $src | Out-Null }
    else { Copy-Item -Recurse $src $dst }
  }
  if ($setup -match '(?m)^\s*PORT\s*=\s*(\d+)') { $t.env['PORT'] = $Matches[1] }
  return $t
}

# --- -Status: process state of all tasks
if ($Status) {
  Get-ChildItem $rtDir -Filter 'T-*.json' | Sort-Object Name | ForEach-Object {
    $rt = Get-Content $_.FullName -Raw | ConvertFrom-Json
    $state = $rt.status
    if ($state -eq 'running' -and -not (Test-Alive $rt)) { $state = 'dead' }
    '{0}  {1,-9}  tool={2}  exit={3}  limitHit={4}  finished={5}' -f $rt.taskId, $state, $rt.tool, $rt.exitCode, $rt.limitHit, $rt.finishedAt
  }
  return
}
if ($TaskId -notmatch '^T-\d+$') { throw 'TaskId T-NNN required' }

# --- -Stop: kill a hung worker, release the lock
if ($Stop) {
  $rt = Read-Rt $TaskId
  if (Test-Alive $rt) { taskkill /PID $rt.pid /T /F | Out-Null }
  if ($rt -and $rt.status -eq 'running') {
    $rt.status = 'failed'; $rt.exitCode = -1; $rt.finishedAt = Now; $rt.note = 'stopped with -Stop'
    Write-Rt $TaskId $rt
  }
  Write-Host "$TaskId stopped, lock released"; return
}

# --- -MarkFinished: tool was started by hand
if ($MarkFinished) {
  $t = Get-Task $TaskId
  Write-Rt $TaskId ([ordered]@{ taskId = $TaskId; tool = 'manual'; role = $t.role; status = 'completed'; pid = $null; pidStart = $null
    exitCode = 0; startedAt = $null; finishedAt = Now; limitHit = $false; taskFile = $t.rel; log = $null; note = 'started by hand' })
  Write-Host "$TaskId marked completed"; return
}

# --- -Worker: runs inside the visible window
if ($Worker) {
  $ErrorActionPreference = 'Continue'   # native stderr must not abort the worker
  $t = Get-Task $TaskId
  Set-Location -LiteralPath $t.workdir
  foreach ($k in $t.env.Keys) { Set-Item "env:$k" $t.env[$k] }
  $spec = $Tools[$Tool]; $a = & $spec.args $t.prompt $t.role
  $log = Join-Path $rtDir "$TaskId.log"
  $code = 1; $note = $null
  try {
    if ($spec.pipe) {
      & $spec.exe @a 2>&1 | Tee-Object -FilePath $log -Append
    } else {
      Start-Transcript -Path $log -Append | Out-Null
      & $spec.exe @a
    }
    $code = $LASTEXITCODE
  } catch {
    $note = "launch error: $_"; Write-Host $note
  } finally {
    if (-not $spec.pipe) { try { Stop-Transcript | Out-Null } catch {} }
  }
  $rt = Read-Rt $TaskId   # re-read: launcher wrote pid after start
  $rt.exitCode = $code
  $rt.status = if ($code -eq 0) { 'completed' } else { 'failed' }
  $rt.finishedAt = Now
  $rt.limitHit = (Test-Path $log) -and [bool](Select-String -Path $log -Pattern 'usage limit|rate limit|quota' -Quiet)
  if ($note) { $rt.note = $note }
  Write-Rt $TaskId $rt
  Write-Host "`n$TaskId process $($rt.status) (exit $code). You can close this window."
  return
}

# --- launch
if (-not $Tool) { throw 'Tool required: codex | claude | agy' }
# startup mutex: atomic create, held from the state check until the pid is recorded
$lockPath = Join-Path $rtDir "$TaskId.lock"
if ((Test-Path $lockPath) -and ((Get-Date) - (Get-Item $lockPath).LastWriteTime).TotalMinutes -gt 2) {
  Remove-Item $lockPath   # left by a crashed launcher
}
try { $lock = [IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None') }
catch { throw "$TaskId is being launched by another run-task.ps1 right now ($lockPath). Wait and check -Status." }
try {
  $prev = Read-Rt $TaskId
  if (Test-Alive $prev) {
    throw "$TaskId already has a live worker (pid $($prev.pid), $($prev.tool)). One task = one worker. Stop it first: tools\run-task.ps1 $TaskId -Stop"
  }
  if ($prev -and $prev.status -eq 'running') { Write-Warning "previous worker of $TaskId died without a final state (window closed?). Recovery applies." }

  $t = Get-Task $TaskId -Prepare
  if ($t.role -notin 'developer', 'tester') {
    throw "Role '$($t.role)': this launcher starts developer and tester only. Deployer runs in the session the human designated."
  }
  if ($Tool -eq 'agy') { Write-Host "Antigravity: make sure '$($t.workdir)' is in its trusted folders before the first run." }

  $log = Join-Path $rtDir "$TaskId.log"
  if (Test-Path $log) { Remove-Item $log }   # new attempt = clean log
  $rt = [ordered]@{ taskId = $TaskId; tool = $Tool; role = $t.role; status = 'running'; pid = $null; pidStart = $null
    exitCode = $null; startedAt = Now; finishedAt = $null; limitHit = $false; taskFile = $t.rel; log = $log; note = $null }
  Write-Rt $TaskId $rt   # running state = lock for the worker's lifetime

  $ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
  $p = Start-Process $ps -PassThru -ArgumentList '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$PSCommandPath`"", $TaskId, $Tool, '-Worker'
  $cur = Read-Rt $TaskId
  if ($cur.status -eq 'running') {   # worker may already have finished (e.g. tool not found)
    $cur.pid = $p.Id; $cur.pidStart = [long](Get-Process -Id $p.Id).StartTime.ToUniversalTime().Ticks
    Write-Rt $TaskId $cur
  }
} finally {
  $lock.Dispose(); Remove-Item $lockPath -ErrorAction SilentlyContinue
}
Write-Host "$TaskId started in $Tool (visible window, pid $($p.Id)). log: $log"
