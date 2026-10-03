<#
.SYNOPSIS
  Launch one worker attempt for one task and track its process state.

.EXAMPLE
  tools\run-task.ps1 T-007 codex          # launch a developer or tester task in a visible window
  tools\run-task.ps1 T-007 -Manual        # same gate and preparation, no process: a human starts the tool
  tools\run-task.ps1 -Status              # process state of the last attempt of every task
  tools\run-task.ps1 T-007 -Stop          # kill a hung worker (whole process tree), release the lock
  tools\run-task.ps1 T-007 -MarkFinished  # a manual attempt has finished

.DESCRIPTION
  Rules: docs/ai-handoff-protocol.md, sections "Runtime state" and "Launching workers".
  Task File parsing, preflight and end-of-attempt checks: tools/gate.py. This script does the side effects:
  worktrees and checkouts, environment, windows, processes, tasks\.runtime\T-NNN.json (attempt history).
  Tool command lines in $Tools are defaults: verify them once against your installed versions.
  Machine settings are environment variables, not edits of $Tools:
    AGENTFLOW_CODEX       codex executable; wildcards allowed, the newest match wins
    AGENTFLOW_CODEX_ARGS  extra codex exec arguments, space-separated (for example: -m <model>)
#>
param(
  [Parameter(Position = 0)][string]$TaskId,
  [Parameter(Position = 1)][ValidateSet('codex', 'claude', 'agy')][string]$Tool,
  [switch]$Status,
  [switch]$Stop,
  [switch]$MarkFinished,
  [switch]$Manual,
  [switch]$Worker
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtDir = Join-Path $root 'tasks\.runtime'
New-Item -ItemType Directory -Force $rtDir | Out-Null
$env:PYTHONUTF8 = '1'

$codexExe = 'codex'
if ($env:AGENTFLOW_CODEX) {   # machine override; wildcards allowed, newest match wins
  $m = Get-Item $env:AGENTFLOW_CODEX -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  $codexExe = if ($m) { $m.FullName } else { $env:AGENTFLOW_CODEX }
}
$codexArgs = @(if ($env:AGENTFLOW_CODEX_ARGS) { $env:AGENTFLOW_CODEX_ARGS.Trim() -split '\s+' })

# pipe = output goes through Tee into the log (non-interactive mode).
# Interactive tools (pipe = $false) keep the window until a human exits them; the log is a transcript.
# Tester: review isolation. It runs in a disposable checkout; codex is sandboxed to it plus the main tasks\
# folder (for its "## Result"); claude cannot be sandboxed, so the end-of-attempt check catches changes.
$Tools = @{
  codex  = @{ exe = $codexExe; pipe = $true
              args = { param($p, $r)
                if ($r -eq 'developer') { @('exec') + $codexArgs + @('--sandbox', 'danger-full-access', $p) }
                else { @('exec') + $codexArgs + @('--sandbox', 'workspace-write', '--add-dir', (Join-Path $root 'tasks'), '-c', 'sandbox_workspace_write.network_access=true', $p) } } }
  claude = @{ exe = 'claude'; pipe = $true   # -p prints the answer only at the end
              args = { param($p, $r) if ($r -eq 'developer') { @('-p', $p, '--dangerously-skip-permissions') } else { @('-p', $p, '--allowedTools', 'Read,Grep,Glob,Bash,Edit') } } }
  agy    = @{ exe = 'agy'; pipe = $false       # -i only: -p prints nothing until the end
              args = { param($p, $r) if ($r -eq 'developer') { @('-i', $p, '--dangerously-skip-permissions') } else { @('-i', $p) } } }
}

function Now { [DateTime]::UtcNow.ToString('s') + 'Z' }
function Invoke-Gate([string]$cmd, [string]$id, [string[]]$more = @()) {   # tools/gate.py -> object; exit 2 = gate error
  $out = Join-Path $rtDir "$id.gate.json"
  $msg = & python (Join-Path $root 'tools\gate.py') $cmd $id @more --out $out 2>&1
  if ($LASTEXITCODE -ge 2 -or -not (Test-Path $out)) { throw "gate.py $cmd ${id}: $msg" }
  try { Get-Content $out -Raw -Encoding utf8 | ConvertFrom-Json } finally { Remove-Item $out -ErrorAction SilentlyContinue }
}
# State: tasks\.runtime\T-NNN.json = { taskId, attempts: [...] }. Attempts are appended, never overwritten.
function Read-Rt([string]$id) {
  $p = Join-Path $rtDir "$id.json"
  if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json } else { $null }
}
function Write-Rt([string]$id, $obj) {
  $p = Join-Path $rtDir "$id.json"; $tmp = "$p.tmp"
  [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
  Move-Item -Force $tmp $p
}
function Get-Last($rt) { if ($rt -and $rt.attempts) { @($rt.attempts)[-1] } }
function Test-Alive($a) {
  if (-not $a -or $a.status -ne 'running' -or -not $a.pid) { return $false }
  $p = Get-Process -Id $a.pid -ErrorAction SilentlyContinue
  return [bool]($p -and [long]$p.StartTime.ToUniversalTime().Ticks -eq [long]$a.pidStart)   # pid reuse guard
}
function Test-Held($a) { $a -and $a.status -eq 'running' -and ($a.manual -or -not $a.pid -or (Test-Alive $a)) }

function Remove-Checkout($t) {   # tester checkouts are disposable
  if ($t.role -ne 'tester' -or -not (Test-Path $t.workdir)) { return }
  git -C $root worktree remove --force $t.workdir 2>$null
  if ($LASTEXITCODE -and (Test-Path $t.workdir)) {
    try { Remove-Item -Recurse -Force $t.workdir -ErrorAction Stop; git -C $root worktree prune }
    catch { Write-Warning "could not remove tester checkout $($t.workdir): $($_.Exception.Message)" }
  }
}
function Initialize-Workdir($t) {   # worktree (developer) or disposable checkout (tester), then Setup links and copies
  if ($t.role -eq 'developer') {
    if (Test-Path $t.workdir) {
      $cur = git -C $t.workdir rev-parse --abbrev-ref HEAD 2>$null
      if ($cur -ne $t.branch) { throw "worktree $($t.workdir) is on branch '$cur', task needs '$($t.branch)'. Not this task's: stop." }
      Write-Host "worktree exists on $($t.branch): resume"
    } else {
      git -C $root worktree add $t.workdir -b $t.branch
      if ($LASTEXITCODE) { throw 'git worktree add failed' }
    }
  }
  if ($t.role -eq 'tester') {
    Remove-Checkout $t
    git -C $root worktree add --detach $t.workdir $t.sha
    if ($LASTEXITCODE) { throw 'git worktree add (tester checkout) failed' }
    New-Item -ItemType Directory -Force (Join-Path $rtDir "$($t.id).evidence") | Out-Null
  }
  foreach ($s in @($t.setup)) {
    $src = Join-Path $root $s.path; $dst = Join-Path $t.workdir $s.path
    if (Test-Path $dst) { continue }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    if ($s.kind -eq 'link') { New-Item -ItemType Junction -Path $dst -Target $src | Out-Null }
    else { Copy-Item -Recurse $src $dst }
  }
}
function Get-WorkerEnv($t) {
  $e = [ordered]@{}
  foreach ($p in $t.env.PSObject.Properties) { $e[$p.Name] = $p.Value }
  $e['AGENTFLOW_TARGET'] = $t.target   # after the Task File env: production is never opted into by a task
  if ($t.role -eq 'tester') { $e['AGENTFLOW_EVIDENCE'] = Join-Path $rtDir "$($t.id).evidence" }
  return $e
}
function Complete-Attempt([string]$id, $rt, [string]$state) {   # end-of-attempt check, then the final state
  $a = Get-Last $rt
  try {
    $bad = @((Invoke-Gate endcheck $id).violations)
    Remove-Checkout (Invoke-Gate task $id)
  } catch { $bad = @("end check failed: $($_.Exception.Message)") }
  if ($bad.Count) { $state = 'error'; $a.note = (@($a.note) + $bad | Where-Object { $_ }) -join '; ' }
  $a.status = $state; $a.finishedAt = Now
  Write-Rt $id $rt
  if ($bad.Count) { Write-Warning "$id attempt $($a.n) failed the end check: $($bad -join '; ')" }
}

# --- -Status: process state of the last attempt of every task
if ($Status) {
  Get-ChildItem $rtDir -Filter 'T-*.json' | Where-Object { $_.Name -match '^T-\d+\.json$' } | Sort-Object Name | ForEach-Object {
    $rt = Get-Content $_.FullName -Raw | ConvertFrom-Json; $a = Get-Last $rt
    $state = $a.status
    if ($state -eq 'running' -and -not $a.manual -and -not (Test-Alive $a)) { $state = 'dead' }
    '{0}  {1,-8} attempt={2}  tool={3}  exit={4}  limitHit={5}  finished={6}' -f $rt.taskId, $state, $a.n, $a.tool, $a.exitCode, $a.limitHit, $a.finishedAt
  }
  return
}
if ($TaskId -notmatch '^T-\d+$') { throw 'TaskId T-NNN required' }

# --- -Stop: kill a hung worker (or end a manual attempt), release the lock
if ($Stop) {
  $rt = Read-Rt $TaskId; $a = Get-Last $rt
  if (Test-Alive $a) { taskkill /PID $a.pid /T /F | Out-Null }
  if ($a -and $a.status -eq 'running') {
    $a.exitCode = -1; $a.note = 'stopped with -Stop'
    Complete-Attempt $TaskId $rt 'error'
  }
  Write-Host "$TaskId stopped, lock released"; return
}

# --- -MarkFinished: a manual attempt has finished (no process was observed: exit code stays empty)
if ($MarkFinished) {
  $rt = Read-Rt $TaskId; $a = Get-Last $rt
  if (-not $a -or -not $a.manual -or $a.status -ne 'running') { throw "$TaskId has no running manual attempt (start one with -Manual)" }
  Complete-Attempt $TaskId $rt 'exited'
  Write-Host "$TaskId manual attempt $($a.n): $($a.status)"; return
}

# --- -Worker: runs inside the visible window
if ($Worker) {
  [Console]::OutputEncoding = [Console]::InputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new($false)   # tool output is UTF-8
  $ErrorActionPreference = 'Continue'   # native stderr must not abort the worker
  $spec = $Tools[$Tool]
  $rt = Read-Rt $TaskId; $log = (Get-Last $rt).log
  $code = 1; $note = $null
  try {
    # inside try: the window closes on exit, so a setup error must end up in the state file
    $t = Invoke-Gate task $TaskId
    Set-Location -LiteralPath $t.workdir -ErrorAction Stop
    $e = Get-WorkerEnv $t
    foreach ($k in $e.Keys) { Set-Item "env:$k" $e[$k] }
    $argv = & $spec.args $t.prompt $t.role
    if ($spec.pipe) {
      & $spec.exe @argv 2>&1 | Tee-Object -FilePath $log -Append
    } else {
      Start-Transcript -Path $log -Append | Out-Null
      & $spec.exe @argv
    }
    $code = $LASTEXITCODE
  } catch {
    $note = "launch error: $_"; Write-Host $note
  } finally {
    if (-not $spec.pipe) { try { Stop-Transcript | Out-Null } catch {} }
  }
  Set-Location -LiteralPath $root   # leave the checkout so it can be removed
  $rt = Read-Rt $TaskId; $a = Get-Last $rt   # re-read: the launcher wrote the pid after start
  $a.exitCode = $code
  $a.limitHit = (Test-Path $log) -and [bool](Get-Content $log -Tail 50 | Select-String -Pattern 'usage limit|rate limit|quota' -Quiet)
  if ($note) { $a.note = $note }
  Complete-Attempt $TaskId $rt $(if ($code -eq 0) { 'exited' } else { 'error' })
  Write-Host "`n$TaskId attempt $($a.n): $($a.status) (exit $code)."
  return   # no -NoExit: the window closes here
}

# --- launch (or -Manual): one global mutex from preflight until the state is written, so two launches never pass preflight together
if (-not $Tool -and -not $Manual) { throw 'Tool required: codex | claude | agy (or -Manual)' }
$lockPath = Join-Path $rtDir 'launch.lock'
if ((Test-Path $lockPath) -and ((Get-Date) - (Get-Item $lockPath).LastWriteTime).TotalMinutes -gt 5) {
  Remove-Item $lockPath   # left by a crashed launcher
}
try { $lock = [IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None') }
catch { throw "another run-task.ps1 launch is in progress ($lockPath). Wait and check -Status." }
try {
  $rt = Read-Rt $TaskId; $prev = Get-Last $rt
  if (Test-Held $prev) {
    throw "$TaskId already has a running attempt ($($prev.tool), pid $($prev.pid)). One task = one worker. Stop it first: tools\run-task.ps1 $TaskId -Stop"
  }
  if ($prev -and $prev.status -eq 'running') {
    Write-Warning "previous attempt of $TaskId died without a final state (window closed?). Recovery applies."
    $prev.status = 'error'; $prev.note = 'dead: process gone without a final state'
  }
  $live = @(Get-ChildItem $rtDir -Filter 'T-*.json' | Where-Object { $_.Name -match '^T-\d+\.json$' } | ForEach-Object {
    $o = Get-Content $_.FullName -Raw | ConvertFrom-Json; if (Test-Held (Get-Last $o)) { $o.taskId } })
  $pf = Invoke-Gate preflight $TaskId (@('--live', ($live -join ',')) + $(if ($Manual) { @('--manual') } else { @() }))
  if (-not $pf.ok) {
    throw "$TaskId preflight failed, nothing was created:`n  - $($pf.problems -join "`n  - ")`nFix the Task File (or the project Preflight rules) and launch again."
  }
  $t = $pf.task
  if (-not $Manual -and $t.role -notin 'developer', 'tester') { throw "Role '$($t.role)': the launcher starts developer and tester only. Use -Manual." }
  Initialize-Workdir $t
  if ($Tool -eq 'agy') { Write-Host "Antigravity: make sure '$($t.workdir)' is in its trusted folders before the first run." }

  if (-not $rt) { $rt = [pscustomobject]@{ taskId = $TaskId; attempts = @() } }
  $n = @($rt.attempts).Count + 1
  $a = [pscustomobject][ordered]@{ n = $n; tool = $(if ($Tool) { $Tool } else { 'manual' }); toolArgs = $(if ($Tool -eq 'codex') { $codexArgs -join ' ' })
    role = $t.role; manual = $Manual.IsPresent; status = 'running'; pid = $null; pidStart = $null; exitCode = $null
    startedAt = Now; finishedAt = $null; limitHit = $false; target = $t.target; workdir = $t.workdir
    log = $(if ($Manual) { $null } else { Join-Path $rtDir "$TaskId.$n.log" }); baseline = (Invoke-Gate task $TaskId).baseline; note = $null }
  $rt.attempts = @($rt.attempts) + $a
  Write-Rt $TaskId $rt   # running attempt = lock for the worker's lifetime

  if ($Manual) {
    $e = Get-WorkerEnv $t
    Write-Host "$TaskId attempt $n ready for a manual start.`n  folder: $($t.workdir)`n  env:    $(@($e.Keys | ForEach-Object { "$_=$($e[$_])" }) -join ', ')`n  prompt: $($t.prompt)`nWhen it ends: tools\run-task.ps1 $TaskId -MarkFinished"
    return
  }
  $ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
  $p = Start-Process $ps -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$PSCommandPath`"", $TaskId, $Tool, '-Worker'
  $rt = Read-Rt $TaskId; $cur = Get-Last $rt
  $wp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue   # window closes on exit: may be gone already
  if ($cur.status -eq 'running' -and $wp) {   # worker may already have finished (e.g. tool not found)
    $cur.pid = $p.Id; $cur.pidStart = [long]$wp.StartTime.ToUniversalTime().Ticks
    Write-Rt $TaskId $rt
  }
} finally {
  $lock.Dispose(); Remove-Item $lockPath -ErrorAction SilentlyContinue
}
Write-Host "$TaskId attempt $n started in $Tool (visible window, pid $($p.Id)). log: $($a.log)"
