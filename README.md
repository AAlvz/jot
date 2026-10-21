# jot

[![test](https://github.com/AAlvz/jot/actions/workflows/test.yml/badge.svg)](https://github.com/AAlvz/jot/actions/workflows/test.yml)

A pop-up notepad for Emacs, for taking notes while you read.

You are reading long output — an AI assistant's answer, a build log, a diff —
and want to note things about several parts of it. Jot pops a small notepad up
right under the line you are on, like a sticky note, with that line already
quoted. Type your note, press the key again, and you are back exactly where you
were. Notes pile up as you go, and when you are done reading, one key pastes
them all.

It was built for terminals inside Emacs, and it works from **vterm's copy
mode**: no toggling in and out of copy mode for every note.

![jot demo: notes pop up under the line being read, quoting it, then every note is pasted at the prompt](demo/jot.gif)

## Contents

- [How it works](#how-it-works)
- [Install](#install)
- [Configuration](#configuration)
- [The pop-up](#the-pop-up)
- [Terminals](#terminals)
- [Development](#development)

## How it works

| Key (suggested) | Command | What it does |
|---|---|---|
| `C-c j` | `jot-toggle` | Pop the notepad up, quoting the line at point (or the region). Again: hide it and go back |
| `C-u C-c j` | `jot-toggle` | Pop it up without quoting anything |
| `C-c C-c` | `jot-hide` | In the notepad: hide it and go back |
| `C-c J` | `jot-paste` | Paste every note at point, then clear the notepad |
| `C-u C-c J` | `jot-paste` | Paste, but keep the notes |
| | `jot-clear` | Empty the notepad (its contents go to the kill ring) |

A session looks like this:

1. Read. In a vterm, enter copy mode (`C-c C-t`) and move around as usual.
2. `C-c j` on a line worth a note. The notepad pops up below it with
   `> the line` already in it. Type.
3. `C-c j` again. You are back on the same line, still in copy mode.
4. Repeat as often as you like. Notes accumulate.
5. `C-c J` at the prompt. Every note arrives as one paste, ready to edit and
   send.

Details worth knowing:

- **Peeking is free.** Open and close without typing and nothing is left
  behind, not even the quote.
- **Nothing is lost.** Pasted or cleared notes also go on the kill ring, and
  the notepad is a plain file saved each time it hides, so notes survive a
  restart.
- **Quotes are cleaned up.** Surrounding whitespace and the box-drawing
  borders (`│┃║`) that terminal UIs draw are trimmed.

## Install

Jot needs Emacs 29.1 or later. The pop-up needs a graphical Emacs, or Emacs 31
or later in a terminal; elsewhere jot uses a side window instead, with no
configuration needed. vterm is optional.

**Emacs 30 and later**, straight from GitHub:

```elisp
(use-package jot
  :vc (:url "https://github.com/AAlvz/jot" :rev :newest)
  :bind (("C-c j" . jot-toggle)
         ("C-c J" . jot-paste)))
```

**Emacs 29** has no `:vc` keyword. Install once with
`M-x package-vc-install RET https://github.com/AAlvz/jot RET`, then:

```elisp
(use-package jot
  :bind (("C-c j" . jot-toggle)
         ("C-c J" . jot-paste)))
```

**By hand:** put `jot.el` on your `load-path`, `(require 'jot)`, and bind the
keys.

Jot binds no global keys itself, since `C-c` followed by a letter is reserved
for users. Any keys work; the ones above are only a suggestion.

## Configuration

Everything is available through `M-x customize-group RET jot`.

| Option | Default | |
|---|---|---|
| `jot-display` | `popup` | `popup` next to point, or `side` for a docked window |
| `jot-popup-width` | `60` | Pop-up width in columns, narrowed to fit the window |
| `jot-popup-height` | `8` | Pop-up height in lines, at most half the window |
| `jot-popup` (face) | inherits `tooltip` | Pop-up background and text colors |
| `jot-window-side` | `bottom` | Side window position: `bottom`, `top`, `left`, `right` |
| `jot-window-size` | `0.3` | Side window size: a fraction of the frame, or lines/columns |
| `jot-file` | `~/.emacs.d/jot.md` | Where the notes live |
| `jot-quote-prefix` | `"> "` | Put before each quoted line |
| `jot-trim-regexp` | whitespace and `│┃║` | Trimmed from both ends of quoted lines |
| `jot-clear-after-paste` | `t` | Empty the notepad after pasting; `C-u` inverts it once |
| `jot-quote-predicates` | vterm check | Functions that can veto quoting the line at point |
| `jot-paste-functions` | vterm paste | Functions that paste into special buffers |

A fuller setup:

```elisp
(use-package jot
  :vc (:url "https://github.com/AAlvz/jot" :rev :newest)
  :bind (("C-c j" . jot-toggle)
         ("C-c J" . jot-paste))
  :custom
  (jot-popup-width 70)            ; a wider sticky note
  (jot-popup-height 10)
  (jot-file "~/Documents/jot.md") ; keep notes somewhere you back up
  :custom-face
  (jot-popup ((t :background "#3b3f4c" :foreground "#e6e6e6"))))
```

## The pop-up

`jot-toggle` opens the pop-up just below the line at point, or just above it
when there is no room below, always inside the window you are reading.

It is not a separate scratch area: it shows the **whole notepad**, opened on
the newest note. Scroll up or search (`C-r`) inside it to reach earlier notes.

It is an Emacs *child frame*: a small frame floating over the main one, the
same mechanism completion pop-ups such as Corfu use. Graphical Emacs has
always had them; Emacs 31 added them to text terminals, which is what makes
jot's pop-up work in `emacs -nw`. When they are not available, or with
`jot-display` set to `side`, the notepad opens in a side window instead and
works the same way.

The pop-up takes its colors from the `jot-popup` face, which inherits from
`tooltip`. If it blends in with your theme, give it a background of its own
(see the setup above), or run `M-x customize-face RET jot-popup RET`.

## Terminals

In a vterm buffer, point means something only in `vterm-copy-mode`, so that
is when the line is quoted; in a live terminal point is just the prompt.
`jot-paste` leaves copy mode on its own and sends the notes as a single
*bracketed paste*, so programs such as Claude Code or your shell receive the
newlines as text instead of pressing Enter on each one.

Other terminals plug in through two hooks:

- `jot-quote-predicates`: return `no` when the line at point is not worth
  quoting.
- `jot-paste-functions`: called with the text; send it and return non-nil
  when you handle the paste.

For example, an `eat` terminal:

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

The demo in `demo/` is scripted with [VHS](https://github.com/charmbracelet/vhs)
in a throwaway Emacs and shell, so it can be re-recorded after any change.
Changes are listed in [CHANGELOG.md](CHANGELOG.md). Ideas and pull requests
are welcome.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
