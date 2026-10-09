<#
.SYNOPSIS
  Launch one worker attempt for one task and track its process state.

.EXAMPLE
  .agentflow\tools\run-task.ps1 T-007 codex          # launch a developer or tester task in a visible window
  .agentflow\tools\run-task.ps1 T-007 -Manual        # same gate and preparation, no process: a human starts the tool
  .agentflow\tools\run-task.ps1 -Status              # process state of the last attempt of every task
  .agentflow\tools\run-task.ps1 -Limits              # last usage-limit hit per tool, with the log line
  .agentflow\tools\run-task.ps1 -Wait [T-007,T-008]  # block until a task finishes (no ids: every running one), print one line
  .agentflow\tools\run-task.ps1 T-007 -Stop          # end a worker (whole process tree), release the lock
  .agentflow\tools\run-task.ps1 T-007 -MarkFinished  # a manual attempt has finished
  .agentflow\tools\run-task.ps1 T-007 -Cleanup       # after the worktree is removed: drop the task's folder trust entries

.DESCRIPTION
  Rules: .agentflow/protocol.md, sections "Runtime state" and "Launching workers".
  Task File parsing, preflight and end-of-attempt checks: .agentflow/tools/gate.py. This script does the side effects:
  worktrees and checkouts, environment, windows, processes, docs\tasks\.runtime\T-NNN.json (attempt history).
  Tool command lines in $Tools are defaults: verify them once against your installed versions.
  Machine settings are environment variables, not edits of $Tools:
    AGENTFLOW_CODEX       codex executable; wildcards allowed, the newest match wins
    AGENTFLOW_CODEX_ARGS  extra codex exec arguments, space-separated (for example: -m <model>)
    AGENTFLOW_AGY_SETTINGS  Antigravity CLI settings file (default %USERPROFILE%\.gemini\antigravity-cli\settings.json)
  -Wait exit codes: 0 a task finished, 3 timeout (-TimeoutMin), 4 nothing to wait for.
