# Scriptorium for Antigravity

A provider plugin for [Scriptorium](https://github.com/KadaXuanwu/Scriptorium): it runs the queue's workers on
Google's Antigravity CLI (`agy`) with a Google AI plan.

**Status: its hooks work with the real tool, and one small ticket has run through it, from the queue to its merged
pull request.** Checked on 2026-11-25 against agy 1.5.17 on Windows with a free plan
([Proven and not](#proven-and-not)). A worker runs on Antigravity when its
account is an Antigravity account, beside workers on another coding tool in the same project (Scriptorium's
`docs/QUEUE.md`, Settings, `accounts.<name>.provider`).

## What it needs

- Antigravity CLI on the PATH: `agy --version` answers. Install it from
  [Antigravity's Quickstart](https://www.antigravity.google/docs/getting-started/).
- One sign-in: run `agy` once in a terminal, sign in with the Google account and trust the folder that holds the
  project and its worker copies. Antigravity keeps the login in the OS keyring, and a run with nobody there uses it.
- Scriptorium with provider plugins (its `docs/PLUGINS.md`, A provider), with the hooks `GetProbe` and `GetCompact`.
  An older base finds no probe and no compaction here.

## Use it

1. Add the plugin to one project's `scriptorium.json`, after its other plugins:

   ```json
   "antigravity": {}
   ```

   Scriptorium lists the plugin by name. A Scriptorium from before that needs the source in the entry:
   `{ "source": "https://github.com/KadaXuanwu/Scriptorium-Antigravity" }`.

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
| `GetProbe` | Gives the base `agy -p /usage`: the plan's usage windows and whether the login answers. It asks the model nothing, so it costs no usage. The base runs it, with a time limit |
| `ReadProbe` | Reads the usage windows and the refusal from what the probe printed |
| `GetLogin` | The login's email for the account's card, from the line that each start of `agy` writes into its own log. No process is started |
| `GetCompact` | Gives the base `/compact` on a held session, with the run's model and settings. The base runs it, with a time limit |
| `ReadCompact` | Reads from what the compaction printed whether the session is compacted. Gives no line for one that failed |
| `ReadStep` | The tool a run starts, with its command or its file |
| `ReadEnd` | Why a run ended: its status, its error, or the action that nobody could approve |

`models.json` holds the models, which one a complexity runs on, and the usage window. `agy` names a model and its
effort as one model (`agy models` lists them: `gemini-4-hydrogen-high`); the list holds each model with its own
efforts, so a worker's Config offers the two apart, and a run joins them into `agy`'s name. The list is the Gemini
models of a free plan; a paid plan has more. A project whose default provider is this plugin sets its own under `complexities` in its
`scriptorium.json`. In every other project, an Antigravity worker runs on this file's list.

## Permissions

A run gets its rules for itself alone: the plugin writes them into `run-settings.json` in the worker's queue folder
and hands that file over with `--settings`, which saves nothing. `--settings` is in the tool's help (agy 1.5.17), not
in Antigravity's docs. The owner's own
`~/.gemini/antigravity-cli/settings.json` is never written.

- Each command the base and the plugins allow becomes two rules. `git` becomes `command(git)`, which covers a line
  by how it starts, and a pattern for the whole line: the command, then plain words and quoted text, with no chain,
  pipe, redirection or command inside the command. Antigravity takes the first only in a shell whose lines it can
  split into words. In Windows PowerShell a rule must cover the whole line, so there the second one counts.
- Rules in Antigravity's own syntax go in this plugin's entry in `scriptorium.json`, under `allowedTools`. Only
  Antigravity reads them there, and they are handed on as they are:

  ```json
  "plugins": { "antigravity": { "allowedTools": ["command(dotnet)", "read_url(github.com)"] } }
  ```

- `allowedTools` at the top of `scriptorium.json` and the rules other plugins give are the older form: every provider
  gets them. A rule of that form is handed on when it is in Antigravity's syntax (`read_url(github.com)`), and left out
  when it is another tool's.
- No mode is set. Seen with nobody there on a free plan: file edits ran, a command with no rule (`dotnet --version`)
  ran inside the sandbox, and an action that needed approval was refused. The run ended there, and its result named
  the action: the plugin reads that as the run's failure.

Antigravity runs a command inside a sandbox that cannot write to `.git` and has no network. Antigravity's docs do not
name the sandbox: it was seen on 2026-11-25 with agy 1.5.17. A command that a rule covers may start outside it, alone
in its call. The run's playbook
(`PLAYBOOK.md`) therefore tells it to start each `git` and `gh` command outside the sandbox, alone in its call, and
which lines the rules cover.

With no mode set, a run is in Antigravity's Auto mode where the plan has it. There a model of Antigravity's reviews
each command that asks to leave the sandbox. When the review says no, or fails, Antigravity asks the user, and a
rule that covers the line answers for the user. A line that no rule covers has nobody to answer: the run ends there.
The review still runs for a line that a rule covers, so the rules save none of its requests.

## What Antigravity does not give

| Feature of the base | With Antigravity | So |
| ------------------- | ---------------- | -- |
| A usage reading inside a run's log | The log holds none; only `/usage` does | A worker reads the usage with `/usage` when a run ends, and before it takes a job when the last reading is older than 30 minutes. A stop line is not seen while a run works. The page's Ping shows that the login answers and reads the usage too |
| Several accounts on one PC | One login for each OS user | Every account of the page is the same login |
| Sign-in and sign-out from the page | The first sign-in needs a terminal | The page offers none |
| The plan's name and size, and whether the login is signed in | Not in a file: the sign-in is in the OS keyring | Every account counts as signed in, on a plan of size 1. The card shows the login's email, read from `agy`'s own log; with no log that names it, the card shows none |
| A cap for one run, a cost in money, an advisor, a compact size | None | Left out |
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
- A whole ticket of size S, with the base's own playbook as the prompt, from the worker's logon task: the run read
  the ticket, made its branch and the ticket's edit, committed, rebased, pushed and opened its pull request, and the
  merger merged it. A first run of the same ticket ended at `git add`, before the rule above.
- `/usage` with nobody there: the week of the Gemini models, its share left and its reset.
- `/compact` on a named session.
- An unknown model, and the service's own shortage (error 503) in the middle of a session. The plugin reads the
  shortage as a limit: the base holds the job with its session and resumes it after 30 minutes.
- A model's name with `--effort` beside it is refused.

Not proven:

1. A ticket whose checks must pass inside the sandbox. Scriptorium's own `check.ps1` fails there: one test starts
   a background job, which the sandbox denies. The run opened its pull request all the same, and its text did not
   name the failed test.
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
