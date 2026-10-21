# Records the README GIF:  vhs demo/demo.tape   (from the repo root)
# Needs vhs, zsh, and vterm installed in ~/.emacs.d.  Everything on screen is
# made up: a throwaway Emacs (demo-init.el) and a zsh with a bare prompt.

Output demo/jot.gif
Set Shell "bash"
Set FontSize 18
Set Width 1100
Set Height 700
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "TERM=xterm-256color COLORTERM=truecolor emacs -Q -nw -l demo/demo-init.el" Enter
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

# C-c J: every note goes to the prompt as one paste, nothing is sent.
Ctrl+C
Type "J"
Sleep 4s
