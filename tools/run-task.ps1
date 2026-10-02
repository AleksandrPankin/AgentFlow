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
  Tester, pre-merge (no "Environment:"): runs in the worktree of the task named in "Checks: T-xxx"; no worktree = stop.
  Tester, live / post-deploy ("Environment: staging" or "prod"): runs in the main folder, no worktree.
  The worker gets the absolute path of its Task File in the main folder: "## Result" is written there.
  Each new attempt starts with a clean log. The window closes when the worker ends.

  The launcher reads tasks\T-NNN-*.md: Role, Branch, Worktree, and lines in "## Environment setup"
  (link/copy sources are required: missing in the main folder = stop before anything is created):
    - link: node_modules        (junction from the main folder into the worktree)
    - copy: viewers\gs\dist     (copied once)
    - env: FOO=bar              (set for the worker process)
  and PORT=NNNN in "## Port". The worker runs in a visible window: this script again with -Worker.

  Preflight (protocol: Launching workers, rule 9): before anything is created the launch checks the
  Task File and stops with the full list of problems: Depends on not done, Allowed files / Port /
  Rebuild together shared with a live worker, Allowed files inside Do not touch, empty or template
  Acceptance criteria / Checks, Branch not named after the task, env: AGENTFLOW_*, and the project
  rules in "## Preflight" of docs\engineering-rules.md or AGENTS.md (deny / require patterns).

  Production is opt-in: the worker gets AGENTFLOW_TARGET = local, or the Environment of a live
  tester (staging | prod). A Task File cannot override it. Project test configs treat "unset" as local.

  Tool command lines in $Tools are defaults: verify them once against your installed versions.
  Machine settings go to environment variables, not into $Tools:
    AGENTFLOW_CODEX       codex executable; wildcards allowed, the newest match wins
    AGENTFLOW_CODEX_ARGS  extra codex exec arguments, space-separated (for example: -m <model>)
  Developer gets a full-access mode, tester does not (protocol: Launching workers, rule 4).
  Tester may write only its own "## Result" and evidence; it gets network for live checks.
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

$codexExe = 'codex'
if ($env:AGENTFLOW_CODEX) {   # machine override; wildcards allowed, newest match wins
  $m = Get-Item $env:AGENTFLOW_CODEX -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  $codexExe = if ($m) { $m.FullName } else { $env:AGENTFLOW_CODEX }
}
$codexArgs = @(if ($env:AGENTFLOW_CODEX_ARGS) { $env:AGENTFLOW_CODEX_ARGS.Trim() -split '\s+' })

# Defaults, verify once. pipe = output goes through Tee into the log (non-interactive mode).
# Interactive tools (pipe = $false) keep the window until a human exits them; the log is a transcript.
# Tester: no full access, but it must write its "## Result" in the main folder's tasks\ (codex: --add-dir; claude: Edit).
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

