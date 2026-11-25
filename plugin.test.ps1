# Checks plugin.ps1 with logs in the shape of agy 1.5.17's own (shortened real lines) and a stand-in for the agy
# command: no Antigravity, no network.
#   powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1 (prints ok or throws).
$ErrorActionPreference = 'Stop'

function Assert-Equal($actual, $expected, [string] $what) {
    if ("$actual" -ne "$expected") {
        throw "${what}: expected '$expected', got '$actual'"
    }
}

# Loaded as the base loads a plugin (Scriptorium's docs/PLUGINS.md): in a module of its own.
$module = New-Module -ArgumentList (Join-Path $PSScriptRoot 'plugin.ps1') -ScriptBlock {
    param($file)
    $Hooks = . $file
    Export-ModuleMember -Variable Hooks
}
$hooks = & $module { $Hooks }

$said = New-Object System.Collections.ArrayList
$root = Join-Path ([IO.Path]::GetTempPath()) "scriptorium-antigravity-test-$PID"
$queue = Join-Path $root 'queue'
New-Item -ItemType Directory -Force $queue | Out-Null
function New-Context($fields = @{}) {
    $ctx = @{ Api = 1; Project = $root; Copy = $root; Worker = 1; QueueDir = $queue; Settings = @{}
        Report = { param($text) [void]$said.Add($text) }; Log = { param($text) [void]$said.Add($text) } }
    foreach ($key in $fields.Keys) {
        $ctx[$key] = $fields[$key]
    }
    return $ctx
}

