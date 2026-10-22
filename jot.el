;;; jot.el --- Pop-up notepad for taking notes while you read -*- lexical-binding: t -*-

;; Copyright (C) 2026 AAlvz

;; Author: AAlvz <alfonso@alvz.mx>
;; Maintainer: AAlvz <alfonso@alvz.mx>
;; Assisted-by: Claude Code:claude-opus-5-5
;; URL: https://github.com/AAlvz/jot
;; Version: 0.2.1
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, terminals, outlines

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Jot is a notepad that pops up over whatever you are reading, so you can
;; take notes on long output -- an AI assistant's answer, a build log, a
;; diff -- without losing your place.
;;
;; `jot-toggle' pops the notepad up right below the line you are on, like a
;; sticky note, and quotes that line (or the region) so each note says what
;; it is about.  Calling it again hides the notepad and returns you to the
;; window and position you came from.  Notes accumulate across toggles until
;; `jot-paste' inserts them all at point and clears the notepad.
;;
;; The pop-up shows the whole notepad, opened on the newest note: scroll or
;; search to reach earlier ones.  It needs a graphical display, or Emacs 31
;; or later on a text terminal; anywhere else, or with `jot-display' set to
;; `side', the notepad docks in a side window instead.
;;
;; It was written for terminals inside Emacs.  In a vterm buffer, point is
;; only meaningful in `vterm-copy-mode', so that is when the line is quoted,
;; and `jot-paste' leaves copy mode and sends the notes as a single bracketed
;; paste, so a program such as Claude Code or a shell receives the newlines
;; as text instead of as Enter.  Everywhere else the notes are simply
;; inserted.  Other terminals can be supported through `jot-paste-functions'
;; and `jot-quote-predicates'.
;;
;; Jot binds no keys globally.  A typical setup:
;;
;;   (use-package jot
;;     :bind (("C-c j" . jot-toggle)
;;            ("C-c J" . jot-paste)))
;;
;; The notepad is an ordinary file (`jot-file'), saved every time it is
;; hidden, so notes survive restarts.

;;; Code:

(require 'seq)
(require 'subr-x)

(declare-function vterm-send-string "ext:vterm" (string &optional paste-p))
(declare-function vterm-copy-mode "ext:vterm" (&optional arg))
(declare-function project-root "project" (project))
(defvar vterm--process)
(defvar vterm-copy-mode)

(defgroup jot nil
  "Pop-up notepad for taking notes while reading."
  :group 'convenience
  :prefix "jot-")

(defcustom jot-file (locate-user-emacs-file "jot.md")
  "File that holds the notepad's contents."
  :type 'file)

(defcustom jot-window-side 'bottom
  "Side of the frame where the notepad docks, when not a pop-up."
  :type '(choice (const bottom) (const top) (const left) (const right)))

(defcustom jot-window-size 0.3
  "Size of the notepad window.
A float is a fraction of the frame, an integer a number of lines (or
columns, for the left and right sides)."
  :type 'number)

(defcustom jot-display 'popup
  "How the notepad is shown.
`popup' floats it in a small frame next to point, like a sticky note,
sized by `jot-popup-width' and `jot-popup-height' and colored by the
`jot-popup' face.  It needs a graphical display, or Emacs 31 or later on
a text terminal; elsewhere jot falls back to `side'.  `side' docks it in
a side window, see `jot-window-side' and `jot-window-size'."
  :type '(choice (const :tag "Side window" side)
                 (const :tag "Pop-up next to point" popup))
  :package-version '(jot . "0.2.0"))

