# Scriptorium's provider for Google's Antigravity CLI, `agy` (Scriptorium's docs/PLUGINS.md, A provider): starts a run
# with `agy -p`, reads its stream-json log, and reads the plan's usage with `/usage`. Checked against agy 1.5.17 on
# Windows with a free plan (README.md, Proven and not). Runs in Windows PowerShell 5.1 and in PowerShell 7. Only
# definitions; the last statement is the hooks. Checked by plugin.test.ps1.
#
# The log, one JSON object on each line, its payload under the key of its `event`:
#   {"event":"init","conversation_id":"c-1","init":{"model":"...","cwd":"...","tools":[...],"permission_mode":"..."}}
#   {"event":"step_update","step_update":{"conversation_id":"c-1","step_index":3,"state":"ACTIVE"|"DONE",
#       "step_type":"user_input"|"agent_response"|"tool"|"checkpoint"|"system_message"|"error_message",
#       "tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"..."},"output":"..."},
#       "text_delta":"a piece of the words","usage":{"input_tokens":1,"cache_read_tokens":1,"total_tokens":2}}}
#   {"event":"result","result":{"conversation_id":"c-1","status":"SUCCESS"|"ERROR"|...,"response":"...","error":"...",
#       "num_turns":1,"usage":{...},"denied_actions":[{"action":"command","display_name":"Bash"}]}}
# A step's `usage` is one request's; `input_tokens` does not hold the tokens read from the cache. The result's usage
# is the whole session's, the part before a resume too. `num_turns` counts the prompts, not the requests.

# The actions of a rule that Antigravity reads (`command(git)`, `write_file(src/)`).
$RuleActions = 'read_file|write_file|read_url|execute_url|command|unsandboxed|mcp'

# What may follow a command's name on a line that a rule covers whole (Get-RunCommand): words with no shell operator
# in them, text in single quotes, and text in double quotes that the shell does not expand (no `$`, no backtick). So
# no chain, no pipe, no redirection and no command inside the command. Braces pass: no shell runs what is in them,
# and `gh api` and git's own names use them (`repos/{owner}/{repo}`, `HEAD@{1}`).
# shortcut: an option of the command that runs a program (git -c core.pager=...) passes, as under the plain rule of
# another shell's provider; name such options here when a run must not be trusted with them.
$RuleWords = '( +("[^"`$]*"|''[^'']*''|[^\s;|&<>`$()"'']+))*'

# One line of a log as an object, $null for a line that is no event.
function Read-Event([string] $line) {
    if ($line -notmatch '^\s*\{.*"event"') {
        return $null
    }
    try {
        return $line | ConvertFrom-Json
    } catch {
        return $null
    }
}

# The last result of a log's text, $null without one. Found by its event name: an escaped quote inside a tool's output
# never matches.
function Read-Result([string] $text) {
    $line = ($text -split "`n") | Where-Object { $_ -match '"event"\s*:\s*"result"' } | Select-Object -Last 1
    $entry = if ($line) { Read-Event $line }
    return $(if ($entry) { $entry.result })
}

# The words of a result: its error where it has one, else the response. A run that ended on an action nobody could
# approve has neither: its words name the action.
function Get-ResultText($result) {
    if ($result.error) {
        return [string]$result.error
    }
    if (-not $result.response -and $result.denied_actions) {
        return 'Antigravity refused an action that needs approval: ' + (@($result.denied_actions | ForEach-Object { $_.action }) -join ', ')
    }
    return [string]$result.response
}

# Whether a result is a failure: any status but a success, and a success that an action nobody could approve ended
# (Antigravity ends the run there with no words). A run that was refused an action and still finished is a success.
function Test-Failed($result) {
    return [bool]($result.status -ne 'SUCCESS' -or ($result.denied_actions -and -not $result.response))
}

# Why a run that ended with an error is not its ticket's failure (the base's kinds, Scriptorium's limits.ps1): 'login'
# (not signed in), 'model' (the account cannot use the model), 'limit' (the service takes no request now: the run is
# held and resumes later) or 'start' (the session made no request, for a cause the text does not name). '' for the
# run's own failure or no error.
# Seen: "... (UNAVAILABLE (code 503): No capacity available for model ...)", the service's own shortage.
# shortcut: the wording at a plan's limit was not seen. RESOURCE_EXHAUSTED and code 429 are the service's names for it
# in the same form as the 503; check them against a real log (README.md, Proven and not).
function Get-Refusal($result) {
    if (-not $result -or $result.status -eq 'SUCCESS') {
        return ''
    }
    $text = Get-ResultText $result
    if ($text -match 'authentication required') {
        return 'login'
    }
    if ($text -match 'invalid model') {
        return 'model'
    }
    if ($text -match 'UNAVAILABLE \(code 503\)|RESOURCE_EXHAUSTED|\(code 429\)') {
        return 'limit'
    }
    return $(if ([long]$result.usage.total_tokens -gt 0) { '' } else { 'start' })
}

