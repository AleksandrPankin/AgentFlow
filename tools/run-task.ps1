<#
.SYNOPSIS
  Launch one worker session for one task and track its process state.

.EXAMPLE
  tools\run-task.ps1 T-007 codex          # launch a developer or tester task in a visible window
  tools\run-task.ps1 T-007 -Manual        # same gate and preparation, no process: a human starts the tool
  tools\run-task.ps1 -Status              # process state of all tasks
  tools\run-task.ps1 T-007 -Stop          # kill a hung worker (whole process tree), release the lock
  tools\run-task.ps1 T-007 -MarkFinished  # a manual attempt has finished

.DESCRIPTION
  Rules: docs/ai-handoff-protocol.md, sections "Runtime state" and "Launching workers".
  State: tasks\.runtime\T-NNN.json, written only by this script.
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
function Test-Held($rt) { $rt -and $rt.status -eq 'running' -and ($rt.manual -or -not $rt.pid -or (Test-Alive $rt)) }
function Get-Hash([string]$s) { [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($s))) -replace '-', '' }
function Get-Git([string]$dir) { $o = git -C $dir @args 2>$null; if ($LASTEXITCODE) { $null } else { "$o".Trim() } }

# Task File parsing. HTML comments (template hints) are not content.
function Get-Section([string]$text, [string]$name) {
  if ($text -match "(?ms)^## $([regex]::Escape($name))\s*\r?\n(.*?)(?=^## |\z)") { $Matches[1] -replace '(?s)<!--.*?-->', '' } else { '' }
}
function Get-Header([string]$text) { ($text -replace "`r`n", "`n") -replace '(?ms)^## Result\s*$.*\z', '' }   # everything the worker must not change
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

