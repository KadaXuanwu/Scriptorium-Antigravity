# Scriptorium for Antigravity

A provider plugin for [Scriptorium](https://github.com/KadaXuanwu/Scriptorium): it runs the queue's workers on
Google's Antigravity CLI (`agy`) with a Google AI plan.

**Status: its hooks work with the real tool, and no ticket has run through it yet.** Checked on 2026-11-25 against
agy 1.5.17 on Windows with a free plan ([Proven and not](#proven-and-not)). Scriptorium's base still needs one change
before a project can use it beside a project on another provider: an account has no provider of its own yet, so both
would share one account's usage records.

## What it needs

- Antigravity CLI on the PATH: `agy --version` answers. Install it from
  [Antigravity's Quickstart](https://www.antigravity.google/docs/getting-started/).
- One sign-in: run `agy` once in a terminal, sign in with the Google account and trust the folder that holds the
  project and its worker copies. Antigravity keeps the login in the OS keyring, and a run with nobody there uses it.
- Scriptorium with provider plugins (its `docs/PLUGINS.md`, A provider).

## Use it

In the project's `scriptorium.json`, until the plugin is listed by name:

```json
"plugins": { "antigravity": { "source": "https://github.com/KadaXuanwu/Scriptorium-Antigravity" } }
```

Then run Scriptorium's `setup.ps1` again. A project has one provider, so take another provider's entry out.

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
(`agy models` lists them), so runs have no effort of their own. The list is the Gemini models of a free plan: a paid
plan has more, and its owner sets them under `complexities` in the project's `scriptorium.json`.

## Permissions

A run gets its rules for itself alone: the plugin writes them into `run-settings.json` in the worker's queue folder
and hands that file over with `--settings`, which saves nothing. The owner's own
`~/.gemini/antigravity-cli/settings.json` is never written.

- Each command the base and the plugins allow becomes a rule: `git` becomes `command(git)`.
- A rule from `allowedTools` in `scriptorium.json` is handed on when it is in Antigravity's syntax
  (`read_url(github.com)`), and left out when it is another tool's.
- No mode is set. Seen with nobody there on a free plan: file edits ran, a command with no rule (`dotnet --version`)
  ran inside the sandbox, and an action that needed approval was refused. The run ended there, and its result named
  the action: the plugin reads that as the run's failure.

Antigravity runs a command inside a sandbox that cannot write to `.git` and has no network. The run's playbook
(`PLAYBOOK.md`) therefore tells it to start each `git` and `gh` command outside the sandbox, alone in its call: an
allow rule covers a command by how it starts, and a chained command line is refused.

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
- The rules of `--settings`: a `git` command passes outside the sandbox, a chained one is refused and ends the run.
- `/usage` with nobody there: the week of the Gemini models, its share left and its reset.
- `/compact` on a named session.
- An unknown model, and the service's own shortage (error 503) in the middle of a session. The plugin reads the
  shortage as a limit: the base holds the job with its session and resumes it after 30 minutes.
- A model's name with `--effort` beside it is refused.

Not proven:

1. A whole ticket: `git push` and `gh pr create` from a worker copy, and the base's own playbook as the prompt.
2. A run at the plan's limit: the wording is taken from the service's names for it, not from a log.
3. A run without a login: the wording is from Antigravity's docs.
4. A paid plan: its models, its 5-hour window (the plugin reads every `gemini-` window that `/usage` names, and
   `models.json` knows only the week), and whether its auto mode behaves like the free plan's.
5. A folder that Antigravity does not trust yet, with nobody there.
6. macOS and Linux, and PowerShell 7 outside this repo's CI.

## Token savings

None of its own yet. The base's are in
[Scriptorium's README](https://github.com/KadaXuanwu/Scriptorium#built-in-token-savings). Measured on 2026-11-25: a
run's first request reads about 10,500 tokens before its prompt, with Antigravity's own tools and no MCP server.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1
```

It prints `ok` or throws. It needs no Antigravity and no network.
