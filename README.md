# jot

A pop-up notepad for Emacs, for taking notes while you read.

You are reading long output — an AI assistant's answer, a build log, a diff —
and want to note things about several parts of it. Jot pops a notepad up over
it, quotes the line you are on, lets you type, and puts you back exactly where
you were. Notes pile up as you go. When you are done reading, one key pastes
them all.

It was built for terminals inside Emacs, and it works from **vterm's copy
mode**: there is no need to toggle in and out of copy mode for every note.

![jot demo: quoting lines from vterm copy mode into the notepad, then pasting every note at the prompt](demo/jot.gif)

## How it works

| Key (suggested) | Command | What it does |
|---|---|---|
| `C-c j` | `jot-toggle` | Open the notepad, quoting the line at point (or the region). Again: hide it and go back |
| `C-u C-c j` | `jot-toggle` | Open without quoting |
| `C-c C-c` | `jot-hide` | In the notepad: hide it |
| `C-c J` | `jot-paste` | Paste every note at point and clear the notepad |
| `C-u C-c J` | `jot-paste` | Paste but keep the notes |
| | `jot-clear` | Empty the notepad (contents go to the kill ring) |

- **In a vterm**, the line is quoted only in copy mode, because in a live
  terminal point is the prompt. `jot-paste` leaves copy mode and sends the
  notes as one *bracketed paste*, so programs such as Claude Code or your
  shell receive the newlines as text instead of pressing Enter on each one.
- **Anywhere else**, the notes are inserted at point.
- Opening and closing without typing leaves nothing behind, so the toggle
  doubles as a quick peek.
- Box-drawing borders (`│┃║`) are trimmed from quotes.
- Pasted notes also go on the kill ring, so a clear is never a loss.
- The notepad is a plain file, saved each time it hides, so notes survive
  restarts.

## Install

Jot needs Emacs 29.1 or later. vterm is optional.

**Emacs 30+**, straight from GitHub:

```elisp
(use-package jot
  :vc (:url "https://github.com/AAlvz/jot")
  :bind (("C-c j" . jot-toggle)
         ("C-c J" . jot-paste)))
```

**Emacs 29**: run `M-x package-vc-install RET https://github.com/AAlvz/jot RET`
once, then:

```elisp
(use-package jot
  :bind (("C-c j" . jot-toggle)
         ("C-c J" . jot-paste)))
```

**Manually**: put `jot.el` on your `load-path`, `(require 'jot)`, and bind the
keys yourself.

Jot binds no global keys on its own: `C-c` followed by a letter is reserved for
users. Any keys work; the ones above are just a suggestion.

## Options

`M-x customize-group RET jot` lists them all.

| Option | Default | |
|---|---|---|
| `jot-file` | `~/.emacs.d/jot.md` | Where the notes live |
| `jot-window-side` | `bottom` | `bottom`, `top`, `left` or `right` |
| `jot-window-size` | `0.3` | Fraction of the frame, or lines/columns |
| `jot-quote-prefix` | `"> "` | Put before each quoted line |
| `jot-trim-regexp` | whitespace and `│┃║` | Trimmed from both ends of quoted lines |
| `jot-clear-after-paste` | `t` | `C-u` inverts it for one paste |
| `jot-quote-predicates` | vterm check | Functions that can veto quoting the line at point |
| `jot-paste-functions` | vterm paste | Functions that paste into special buffers |

### Other terminals

`jot-quote-predicates` and `jot-paste-functions` are how jot learns about a
terminal. For example, to paste into an `eat` terminal:

```elisp
(defun my/jot-eat-paste (text)
  (when (derived-mode-p 'eat-mode)
    (eat-term-send-string eat-terminal text)
    t))
(add-hook 'jot-paste-functions #'my/jot-eat-paste)
```

## Development

```
make compile     # byte-compile, warnings are errors
make lint        # checkdoc + package-lint
make test        # ERT suite
make test-vterm  # the suite plus a real vterm test, using your installed vterm
make demo        # re-record demo/jot.gif (needs vhs and gifsicle)
```

Ideas and pull requests are welcome.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
