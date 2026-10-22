;;; jot-ask.el --- Ask quick questions from the jot notepad -*- lexical-binding: t -*-

;; Copyright (C) 2026 AAlvz

;; Author: AAlvz <alfonso@alvz.mx>
;; Maintainer: AAlvz <alfonso@alvz.mx>
;; Assisted-by: Claude Code:claude-opus-5-5
;; URL: https://github.com/AAlvz/jot

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

;; A note in the jot notepad can be sent as a question.  The answer comes
;; back into the notepad, right under the question, and a follow-up written
;; under the answer continues the same conversation.
;;
;; `jot-ask' pops the notepad up with the line or region quoted and a
;; question line ready.  `jot-ask-send' (\\<jot-mode-map>\\[jot-ask-send] in the notepad) sends the note
;; being written.  Nothing waits on the answer: close the notepad and keep
;; reading, and the answer is written in when it arrives.
;;
;; Questions go out in one of two modes.  `quick' asks from a clean folder,
;; `jot-ask-quick-directory', with no tools, for generic questions.
;; `project' asks from the project of the buffer being read, so its
;; CLAUDE.md is loaded and its files can be read, but never changed.
;; `jot-ask-default-mode' picks the default and `jot-ask-toggle-mode'
;; switches it for one question.
;;
;; By default questions go to Claude Code in print mode (`claude -p').
;; `jot-ask-command-function' builds the command, so other command-line
;; tools can be used instead.
;;
;; Only the quote and what was typed in the entry are sent: never the
;; screen, the rest of the notepad or the surrounding output.

;;; Code:

(require 'jot)

(defgroup jot-ask nil
  "Ask quick questions from the jot notepad."
  :group 'jot
  :prefix "jot-ask-")

(defcustom jot-ask-program "claude"
  "The Claude Code executable used by `jot-ask-claude-command'."
  :type 'string)

(defcustom jot-ask-model nil
  "Model for questions, as given to `claude --model', or nil.
Nil uses whatever model Claude Code is set up to use."
  :type '(choice (const :tag "Claude Code's default" nil) string))

(defcustom jot-ask-instructions
  "You are answering inside a small pop-up notepad in Emacs, about 60 \
columns wide. Answer in a few sentences of plain text. No headings, no \
tables, no Markdown formatting, no preamble. If the question is \
ambiguous, answer the most likely reading."
  "Instructions sent with every question, in both modes."
  :type 'string)

(defcustom jot-ask-quick-directory (locate-user-emacs-file "jot-ask/")
  "Folder that `quick' questions are asked from.
It starts empty.  A CLAUDE.md placed in it applies to quick questions
only."
  :type 'directory)

(defcustom jot-ask-project-tools "Read,Grep,Glob"
  "Tools a `project' question may use, as given to `claude --tools'.
The default can read the project but never change it.  Quick questions
get no tools, and neither mode can reach MCP servers."
  :type 'string)

(defcustom jot-ask-command-function #'jot-ask-claude-command
  "Function returning the command that answers a question.
It is called with PROMPT, MODE (`quick' or `project'), SESSION (a UUID
string) and RESUME (non-nil for a follow-up in that session), and
returns the program and its arguments as a list.  The command runs in
the mode's folder and its standard output is the answer."
  :type 'function)

(defcustom jot-ask-expected-seconds 5
  "Roughly how long an answer takes, for the countdown while waiting.
The countdown runs from this down towards zero.  When an answer takes
longer it never gets there: it shows 0.1, then 0.01, 0.001 and so on."
  :type 'natnum)

(defcustom jot-ask-timeout 180
  "Seconds to wait for an answer before giving up on it."
  :type 'natnum)

(defface jot-ask-pending '((t :inherit shadow :slant italic))
  "Face for the placeholder shown while a question is being answered.")

;;;; The command

(defun jot-ask-claude-command (prompt mode session resume)
  "Return a `claude -p' command for PROMPT.
MODE, SESSION and RESUME are as described in `jot-ask-command-function'."
  `(,jot-ask-program
    "-p"
    ,@(when jot-ask-model (list "--model" jot-ask-model))
    "--tools" ,(if (eq mode 'project) jot-ask-project-tools "")
    ;; `--tools' alone leaves every MCP server callable, mail and calendar
    ;; connectors included.  A quick question should reach none of them.
    "--strict-mcp-config"
    "--append-system-prompt" ,jot-ask-instructions
    ,@(if resume (list "--resume" session) (list "--session-id" session))
    ;; `--tools' takes several values, so mark where the prompt starts.
    "--" ,prompt))

(defun jot-ask--uuid ()
  "Return a random version 4 UUID."
  (let ((bytes (mapcar (lambda (_) (random 256)) (make-list 16 0))))
    (setf (nth 6 bytes) (logior #x40 (logand (nth 6 bytes) #x0f))
          (nth 8 bytes) (logior #x80 (logand (nth 8 bytes) #x3f)))
    (apply #'format "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x"
           bytes)))

;;;; Reading the entry

(defun jot-ask--prefixed-p (prefix)
  "Return non-nil if the line at point starts with PREFIX."
  (looking-at-p (regexp-quote prefix)))

(defun jot-ask--answer-line-p ()
  "Return non-nil if the line at point is part of an answer."
  (or (jot-ask--prefixed-p jot-answer-prefix)
      (and (looking-at-p (concat (regexp-quote
                                  (make-string (length jot-answer-prefix) ?\s))
                                 "\\S-"))
           (save-excursion
             (forward-line -1)
             (while (and (not (bobp))
                         (not (jot-ask--prefixed-p jot-answer-prefix))
                         (looking-at-p "[ \t]"))
               (forward-line -1))
             (jot-ask--prefixed-p jot-answer-prefix)))))

(defun jot-ask--entry ()
  "Describe the entry around point for sending.
Return a plist: :quote, the quoted lines without their prefix; :start and
:end of the question still to be sent; :session, the conversation an
earlier question in this entry belongs to, if any."
  (pcase-let ((`(,start . ,end) (jot--entry-bounds))
              (quote-lines nil)
              (q-start nil)
              (session nil))
    (save-excursion
      (goto-char start)
      (while (< (point) end)
        (cond ((jot-ask--prefixed-p jot-quote-prefix)
               (push (buffer-substring-no-properties
                      (+ (point) (length jot-quote-prefix)) (line-end-position))
                     quote-lines)
               (setq q-start nil))
              ((jot-ask--answer-line-p)
               (setq q-start nil))
              (t
               (when-let* ((s (get-text-property (point) 'jot-ask-session)))
                 (setq session s))
               (unless q-start (setq q-start (point)))))
        (forward-line 1)))
    (list :quote (nreverse quote-lines)
          :start q-start
          :end end
          :session session)))

(defun jot-ask--prompt (quote question)
  "Return the text sent for QUESTION about QUOTE, a list of lines."
  (if quote
      (concat "About this text:\n\n" (string-join quote "\n")
              "\n\nQuestion: " question)
    question))

;;;; Waiting and answering

(defvar jot-ask--spinner-frames ["⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"])

(defvar jot-ask--pending nil
  "Overlays of the questions being answered.")

(defvar jot-ask--timer nil
  "Timer that animates the placeholders in `jot-ask--pending'.")

(defun jot-ask--countdown (elapsed)
  "Return the countdown to show ELAPSED seconds after asking.
It counts down from `jot-ask-expected-seconds' and never reaches zero:
past the expected time, each second adds a decimal place instead."
  (let ((left (- jot-ask-expected-seconds elapsed)))
    (if (>= left 1)
        (number-to-string (ceiling left))
      ;; One decimal place for the first second past 1, then one more for
      ;; each second after that.
      (let ((places (min 30 (1+ (floor (- 1 left))))))
        (concat "0." (make-string (1- places) ?0) "1")))))

(defun jot-ask--placeholder (start-time frame)
  "Return the placeholder for a question asked at START-TIME, at FRAME."
  (propertize (format "\n%s%s sent · answer in %s" jot-answer-prefix
                      (aref jot-ask--spinner-frames
                            (mod frame (length jot-ask--spinner-frames)))
                      (jot-ask--countdown (float-time (time-since start-time))))
              'face 'jot-ask-pending))

(defun jot-ask--tick ()
  "Advance every placeholder, and stop when none is left."
  (setq jot-ask--pending (seq-filter #'overlay-buffer jot-ask--pending))
  (if (null jot-ask--pending)
      (progn (cancel-timer jot-ask--timer)
             (setq jot-ask--timer nil))
    (dolist (ov jot-ask--pending)
      (let ((frame (1+ (overlay-get ov 'jot-ask-frame)))
            (proc (overlay-get ov 'jot-ask-process)))
        (overlay-put ov 'jot-ask-frame frame)
        (overlay-put ov 'after-string
                     (jot-ask--placeholder (overlay-get ov 'jot-ask-time) frame))
        (when (and (process-live-p proc)
                   (> (float-time (time-since (overlay-get ov 'jot-ask-time)))
                      jot-ask-timeout))
          (overlay-put ov 'jot-ask-timed-out t)
          (delete-process proc))))))

(defun jot-ask--format-answer (text)
  "Return TEXT as notepad lines: the answer prefix, then indented lines.
Blank lines are dropped, since they would split the entry."
  (let ((indent (make-string (length jot-answer-prefix) ?\s))
        (lines (seq-remove (lambda (l) (string-blank-p l))
                           (split-string (string-trim text) "\n"))))
    (concat jot-answer-prefix
            (mapconcat #'string-trim-right lines (concat "\n" indent)))))

(defun jot-ask--insert-answer (marker text)
  "Write TEXT in as the answer at MARKER, readying a follow-up if in view."
  (let ((buf (marker-buffer marker)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let* ((wins (get-buffer-window-list buf nil t))
               (waiting (seq-filter (lambda (w) (= (window-point w) marker)) wins))
               (at-point (= (point) marker)))
          (save-excursion
            (goto-char marker)
            (insert "\n" (jot-ask--format-answer text))
            ;; Whoever was waiting right at the question goes past the
            ;; answer, onto a fresh line for a follow-up.
            (when (or waiting at-point)
              (insert "\n" jot-question-prefix)
              (let ((ready (point)))
                (dolist (w waiting) (set-window-point w ready))
                (when at-point (setq at-point ready)))))
          (when (integerp at-point) (goto-char at-point)))
        (jot--save buf)))
    (set-marker marker nil)))

(defun jot-ask--finish (proc marker overlay out err)
  "Handle the end of question PROC: write its answer in at MARKER.
OVERLAY is its placeholder; OUT and ERR hold its output and errors."
  (let ((answer (with-current-buffer out (string-trim (buffer-string))))
        (problem (with-current-buffer err (string-trim (buffer-string))))
        (timed-out (overlay-get overlay 'jot-ask-timed-out)))
    (delete-overlay overlay)
    (jot-ask--insert-answer
     marker
     (cond (timed-out
            (format "[error] no answer after %d seconds; see `jot-ask-timeout'"
                    jot-ask-timeout))
           ((and (zerop (process-exit-status proc)) (not (string-empty-p answer)))
            answer)
           ((not (string-empty-p problem))
            (format "[error] %s" (car (split-string problem "\n"))))
           ((not (string-empty-p answer))
            (format "[error] %s" (car (split-string answer "\n"))))
           (t (format "[error] %s exited with status %d"
                      (process-name proc) (process-exit-status proc)))))
    (message "Jot: answer ready"))
  (kill-buffer out)
  (kill-buffer err))

(defun jot-ask--start (prompt mode session resume directory marker)
  "Ask PROMPT in MODE from DIRECTORY, and answer at MARKER.
SESSION and RESUME are as described in `jot-ask-command-function'."
  (let* ((default-directory directory)
         (command (funcall jot-ask-command-function prompt mode session resume))
         (out (generate-new-buffer " *jot-ask*"))
         (err (generate-new-buffer " *jot-ask-errors*"))
         (overlay (make-overlay marker marker nil t nil)))
    (unless (executable-find (car command))
      (kill-buffer out) (kill-buffer err) (delete-overlay overlay)
      (user-error "Jot: cannot find `%s'; see `jot-ask-program'" (car command)))
    (overlay-put overlay 'jot-ask-time (current-time))
    (overlay-put overlay 'jot-ask-frame 0)
    (overlay-put overlay 'after-string (jot-ask--placeholder (current-time) 0))
    (push overlay jot-ask--pending)
    (unless jot-ask--timer
      (setq jot-ask--timer (run-at-time 0.1 0.1 #'jot-ask--tick)))
    (let ((proc (make-process
                 :name "jot-ask"
                 :buffer out
                 :stderr err
                 :command command
                 :connection-type 'pipe
                 :noquery t
                 :sentinel (lambda (proc _event)
                             (unless (process-live-p proc)
                               (jot-ask--finish proc marker overlay out err))))))
      (overlay-put overlay 'jot-ask-process proc)
      ;; Print mode would otherwise wait for more input on stdin.
      (process-send-eof proc)
      (when-let* ((errproc (get-buffer-process err)))
        (set-process-query-on-exit-flag errproc nil)))))

;;;; Commands

(defun jot-ask--directory-for (mode)
  "Return the folder a MODE question runs in, and the mode it ends up in.
A project question with no project to ask from goes out quick."
  (let ((project (and (eq mode 'project) (jot--ask-directory))))
    (if project
        (cons project 'project)
      (when (eq mode 'project)
        (message "Jot: no project found for this buffer, asking quick"))
      (make-directory jot-ask-quick-directory t)
      (cons (file-name-as-directory (expand-file-name jot-ask-quick-directory))
            'quick))))

;;;###autoload
(defun jot-ask-send ()
  "Send the question being written in the notepad entry at point.
The question is what was typed after the quote, or after the last
answer.  A follow-up in an entry that was already answered continues
that conversation, if it was asked in the same mode."
  (interactive)
  (unless (eq (current-buffer) (jot--buffer))
    (user-error "Not in the jot notepad"))
  (pcase-let ((`(,entry-start . ,entry-end) (jot--entry-bounds)))
    ;; Two questions at once in one conversation can leave Claude Code
    ;; stuck, and the second would not see the first answer anyway.
    (when (seq-some (lambda (ov)
                      (and (overlay-buffer ov)
                           (<= entry-start (overlay-start ov) entry-end)))
                    jot-ask--pending)
      (user-error "Still waiting for the answer to this entry's last question")))
  (let* ((entry (jot-ask--entry))
         (quote (plist-get entry :quote))
         (start (plist-get entry :start))
         (end (plist-get entry :end))
         (session (plist-get entry :session))
         (question (and start (string-trim
                               (buffer-substring-no-properties start end)))))
    (when (or (null question)
              (string-empty-p (string-remove-prefix
                               (string-trim jot-question-prefix) question)))
      (user-error "Type a question first"))
    ;; A plain note becomes a question by being sent.
    (save-excursion
      (goto-char start)
      (unless (jot-ask--prefixed-p jot-question-prefix)
        (insert jot-question-prefix)
        (setq end (+ end (length jot-question-prefix)))))
    (setq question (string-trim (string-remove-prefix
                                 (string-trim jot-question-prefix) question)))
    (pcase-let* ((`(,dir . ,mode) (jot-ask--directory-for (jot--ask-mode)))
                 (resume (and session
                              (equal (plist-get session :dir) dir)
                              (eq (plist-get session :mode) mode)))
                 (id (if resume (plist-get session :id) (jot-ask--uuid)))
                 (prompt (if resume question (jot-ask--prompt quote question)))
                 ;; Right after the question text, so trailing blank lines
                 ;; cannot end up between the question and its answer.
                 (marker (copy-marker (save-excursion
                                        (goto-char end)
                                        (skip-chars-backward " \t\n" start)
                                        (point)))))
      (put-text-property start end 'jot-ask-session
                         (list :id id :dir dir :mode mode))
      (setq jot--pending nil)
      (jot-ask--start prompt mode id resume dir marker)
      (jot--set-asking t)
      (message "Jot: asking %s…" (if (eq mode 'project)
                                     (format "from %s" (abbreviate-file-name dir))
                                   "quick")))))

;;;###autoload
(defun jot-ask (&optional other-mode)
  "Pop the notepad up with the line or region quoted, ready for a question.
Type the question and send it with \\<jot-mode-map>\\[jot-ask-send].  In the notepad, add
a question to the entry at point instead.  With a prefix
argument OTHER-MODE, ask in the mode other than `jot-ask-default-mode'."
  (interactive "P")
  (if (eq (window-buffer) (jot--buffer))
      ;; Already in the notepad: ask more in the entry at point, which keeps
      ;; its quote as the question's context.
      (progn
        (goto-char (cdr (jot--entry-bounds)))
        (unless (looking-back (concat "^" (regexp-quote jot-question-prefix))
                              (line-beginning-position))
          (insert (if (bolp) "" "\n") jot-question-prefix)))
    (jot--open nil jot-question-prefix))
  (jot--set-asking t)
  (when other-mode (jot-ask-toggle-mode)))

(provide 'jot-ask)
;;; jot-ask.el ends here