(defcustom jot-popup-width 60
  "Width of the pop-up notepad, in columns.
It is narrowed to fit when the window is smaller."
  :type 'natnum
  :package-version '(jot . "0.2.0"))

(defcustom jot-popup-height 8
  "Height of the pop-up notepad, in lines.
It never takes more than half of the window it pops up over."
  :type 'natnum
  :package-version '(jot . "0.2.0"))

(defface jot-popup '((t :inherit tooltip))
  "Face for the pop-up notepad: its text, background and border.
Only the colors are used."
  :package-version '(jot . "0.2.0"))

(defcustom jot-quote-prefix "> "
  "String put in front of each quoted line."
  :type 'string)

(defcustom jot-trim-regexp "[ \t│┃║]+"
  "Regexp trimmed from both ends of each quoted line.
The default also removes the box-drawing borders that terminal UIs draw
around their output."
  :type 'regexp)

(defcustom jot-clear-after-paste t
  "Non-nil means `jot-paste' empties the notepad after pasting.
A prefix argument to `jot-paste' inverts this for one call."
  :type 'boolean)

(defcustom jot-question-prefix "? "
  "String that starts a question line, see `jot-ask'."
  :type 'string
  :package-version '(jot . "0.3.0"))

(defcustom jot-answer-prefix "= "
  "String that starts an answer.  Its other lines are indented to match."
  :type 'string
  :package-version '(jot . "0.3.0"))

(defcustom jot-paste-answers t
  "Non-nil means `jot-paste' includes the answers from `jot-ask'.
Nil pastes the notes and questions only."
  :type 'boolean
  :package-version '(jot . "0.3.0"))

(defcustom jot-show-hints t
  "Non-nil means the notepad shows its main keys on its top line.
The line also shows whether `jot-ask' questions go out in quick or
project mode."
  :type 'boolean
  :package-version '(jot . "0.3.0"))

(defcustom jot-ask-default-mode 'quick
  "Context that `jot-ask' questions start with.
`quick' asks with no project context; `project' asks from the project
of the buffer being read, so its instructions and files are known.
\\<jot-mode-map>\\[jot-ask-toggle-mode] in the notepad switches it for one question."
  :type '(choice (const :tag "Quick, no context" quick)
                 (const :tag "From the project being read" project))
  :package-version '(jot . "0.3.0"))

(defcustom jot-quote-predicates (list #'jot--vterm-quotable-p)
  "Functions deciding whether the line at point is worth quoting.
Each is called with no arguments in the buffer being read.  If any
returns the symbol `no', nothing is quoted.  This exists for terminals,
where point may sit on a live prompt rather than on output."
  :type 'hook)

(defcustom jot-paste-functions (list #'jot--vterm-paste)
  "Functions that paste text into special buffers, such as terminals.
Each is called with the text in the target buffer and returns non-nil if
it handled the paste.  When none does, the text is inserted at point."
  :type 'hook)

(defvar jot--return-window nil
  "Window that was selected when the notepad was opened.")

(defvar jot--popup-frame nil
  "The child frame showing the notepad in `popup' display, if any.")

(defvar jot--pending nil
  "(START . TEXT) of the quote inserted on the last open, until written under.")

(defvar jot--ask-mode nil
  "Mode for the next `jot-ask' question: `quick' or `project'.")

(defvar jot--ask-directory nil
  "Project directory for `project' questions, worked out on demand.
The symbol `unknown' until it is first needed after an open.")

;; The asking side lives in jot-ask.el and loads on first use.  Declared
;; here so the keys work however jot was installed, autoloads or not.
(autoload 'jot-ask "jot-ask"
  "Pop the notepad up with the line or region quoted, ready for a question." t)
(autoload 'jot-ask-send "jot-ask"
  "Send the question being written in the notepad." t)

(defvar-keymap jot-mode-map
  :doc "Keymap for `jot-mode'."
  "C-c C-c" #'jot-hide
  "C-c C-k" #'jot-hide
  "C-c C-a" #'jot-ask-send
  "C-c C-p" #'jot-ask-toggle-mode
  "C-c C-d" #'jot-set-directory)

;; Of the two ways to close, show the one most notepads use.
(put 'jot-hide :advertised-binding (kbd "C-c C-c"))

(define-minor-mode jot-mode
  "Minor mode for the jot notepad buffer.

\\{jot-mode-map}"
  :lighter " Jot"
  ;; Quotes are often longer than the pop-up is wide: wrap them at word
  ;; boundaries, without the backslash a terminal puts at each wrap.
  (when jot-mode
    (setq-local word-wrap t)
    (let ((table (make-display-table)))
      (set-display-table-slot table 'wrap ?\s)
      (setq-local buffer-display-table table))
    (setq-local header-line-format '(:eval (jot--header-line)))))

;;;; Terminal integration

(defun jot--vterm-quotable-p ()
  "Return `no' in a live vterm, where point is the prompt, not output."
  (and (derived-mode-p 'vterm-mode)
       (not (bound-and-true-p vterm-copy-mode))
       'no))

(defun jot--vterm-paste (text)
  "Send TEXT to a vterm as one bracketed paste, leaving copy mode first.
Return nil outside vterm buffers."
  (when (derived-mode-p 'vterm-mode)
    (when (bound-and-true-p vterm-copy-mode)
      (vterm-copy-mode -1))
    (vterm-send-string text t)
    t))

;;;; Internals

(defun jot--buffer ()
  "Return the notepad buffer, visiting `jot-file' if needed."
  (let ((buf (find-file-noselect jot-file)))
    (with-current-buffer buf
      (unless jot-mode (jot-mode 1)))
    buf))

(defun jot--quote ()
  "Return the region, or the line at point, as quoted lines, or nil.
A rectangular region quotes only the rectangle.
Nil when a predicate in `jot-quote-predicates' vetoes it and no region
is active."
  (when (or (use-region-p)
            (not (memq 'no (mapcar #'funcall jot-quote-predicates))))
    (let* ((text (if (use-region-p)
                     ;; The same extraction copy and kill use, so a
                     ;; `rectangle-mark-mode' region gives just its columns.
                     (substring-no-properties (funcall region-extract-function nil))
                   (buffer-substring-no-properties (line-beginning-position)
                                                   (line-end-position))))
           (lines (seq-remove #'string-empty-p
                              (mapcar (lambda (l)
                                        (string-trim l jot-trim-regexp jot-trim-regexp))
                                      (split-string text "\n")))))
      (when lines
        (mapconcat (lambda (l) (concat jot-quote-prefix l)) lines "\n")))))

(defun jot--save (buf)
  "Save BUF quietly if it is modified."
  (with-current-buffer buf
    (when (buffer-modified-p)
      (let ((save-silently t))
        (save-buffer)))))

;;;; Questions and context

(defun jot--header-line ()
  "Return the notepad's top line: the question mode and the main keys."
  (when jot-show-hints
    (let ((close (or (where-is-internal #'jot-toggle nil t)
                     (where-is-internal #'jot-hide jot-mode-map t))))
      (concat
       " " (propertize (jot--ask-mode-label) 'face 'bold) "  "
       (propertize
        (substitute-command-keys
         (concat "\\<jot-mode-map>\\[jot-ask-send] ask · "
                 "\\[jot-ask-toggle-mode] mode · "
                 (key-description close) " close"))
        'face 'shadow)))))

(defun jot--ask-mode-label ()
  "Return a label for the question mode, naming the project if any."
  (if (eq (jot--ask-mode) 'project)
      (let ((dir (jot--ask-directory)))
        (format "[project: %s]"
                (if dir
                    (file-name-nondirectory (directory-file-name dir))
                  "none, asks quick")))
    "[quick]"))

(defun jot--ask-mode ()
  "Return the mode for the next question."
  (or jot--ask-mode jot-ask-default-mode))

(defun jot-ask-toggle-mode ()
  "Switch the next question between quick and project mode."
  (interactive)
  (setq jot--ask-mode (if (eq (jot--ask-mode) 'project) 'quick 'project))
  (force-mode-line-update)
  (message "Jot: next question asks %s" (jot--ask-mode-label)))

(defun jot--ask-directory ()
  "Return the project directory of the buffer being read, or nil.
Worked out once per open, since for a terminal it can mean asking the
operating system."
  (when (eq jot--ask-directory 'unknown)
    (setq jot--ask-directory
          (when-let* ((win jot--return-window)
                      ((window-live-p win))
                      (dir (jot--source-directory (window-buffer win))))
            (if-let* (((require 'project nil t))
                      (project (project-current nil dir)))
                (expand-file-name (project-root project))
              dir))))
  jot--ask-directory)

(defvar-local jot-directory nil
  "Directory `project' questions about this buffer are asked from.
Set with `jot-set-directory'; when nil, jot works it out.")

(defvar jot-source-directory-functions (list #'jot--vterm-directory)
  "Functions that find the directory a special buffer is really in.
Each is called with the buffer and returns a directory, the symbol
`remote' when the buffer is about another machine, or nil to let the
next one try.  When none answers, the buffer's `default-directory' is
used.  Terminals need this: their `default-directory' is often only
where they were started.")

(defun jot--source-directory (buf)
  "Return the directory BUF is in, for `project' questions, or nil."
  (let ((dir (or (buffer-local-value 'jot-directory buf)
                 (run-hook-with-args-until-success
                  'jot-source-directory-functions buf)
                 (buffer-local-value 'default-directory buf))))
    ;; A remote directory cannot be a working directory for a local
    ;; command, so such questions go out quick instead.
    (when (and (stringp dir) (not (file-remote-p dir)) (file-directory-p dir))
      (file-name-as-directory (expand-file-name dir)))))

(defun jot-set-directory (dir)
  "Ask `project' questions about the buffer being read from DIR.
In the notepad, this sets it for the buffer the notepad was opened from.
With an empty answer, go back to working it out."
  (interactive
   (list (read-directory-name "Ask project questions from: " nil nil t)))
  (let ((buf (if (and (eq (current-buffer) (jot--buffer))
                      (window-live-p jot--return-window))
                 (window-buffer jot--return-window)
               (current-buffer))))
    (with-current-buffer buf
      (setq jot-directory (and (not (string-empty-p dir)) dir)))
    (setq jot--ask-directory 'unknown)
    (force-mode-line-update t)
    (message "Jot: project questions about %s ask from %s"
             (buffer-name buf) (or (jot--ask-directory) "nowhere, quick"))))

;; vterm's `default-directory' only follows `cd' when the shell reports it,
;; so ask the operating system where the terminal's foreground program
;; runs.  That also catches programs that change directory on their own.

(defun jot--pid-directory (pid)
  "Return the working directory of process PID, or nil."
  (let ((proc-link (format "/proc/%d/cwd" pid)))
    (cond ((file-exists-p proc-link)        ; Linux, WSL
           (ignore-errors (file-truename proc-link)))
          ((executable-find "lsof")         ; macOS, BSD
           (with-temp-buffer
             (when (eq 0 (call-process "lsof" nil t nil "-a" "-p"
                                       (number-to-string pid) "-d" "cwd" "-Fn"))
               (goto-char (point-min))
               (when (re-search-forward "^n\\(/.*\\)$" nil t)
                 (match-string 1))))))))

(defun jot--vterm-directory (buf)
  "Return the directory of the program in vterm BUF, `remote', or nil.
That is the foreground program's working directory: a shell at its
prompt, or whatever runs in it, such as Claude Code.  Inside tmux it is
the active pane's directory, and over ssh it is `remote'."
  (when-let* (((eq (buffer-local-value 'major-mode buf) 'vterm-mode))
              (proc (buffer-local-value 'vterm--process buf))
              ((process-live-p proc))
              (pid (alist-get 'tpgid (process-attributes (process-id proc)))))
    (let* ((args (alist-get 'args (process-attributes pid)))
           (program (and args (file-name-nondirectory
                               (car (split-string args))))))
      (cond ((member program '("ssh" "mosh" "mosh-client" "et")) 'remote)
            ((and (equal program "tmux") (executable-find "tmux"))
             (let ((dir (string-trim
                         (with-output-to-string
                           (call-process "tmux" nil standard-output nil
                                         "display-message" "-p" "-c"
                                         (process-tty-name proc)
                                         "#{pane_current_path}")))))
               (and (not (string-empty-p dir)) dir)))
            (t (jot--pid-directory pid))))))

(defun jot--entry-bounds ()
  "Return (START . END) of the notepad entry around point.
Entries are separated by blank lines."
  (save-excursion
    (let* ((start (progn (if (re-search-backward "\n[ \t]*\n" nil t)
                            (match-end 0)
                          (point-min))))
           (end (progn (goto-char start)
                      (if (re-search-forward "\n[ \t]*\n" nil t)
                          (match-beginning 0)
                        (point-max)))))
      (cons start end))))

(defun jot--strip-answers (text)
  "Return TEXT without the answers `jot-ask' wrote into it."
  (let ((indent (make-string (length jot-answer-prefix) ?\s)))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward (concat "^" (regexp-quote jot-answer-prefix)) nil t)
        (let ((start (line-beginning-position)))
          (forward-line 1)
          (while (and (not (eobp))
                      (looking-at (concat (regexp-quote indent) "\\S-")))
            (forward-line 1))
          (delete-region start (point))))
      (buffer-string))))

;;;; Display

(defun jot--popup-p ()
  "Return non-nil if the notepad should be shown as a pop-up here."
  (and (eq jot-display 'popup)
       ;; Batch Emacs 31 has the feature but no screen to show a frame on.
       (not noninteractive)
       (or (display-graphic-p) (featurep 'tty-child-frames))))

(defun jot--popup-geometry ()
  "Return (LEFT TOP WIDTH HEIGHT) for a pop-up next to point.
LEFT and TOP are in pixels relative to the frame, WIDTH and HEIGHT in
characters.  The pop-up goes just below the line at point, or just above
it when there is no room below, and always inside the selected window."
  (let* ((cw (frame-char-width))
         (ch (frame-char-height))
         (edges (window-inside-pixel-edges))
         (xy (or (posn-x-y (posn-at-point)) (cons 0 0)))
         (cols (/ (- (nth 2 edges) (nth 0 edges)) cw))
         (lines (/ (- (nth 3 edges) (nth 1 edges)) ch))
         (width (max 20 (min jot-popup-width (- cols 4))))
         (height (max 3 (min jot-popup-height (/ lines 2))))
         ;; Outer size, counting one cell of border on each side.
         (outer-w (* (+ width 2) cw))
         (outer-h (* (+ height 2) ch))
         (x (+ (nth 0 edges) (car xy)))
         (y (+ (nth 1 edges) (cdr xy)))
         (left (max (nth 0 edges) (min (- x (* 2 cw)) (- (nth 2 edges) outer-w))))
         (top (if (<= (+ y ch outer-h) (nth 3 edges))
                  (+ y ch)
                (max (nth 1 edges) (- y outer-h)))))
    (list left top width height)))

(defun jot--show-popup (buf)
  "Show BUF in a child frame next to point, select it, and return its window."
  (pcase-let ((`(,left ,top ,width ,height) (jot--popup-geometry))
              (parent (selected-frame)))
    (when (frame-live-p jot--popup-frame)
      (delete-frame jot--popup-frame))
    (let* ((frame (make-frame
                   `((parent-frame . ,parent)
                     (minibuffer . ,(minibuffer-window parent))
                     (name . "jot")
                     (left . ,left) (top . ,top)
                     (width . ,width) (height . ,height)
                     (child-frame-border-width . 1)
                     (undecorated . t)
                     (no-other-frame . t)
                     (unsplittable . t)
                     (desktop-dont-save . t)
                     (menu-bar-lines . 0) (tool-bar-lines . 0) (tab-bar-lines . 0)
                     (vertical-scroll-bars . nil) (horizontal-scroll-bars . nil)
                     (left-fringe . 0) (right-fringe . 0))))
           (win (frame-root-window frame)))
      (setq jot--popup-frame frame)
      (set-window-buffer win buf)
      (set-window-dedicated-p win t)
      (set-window-parameter win 'mode-line-format 'none)
      (set-window-margins win 1 1)
      ;; Its own colors, so it reads as a note on top of the text rather
      ;; than a hole in it.  Frame-local, so other frames are untouched.
      (let ((bg (face-background 'jot-popup nil t))
            (fg (face-foreground 'jot-popup nil t)))
        (dolist (face '(default fringe))
          (set-face-attribute face frame :background bg :foreground fg))
        (set-face-background 'child-frame-border fg frame))
      (select-frame-set-input-focus frame)
      (select-window win)
      win)))

(defun jot--show-side (buf)
  "Show BUF in a side window, select it, and return the window."
  (select-window
   (display-buffer buf `((display-buffer-in-side-window)
                         (side . ,jot-window-side)
                         ,(if (memq jot-window-side '(left right))
                              `(window-width . ,jot-window-size)
                            `(window-height . ,jot-window-size))))))

(defun jot--close-windows (buf)
  "Delete the pop-up frame and quit any window showing BUF."
  (when (frame-live-p jot--popup-frame)
    (let ((frame jot--popup-frame))
      (setq jot--popup-frame nil)
      (when (eq (selected-frame) frame)
        (select-frame-set-input-focus (frame-parent frame)))
      (delete-frame frame)))
  (when-let* ((win (get-buffer-window buf)))
    (quit-window nil win)))

;;;; Commands

;;;###autoload
(defun jot-toggle (&optional no-quote)
  "Pop up the notepad, quoting the line at point; hide it if already in it.
With the region active, quote the region instead.  With a prefix
argument NO-QUOTE, open the notepad without quoting anything.
Where it appears is set by `jot-display'."
  (interactive "P")
  (if (eq (window-buffer) (jot--buffer))
      (jot-hide)
    (jot--open no-quote)))

(defun jot--open (&optional no-quote suffix)
  "Pop the notepad up as `jot-toggle' does, then insert SUFFIX if given.
With NO-QUOTE, quote nothing.  Return the notepad's window."
  (let* ((buf (jot--buffer))
         (quoted (unless no-quote (jot--quote)))
         (popup (jot--popup-p))
         (win (progn
                (when (use-region-p) (deactivate-mark))
                (setq jot--return-window (selected-window)
                      jot--ask-mode nil
                      jot--ask-directory 'unknown)
                (if popup (jot--show-popup buf) (jot--show-side buf)))))
    ;; Normalise the tail so repeated toggles never pile up blank lines.
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (delete-region (point) (point-max))
    (let ((start (point)))
      ;; A quote or a question starts a new entry; a bare reopen does not.
      (unless (bobp) (insert (if (or quoted suffix) "\n\n" "\n")))
      ;; A pop-up opens on the newest note; earlier ones are a scroll or a
      ;; search away.
      (when popup
        (set-window-start win (line-beginning-position)))
      (when quoted (insert quoted "\n"))
      (when suffix (insert suffix))
      (setq jot--pending
            (and (or quoted suffix)
                 (cons start (buffer-substring start (point))))))
    win))

;;;###autoload
(defun jot-hide ()
  "Save and hide the notepad, returning to the window it was opened from."
  (interactive)
  (let ((buf (jot--buffer)))
    (with-current-buffer buf
      ;; Opened and closed without writing anything: drop that quote, so a
      ;; quick look does not leave a dangling one behind.
      (pcase jot--pending
        (`(,start . ,text)
         (when (and (<= start (point-max))
                    (equal (buffer-substring start (point-max)) text))
           (delete-region start (point-max)))))
      (setq jot--pending nil)
      ;; Nor an empty question line, such as the one an answer leaves ready.
      (save-excursion
        (goto-char (point-max))
        (skip-chars-backward " \t\n")
        (when (looking-back (concat "^" (regexp-quote (string-trim-right jot-question-prefix)))
                            (line-beginning-position))
          (delete-region (line-beginning-position) (point-max)))))
    (jot--save buf)
    (jot--close-windows buf)
    (when (window-live-p jot--return-window)
      (select-frame-set-input-focus (window-frame jot--return-window))
      (select-window jot--return-window))))

;;;###autoload
(defun jot-paste (&optional arg)
  "Paste the whole notepad at point, then clear it.
In a terminal handled by `jot-paste-functions', send it there instead.
The text is also put on the kill ring.  With a prefix argument ARG, do
the opposite of `jot-clear-after-paste' for this call."
  (interactive "P")
  (let* ((buf (jot--buffer))
         (text (string-trim
                (funcall (if jot-paste-answers #'identity #'jot--strip-answers)
                         (with-current-buffer buf
                           (buffer-substring-no-properties (point-min) (point-max))))))
         (clear (if arg (not jot-clear-after-paste) jot-clear-after-paste)))
    (when (string-empty-p text)
      (user-error "Jot is empty"))
    (when (eq (current-buffer) buf)
      (jot-hide))
    (kill-new text)
    (unless (run-hook-with-args-until-success 'jot-paste-functions text)
      (insert text))
    (when clear
      (with-current-buffer buf (erase-buffer))
      (jot--save buf))
    (message "Jot pasted%s" (if clear " and cleared" ""))))

;;;###autoload
(defun jot-clear ()
  "Empty the notepad.  Its contents go to the kill ring first."
  (interactive)
  (let ((buf (jot--buffer)))
    (with-current-buffer buf
      (unless (= (point-min) (point-max))
        (kill-new (buffer-substring-no-properties (point-min) (point-max)))
        (erase-buffer)))
    (jot--save buf)
    (message "Jot cleared")))

(provide 'jot)
;;; jot.el ends here