# -Brief: fields only, no git checks (used to compare with other open tasks).
function Get-Task([string]$id, [switch]$Prepare, [switch]$Brief) {
  $f = Get-ChildItem (Join-Path $root 'tasks') -Filter "$id-*.md" | Select-Object -First 1
  if (-not $f) { throw "Task File tasks\$id-*.md not found" }
  $text = Get-Content $f.FullName -Raw -Encoding utf8
  $field = { param($n, $src = $text) if ($src -match "(?m)^$n\s*:\s*(.+?)\s*(<!--.*)?$") { $Matches[1].Trim() } }
  $section = { param($n) Get-Section $text $n }

  $t = @{ id = $id; file = $f.FullName; rel = "tasks/$($f.Name)"; text = $text; role = & $field 'Role'
          branch = & $field 'Branch'; worktree = & $field 'Worktree'; depends = & $field 'Depends on'; env = @{}
          allowed = Get-Paths (& $section 'Allowed files'); denied = Get-Paths (& $section 'Do not touch')
          rebuild = @(Get-Bullets (& $section 'Rebuild together') | ForEach-Object { (($_ -replace '`', '') -split '\s+')[0].ToLower() } | Where-Object { $_ -match '[a-z0-9]' })
          checks = Get-Commands (& $section 'Checks'); target = 'local' }
  # absolute path: the worker runs in a worktree or checkout, but its Task File (and "## Result") lives in the main folder
  $t.prompt = "Your role: roles/$($t.role).md. Your task: $($t.file). Follow docs/ai-handoff-protocol.md, section 'Starting a role session'."

  if ($t.role -in 'tester', 'deployer') {
    $tg = & $field 'Target'
    if ($tg) {
      if ($tg -notmatch '^(staging|prod)$') { throw "Target '$tg': expected staging or prod" }
      $t.target = $tg
    }
  }
  if ($t.role -eq 'tester') {
    # the checked task and commit: "Verifies: T-xxx @ <SHA>"
    if ((& $field 'Verifies') -notmatch '^(T-\d+)\s*@\s*([0-9a-fA-F]{7,40})$') { throw 'tester task needs "Verifies: T-xxx @ <SHA>"' }
    $t.checked = $Matches[1]; $t.sha = $Matches[2].ToLower()
    $cf = Get-ChildItem (Join-Path $root 'tasks') -Filter "$($t.checked)-*.md" | Select-Object -First 1
    if (-not $cf) { throw "checked task $($t.checked) has no Task File" }
    $tt = Get-Content $cf.FullName -Raw -Encoding utf8
    $t.checkedFile = $cf.FullName; $t.checkedResult = Get-Section $tt 'Result'
    $t.checkedBranch = & $field 'Branch' $tt; $t.checkedWorktree = & $field 'Worktree' $tt
    if (-not $t.checkedWorktree) { throw "checked task $($cf.Name) has no Worktree" }
    $t.worktree = "$($t.checkedWorktree).$($id.ToLower())"   # disposable checkout of the checked commit
    if (-not $Brief) {
      if ($t.target -eq 'local') {   # before merge: the branch must still be at the checked commit
        $head = Get-Git $root rev-parse --verify --quiet "$($t.checkedBranch)^{commit}"
        if (-not $head -or -not $head.StartsWith($t.sha)) { throw "branch '$($t.checkedBranch)' is at '$head', task verifies $($t.sha)" }
      } else {                       # live: the checked commit must be merged
        git -C $root merge-base --is-ancestor $t.sha HEAD 2>$null
        if ($LASTEXITCODE) { throw "commit $($t.sha) is not merged into the main branch" }
      }
    }
  }
  if ($t.role -eq 'deployer') {
    if ((& $field 'Deploys') -notmatch '^([0-9a-fA-F]{7,40})') { throw 'deployer task needs "Deploys: <SHA>"' }
    $t.sha = $Matches[1].ToLower()
    if ($t.target -eq 'local') { throw 'deployer task needs "Target: staging | prod"' }
    if (-not $Brief) {
      git -C $root merge-base --is-ancestor $t.sha HEAD 2>$null
      if ($LASTEXITCODE) { throw "commit $($t.sha) is not merged into the main branch" }
    }
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
      $cur = Get-Git $t.worktree rev-parse --abbrev-ref HEAD
      if ($cur -ne $t.branch) { throw "worktree $($t.worktree) is on branch '$cur', task needs '$($t.branch)'. Not this task's: stop." }
      Write-Host "worktree exists on $($t.branch): resume"
    } else {
      git -C $root worktree add $t.worktree -b $t.branch
      if ($LASTEXITCODE) { throw 'git worktree add failed' }
    }
  }
  if ($Prepare -and $t.role -eq 'tester') {
    Remove-Checkout $t
    git -C $root worktree add --detach $t.worktree $t.sha
    if ($LASTEXITCODE) { throw 'git worktree add (tester checkout) failed' }
  }
  if ($t.role -eq 'deployer') { $t.worktree = $null }
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

function Remove-Checkout($t) {   # tester checkouts are disposable
  if ($t.role -ne 'tester' -or -not $t.worktree -or -not (Test-Path $t.worktree)) { return }
  git -C $root worktree remove --force $t.worktree 2>$null
  if ($LASTEXITCODE -and (Test-Path $t.worktree)) {
    try { Remove-Item -Recurse -Force $t.worktree -ErrorAction Stop; git -C $root worktree prune }
    catch { Write-Warning "could not remove tester checkout $($t.worktree): $($_.Exception.Message)" }
  }
}

