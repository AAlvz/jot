# Changelog

All notable changes to jot. Versions follow [semver](https://semver.org).

## 0.2.1 — 2026-10-22

### Fixed

- A region made with `rectangle-mark-mode` (`C-x SPC`) now quotes only the
  rectangle's columns instead of every line it spans in full.

## 0.2.0 — 2026-10-21

### Added

- **Pop-up display.** `jot-toggle` now opens the notepad in a small floating
  frame right below the line at point (or above it near the bottom of the
  window), like a sticky note. It shows the whole notepad opened on the newest
  note, so scrolling and `C-r` still reach every earlier one.
- `jot-display` chooses between `popup` and the docked `side` window.
- `jot-popup-width` and `jot-popup-height` size the pop-up; it always fits
  inside the window it opens over.
- The `jot-popup` face colors the pop-up. It inherits from `tooltip`.
- The notepad wraps long lines at word boundaries.

### Changed

- **`popup` is the default display.** It needs a graphical Emacs, or Emacs 31
  or later in a terminal; everywhere else jot falls back to the side window as
  before. To keep the docked window everywhere, set `jot-display` to `side`.

## 0.1.0 — 2026-10-20

First release.

- `jot-toggle` opens the notepad in a side window, quoting the line at point
  or the region, and hides it again, returning to where you were.
- `jot-paste` pastes every note at point and clears the notepad; `jot-clear`
  empties it.
- vterm support: quoting from `vterm-copy-mode`, and pasting as one bracketed
  paste that leaves copy mode first.
- `jot-quote-predicates` and `jot-paste-functions` for other terminals.
