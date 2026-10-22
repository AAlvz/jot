# jot-ask: quick questions from the notepad

Status: **design**, not built. Comments welcome before any code.

## The idea

jot already grabs what you are reading, pops up next to it, and keeps what you
write. jot-ask adds one thing: **a note can be sent as a question**. The answer
comes back into the notepad, right under the question, and you can follow up
in the same place.

```
  b. Move the migration to a pre-deploy hook with lock_timeout
     set, so it fails fast and retries instead of hanging.
   ┌ [quick]  C-c C-a ask · C-c C-p mode · C-c j close ───┐
   │ > b. Move the migration to a pre-deploy hook with    │
   │   lock_timeout set, so it fails fast and retries     │
   │ ? what's a sane lock_timeout for a 40GB table?       │
   │ = Table size doesn't change it: lock_timeout bounds  │
   │   how long you wait to acquire the lock. 2–5s with   │
   │   retries is typical.                                │
   │ ? and statement_timeout?█                            │
   └──────────────────────────────────────────────────────┘
```

Questions and answers are ordinary notepad text: searchable with `C-r`, saved
with everything else, and pasted by `C-c J` along with the notes.

## Flow

Two ways in, same result:

1. **From the highlight.** `jot-ask` pops the notepad up with the highlight
   quoted and a `? ` line ready for the question. Type it and press `C-c C-a`.
2. **From a note.** Write a note as usual, then press `C-c C-a` instead of
   closing. That note is sent as the question.

While the answer is on its way the entry shows `⠋ asking…`. Closing the popup
does not cancel anything: the answer lands in the notepad when it arrives, and
the echo area says so.

A follow-up is another `? ` line under the answer, sent with `C-c C-a`. It
continues the same conversation.

## Visible keys

The popup's top line shows the mode and the few keys that matter, so nothing
has to be memorized:

```
[quick]  C-c C-a ask · C-c C-p mode · C-c j close
[project: tribu]  C-c C-a ask · C-c C-p mode · C-c j close
```

Only the everyday keys and toggles go there. Everything deeper (model,
command, instructions) is ordinary package configuration. The hint line can be
turned off with `jot-show-hints`.

| Key | Where | Does |
|---|---|---|
| `C-c a` (suggested) | anywhere | `jot-ask`: pop up with the highlight quoted, ready for a question |
| `C-u C-c a` | anywhere | the same, in the other mode for this question |
| `C-c C-a` | in the notepad | send the current note or follow-up as a question |
| `C-c C-p` | in the notepad | switch this question between quick and project |
| `C-c j`, `C-c C-c`, `C-c J` | | unchanged: close, close, paste |

`C-c C-c` keeps meaning "close", as it does today, so existing habits still
work.

## Two modes

| | **Quick** | **Project** |
|---|---|---|
| Runs in | a clean jot folder, `~/.emacs.d/jot-ask/` | the project of the buffer being read |
| Claude knows | the highlight and the question | that project's `CLAUDE.md`, and can read its files |
| Tools | none (`--tools ""`) | read-only: `Read,Grep,Glob` |
| Typical answer time | a few seconds | longer if it reads files first, up to ~30s |
| Good for | "what is lock_timeout?" | "why does *our* deploy do this?" |

`jot-ask-default-mode` picks the default. `C-u` before `jot-ask`, or `C-c C-p`
in the popup, flips it for one question. The popup always shows which mode is
active, and in project mode, which project.

**Project mode never changes anything.** Only read-only tools are allowed: no
shell commands, no edits.

### jot's instructions go with every question

The "this is a narrow popup" instructions cannot live only in the clean
folder, or project mode would ignore them (there Claude reads the project's
`CLAUDE.md`). So they are passed on every call with `--append-system-prompt`,
from `jot-ask-instructions`. The default is roughly:

> You are answering inside a small pop-up notepad in Emacs, about 60 columns
> wide. Answer in a few sentences of plain text. No headings, no tables, no
> preamble. If the question is ambiguous, answer the most likely reading.

The clean folder starts empty. Put a `CLAUDE.md` in it for extra
quick-mode-only behavior.

### Finding "the project"

jot asks Emacs for the project of the buffer being read (`project-current`,
the same lookup `C-x p` uses), falling back to that buffer's directory.

In a vterm, Emacs only knows the shell's *current* directory if the shell
reports it on every `cd`. Otherwise `default-directory` stays where the vterm
started. vterm documents a few shell lines for this ("directory tracking"), so
dot_files' `.shell_common` should get them. The popup showing the project name
is the safety net.

## Conversations

- Every first question starts a new conversation with an ID jot chooses
  itself (`--session-id <uuid>`), so no output parsing is needed to continue it.
- A follow-up runs `--resume <uuid>` **from the same directory**. Claude Code
  stores conversations per directory, so jot records the directory and mode
  with each conversation.
- Switching modes in the middle of a conversation starts a new one instead of
  half-continuing the old one.
- Conversation IDs live in memory for this Emacs session. After a restart, a
  follow-up on an old question starts a new conversation.

## Command and configuration

The default runs Claude Code in print mode, which answers once and exits:

```
claude -p --model <jot-ask-model> --tools "" \
       --append-system-prompt <jot-ask-instructions> \
       --session-id <uuid> "<quote + question>"
```

It runs as an asynchronous process, so Emacs never freezes.

| Option | Default | |
|---|---|---|
| `jot-ask-default-mode` | `quick` | `quick` or `project` |
| `jot-ask-model` | `nil` | `nil` = the user's normal Claude model |
| `jot-ask-command` | `claude` CLI | a function or command template, so other CLIs work (`llm`, `ollama run`, `gemini -p`) |
| `jot-ask-instructions` | as above | sent with every question |
| `jot-ask-quick-directory` | `~/.emacs.d/jot-ask/` | where quick questions run |
| `jot-ask-project-tools` | `Read,Grep,Glob` | what project mode may use |
| `jot-paste-answers` | `t` | `nil` leaves answers out of `C-c J` |
| `jot-show-hints` | `t` | the key line at the top of the popup |

Other CLIs may have no sessions or system prompts. For those, follow-ups resend
the earlier questions and answers as context, and the instructions are
prepended to the prompt.

## Notepad format

```
> quoted highlight
? the question
= the answer, wrapped like any note
? a follow-up
= its answer
```

`? ` and `= ` are prefixes, like the existing `> `, and configurable.
`jot-paste-answers` set to `nil` drops the `= ` blocks when pasting and keeps
everything else.

## Privacy

Only what is explicitly in the entry is sent: the quote and what you typed.
jot-ask never sends the screen, the notepad's other notes, or surrounding
output on its own. Terminal output can hold tokens and internal names, so the
README will say this plainly.

## Packaging

- A separate file, `jot-ask.el`, in this repo. It loads only when used, and
  `jot.el` keeps working without it.
- It is not part of the first MELPA submission. It merges once it has settled.

## To verify in the prototype

- [ ] `claude -p` in a folder it has never seen does not stop to ask whether
      the folder is trusted.
- [ ] What quick mode still loads. The user's own `~/.claude/CLAUDE.md`, hooks
      and MCP servers apply in every directory, so the clean folder is not fully
      clean. Check whether `--setting-sources`, `--strict-mcp-config` or an empty
      `--mcp-config` make it cleaner without losing the user's login.
      `--bare` would, but it ignores OAuth/keychain logins and only accepts an
      API key, so it cannot be the default.
- [ ] Answer latency in both modes, and whether streaming
      (`--output-format stream-json`) is worth it for the popup.
- [ ] Process cleanup: closing Emacs, or deleting the entry, while a question
      is running.