# What the worker must not change. Compared at the end of the attempt.
function Get-Baseline($t) {
  $b = [ordered]@{ taskHash = Get-Hash (Get-Header (Get-Content $t.file -Raw -Encoding utf8)) }
  if ($t.role -eq 'tester') {   # review isolation: the checked branch, worktree and Task File
    $b.checkedRef = Get-Git $root rev-parse --verify --quiet "$($t.checkedBranch)^{commit}"
    $b.checkedTree = if (Test-Path $t.checkedWorktree) { Get-Hash ((Get-Git $t.checkedWorktree rev-parse HEAD) + (Get-Git $t.checkedWorktree status --porcelain)) }
    $b.checkedFileHash = Get-Hash (Get-Content $t.checkedFile -Raw -Encoding utf8)
  }
  return $b
}
function Test-Baseline($t, $rt) {
  $now = Get-Baseline $t; $bad = @()
  if ($now.taskHash -ne $rt.taskHash) { $bad += 'Task File changed above ## Result' }
  if ($t.role -eq 'tester') {
    if ($now.checkedRef -ne $rt.checkedRef) { $bad += "review isolation: branch $($t.checkedBranch) moved" }
    if ($now.checkedTree -ne $rt.checkedTree) { $bad += "review isolation: worktree $($t.checkedWorktree) changed" }
    if ($now.checkedFileHash -ne $rt.checkedFileHash) { $bad += "review isolation: Task File of $($t.checked) changed" }
  }
  return $bad
}
function Complete-Attempt([string]$id, $rt, [string]$state) {   # end-of-attempt check, then the final state
  try {
    $t = Get-Task $id -Brief
    $bad = @(Test-Baseline $t $rt)
    Remove-Checkout $t
  } catch { $bad = @("end check failed: $($_.Exception.Message)") }
  if ($bad.Count) { $state = 'failed'; $rt.note = (@($rt.note) + $bad | Where-Object { $_ }) -join '; ' }
  $rt.status = $state; $rt.finishedAt = Now
  Write-Rt $id $rt
  if ($bad.Count) { Write-Warning "$id attempt failed the end check: $($bad -join '; ')" }
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
function Test-Preflight($t, [bool]$manual) {
  $bad = [Collections.Generic.List[string]]::new()
  $ledger = Get-LedgerStatus
  $tpl = Get-Content (Join-Path $root 'tasks\_template.md') -Raw -Encoding utf8

  if ($t.role -notin 'developer', 'tester', 'deployer') { $bad.Add("Role '$($t.role)': expected developer, tester or deployer") }
  if (-not $manual -and $t.role -eq 'deployer') { $bad.Add('a Deployer runs only in the session the human designated: use -Manual') }
  if (-not $manual -and $t.role -eq 'tester' -and $t.target -eq 'prod') { $bad.Add('a live Tester on prod runs only in the session the human designated: use -Manual') }
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
    if ($d -eq $t.checked -and $t.target -eq 'local') { continue }   # pre-merge tester: the checked task is in review, not done
    if ($ledger[$d] -ne 'done') { $bad.Add("Depends on $d is '$($ledger[$d])' in the ledger, needs 'done'") }
  }
  if ($t.checked -and $t.target -eq 'local' -and $t.checkedResult -notmatch '(?m)^Status\s*:\s*(done|partial)\b') {
    $bad.Add("checked task $($t.checked) has no Result with Status done or partial")
  }

  # other tasks: issued and not accepted (ledger) or with a worker process (runtime, also mid-launch or manual)
  $live = @{}
  foreach ($f in Get-ChildItem $rtDir -Filter 'T-*.json') {
    $rt = Get-Content $f.FullName -Raw | ConvertFrom-Json
    if (Test-Held $rt) { $live[$rt.taskId] = $true }
  }
  $open = @($ledger.Keys | Where-Object { $ledger[$_] -in 'in progress', 'review' }) + @($live.Keys) | Sort-Object -Unique
  foreach ($id in $open) {
    if ($id -eq $t.id) { continue }
    if ($id -eq $t.checked) {
      if ($live[$id]) { $bad.Add("checked task $id still has a live worker") }
      continue
    }
    try { $o = Get-Task $id -Brief } catch { $bad.Add("open task ${id}: $($_.Exception.Message)"); continue }   # unknown never passes
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
        } else { $bad.Add("project Preflight: unknown rule '$r'") }
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
    if ($state -eq 'running' -and -not $rt.manual -and -not (Test-Alive $rt)) { $state = 'dead' }
    '{0}  {1,-9}  tool={2}  exit={3}  limitHit={4}  finished={5}' -f $rt.taskId, $state, $rt.tool, $rt.exitCode, $rt.limitHit, $rt.finishedAt
  }
  return
}
if ($TaskId -notmatch '^T-\d+$') { throw 'TaskId T-NNN required' }

# --- -Stop: kill a hung worker (or end a manual attempt), release the lock
if ($Stop) {
  $rt = Read-Rt $TaskId
  if (Test-Alive $rt) { taskkill /PID $rt.pid /T /F | Out-Null }
  if ($rt -and $rt.status -eq 'running') {
    $rt.exitCode = -1; $rt.note = 'stopped with -Stop'
    Complete-Attempt $TaskId $rt 'failed'
  }
  Write-Host "$TaskId stopped, lock released"; return
}

