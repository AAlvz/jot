;;; jot-test.el --- Tests for jot -*- lexical-binding: t -*-

;;; Commentary:

;; Run with `make test'.  The vterm test needs vterm and its compiled
;; module, so it is skipped there and in CI; `make test-vterm' runs it
;; against the packages installed in your own Emacs.

;;; Code:

(require 'ert)
(require 'jot)

(defvar jot-test-skip-vterm (getenv "JOT_SKIP_VTERM")
  "Non-nil to skip the vterm test even where vterm is installed.")

(defmacro jot-test--with-env (&rest body)
  "Run BODY with a fresh notepad file and a reading buffer selected."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "jot-test" t))
          (jot-file (expand-file-name "jot.md" dir))
          (jot--pending nil)
          (jot--return-window nil)
          (reading (get-buffer-create "*jot-test-reading*")))
     (unwind-protect
         (progn
           (delete-other-windows)
           (switch-to-buffer reading)
           (erase-buffer)
           (insert "   │ first important line │  \nsecond line\nthird\n")
           (goto-char (point-min))
           ,@body)
       (when-let* ((b (get-file-buffer jot-file)))
         (with-current-buffer b (set-buffer-modified-p nil))
         (kill-buffer b))
       (kill-buffer reading)
       (delete-directory dir t))))

(defun jot-test--contents ()
  "Return the notepad file's contents on disk, minus trailing newlines.
Whether a final newline is written depends on `require-final-newline'."
  (with-temp-buffer
    (insert-file-contents jot-file)
    (string-trim-right (buffer-string) "\n+")))

(ert-deftest jot-test-toggle-quotes-and-returns ()
  (jot-test--with-env
    (let ((win (selected-window)))
      (jot-toggle)
      (should (eq (current-buffer) (get-file-buffer jot-file)))
      (should (window-parameter (selected-window) 'window-side))
      (insert "note one")
      (jot-toggle)
      (should (eq (selected-window) win))
      (should (eq (current-buffer) (get-buffer "*jot-test-reading*")))
      (should (= (line-number-at-pos) 1))
      (should (equal (jot-test--contents) "> first important line\nnote one")))))

(ert-deftest jot-test-notes-accumulate ()
  (jot-test--with-env
    (jot-toggle) (insert "note one") (jot-toggle)
    (forward-line 2)
    (jot-toggle) (insert "note two") (jot-toggle)
    (should (equal (jot-test--contents)
                   "> first important line\nnote one\n\n> third\nnote two"))))

(ert-deftest jot-test-peek-leaves-nothing ()
  (jot-test--with-env
    (jot-toggle) (insert "note one") (jot-toggle)
    (forward-line 1)
    (dotimes (_ 3) (jot-toggle) (jot-toggle))
    (should (equal (jot-test--contents) "> first important line\nnote one"))))

(ert-deftest jot-test-region-is-quoted ()
  (jot-test--with-env
    (transient-mark-mode 1)
    (set-mark (point))
    (forward-line 2)
    (activate-mark)
    (jot-toggle)
    (insert "both")
    (jot-toggle)
    (should-not (region-active-p))
    (should (equal (jot-test--contents)
                   "> first important line\n> second line\nboth"))))

(ert-deftest jot-test-rectangle-is-quoted ()
  "With `rectangle-mark-mode', only the rectangle's columns are quoted."
  (jot-test--with-env
    (erase-buffer)
    (insert "alpha  KEEP-1  tail one\nbeta   KEEP-2  tail two\n")
    (goto-char (point-min))
    (transient-mark-mode 1)
    (move-to-column 7)
    (rectangle-mark-mode 1)
    (forward-line 1)
    (move-to-column 13)
    (jot-toggle)
    (insert "cols only")
    (jot-toggle)
    (should-not (region-active-p))
    (should-not (bound-and-true-p rectangle-mark-mode))
    (should (equal (jot-test--contents)
                   "> KEEP-1\n> KEEP-2\ncols only"))))

(ert-deftest jot-test-prefix-skips-quote ()
  (jot-test--with-env
    (jot-toggle t) (insert "plain") (jot-toggle)
    (should (equal (jot-test--contents) "plain"))))

