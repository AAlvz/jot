# Records the README GIF:  vhs demo/demo.tape   (from the repo root)
# Needs vhs, zsh, vterm installed in ~/.emacs.d, and a logged-in `claude`.  Everything on screen is
# made up: a throwaway Emacs (demo-init.el) and a zsh with a bare prompt.

Output demo/jot.gif
Set Shell "bash"
Set FontSize 18
Set Width 1100
Set Height 760
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "env -u CLAUDECODE TERM=xterm-256color COLORTERM=truecolor emacs -Q -nw -l demo/demo-init.el" Enter
Sleep 4s
Show

# Some long output to read.
Sleep 2s

# Copy mode, then search to the first thing worth a note.
Ctrl+C Ctrl+T
Sleep 800ms
Ctrl+R
Type "release job"
Enter
Sleep 1s

# C-c j: the note pops up under the line, already quoted.  Type, then
# C-c j again: back to reading, still in copy mode.
Ctrl+C
Type "j"
Sleep 1200ms
Type "which table? users is 40GB"
Sleep 800ms
Ctrl+C
Type "j"
Sleep 1500ms

# A region works too.
Ctrl+S
Type "Move the"
Enter
Ctrl+A
Ctrl+Space
Ctrl+N
Ctrl+E
Sleep 1200ms
Ctrl+C
Type "j"
Sleep 1200ms
Type "what lock_timeout? 5s?"
Sleep 1200ms

# The pop-up opens on the newest note, but every earlier one is a search away.
Ctrl+R
Type "users"
Sleep 1800ms
Enter
Sleep 600ms
Ctrl+C Ctrl+C
Sleep 1500ms

# C-c a: ask Claude about a line.  The pop-up turns blue, counts down while
# it waits, and the answer lands under the question.
Ctrl+R
Type "lock_timeout"
Enter
Sleep 600ms
Ctrl+C
Type "a"
Sleep 1200ms
Type "what's a sane lock_timeout here? one sentence"
Sleep 800ms
Ctrl+C Ctrl+A
Sleep 9s
Ctrl+C Ctrl+C
Sleep 1500ms

# C-c J: every note, question and answer goes to the prompt as one paste,
# and nothing is sent.
Ctrl+C
Type "J"
Sleep 4s