# --- -MarkFinished: a manual attempt has finished (no process was observed: exit code stays empty)
if ($MarkFinished) {
  $rt = Read-Rt $TaskId
  if (-not $rt -or -not $rt.manual -or $rt.status -ne 'running') { throw "$TaskId has no running manual attempt (start one with -Manual)" }
  Complete-Attempt $TaskId $rt 'completed'
  Write-Host "$TaskId manual attempt $($rt.status)"; return
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
    $t = Get-Task $TaskId -Brief
    Set-Location -LiteralPath $t.workdir -ErrorAction Stop
    foreach ($k in $t.env.Keys) { Set-Item "env:$k" $t.env[$k] }
    $env:AGENTFLOW_TARGET = $t.target   # after the Task File env: production is never opted into by a task
    if ($t.role -eq 'tester') { $env:AGENTFLOW_EVIDENCE = Join-Path $rtDir "$TaskId.evidence" }
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
  Set-Location -LiteralPath $root   # leave the checkout so it can be removed
  $rt = Read-Rt $TaskId   # re-read: launcher wrote pid after start
  $rt.exitCode = $code
  $rt.limitHit = (Test-Path $log) -and [bool](Get-Content $log -Tail 50 | Select-String -Pattern 'usage limit|rate limit|quota' -Quiet)
  if ($note) { $rt.note = $note }
  Complete-Attempt $TaskId $rt $(if ($code -eq 0) { 'completed' } else { 'failed' })
  Write-Host "`n$TaskId process $($rt.status) (exit $code)."
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
  $prev = Read-Rt $TaskId
  if (Test-Held $prev) {
    throw "$TaskId already has a running attempt ($($prev.tool), pid $($prev.pid)). One task = one worker. Stop it first: tools\run-task.ps1 $TaskId -Stop"
  }
  if ($prev -and $prev.status -eq 'running') { Write-Warning "previous worker of $TaskId died without a final state (window closed?). Recovery applies." }

  $t = Get-Task $TaskId
  if (-not $Manual -and $t.role -notin 'developer', 'tester') { throw "Role '$($t.role)': the launcher starts developer and tester only. Use -Manual." }
  Test-Preflight $t $Manual.IsPresent
  $t = Get-Task $TaskId -Prepare
  if ($t.role -eq 'tester') { New-Item -ItemType Directory -Force (Join-Path $rtDir "$TaskId.evidence") | Out-Null }
  if ($Tool -eq 'agy') { Write-Host "Antigravity: make sure '$($t.workdir)' is in its trusted folders before the first run." }

  $log = Join-Path $rtDir "$TaskId.log"
  if (Test-Path $log) { Remove-Item $log }   # new attempt = clean log
  $rt = [ordered]@{ taskId = $TaskId; tool = $(if ($Tool) { $Tool } else { 'manual' }); role = $t.role; manual = $Manual.IsPresent
    status = 'running'; pid = $null; pidStart = $null; exitCode = $null; startedAt = Now; finishedAt = $null; limitHit = $false
    target = $t.target; workdir = $t.workdir; taskFile = $t.rel; log = $(if ($Manual) { $null } else { $log }); note = $null }
  foreach ($kv in (Get-Baseline $t).GetEnumerator()) { $rt[$kv.Key] = $kv.Value }
  Write-Rt $TaskId $rt   # running state = lock for the worker's lifetime

  if ($Manual) {
    $envs = @("AGENTFLOW_TARGET=$($t.target)") + @($t.env.Keys | ForEach-Object { "$_=$($t.env[$_])" })
    if ($t.role -eq 'tester') { $envs += "AGENTFLOW_EVIDENCE=$(Join-Path $rtDir "$TaskId.evidence")" }
    Write-Host "$TaskId ready for a manual start.`n  folder: $($t.workdir)`n  env:    $($envs -join ', ')`n  prompt: $($t.prompt)`nWhen it ends: tools\run-task.ps1 $TaskId -MarkFinished"
    return
  }
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