try {
    # The manifest and the model list: a provider with the window that `/usage` names, and every model that a
    # complexity names.
    $manifest = Get-Content (Join-Path $PSScriptRoot 'plugin.json') -Raw | ConvertFrom-Json
    Assert-Equal "$($manifest.name) $($manifest.api) $($manifest.provider) $($manifest.skills) $($manifest.requires)" 'antigravity 1 True .agents/skills agy' 'the manifest'
    $models = Get-Content (Join-Path $PSScriptRoot 'models.json') -Raw | ConvertFrom-Json
    $named = @($models.complexities.PSObject.Properties | ForEach-Object { $_.Value.models }) | ForEach-Object { ($_ -split '@')[0] }
    Assert-Equal @($named | Where-Object { -not $models.models.$_ }).Count 0 'every model that the list names is in it'
    Assert-Equal (@('low', 'medium', 'high', 'design') | Where-Object { -not $models.complexities.$_ }).Count 0 'the base''s four complexities'
    Assert-Equal "$(@($models.windows.PSObject.Properties.Name) -join ',') $($models.windows.'gemini-weekly'.keep) $($null -eq $models.efforts)" 'gemini-weekly True True' 'the week of the Gemini models, and no efforts: a model''s name holds its effort'

    # A run that did its job: a file written, a command that fails in the sandbox and passes outside it, the run's
    # words in pieces, a compaction, the result.
    $log = @(
        '{"event":"init","conversation_id":"c-7","init":{"model":"gemini-3.8-flash-low","cwd":"D:\\Work\\App-w1","tools":["run_command","write_file"],"permission_mode":"request-review"}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":0,"state":"DONE","step_type":"user_input"}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":1,"state":"DONE","step_type":"agent_response","duration_seconds":2.5,"usage":{"input_tokens":10550,"output_tokens":64,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":10614}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"write_file","tool_info":{"name":"write_file","parameters":{"Overwrite":true,"Path":"D:\\Work\\App-w1\\e.txt"}}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":2,"state":"DONE","step_type":"tool","tool_name":"write_file","duration_seconds":0.1,"tool_info":{"name":"write_file","parameters":{"Overwrite":true,"Path":"D:\\Work\\App-w1\\e.txt"}}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":3,"state":"DONE","step_type":"agent_response","duration_seconds":2.6,"usage":{"input_tokens":2159,"output_tokens":93,"thinking_tokens":0,"cache_read_tokens":8506,"total_tokens":2252}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":4,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"git add -A"}}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":4,"state":"DONE","step_type":"tool","tool_name":"run_command","duration_seconds":2.0,"tool_info":{"name":"run_command","parameters":{"CommandLine":"git add -A"},"output":"Command exited with code 1.\n\nCommand output:\nfatal: Unable to create ''D:/Work/App-w1/.git/index.lock'': Permission denied\n{\"event\":\"result\",\"state\":\"DONE\",\"usage\":{}}"}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":5,"state":"DONE","step_type":"system_message","duration_seconds":0}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":6,"state":"DONE","step_type":"error_message","duration_seconds":0}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":7,"state":"ACTIVE","step_type":"agent_response","text_delta":"The ticket "}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":7,"state":"DONE","step_type":"agent_response","text_delta":"is done.\n","duration_seconds":8.6,"usage":{"input_tokens":2316,"output_tokens":51,"thinking_tokens":0,"cache_read_tokens":8629,"total_tokens":2367}}}'
        '{"event":"step_update","step_update":{"conversation_id":"c-7","step_index":8,"state":"DONE","step_type":"checkpoint","duration_seconds":6.5,"usage":{"input_tokens":3120,"output_tokens":536,"thinking_tokens":0,"cache_read_tokens":9146,"total_tokens":3656}}}'
        '{"event":"result","result":{"conversation_id":"c-7","status":"SUCCESS","response":"The ticket is done.\n","duration_seconds":30.1,"num_turns":1,"usage":{"input_tokens":18145,"output_tokens":744,"thinking_tokens":0,"cache_read_tokens":26281,"total_tokens":18889}}}'
    )
    $read = & $hooks.ReadRun (New-Context @{ Text = ($log -join "`n") })
    Assert-Equal "$($read.Session) $($read.Ended) $($read.Error) '$($read.Kind)' $($read.Worked) $($read.Capped) $($read.Cost) $($read.Text.Trim())" "c-7 True False '' True False 0 The ticket is done." 'a run that did its job'
    $n = $read.Numbers
    Assert-Equal "$($n.requests) $($n.toolCalls) $($n.first) $($n.ctxMean) $($n.ctxMax) $($n.read) $($n.compactions)" '4 2 10550 11106 12266 26281 1' 'its numbers: a request is a step with a usage, its context the input and the cache'
    # The same log with Windows line ends and a line that is no JSON.
    $read = & $hooks.ReadRun (New-Context @{ Text = (@('agy 1.5.17') + $log) -join "`r`n" })
    Assert-Equal "$($read.Session) $($read.Ended) $($read.Numbers.toolCalls)" 'c-7 True 2' 'Windows line ends and a line that is no event'

    # The steps: a tool when it starts, with its command or its first text parameter. The run's words are no step.
    $steps = @($log | ForEach-Object { & $hooks.ReadStep (New-Context @{ Line = $_ }) } | Where-Object { $null -ne $_ })
    Assert-Equal ($steps -join ' | ') 'write_file: D:\Work\App-w1\e.txt | run_command: git add -A' 'the steps'
    Assert-Equal ($null -eq (& $hooks.ReadStep (New-Context @{ Line = 'not json {"event"' }))) $true 'a line that is no event is no step'

    # The end of a log.
    $end = & $hooks.ReadEnd (New-Context @{ Text = ($log -join "`n") })
    Assert-Equal "$($end.Error) '$($end.Detail)' $($end.Text.Trim())" "False '' The ticket is done." 'the end of a run that did its job'
    Assert-Equal ($null -eq (& $hooks.ReadEnd (New-Context @{ Text = ($log[0..7] -join "`n") }))) $true 'a log with no result has no end'
    $cut = & $hooks.ReadRun (New-Context @{ Text = ($log[0..7] -join "`n") })
    Assert-Equal "$($cut.Session) $($cut.Ended) $($cut.Numbers.requests) $($cut.Numbers.toolCalls)" 'c-7 False 2 2' 'a run whose process died: the session, no end'

    # Ends that are no success. A model the account cannot use and a missing sign-in: the account's, not the
    # ticket's. An error before any request with no known wording: 'start'. An error after work: the run's own. An
    # action nobody could approve: a success with no words, which names the action. A canceled run has a detail.
    function Read-End([string] $result) {
        $text = '{"event":"result","result":' + $result + '}'
        $run = & $hooks.ReadRun (New-Context @{ Text = $text })
        $end = & $hooks.ReadEnd (New-Context @{ Text = $text })
        return "$($run.Ended) $($run.Error) '$($run.Kind)' $($run.Worked) '$($run.Session)' $($run.Text) | $($end.Error) '$($end.Detail)'"
    }
    $none = '"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0}'
    Assert-Equal (Read-End "{`"conversation_id`":`"`",`"status`":`"ERROR`",`"response`":`"`",`"error`":`"invalid model selection (--model \`"x\`" --effort \`"\`"): model x is not recognized`",`"num_turns`":0,$none,`"finished_reason`":`"error`"}") "True True 'model' False '' invalid model selection (--model `"x`" --effort `"`"): model x is not recognized | True ''" 'a model the account cannot use'
    Assert-Equal (Read-End "{`"conversation_id`":`"`",`"status`":`"ERROR`",`"response`":`"`",`"error`":`"authentication required`",`"num_turns`":0,$none}") "True True 'login' False '' authentication required | True ''" 'not signed in'
    Assert-Equal (Read-End "{`"conversation_id`":`"c-2`",`"status`":`"ERROR`",`"response`":`"`",`"error`":`"something else`",`"num_turns`":1,$none}") "True True 'start' False 'c-2' something else | True ''" 'an error before any request'
    Assert-Equal (Read-End '{"conversation_id":"c-2","status":"ERROR","response":"half","error":"tool failed","num_turns":1,"usage":{"total_tokens":500}}') "True True '' True 'c-2' tool failed | True ''" 'an error after work is the run''s own'
    # The service's own shortage, as agy 1.5.17 words it, in the middle of a session: held, not the ticket's failure.
    Assert-Equal (Read-End '{"conversation_id":"c-2","status":"ERROR","response":"","error":"Our servers are experiencing high traffic right now, please try again in a minute. (UNAVAILABLE (code 503): No capacity available for model gemini-3.8-flash-low on the server)","num_turns":2,"usage":{"total_tokens":20034},"finished_reason":"error"}') "True True 'limit' True 'c-2' Our servers are experiencing high traffic right now, please try again in a minute. (UNAVAILABLE (code 503): No capacity available for model gemini-3.8-flash-low on the server) | True ''" 'the service takes no request now'
    Assert-Equal (Read-End '{"conversation_id":"c-2","status":"SUCCESS","response":"","num_turns":1,"usage":{"total_tokens":11737},"denied_actions":[{"action":"command","display_name":"Bash"}]}') "True True '' True 'c-2' Antigravity refused an action that needs approval: command | True 'refused: command'" 'an action nobody could approve ends the run: a failure'
    Assert-Equal (Read-End '{"conversation_id":"c-2","status":"SUCCESS","response":"Done without the web.","num_turns":1,"usage":{"total_tokens":11737},"denied_actions":[{"action":"read_url","display_name":"Web"}]}') "True False '' True 'c-2' Done without the web. | False 'refused: read_url'" 'a run that was refused an action and still finished'
    Assert-Equal (Read-End '{"conversation_id":"c-2","status":"CANCELED","response":"stopped","num_turns":1,"usage":{"total_tokens":9}}') "True True '' True 'c-2' stopped | True 'canceled'" 'a canceled run'

    # The usage that `/usage` prints: the windows of the Gemini models by their buckets' ids, the share used from the
    # share left. The other models' windows are left out.
    $usageLine = '{"event":"command_result","command":{"name":"usage","data":{"description":"d","groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.75,"reset_time":"2026-12-02T14:18:41Z"},{"id":"gemini-5h","window":"5h","remaining_fraction":1,"reset_time":"1970-01-01T00:00:00Z"}]},{"name":"Claude and GPT models","buckets":[{"id":"3p-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"1970-01-01T00:00:00Z"}]}]}}}'
    $usageResult = '{"event":"result","result":{"conversation_id":"","status":"SUCCESS","response":"Gemini Models Weekly Limit Remaining 75 percent","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"total_tokens":0}}}'
    $usage = & $module { param($text) Read-UsageText $text } "$usageLine`n$usageResult"
    Assert-Equal "$(@($usage.Windows.Keys | Sort-Object) -join ',') $($usage.Windows.'gemini-weekly'.Used) $($usage.Windows.'gemini-weekly'.ResetsAt) $($usage.Windows.'gemini-5h'.Used) $($usage.Windows.'gemini-5h'.ResetsAt) '$($usage.Refused)'" "gemini-5h,gemini-weekly 0.25 1796221121 0 0 ''" 'the usage reading'
    Assert-Equal ($null -eq (& $module { param($text) Read-UsageText $text } ($log -join "`n"))) $true 'a run''s log holds no usage'

    # A stand-in for the agy command, first on the PATH: it prints a usage, a compaction and a result.
    $bin = Join-Path $root 'bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $lines = @($usageLine, $log[12], $usageResult)
    if ($env:OS -eq 'Windows_NT') {
        Set-Content (Join-Path $bin 'agy.cmd') (@('@echo off') + @($lines | ForEach-Object { "echo $_" })) -Encoding ascii
        $env:PATH = "$bin;$env:PATH"
    } else {
        Set-Content (Join-Path $bin 'agy') (@('#!/bin/sh', "cat <<'EOF'") + $lines + @('EOF')) -Encoding ascii
        & chmod +x (Join-Path $bin 'agy')
        $env:PATH = "${bin}:$env:PATH"
    }

    # The command of a run: the prompt, the log's form, the model, the run's settings, the other folder. The settings
    # hold the run's commands as rules and the project's rules in Antigravity's syntax, not another tool's. No effort,
    # no variable, and a line in the worker's log for the MCP server it does not hand over.
    $run = @{
        Prompt = 'Do ticket #5.'; Session = ''; Model = 'gemini-4-hydrogen-high'; Effort = ''; Advisor = ''; CompactAt = 0; Cap = 0
        Login = 'C:/logins/a'; Commands = @('git', 'gh', 'unity command'); Tools = @('Bash(dotnet:*)', 'read_url(github.com)', 'mcp__Docs')
        Dir = $root; AddDirs = @('D:/Work/App-w1'); McpServers = [ordered]@{ Docs = @{ command = 'docs' } }
    }
    $command = & $hooks.GetCommand (New-Context @{ Run = $run })
    $settingsFile = Join-Path $queue 'run-settings.json'
    Assert-Equal ((Split-Path $command.FilePath -Leaf) -replace '\.cmd$', '') 'agy' 'the agy command on the PATH'
    Assert-Equal ($command.Arguments -join ' ') "-p `"Do ticket #5.`" --output-format stream-json --model gemini-4-hydrogen-high --settings `"$settingsFile`" --add-dir `"D:/Work/App-w1`"" 'the arguments of a run'
    Assert-Equal ((Get-Content $settingsFile -Raw | ConvertFrom-Json).permissions.allow -join ' ') 'command(git) command(gh) command(unity command) read_url(github.com)' 'the run''s rules'
    Assert-Equal "$($command.Env.Count) $($said[-1])" '0 Antigravity gets no MCP servers from the plugins yet: Docs' 'no variable, and the MCP server named in the log'
    # A resumed run with no MCP server and no rule.
    $said.Clear()
    $held = @{ Prompt = 'Go on.'; Session = 'c-7'; Model = 'gemini-3.8-flash-medium'; Effort = ''; Login = ''; Commands = @(); Tools = @(); Dir = $root; AddDirs = @(); McpServers = @{} }
    $command = & $hooks.GetCommand (New-Context @{ Run = $held })
    Assert-Equal ($command.Arguments -join ' ') "-p `"Go on.`" --output-format stream-json --model gemini-3.8-flash-medium --settings `"$settingsFile`" --conversation c-7" 'the arguments of a resumed run'
    Assert-Equal "$(Get-Content $settingsFile -Raw) $($said.Count)" '{"permissions":{"allow":[]}} 0' 'no rule, and nothing in the log'

    # A probe and a compaction, with the stand-in.
    $probe = & $hooks.Probe (New-Context @{ Login = ''; Dir = $root })
    Assert-Equal "$($probe.Answered) '$($probe.Kind)' $($probe.Usage.Windows.'gemini-weekly'.Used) $($probe.Text)" "True '' 0.25 Gemini Models Weekly Limit Remaining 75 percent" 'a probe that the login answered'
    Assert-Equal "$((Get-Location).Path -ne $root)" 'True' 'the probe leaves the folder as it was'
    $line = & $hooks.Compact (New-Context @{ Run = $held; Log = (Join-Path $root 'compact.jsonl') })
    Assert-Equal $line 'the session is compacted.' 'a compaction'
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'ok'