#>
param(
  [Parameter(Position = 0)][string]$TaskId,
  [Parameter(Position = 1)][ValidateSet('codex', 'claude', 'agy')][string]$Tool,
  [switch]$Status,
  [switch]$Limits,
  [switch]$Wait,
  [int]$PollSec = 30,
  [int]$TimeoutMin = 0,
  [int]$GraceSec = 20,
  [switch]$Stop,
  [switch]$MarkFinished,
  [switch]$Cleanup,
  [switch]$Manual,
  [switch]$Worker
)
$ErrorActionPreference = 'Stop'
$flow = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path   # .agentflow/: template-owned
$root = Split-Path $flow -Parent                              # project root: code and docs/
$rtDir = Join-Path $root 'docs\tasks\.runtime'
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
# Model and effort ($l = the task's resolved launch: .agentflow/tools/models.json via gate.py) are added only when the Task File
# sets them: no Model / Effort line = the tool's own default, the command line as before.
function Get-CodexArgs($l) {   # AGENTFLOW_CODEX_ARGS without the model / effort the task sets itself (the task wins)
  $out = [Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $codexArgs.Count; $i++) {
    $x = $codexArgs[$i]
    if ($l.model -and $x -in '-m', '--model') { $i++; continue }
    if ($l.model -and $x -like '--model=*') { continue }
    if ($l.effort -and $x -in '-c', '--config' -and $codexArgs[$i + 1] -like 'model_reasoning_effort=*') { $i++; continue }
    $out.Add($x)
  }
  @($out) + @(if ($l.model) { '-m', $l.model }) + @(if ($l.effort) { '-c', "model_reasoning_effort=`"$($l.effort)`"" })
}
function Get-ModelArgs($l) { @(if ($l.model) { '--model', $l.model }) + @(if ($l.effort) { '--effort', $l.effort }) }   # claude, agy
$Tools = @{
  codex  = @{ exe = $codexExe; pipe = $true
              args = { param($p, $r, $l)
                if ($r -eq 'developer') { @('exec') + (Get-CodexArgs $l) + @('--sandbox', 'danger-full-access', $p) }
                else { @('exec') + (Get-CodexArgs $l) + @('--sandbox', 'workspace-write', '--add-dir', (Join-Path $root 'docs\tasks'), '-c', 'sandbox_workspace_write.network_access=true', $p) } } }
  claude = @{ exe = 'claude'; pipe = $true   # -p prints the answer only at the end
              args = { param($p, $r, $l) $(if ($r -eq 'developer') { @('-p', $p, '--dangerously-skip-permissions') } else { @('-p', $p, '--allowedTools', 'Read,Grep,Glob,Bash,Edit') }) + (Get-ModelArgs $l) } }
  agy    = @{ exe = 'agy'; pipe = $false       # -i only: -p prints nothing until the end
              args = { param($p, $r, $l) $(if ($r -eq 'developer') { @('-i', $p, '--dangerously-skip-permissions') } else { @('-i', $p) }) + (Get-ModelArgs $l) } }
}

function Now { [DateTime]::UtcNow.ToString('s') + 'Z' }
function Invoke-Gate([string]$cmd, [string]$id, [string[]]$more = @()) {   # .agentflow/tools/gate.py -> object; exit 2 = gate error
  $out = Join-Path $rtDir "$id.gate.$PID.$([guid]::NewGuid().ToString('N').Substring(0, 8)).json"   # unique: -Wait and the worker window call it at once
  $msg = & python (Join-Path $flow 'tools\gate.py') $cmd $id @more --out $out 2>&1
  if ($LASTEXITCODE -ge 2 -or -not (Test-Path $out)) { throw "gate.py $cmd ${id}: $msg" }
  try { Get-Content $out -Raw -Encoding utf8 | ConvertFrom-Json } finally { Remove-Item $out -ErrorAction SilentlyContinue }
}
# State: docs\tasks\.runtime\T-NNN.json = { taskId, attempts: [...] }. Attempts are appended, never overwritten.
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
function Get-State($a) {   # process state as the protocol names it; 'dead' = running without a live process
  if ($a.status -eq 'running' -and -not $a.manual -and -not (Test-Alive $a)) { 'dead' } else { $a.status }
}

# Antigravity CLI asks "Do you trust this project?" for every new folder; trustedWorkspaces is an exact-path list.
# The launcher adds the worker folder before the start and removes it on cleanup; other keys and entries are kept.
function Set-AgyTrust([string]$dir, [bool]$add) {
  $p = if ($env:AGENTFLOW_AGY_SETTINGS) { $env:AGENTFLOW_AGY_SETTINGS } else { Join-Path $env:USERPROFILE '.gemini\antigravity-cli\settings.json' }
  if (-not $add -and -not (Test-Path $p)) { return }
  $json = if (Test-Path $p) { Get-Content $p -Raw -Encoding utf8 } else { '' }
  $node = [Text.Json.Nodes.JsonObject]::new()   # assigned directly: PowerShell would enumerate a node returned from an if
  if ("$json".Trim()) { $node = [Text.Json.Nodes.JsonNode]::Parse($json) }
  $list = $node['trustedWorkspaces']
  if ($null -eq $list) { if (-not $add) { return }; $list = [Text.Json.Nodes.JsonArray]::new(); $node['trustedWorkspaces'] = $list }
  $hits = @(for ($i = $list.Count - 1; $i -ge 0; $i--) { if ([string]$list[$i] -eq $dir) { $i } })   # -eq: case-insensitive
  if ($add -and $hits) { return }
  if (-not $add -and -not $hits) { return }
  if ($add) { $list.Add([Text.Json.Nodes.JsonValue]::Create($dir)) } else { foreach ($i in $hits) { $list.RemoveAt($i) } }
  $opt = [Text.Json.JsonSerializerOptions]@{ WriteIndented = $true; Encoder = [Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping }
  New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
  $tmp = "$p.agentflow.tmp"
  [IO.File]::WriteAllText($tmp, $node.ToJsonString($opt), [Text.UTF8Encoding]::new($false))
  Move-Item -Force $tmp $p
}

function Remove-Checkout($t) {   # tester checkouts are disposable
  if ($t.role -ne 'tester') { return }
  try { Set-AgyTrust $t.workdir $false } catch { Write-Warning "could not remove the Antigravity trust entry: $($_.Exception.Message)" }
  if (-not (Test-Path $t.workdir)) { return }
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

# End a running attempt: kill the process tree, then the end check. With a valid Outcome in the Result the
# worker has finished (an interactive tool keeps its window open): 'exited'. Without one: 'error' (hung worker).
function Stop-Attempt([string]$id, [string]$how) {
  $rt = Read-Rt $id; $a = Get-Last $rt
  if (Test-Alive $a) { taskkill /PID $a.pid /T /F | Out-Null }
  if (-not $a -or $a.status -ne 'running') { return }
  if ((Invoke-Gate result $id).class -ne 'none') { $a.note = "closed after Result ($how)"; Complete-Attempt $id $rt 'exited' }
  else { $a.exitCode = -1; $a.note = "stopped with $how"; Complete-Attempt $id $rt 'error' }
}
function Format-Finished([string]$id, [string]$state, $r, [string]$note) {   # the one line -Wait prints
  $s = "$id finished: attempt=$state result=$($r.class)"
  if ($r.roleValue) { $s += " $($r.roleField)=$($r.roleValue)" }
  if ($r.problem) { $s += " problem=`"$($r.problem)`"" }
  if ($r.class -ne 'none' -and $r.formatOk -eq $false) { $s += ' format=loose (verify reads strict fields)' }
  if ((Get-Last (Read-Rt $id)).limitHit) { $s += ' limit' }
  if ($note) { $s += " note=`"$note`"" }
  $s
}

# --- -Status: process state of the last attempt of every task
if ($Status) {
  Get-ChildItem $rtDir -Filter 'T-*.json' | Where-Object { $_.Name -match '^T-\d+\.json$' } | Sort-Object Name | ForEach-Object {
    $rt = Get-Content $_.FullName -Raw | ConvertFrom-Json; $a = Get-Last $rt
    $res = try { (Invoke-Gate result $rt.taskId).class } catch { '?' }
    $mdl = if ($a.model -or $a.effort) { "  model=$(if ($a.model) { $a.model } else { 'default' })$(if ($a.effort) { "/$($a.effort)" })" } else { '' }
    '{0}  {1,-8} attempt={2}  tool={3}{8}  exit={4}  limitHit={5}  result={6}  finished={7}' -f $rt.taskId, (Get-State $a), $a.n, $a.tool, $a.exitCode, $a.limitHit, $res, $a.finishedAt, $mdl
  }
  return
}

# --- -Limits: the last usage-limit hit per tool, with the log line (it usually names the reset time)
if ($Limits) {
  $hits = @(Get-ChildItem $rtDir -Filter 'T-*.json' | Where-Object { $_.Name -match '^T-\d+\.json$' } | ForEach-Object {
      $o = Get-Content $_.FullName -Raw | ConvertFrom-Json
      foreach ($x in @($o.attempts)) { if ($x.limitHit) { [pscustomobject]@{ task = $o.taskId; a = $x } } } })
  foreach ($tool in $Tools.Keys | Sort-Object) {
    $last = $hits | Where-Object { $_.a.tool -eq $tool } | Sort-Object { [string]$_.a.finishedAt } | Select-Object -Last 1
    if ($last) { '{0,-7} last limit: {1} attempt {2}, finished {3}: {4}' -f $tool, $last.task, $last.a.n, $last.a.finishedAt, $(if ($last.a.limitText) { $last.a.limitText } else { '(no log line kept)' }) }
    else { '{0,-7} no limit hit recorded' -f $tool }
  }
  return
}

# --- -Wait: block until one task finishes, print one line, exit. No model, no network: the host tool runs it in
# the background (Claude Code run_in_background re-invokes the session on exit). Finished = the process ended,
# or (interactive tool, manual attempt) the Result has a valid Outcome unchanged for -GraceSec; an interactive
# window is then closed as 'exited' (a developer only with a clean worktree at its Change).
if ($Wait) {
  $ids = @(if ($TaskId) { $TaskId -split '[\s,;]+' | Where-Object { $_ } } else {
      Get-ChildItem $rtDir -Filter 'T-*.json' | Where-Object { $_.Name -match '^T-\d+\.json$' } | Sort-Object Name | ForEach-Object {
        $o = Get-Content $_.FullName -Raw | ConvertFrom-Json; if ((Get-Last $o).status -eq 'running') { $o.taskId } } })
  foreach ($id in $ids) { if ($id -notmatch '^T-\d+$') { throw "not a task id: $id" } }
  if (-not $ids) { Write-Output 'nothing to wait for'; exit 4 }
  $deadline = if ($TimeoutMin -gt 0) { (Get-Date).AddMinutes($TimeoutMin) }
  $seen = @{}   # id -> Result hash and when it last changed
  while ($true) {
    foreach ($id in $ids) {
      $a = Get-Last (Read-Rt $id); $state = if ($a) { Get-State $a } else { 'none' }
      $r = Invoke-Gate result $id
      if ($state -ne 'running') { Write-Output (Format-Finished $id $state $r ''); exit 0 }
      $byResult = $a.manual -or ($Tools[$a.tool] -and -not $Tools[$a.tool].pipe)   # pipe tools exit by themselves
      if (-not $byResult -or $r.class -eq 'none') { continue }
      if (-not $seen[$id] -or $seen[$id].hash -ne $r.hash) { $seen[$id] = @{ hash = $r.hash; at = Get-Date }; continue }
      if (((Get-Date) - $seen[$id].at).TotalSeconds -lt $GraceSec) { continue }
      $note = ''
      if ($a.manual) { $note = 'manual attempt: end it with -MarkFinished' }
      else {
        $dirty = $a.role -eq 'developer' -and $r.class -eq 'completed' -and (
          (git -C $a.workdir status --porcelain 2>$null) -or -not "$(git -C $a.workdir rev-parse HEAD 2>$null)".StartsWith($r.roleValue))
        if ($dirty) { $note = 'window left open: worktree not clean at Change' }
        else { Stop-Attempt $id '-Wait'; $state = (Get-Last (Read-Rt $id)).status; $note = 'window closed after Result' }
      }
      Write-Output (Format-Finished $id $state $r $note); exit 0
    }
    if ($deadline -and (Get-Date) -gt $deadline) { Write-Output "timeout after $TimeoutMin min, still running: $($ids -join ', ')"; exit 3 }
    Start-Sleep -Seconds $PollSec
  }
}
if ($TaskId -notmatch '^T-\d+$') { throw 'TaskId T-NNN required' }

# --- -Stop: end a worker (or a manual attempt), release the lock
if ($Stop) {
  Stop-Attempt $TaskId '-Stop'
  $a = Get-Last (Read-Rt $TaskId)
  Write-Host "$TaskId stopped ($($a.status)), lock released"; return
}

# --- -Cleanup: after the worktree is removed, drop the folder trust entries of the task's attempts
if ($Cleanup) {
  $rt = Read-Rt $TaskId
  if (Test-Held (Get-Last $rt)) { throw "$TaskId has a running attempt: -Stop it first" }
  $dirs = @($rt.attempts | ForEach-Object { $_.workdir } | Where-Object { $_ } | Select-Object -Unique)
  foreach ($d in $dirs) { Set-AgyTrust $d $false }
  Write-Host "$TaskId cleanup: trust entries removed for $(if ($dirs) { $dirs -join ', ' } else { 'no folders' })"; return
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
    $t = Invoke-Gate task $TaskId @('--tool', $Tool)
    Set-Location -LiteralPath $t.workdir -ErrorAction Stop
    $e = Get-WorkerEnv $t
    foreach ($k in $e.Keys) { Set-Item "env:$k" $e[$k] }
    $argv = & $spec.args $t.prompt $t.role $t.launch
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
  $hit = if (Test-Path $log) { Get-Content $log -Tail 50 | Select-String -Pattern 'usage limit|rate limit|quota' | Select-Object -Last 1 }
  $a.limitHit = [bool]$hit
  if ($hit) { $line = "$($hit.Line)".Trim(); $a | Add-Member -Force -NotePropertyName limitText -NotePropertyValue $line.Substring(0, [Math]::Min(200, $line.Length)) }   # often names the reset time
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
    throw "$TaskId already has a running attempt ($($prev.tool), pid $($prev.pid)). One task = one worker. Stop it first: .agentflow\tools\run-task.ps1 $TaskId -Stop"
  }
  if ($prev -and $prev.status -eq 'running') {
    Write-Warning "previous attempt of $TaskId died without a final state (window closed?). Recovery applies."
    $prev.status = 'error'; $prev.note = 'dead: process gone without a final state'
  }
  $live = @(Get-ChildItem $rtDir -Filter 'T-*.json' | Where-Object { $_.Name -match '^T-\d+\.json$' } | ForEach-Object {
    $o = Get-Content $_.FullName -Raw | ConvertFrom-Json; if (Test-Held (Get-Last $o)) { $o.taskId } })
  $pf = Invoke-Gate preflight $TaskId (@('--live', ($live -join ',')) + $(if ($Manual) { @('--manual') } else { @('--tool', $Tool) }))
  if (-not $pf.ok) {
    throw "$TaskId preflight failed, nothing was created:`n  - $($pf.problems -join "`n  - ")`nFix the Task File (or the project Preflight rules) and launch again."
  }
  $t = $pf.task
  if (-not $Manual -and $t.role -notin 'developer', 'tester') { throw "Role '$($t.role)': the launcher starts developer and tester only. Use -Manual." }
  Initialize-Workdir $t
  if ($Tool -eq 'agy') {
    try { Set-AgyTrust $t.workdir $true }
    catch { Write-Warning "Antigravity: could not add '$($t.workdir)' to its trusted folders ($($_.Exception.Message)); confirm the prompt in its window." }
  }

  if (-not $rt) { $rt = [pscustomobject]@{ taskId = $TaskId; attempts = @() } }
  $n = @($rt.attempts).Count + 1
  $a = [pscustomobject][ordered]@{ n = $n; tool = $(if ($Tool) { $Tool } else { 'manual' }); toolArgs = $(if ($Tool -eq 'codex') { (Get-CodexArgs $t.launch) -join ' ' })
    role = $t.role; manual = $Manual.IsPresent; status = 'running'; pid = $null; pidStart = $null; exitCode = $null
    startedAt = Now; finishedAt = $null; limitHit = $false; model = $t.launch.model; effort = $t.launch.effort; target = $t.target; workdir = $t.workdir
    log = $(if ($Manual) { $null } else { Join-Path $rtDir "$TaskId.$n.log" }); baseline = (Invoke-Gate task $TaskId).baseline; note = $null }
  $rt.attempts = @($rt.attempts) + $a
  Write-Rt $TaskId $rt   # running attempt = lock for the worker's lifetime

  if ($Manual) {
    $e = Get-WorkerEnv $t
    Write-Host "$TaskId attempt $n ready for a manual start.`n  folder: $($t.workdir)`n  env:    $(@($e.Keys | ForEach-Object { "$_=$($e[$_])" }) -join ', ')`n  prompt: $($t.prompt)$(if ($t.modelSpec -or $t.effortSpec) { "`n  model:  Model: $($t.modelSpec) Effort: $($t.effortSpec) (start the tool with it)" })`nWhen it ends: .agentflow\tools\run-task.ps1 $TaskId -MarkFinished"
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
Write-Host "$TaskId attempt $n started in $Tool$(if ($a.model -or $a.effort) { " (model $(if ($a.model) { $a.model } else { 'default' }), effort $(if ($a.effort) { $a.effort } else { 'default' }))" }) (visible window, pid $($p.Id)). log: $($a.log)"