# Task File parsing. HTML comments (template hints) are not content.
function Get-Section([string]$text, [string]$name) {
  if ($text -match "(?ms)^## $([regex]::Escape($name))\s*\r?\n(.*?)(?=^## |\z)") { $Matches[1] -replace '(?s)<!--.*?-->', '' } else { '' }
}
function Get-Bullets([string]$body) { @([regex]::Matches($body, '(?m)^\s*-\s+(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value }) }
function Get-Paths([string]$body) {   # first token of each bullet that looks like a path: "- `src/a.ts` - why"
  @(Get-Bullets $body | ForEach-Object {
    $tok = if ($_ -match '^`([^`]+)`') { $Matches[1] } else { ($_ -split '\s+')[0] }
    if ($tok -match '[\\/.*]') { ($tok -replace '\\', '/' -replace '^\./', '').TrimEnd('/').ToLower() }
  })
}
function Get-Commands([string]$body) { @(Get-Bullets $body | ForEach-Object { if ($_ -match '`([^`]+)`') { $Matches[1] } }) }
function Test-Glob([string]$pattern, [string]$path) {   # * and ** both match across '/': conservative
  if ($pattern -notmatch '[*?]') { return $false }
  $rx = '^' + ([regex]::Escape($pattern) -replace '(\\\*)+', '.*' -replace '\\\?', '.') + '(/.*)?$'
  return $path -match $rx
}
function Test-Overlap([string]$a, [string]$b) {   # same file, one folder contains the other, or a glob matches
  return ($a -eq $b -or $a.StartsWith("$b/") -or $b.StartsWith("$a/") -or (Test-Glob $a $b) -or (Test-Glob $b $a))
}

function Get-Task([string]$id, [switch]$Prepare) {
  $f = Get-ChildItem (Join-Path $root 'tasks') -Filter "$id-*.md" | Select-Object -First 1
  if (-not $f) { throw "Task File tasks\$id-*.md not found" }
  $text = Get-Content $f.FullName -Raw -Encoding utf8
  $field = { param($n) if ($text -match "(?m)^$n\s*:\s*(.+?)\s*(<!--.*)?$") { $Matches[1].Trim() } }
  $section = { param($n) Get-Section $text $n }

  $t = @{ id = $id; file = $f.FullName; rel = "tasks/$($f.Name)"; text = $text; role = & $field 'Role'
          branch = & $field 'Branch'; worktree = & $field 'Worktree'; depends = & $field 'Depends on'; env = @{}
          allowed = Get-Paths (& $section 'Allowed files'); denied = Get-Paths (& $section 'Do not touch')
          rebuild = @(Get-Bullets (& $section 'Rebuild together') | ForEach-Object { (($_ -replace '`', '') -split '\s+')[0].ToLower() } | Where-Object { $_ -match '[a-z0-9]' })
          checks = Get-Commands (& $section 'Checks'); checkItems = Get-Bullets (& $section 'Checks')
          acceptance = Get-Bullets (& $section 'Acceptance criteria'); target = 'local' }
  # absolute path: the worker runs in a worktree, but its Task File (and "## Result") lives in the main folder
  $t.prompt = "Your role: roles/$($t.role).md. Your task: $($t.file). Follow docs/ai-handoff-protocol.md, section 'Starting a role session'."

  # live / post-deploy tester: checks a deployed environment from the main folder, needs no worktree
  $live = $t.role -eq 'tester' -and ((& $field 'Environment') -match '^(staging|prod)$')
  if ($live) { $t.worktree = $null; $t.target = $Matches[1] }
  if ($t.role -eq 'tester' -and -not $live) {
    # pre-merge tester runs in the worktree of the task it checks (field "Checks: T-xxx, commit <SHA>")
    $checks = & $field 'Checks'
    if ($checks -notmatch '(T-\d+)') { throw 'tester task needs "Checks: T-xxx, commit <SHA>"' }
    $t.checked = $Matches[1]
    $target = Get-ChildItem (Join-Path $root 'tasks') -Filter "$($Matches[1])-*.md" | Select-Object -First 1
    if (-not $target) { throw "checked task $($Matches[1]) has no Task File" }
    $tt = Get-Content $target.FullName -Raw -Encoding utf8
    $t.checkedResult = Get-Section $tt 'Result'
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

function Get-LedgerStatus {   # ID -> Status from state\tasks.md
  $st = @{}; $col = -1
  foreach ($l in Get-Content (Join-Path $root 'state\tasks.md') -Encoding utf8) {
    if (-not $l.StartsWith('|')) { continue }
    $c = @($l.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    if ($c[0] -eq 'ID') { $col = [array]::IndexOf($c, 'Status') }
    elseif ($col -ge 0 -and $c[0] -match '^T-\d+$') { $st[$c[0]] = $c[$col] }
  }
  return $st
}

# --- preflight: all problems of a Task File at once, before anything is created (protocol: Launching workers, rule 9)
function Test-Preflight($t) {
  $bad = [Collections.Generic.List[string]]::new()
  $ledger = Get-LedgerStatus
  $tpl = Get-Content (Join-Path $root 'tasks\_template.md') -Raw -Encoding utf8

  if ($t.role -eq 'developer' -and $t.branch -and $t.branch -notlike "$($t.id.ToLower())-*") {
    $bad.Add("Branch '$($t.branch)' is not named after the task ($($t.id.ToLower())-slug)")
  }
  foreach ($s in 'Acceptance criteria', 'Checks') {
    $own = @(Get-Bullets (Get-Section $t.text $s)); $stub = @(Get-Bullets (Get-Section $tpl $s))
    if (-not ($own | Where-Object { $_ -notin $stub })) { $bad.Add("## $s is empty or still the template text") }
  }
  foreach ($k in $t.env.Keys) { if ($k -like 'AGENTFLOW_*') { $bad.Add("env: $k is set by the launcher, not by a Task File") } }
  foreach ($a in @($t.allowed)) { foreach ($d in @($t.denied)) { if (Test-Overlap $a $d) { $bad.Add("Allowed files '$a' overlaps Do not touch '$d'") } } }

  foreach ($d in @([regex]::Matches("$($t.depends)", 'T-\d+') | ForEach-Object { $_.Value })) {
    if ($d -eq $t.checked) { continue }   # pre-merge tester: the checked task is in review, not done
    if ($ledger[$d] -ne 'done') { $bad.Add("Depends on $d is '$($ledger[$d])' in the ledger, needs 'done'") }
  }
  if ($t.checked -and $t.checkedResult -notmatch '(?m)^Status\s*:\s*(done|partial)\b') {
    $bad.Add("checked task $($t.checked) has no Result with Status done or partial")
  }

  # other tasks: issued and not accepted (ledger) or with a worker process (runtime, also mid-launch)
  $live = @{}
  foreach ($f in Get-ChildItem $rtDir -Filter 'T-*.json') {
    $rt = Get-Content $f.FullName -Raw | ConvertFrom-Json
    if ($rt.status -eq 'running' -and ((Test-Alive $rt) -or -not $rt.pid)) { $live[$rt.taskId] = $true }
  }
  $open = @($ledger.Keys | Where-Object { $ledger[$_] -in 'in progress', 'review' }) + @($live.Keys) | Sort-Object -Unique
  foreach ($id in $open) {
    if ($id -eq $t.id) { continue }
    if ($id -eq $t.checked) {
      if ($live[$id]) { $bad.Add("checked task $id still has a live worker") }
      continue
    }
    try { $o = Get-Task $id } catch { continue }   # no Task File / not launchable: nothing to compare
    foreach ($a in @($t.allowed)) { foreach ($b in @($o.allowed)) { if (Test-Overlap $a $b) { $bad.Add("Allowed files '$a' overlaps $id '$b' (not merged yet)") } } }
    foreach ($r in @($t.rebuild)) { if ($r -in @($o.rebuild)) { $bad.Add("Rebuild together '$r' is shared with $id") } }
    if ($live[$id] -and $t.env['PORT'] -and $t.env['PORT'] -eq $o.env['PORT']) { $bad.Add("PORT=$($t.env['PORT']) is used by running $id") }
  }

  # project rules: "## Preflight" in docs\engineering-rules.md and/or AGENTS.md, for commands that run against local
  #   - deny: <regex>                  no Checks command or Environment setup line may match
  #   - require: <regex> => <regex>    a Checks command matching the first must match the second
  $rules = @('docs\engineering-rules.md', 'AGENTS.md' | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ } |
    ForEach-Object { Get-Bullets (Get-Section (Get-Content $_ -Raw -Encoding utf8) 'Preflight') })
  if ($t.target -eq 'local') {
    $run = @($t.checks) + @(Get-Bullets (Get-Section $t.text 'Environment setup'))
    foreach ($r in $rules) {
      try {
        if ($r -match '^deny\s*:\s*`?(.+?)`?$') {
          $rx = $Matches[1]
          foreach ($c in $run) { if ($c -match $rx) { $bad.Add("'$c' matches project deny rule '$rx'") } }
        } elseif ($r -match '^require\s*:\s*`?(.+?)`?\s*=>\s*`?(.+?)`?$') {
          $when = $Matches[1]; $need = $Matches[2]
          foreach ($c in @($t.checks)) { if ($c -match $when -and $c -notmatch $need) { $bad.Add("'$c' must match '$need' (project rule for '$when')") } }
        }
      } catch { $bad.Add("project Preflight: bad rule '$r': $($_.Exception.Message)") }
    }
  }

  if ($bad.Count) {
    throw "$($t.id) preflight failed, nothing was created:`n  - $($bad -join "`n  - ")`nFix the Task File (or the project Preflight rules) and launch again."
  }
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
  [Console]::OutputEncoding = [Console]::InputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new($false)   # tool output is UTF-8
  $ErrorActionPreference = 'Continue'   # native stderr must not abort the worker
  $spec = $Tools[$Tool]
  $log = Join-Path $rtDir "$TaskId.log"
  $code = 1; $note = $null
  try {
    # inside try: the window closes on exit, so a setup error must end up in the state file
    $t = Get-Task $TaskId
    Set-Location -LiteralPath $t.workdir -ErrorAction Stop
    foreach ($k in $t.env.Keys) { Set-Item "env:$k" $t.env[$k] }
    $env:AGENTFLOW_TARGET = $t.target   # after the Task File env: production is never opted into by a task
    $a = & $spec.args $t.prompt $t.role
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
  Write-Host "`n$TaskId process $($rt.status) (exit $code)."
  return   # no -NoExit: the window closes here
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

  $t = Get-Task $TaskId
  if ($t.role -notin 'developer', 'tester') {
    throw "Role '$($t.role)': this launcher starts developer and tester only. Deployer runs in the session the human designated."
  }
  Test-Preflight $t
  $t = Get-Task $TaskId -Prepare
  if ($Tool -eq 'agy') { Write-Host "Antigravity: make sure '$($t.workdir)' is in its trusted folders before the first run." }

  $log = Join-Path $rtDir "$TaskId.log"
  if (Test-Path $log) { Remove-Item $log }   # new attempt = clean log
  $rt = [ordered]@{ taskId = $TaskId; tool = $Tool; role = $t.role; status = 'running'; pid = $null; pidStart = $null
    exitCode = $null; startedAt = Now; finishedAt = $null; limitHit = $false; taskFile = $t.rel; log = $log; note = $null }
  Write-Rt $TaskId $rt   # running state = lock for the worker's lifetime

  $ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
  $p = Start-Process $ps -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$PSCommandPath`"", $TaskId, $Tool, '-Worker'
  $cur = Read-Rt $TaskId
  $wp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue   # window closes on exit: may be gone already
  if ($cur.status -eq 'running' -and $wp) {   # worker may already have finished (e.g. tool not found)
    $cur.pid = $p.Id; $cur.pidStart = [long]$wp.StartTime.ToUniversalTime().Ticks
    Write-Rt $TaskId $cur
  }
} finally {
  $lock.Dispose(); Remove-Item $lockPath -ErrorAction SilentlyContinue
}
Write-Host "$TaskId started in $Tool (visible window, pid $($p.Id)). log: $log"