(ert-deftest jot-test-quote-predicate-vetoes ()
  (jot-test--with-env
    (let ((jot-quote-predicates (list (lambda () 'no))))
      (jot-toggle) (insert "unquoted") (jot-toggle)
      (should (equal (jot-test--contents) "unquoted")))))

(ert-deftest jot-test-paste-inserts-and-clears ()
  (jot-test--with-env
    (jot-toggle) (insert "note one") (jot-toggle)
    (goto-char (point-max))
    (jot-paste)
    (should (string-suffix-p "third\n> first important line\nnote one"
                             (buffer-string)))
    (should (equal (current-kill 0) "> first important line\nnote one"))
    (should (equal (jot-test--contents) ""))))

(ert-deftest jot-test-paste-prefix-keeps ()
  (jot-test--with-env
    (jot-toggle t) (insert "keep me") (jot-toggle)
    (goto-char (point-max))
    (jot-paste '(4))
    (should (equal (jot-test--contents) "keep me"))))

(ert-deftest jot-test-paste-from-inside-goes-back ()
  (jot-test--with-env
    (jot-toggle t) (insert "from inside")
    (jot-paste)
    (should (eq (current-buffer) (get-buffer "*jot-test-reading*")))
    (should (string-match-p "from inside" (buffer-string)))))

(ert-deftest jot-test-paste-functions-take-over ()
  (jot-test--with-env
    (let* ((got nil)
           (jot-paste-functions (list (lambda (text) (setq got text) t))))
      (jot-toggle t) (insert "routed") (jot-toggle)
      (let ((before (buffer-string)))
        (jot-paste)
        (should (equal got "routed"))
        (should (equal (buffer-string) before))))))

(ert-deftest jot-test-paste-empty-errors ()
  (jot-test--with-env
    (should-error (jot-paste) :type 'user-error)))

(ert-deftest jot-test-clear ()
  (jot-test--with-env
    (jot-toggle t) (insert "gone") (jot-toggle)
    (jot-clear)
    (should (equal (string-trim-right (current-kill 0)) "gone"))
    (should (equal (jot-test--contents) ""))))

(ert-deftest jot-test-popup-falls-back-to-side ()
  "Where a pop-up cannot be shown, as in batch mode, `popup' uses the side window."
  (jot-test--with-env
    (let ((jot-display 'popup))
      (jot-toggle)
      (should (window-parameter (selected-window) 'window-side))
      (should-not jot--popup-frame)
      (insert "fallback")
      (jot-toggle)
      (should (equal (jot-test--contents) "> first important line\nfallback")))))

(ert-deftest jot-test-disabled-modes ()
  "Modes listed in `jot-disabled-modes' are off in the notepad only."
  (jot-test--with-env
    (require 'display-line-numbers)
    (let ((text-mode-hook (list #'display-line-numbers-mode))
          (auto-mode-alist (cons '("\\.md\\'" . text-mode) auto-mode-alist)))
      (with-current-buffer (jot--buffer)
        (should (derived-mode-p 'text-mode))
        (should-not display-line-numbers-mode))
      (with-temp-buffer
        (text-mode)
        (should display-line-numbers-mode)))))

(ert-deftest jot-test-vterm ()
  "Quote from copy mode, then paste into the shell as one block."
  (skip-unless (and (not jot-test-skip-vterm)
                    (require 'vterm nil t)))
  (jot-test--with-env
    (let* ((out (expand-file-name "received.txt" (file-name-directory jot-file)))
           (vterm-shell "/bin/sh")
           (buf (vterm "*jot-test-vterm*")))
      (unwind-protect
          (with-current-buffer buf
            (vterm-send-string (format "echo hello-output; cat > %s\n" out))
            (dotimes (_ 20) (accept-process-output vterm--process 0.1))
            (vterm-copy-mode 1)
            (goto-char (point-min))
            (should (search-forward "hello-output" nil t 2))
            (jot-toggle) (insert "my note") (jot-toggle)
            (should vterm-copy-mode)
            (jot-paste)
            (should-not vterm-copy-mode)
            (vterm-send-string "\n")
            (vterm-send-key "d" nil nil t)
            (dotimes (_ 20) (accept-process-output vterm--process 0.1))
            (should (equal (with-temp-buffer (insert-file-contents out) (buffer-string))
                           "> hello-output\nmy note\n")))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buf))))))

(provide 'jot-test)
;;; jot-test.el ends here
