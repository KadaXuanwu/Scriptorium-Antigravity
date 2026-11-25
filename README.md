# Scriptorium for Antigravity

A provider plugin for [Scriptorium](https://github.com/KadaXuanwu/Scriptorium): it runs the queue's workers on
Google's Antigravity CLI (`agy`) with a Google AI plan.

**Status: its hooks work with the real tool, and no ticket has run through it yet.** Checked on 2026-11-25 against
agy 1.5.17 on Windows with a free plan ([Proven and not](#proven-and-not)). A worker runs on Antigravity when its
account is an Antigravity account, beside workers on another coding tool in the same project (Scriptorium's
`docs/QUEUE.md`, Settings, `accounts.<name>.provider`).

## What it needs

- Antigravity CLI on the PATH: `agy --version` answers. Install it from
  [Antigravity's Quickstart](https://www.antigravity.google/docs/getting-started/).
- One sign-in: run `agy` once in a terminal, sign in with the Google account and trust the folder that holds the
  project and its worker copies. Antigravity keeps the login in the OS keyring, and a run with nobody there uses it.
- Scriptorium with provider plugins (its `docs/PLUGINS.md`, A provider).

## Use it

1. Add the plugin to one project's `scriptorium.json`, after its other plugins, until the plugin is listed by name:

   ```json
   "antigravity": { "source": "https://github.com/KadaXuanwu/Scriptorium-Antigravity" }
   ```

2. Run Scriptorium's `setup.ps1` for that project again. It installs the plugin, and the workers of every project on
   the PC can then run on it.
3. On the page's Accounts tab, add an account and pick Antigravity as its coding tool. The page has no sign-in for
   it: the account is the login of `agy` in a terminal.
4. Put a worker on that account, on its card or with Add a worker. It runs on Antigravity from its next job. A worker
   on another tool's account stays on that tool.

The first provider that a project lists is its default: the models that its `scriptorium.json` and the page's Details
set are that provider's.

## What it does

| Hook | What |
| ---- | ---- |
| `GetCommand` | The command of a run: `agy -p` with the prompt, `--output-format stream-json`, the model, `--settings` with the run's own rules, `--conversation` for a session to resume, and `--add-dir` for each other folder |
| `ReadRun` | The run's end from its log: the session, whether it ended, its error and why (not signed in, a model the account cannot use, the service takes no request, no request made), its words, and the numbers for the history |
| `Probe` | `agy -p /usage`: the plan's usage windows and whether the login answers. It asks the model nothing, so it costs no usage |
| `Compact` | `/compact` on a held session, with the run's model and settings |
| `ReadStep` | The tool a run starts, with its command or its file |
| `ReadEnd` | Why a run ended: its status, its error, or the action that nobody could approve |

`models.json` holds the models, which one a complexity runs on, and the usage window. A model's name holds its effort
(`agy models` lists them), so runs have no effort of their own. The list is the Gemini models of a free plan; a paid
plan has more. A project whose default provider is this plugin sets its own under `complexities` in its
`scriptorium.json`. In every other project, an Antigravity worker runs on this file's list.

## Permissions

A run gets its rules for itself alone: the plugin writes them into `run-settings.json` in the worker's queue folder
and hands that file over with `--settings`, which saves nothing. The owner's own
`~/.gemini/antigravity-cli/settings.json` is never written.

- Each command the base and the plugins allow becomes two rules. `git` becomes `command(git)`, which covers a line
  by how it starts, and a pattern for the whole line: the command, then plain words and quoted text, with no chain,
  pipe, redirection or command inside the command. Antigravity takes the first only in a shell whose lines it can
  split into words. In Windows PowerShell a rule must cover the whole line, so there the second one counts.
- A rule from `allowedTools` in `scriptorium.json` is handed on when it is in Antigravity's syntax
  (`read_url(github.com)`), and left out when it is another tool's.
- No mode is set. Seen with nobody there on a free plan: file edits ran, a command with no rule (`dotnet --version`)
  ran inside the sandbox, and an action that needed approval was refused. The run ended there, and its result named
  the action: the plugin reads that as the run's failure.

Antigravity runs a command inside a sandbox that cannot write to `.git` and has no network. The run's playbook
(`PLAYBOOK.md`) therefore tells it to start each `git` and `gh` command outside the sandbox, alone in its call, and
which lines the rules cover.

With no mode set, a run is in Antigravity's Auto mode where the plan has it. There a model of Antigravity's reviews
each command that asks to leave the sandbox. When the review says no, or fails, Antigravity asks the user, and a
rule that covers the line answers for the user. A line that no rule covers has nobody to answer: the run ends there.
The review still runs for a line that a rule covers, so the rules save none of its requests.

## What Antigravity does not give

The page's Details tab shows the same under Coding tool.

| Feature of the base | With Antigravity | So |
| ------------------- | ---------------- | -- |
| A usage reading inside a run's log | The log holds none; only `/usage` does | A worker reads the usage before it takes a job, when the last reading is older than 30 minutes. A stop line is not seen while a run works. The page's Ping shows that the login answers and saves no reading |
| Several accounts on one PC | One login for each OS user | Every account of the page is the same login |
| Sign-in and sign-out from the page | The first sign-in needs a terminal | The page offers none |
| The plan's name and size | Not in a file | Every account counts as signed in, on a plan of size 1 |
| A cap for one run, a cost in money, an advisor, a compact size, an effort beside the model | None | Left out |
| MCP servers of the plugins | Read from a file inside the checkout | Not handed over. The worker's log names each one |

## Proven and not

Proven with agy 1.5.17 on Windows, a free plan, on 2026-11-25:

- A run's log: the session, the steps, the tokens of each request, the result.
- A resume with `--conversation` and a new prompt.
- A run that writes a file and commits it with the playbook's sandbox rule: no command failed.
- The rules of `--settings` on Windows. With `command(git)` alone, no `git` line had a rule: each passed or failed
  by Auto mode's review, and a review that got the service's shortage (error 503) ended the run at `git add`. With
  the pattern for the whole line beside it, the same lines ran while the review failed, and so did one that the
  review had refused twice (`git stash drop`).
- The base's own playbook as the prompt, from the worker's logon task: the run read the ticket, made its branch and
  made the ticket's edit. It ended at `git add`, before the rule above.
- `/usage` with nobody there: the week of the Gemini models, its share left and its reset.
- `/compact` on a named session.
- An unknown model, and the service's own shortage (error 503) in the middle of a session. The plugin reads the
  shortage as a limit: the base holds the job with its session and resumes it after 30 minutes.
- A model's name with `--effort` beside it is refused.

Not proven:

1. A whole ticket to its end: `git push` and `gh pr create` from a worker copy, and the merge.
2. A run at the plan's limit: the wording is taken from the service's names for it, not from a log.
3. A run without a login: the wording is from Antigravity's docs.
4. A paid plan: its models, its 5-hour window (the plugin reads every `gemini-` window that `/usage` names, and
   `models.json` knows only the week), and whether its auto mode behaves like the free plan's.
5. A folder that Antigravity does not trust yet, with nobody there.
6. macOS and Linux, and PowerShell 7 outside this repo's CI. There the rule by a command's start should count, and
   the pattern for the whole line is not tried.

## Token savings

None of its own yet. The base's are in
[Scriptorium's README](https://github.com/KadaXuanwu/Scriptorium#built-in-token-savings). Measured on 2026-11-25: a
run's first request reads about 10,500 tokens before its prompt, with Antigravity's own tools and no MCP server.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1
```

It prints `ok` or throws. It needs no Antigravity and no network.