# What a run does at one line of its log: the tool it starts, with its command or its first text parameter. $null for
# a line that is no step. The run's words come in pieces, one on each line, so they are no step.
function Get-StepText([string] $line) {
    $entry = Read-Event $line
    $step = if ($entry) { $entry.step_update }
    if (-not $step -or $step.state -ne 'ACTIVE' -or $step.step_type -ne 'tool') {
        return $null
    }
    $name = [string]$(if ($step.tool_name) { $step.tool_name } else { $step.tool_info.name })
    $parameters = $step.tool_info.parameters
    $detail = if ($parameters) {
        @($parameters.CommandLine) + @($parameters.PSObject.Properties | ForEach-Object { $_.Value }) |
            Where-Object { $_ -is [string] -and $_ } | Select-Object -First 1
    }
    return "$name$(if ($detail) { ': ' + $detail })"
}

# The numbers of one run log's text for the history. A request is a step that is done and has a usage: the run's words
# or a compaction. Its context is its input tokens and the ones read from the cache. Only lines of steps that are done
# are parsed: the pieces of the run's words are most of a log.
function Get-RunNumbers([string] $text) {
    $sizes = @()
    $read = 0
    $toolCalls = 0
    $compactions = 0
    foreach ($line in $text -split "`n") {
        if ($line -notmatch '"state"\s*:\s*"DONE"') {
            continue
        }
        if ($line -match '"step_type"\s*:\s*"tool"') {
            $toolCalls++
            continue
        }
        if ($line -notmatch '"usage"\s*:') {
            continue
        }
        $entry = Read-Event $line
        $usage = if ($entry) { $entry.step_update.usage }
        if (-not $usage) {
            continue
        }
        if ($entry.step_update.step_type -eq 'checkpoint') {
            $compactions++
        }
        $read += [long]$usage.cache_read_tokens
        $sizes += [long]$usage.input_tokens + [long]$usage.cache_read_tokens
    }
    return [ordered]@{
        requests = $sizes.Count
        toolCalls = $toolCalls
        first = $(if ($sizes.Count) { $sizes[0] } else { 0 })
        ctxMean = $(if ($sizes.Count) { [long][math]::Round(($sizes | Measure-Object -Sum).Sum / $sizes.Count) } else { 0 })
        ctxMax = $(if ($sizes.Count) { [long]($sizes | Measure-Object -Maximum).Maximum } else { 0 })
        read = $read
        compactions = $compactions
    }
}

# The plan's usage from what `/usage` prints (its command_result event), as the base reads it: each window's share
# used and its reset. $null for a text with none. A window's name is its bucket's id (`gemini-weekly`).
# shortcut: only the windows of the Gemini models, the ones models.json offers; the other models of a plan have
# windows of their own (`3p-weekly`, `3p-5h`). Read those when the model list offers such a model.
function Read-UsageText([string] $text) {
    $line = ($text -split "`n") | Where-Object { $_ -match '"event"\s*:\s*"command_result"' } | Select-Object -Last 1
    $entry = if ($line) { Read-Event $line }
    if (-not $entry -or $entry.command.name -ne 'usage') {
        return $null
    }
    $read = @{ Windows = @{}; Refused = ''; RefusedResetsAt = 0 }
    foreach ($bucket in @($entry.command.data.groups | ForEach-Object { $_.buckets })) {
        if ($bucket -and $bucket.id -like 'gemini-*') {
            # A window that was never used resets at the year 1970.
            $resetsAt = [long][math]::Max(0, ([DateTimeOffset]::Parse([string]$bucket.reset_time, [cultureinfo]::InvariantCulture)).ToUnixTimeSeconds())
            $read.Windows[[string]$bucket.id] = @{ Used = 1 - [double]$bucket.remaining_fraction; ResetsAt = $resetsAt }
        }
    }
    return $read
}

