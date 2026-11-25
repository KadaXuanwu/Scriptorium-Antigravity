# Playbook: Antigravity

What a run on Antigravity adds to Scriptorium's `PLAYBOOK.md`. A name in brackets is a part of that playbook.

**The rules file.** The project's rules file is `AGENTS.md`; in a project that has none, `GEMINI.md`, then `CLAUDE.md`.
Antigravity loads `AGENTS.md` and `GEMINI.md` into your context: do not read them again (step 2). Read a `CLAUDE.md`
that stands alone in step 2. In a job in another repository (`PLAYBOOK-repo.md`), this repo's rules file is in an
added folder, so it is not in your context: read it in step 2.

**One shell.** On Windows your shell is Windows PowerShell (One shell): chain commands with `;`, never with `&&`.

**The sandbox.** Your commands run inside a sandbox that cannot write to `.git` and has no network. So run every `git`
and every `gh` command outside the sandbox from the start, and alone: one `git` or `gh` command in one call, never
chained with another command. Its line is allowed when it is the command with plain words and quoted text:

- Outside quotes: no `;`, `|`, `&`, `<`, `>`, `$`, backtick, parenthesis or brace.
- Inside double quotes: no `$` and no backtick. Put such text in single quotes, or in a file that the command reads
  (`--body-file`, `-F`).

Any other line that leaves the sandbox needs an approval that nobody is there to give, and Antigravity ends the run
at once. So does every other command that you start outside the sandbox: start none.

**Compaction.** Antigravity compacts your context when it grows large: the checkpoint's commit and `progress.json` are
what you find again after it (Checkpoints).

**No AI attribution anywhere:** no `Co-Authored-By`, no "Generated with" line, in commits, PR descriptions or
comments.
