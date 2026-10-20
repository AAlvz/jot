;;; jot.el --- Pop-up notepad for taking notes while you read -*- lexical-binding: t -*-

;; Copyright (C) 2026 AAlvz

;; Author: AAlvz <alfonso@alvz.mx>
;; Maintainer: AAlvz <alfonso@alvz.mx>
;; URL: https://github.com/AAlvz/jot
;; Version: 0.1.0
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
;; `jot-toggle' opens the notepad in a side window, quoting the line at
;; point (or the region) so each note says what it is about.  Calling it
;; again hides the notepad and returns you to the window and position you
;; came from.  Notes accumulate across toggles until `jot-paste' inserts them
;; all at point and clears the notepad.
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
(defvar vterm-copy-mode)

(defgroup jot nil
  "Pop-up notepad for taking notes while reading."
  :group 'convenience
  :prefix "jot-")

(defcustom jot-file (locate-user-emacs-file "jot.md")
  "File that holds the notepad's contents."
  :type 'file)

(defcustom jot-window-side 'bottom
  "Side of the frame on which the notepad pops up."
  :type '(choice (const bottom) (const top) (const left) (const right)))

(defcustom jot-window-size 0.3
  "Size of the notepad window.
A float is a fraction of the frame, an integer a number of lines (or
columns, for the left and right sides)."
  :type 'number)

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

(defvar jot--pending nil
  "(START . TEXT) of the quote inserted on the last open, until written under.")

(defvar-keymap jot-mode-map
  :doc "Keymap for `jot-mode'."
  "C-c C-c" #'jot-hide
  "C-c C-k" #'jot-hide)

(define-minor-mode jot-mode
  "Minor mode for the jot notepad buffer.

\\{jot-mode-map}"
  :lighter " Jot")

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
Nil when a predicate in `jot-quote-predicates' vetoes it and no region
is active."
  (when (or (use-region-p)
            (not (memq 'no (mapcar #'funcall jot-quote-predicates))))
    (let* ((text (if (use-region-p)
                     (buffer-substring-no-properties (region-beginning) (region-end))
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

;;;; Commands

;;;###autoload
(defun jot-toggle (&optional no-quote)
  "Pop up the notepad, quoting the line at point; hide it if already in it.
With the region active, quote the region instead.  With a prefix
argument NO-QUOTE, open the notepad without quoting anything."
  (interactive "P")
  (let* ((buf (jot--buffer))
         (win (get-buffer-window buf)))
    (if (and win (eq win (selected-window)))
        (jot-hide)
      (let ((quoted (unless no-quote (jot--quote))))
        (when (use-region-p) (deactivate-mark))
        (setq jot--return-window (selected-window))
        (select-window
         (display-buffer buf `((display-buffer-in-side-window)
                               (side . ,jot-window-side)
                               ,(if (memq jot-window-side '(left right))
                                    `(window-width . ,jot-window-size)
                                  `(window-height . ,jot-window-size)))))
        ;; Normalise the tail so repeated toggles never pile up blank lines.
        (goto-char (point-max))
        (skip-chars-backward " \t\n")
        (delete-region (point) (point-max))
        (let ((start (point)))
          (unless (bobp) (insert (if quoted "\n\n" "\n")))
          (when quoted (insert quoted "\n"))
          (setq jot--pending
                (and quoted (cons start (buffer-substring start (point))))))))))

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
      (setq jot--pending nil))
    (jot--save buf)
    (when-let* ((win (get-buffer-window buf)))
      (quit-window nil win))
    (when (window-live-p jot--return-window)
      (select-window jot--return-window))))

;;;###autoload
(defun jot-paste (&optional arg)
  "Paste the whole notepad at point, then clear it.
In a terminal handled by `jot-paste-functions', send it there instead.
The text is also put on the kill ring.  With a prefix argument ARG, do
the opposite of `jot-clear-after-paste' for this call."
  (interactive "P")
  (let* ((buf (jot--buffer))
         (text (string-trim (with-current-buffer buf
                              (buffer-substring-no-properties (point-min) (point-max)))))
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