# The command of a run, or with -Compact of the compaction of its session: @{ FilePath; Arguments; Env }. It writes
# the run's settings into the worker's queue folder: run-settings.json, the allow rules of this run alone
# (`--settings` saves nothing).
# - No `--mode`. Seen with nobody there on a free plan: file edits and a command with no rule ran, and an action that
#   needed approval was refused and ended the run: the result names it (`denied_actions`). `--mode auto` printed that
#   the account has no such mode; a run with no mode is in Auto mode all the same, as Antigravity's own log names it.
# - The rules: two for each command of the run, and each rule that the project gives in Antigravity's own syntax. A
#   rule in another tool's syntax is left out. `command(git)` covers a line by how it starts, which Antigravity
#   allows only in a shell whose lines it can split into words. In Windows PowerShell and cmd a rule must cover the
#   whole line, so the second rule is a pattern for the whole line (Antigravity's docs: permissions, CLI
#   cross-platform command matching). Seen without it on Windows: no `git` line had a rule, each waited for Auto
#   mode's review of a command that leaves the sandbox, and a review that failed or said no ended the run.
# - `Run.Login` is not used: Antigravity keeps one login for each OS user, in the OS keyring.
# shortcut: the plugins' MCP servers are not handed over: Antigravity reads them from .agents/mcp_config.json inside
# the checkout, a file of the repo. Write it when an environment plugin gives a server.
function Get-RunCommand($ctx, [switch] $Compact) {
    $run = $ctx.Run
    if ($run.McpServers -and $run.McpServers.Count) {
        & $ctx.Log "Antigravity gets no MCP servers from the plugins yet: $(@($run.McpServers.Keys) -join ', ')"
    }
    $rules = @($run.Commands | Where-Object { $_ } | ForEach-Object { $_.Trim() } | ForEach-Object {
            "command($_)"
            "command(regex:$([regex]::Escape($_) -replace '\\ ', ' ')$RuleWords)"
        }) +
        @($run.Tools | Where-Object { $_ -match "^($RuleActions)\(.+\)$" })
    $runSettings = Join-Path $ctx.QueueDir 'run-settings.json'
    [System.IO.File]::WriteAllText($runSettings, '{"permissions":{"allow":' + (ConvertTo-Json -InputObject @($rules | Select-Object -Unique) -Compress) + '}}')
    $prompt = if ($Compact) { '/compact' } else { "`"$($run.Prompt)`"" }
    $arguments = @('-p', $prompt, '--output-format', 'stream-json', '--model', $run.Model, '--settings', "`"$runSettings`"")
    if ($run.Session) {
        $arguments += @('--conversation', $run.Session)
    }
    foreach ($dir in @($run.AddDirs | Where-Object { $_ })) {
        $arguments += @('--add-dir', "`"$dir`"")
    }
    return @{ FilePath = (Get-Command agy).Source; Arguments = $arguments; Env = @{} }
}

@{
    GetCommand = {
        param($ctx)
        return Get-RunCommand $ctx
    }
    # `/usage` with nobody there: it asks the model nothing, so it costs no usage. It shows the plan's windows and
    # whether the login answers.
    Probe = {
        param($ctx)
        $ErrorActionPreference = 'Continue'
        Push-Location ([string]$ctx.Dir)
        try {
            $text = (& agy -p /usage --output-format stream-json 2>$null) -join "`n"
        } finally {
            Pop-Location
        }
        $result = Read-Result ([string]$text)
        return @{
            Usage = Read-UsageText ([string]$text); Answered = [bool]$result
            Kind = (Get-Refusal $result); Text = [string]$(if ($result) { Get-ResultText $result })
        }
    }
    # `/compact` on the held session, with the run's own model and settings. It returns a line for the worker's log.
    Compact = {
        param($ctx)
        $command = Get-RunCommand $ctx -Compact
        $log = [string]$ctx.Log
        $process = Start-Process $command.FilePath -ArgumentList $command.Arguments -WorkingDirectory $ctx.Run.Dir -NoNewWindow `
            -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        if (-not $process.WaitForExit(600000)) {
            $process.Kill()
            return 'no end after 10 minutes, stopped; the session resumes whole.'
        }
        $text = if (Test-Path $log) { [System.IO.File]::ReadAllText($log) } else { '' }
        if ((Get-RunNumbers $text).compactions -lt 1) {
            return 'failed; the session resumes whole.'
        }
        return 'the session is compacted.'
    }
    # The end of a run from its log: the session to resume, the result (its error, its refusal) and the run's numbers
    # for the history. Antigravity counts no cost in money.
    ReadRun = {
        param($ctx)
        $text = [string]$ctx.Text
        $result = Read-Result $text
        $run = @{
            # The first one is the run's own: a subagent's comes later.
            Session = [regex]::Match($text, '"conversation_id"\s*:\s*"([^"]+)"').Groups[1].Value; Ended = [bool]$result
            Error = $false; Kind = ''; Window = ''; Capped = $false; Text = ''; Worked = $false; Cost = 0.0; Numbers = $null
        }
        try {
            $run.Numbers = Get-RunNumbers $text
        } catch {
            & $ctx.Log "run numbers error: $_"
        }
        if ($result) {
            $run.Error = Test-Failed $result
            # The session's whole usage: a resumed one that is refused at once still did work before.
            $run.Worked = [long]$result.usage.total_tokens -gt 0
            $run.Text = Get-ResultText $result
            $run.Kind = Get-Refusal $result
        }
        return $run
    }
    ReadStep = {
        param($ctx)
        return Get-StepText ([string]$ctx.Line)
    }
    # Why a run ended, from the end of its log. The detail is a status that is neither a success nor a plain error
    # (canceled, interrupted), or the actions that nobody could approve.
    ReadEnd = {
        param($ctx)
        $result = Read-Result ([string]$ctx.Text)
        if (-not $result) {
            return $null
        }
        $status = [string]$result.status
        $detail = if (@('SUCCESS', 'ERROR') -notcontains $status) {
            $status.ToLowerInvariant()
        } elseif ($result.denied_actions) {
            'refused: ' + (@($result.denied_actions | ForEach-Object { $_.action }) -join ', ')
        } else {
            ''
        }
        return @{ Error = (Test-Failed $result); Detail = $detail; Text = (Get-ResultText $result) }
    }
}
