;;; jot-ask-test.el --- Tests for jot-ask -*- lexical-binding: t -*-

;;; Commentary:

;; These never call Claude: `jot-ask-command-function' is replaced by a
;; fake that prints a canned answer and records how it was called.

;;; Code:

(require 'ert)
(require 'jot-ask)
(require 'jot-test)

(defvar jot-ask-test--calls nil
  "Calls to the fake command, newest first: (PROMPT MODE SESSION RESUME DIR).")

(defun jot-ask-test--fake (prompt mode session resume)
  "Record a call and return a command that prints a two-line answer."
  (push (list prompt mode session resume default-directory) jot-ask-test--calls)
  (list "printf" "%s\n\n%s\n" (format "answer %d" (length jot-ask-test--calls))
        "second line"))

(defmacro jot-ask-test--with-env (&rest body)
  "Run BODY in `jot-test--with-env' with the fake command and a quick dir."
  (declare (indent 0))
  `(jot-test--with-env
     (let* ((jot-ask-command-function #'jot-ask-test--fake)
            (jot-ask-quick-directory (expand-file-name "quick/" dir))
            (jot-ask-default-mode 'quick)
            (jot-ask-test--calls nil))
       ,@body)))

(defun jot-ask-test--wait ()
  "Wait until no question is pending."
  (with-timeout (10 (error "Timed out waiting for an answer"))
    (while (seq-some #'overlay-buffer jot-ask--pending)
      (accept-process-output nil 0.05))))

(ert-deftest jot-ask-test-answer-lands-under-question ()
  (jot-ask-test--with-env
    (jot-ask)
    (insert "what is it?")
    (jot-ask-send)
    (jot-ask-test--wait)
    (jot-toggle)
    (should (equal (jot-test--contents)
                   (concat "> first important line\n? what is it?\n"
                           "= answer 1\n  second line")))
    (pcase-let ((`(,prompt ,mode ,_ ,resume ,dir) (car jot-ask-test--calls)))
      (should (string-match-p "first important line" prompt))
      (should (string-match-p "Question: what is it\\?" prompt))
      (should (eq mode 'quick))
      (should-not resume)
      (should (file-equal-p dir jot-ask-quick-directory)))))

(ert-deftest jot-ask-test-plain-note-becomes-question ()
  (jot-ask-test--with-env
    (jot-toggle)
    (insert "just a note")
    (jot-ask-send)
    (jot-ask-test--wait)
    (jot-toggle)
    (should (string-match-p "^\\? just a note\n= answer 1" (jot-test--contents)))))

(ert-deftest jot-ask-test-follow-up-resumes ()
  (jot-ask-test--with-env
    (jot-ask)
    (insert "first?")
    (jot-ask-send)
    (jot-ask-test--wait)
    ;; The answer leaves a fresh question line ready at point.
    (should (looking-back (regexp-quote jot-question-prefix) (line-beginning-position)))
    (insert "and then?")
    (jot-ask-send)
    (jot-ask-test--wait)
    (pcase-let ((`(,p2 ,_ ,s2 ,r2 ,_) (nth 0 jot-ask-test--calls))
                (`(,_ ,_ ,s1 ,r1 ,_) (nth 1 jot-ask-test--calls)))
      (should-not r1)
      (should r2)
      (should (equal s1 s2))
      ;; A follow-up sends only the new question.
      (should (equal p2 "and then?")))
    (jot-toggle)
    (should (string-suffix-p "? and then?\n= answer 2\n  second line"
                             (jot-test--contents)))))

(ert-deftest jot-ask-test-mode-switch-starts-new-conversation ()
  (jot-ask-test--with-env
    (let ((default-directory dir))
      (jot-ask)
      (insert "first?")
      (jot-ask-send)
      (jot-ask-test--wait)
      (jot-ask-toggle-mode)
      (insert "second?")
      (jot-ask-send)
      (jot-ask-test--wait)
      (pcase-let ((`(,_ ,m2 ,s2 ,r2 ,_) (nth 0 jot-ask-test--calls))
                  (`(,_ ,_ ,s1 ,_ ,_) (nth 1 jot-ask-test--calls)))
        (should (eq m2 'project))
        (should-not r2)
        (should-not (equal s1 s2))))))

(ert-deftest jot-ask-test-project-without-project-asks-quick ()
  (jot-ask-test--with-env
    (let ((jot-ask-default-mode 'project)
          (jot-source-directory-functions (list (lambda (_) 'remote))))
      (with-current-buffer "*jot-test-reading*"
        (setq-local default-directory "/ssh:nowhere:/tmp/"))
      (jot-ask)
      (insert "q?")
      (jot-ask-send)
      (jot-ask-test--wait)
      (should (eq (nth 1 (car jot-ask-test--calls)) 'quick)))))

(ert-deftest jot-ask-test-paste-without-answers ()
  (jot-ask-test--with-env
    (jot-ask)
    (insert "what is it?")
    (jot-ask-send)
    (jot-ask-test--wait)
    (jot-toggle)
    (goto-char (point-max))
    (let ((jot-paste-answers nil))
      (jot-paste))
    (should (string-suffix-p "> first important line\n? what is it?"
                             (buffer-string)))))

(ert-deftest jot-ask-test-ask-from-inside-stays-in-entry ()
  "Asking again inside the notepad adds to the entry, keeping its quote."
  (jot-ask-test--with-env
    (jot-ask)
    (jot-ask)                           ; twice in a row: still one `? ' line
    (should (eq (current-buffer) (get-file-buffer jot-file)))
    (insert "why?")
    (jot-ask-send)
    (jot-ask-test--wait)
    (should (string-match-p "first important line" (car (car jot-ask-test--calls))))
    (jot-toggle)
    (should (equal (jot-test--contents)
                   "> first important line\n? why?\n= answer 1\n  second line"))))

(ert-deftest jot-ask-test-empty-question-errors ()
  (jot-ask-test--with-env
    (jot-ask)
    (should-error (jot-ask-send) :type 'user-error)))

(ert-deftest jot-ask-test-close-drops-empty-question ()
  (jot-ask-test--with-env
    (jot-toggle) (insert "a note") (jot-toggle)
    (forward-line 1)
    (jot-ask) (jot-toggle)
    (should (equal (jot-test--contents) "> first important line\na note"))))

(ert-deftest jot-ask-test-header-shows-mode-and-keys ()
  (jot-ask-test--with-env
    (jot-toggle)
    (let ((line (jot--header-line)))
      (should (string-match-p "\\[quick\\]" line))
      (should (string-match-p "C-c C-a ask" line))
      (should (string-match-p "C-c C-p mode" line))
      (should (string-match-p "C-c C-c close" line)))
    (jot-toggle)))

(ert-deftest jot-ask-test-claude-command-shape ()
  "No MCP servers in either mode, and the prompt is marked off by `--'."
  (let ((jot-ask-program "claude") (jot-ask-model nil))
    (dolist (mode '(quick project))
      (let ((cmd (jot-ask-claude-command "--tools trick" mode "id-1" nil)))
        (should (member "--strict-mcp-config" cmd))
        (should (equal (last cmd 2) '("--" "--tools trick")))
        (should (equal (cadr (member "--tools" cmd))
                       (if (eq mode 'project) jot-ask-project-tools "")))
        (should (equal (cadr (member "--session-id" cmd)) "id-1"))
        (should-not (member "--resume" cmd))))
    (let ((cmd (jot-ask-claude-command "again" 'quick "id-1" t)))
      (should (equal (cadr (member "--resume" cmd)) "id-1"))
      (should-not (member "--session-id" cmd)))))

(ert-deftest jot-ask-test-countdown-never-reaches-zero ()
  (let ((jot-ask-expected-seconds 5))
    (should (equal (jot-ask--countdown 0) "5"))
    (should (equal (jot-ask--countdown 3.2) "2"))
    (should (equal (jot-ask--countdown 4.5) "0.1"))
    (should (equal (jot-ask--countdown 5.5) "0.01"))
    (should (equal (jot-ask--countdown 8.5) "0.00001"))
    (should (string-prefix-p "0.000" (jot-ask--countdown 1000)))
    (should (<= (length (jot-ask--countdown 1000)) 32))))

(ert-deftest jot-ask-test-no-double-send ()
  "A second send while the entry is waiting is refused, not sent."
  (jot-ask-test--with-env
    (let ((jot-ask-command-function
           (lambda (&rest args) (apply #'jot-ask-test--fake args)
             (list "sleep" "2"))))
      (jot-ask)
      (insert "slow?")
      (jot-ask-send)
      (should-error (jot-ask-send) :type 'user-error)
      (should (= (length jot-ask-test--calls) 1))
      (jot-ask-test--wait))))

(ert-deftest jot-ask-test-timeout-reports-error ()
  (jot-ask-test--with-env
    (let ((jot-ask-timeout 0.5)
          (jot-ask-command-function (lambda (&rest _) (list "sleep" "30"))))
      (jot-ask)
      (insert "never?")
      (jot-ask-send)
      (jot-ask-test--wait)
      (jot-toggle)
      (should (string-match-p "= \\[error\\] no answer after" (jot-test--contents))))))

(ert-deftest jot-ask-test-trailing-newline-no-blank-line ()
  (jot-ask-test--with-env
    (jot-ask)
    (insert "q? \n")
    (jot-ask-send)
    (jot-ask-test--wait)
    (jot-toggle)
    (should (string-match-p "^\\? q\\? *\n= answer 1" (jot-test--contents)))))

(ert-deftest jot-ask-test-asking-state ()
  (jot-ask-test--with-env
    (jot-toggle)
    (should-not jot--asking)
    (should (eq (jot--popup-face) 'jot-popup))
    (jot-toggle)
    (jot-ask)
    (should jot--asking)
    (should (eq (jot--popup-face) 'jot-popup-ask))
    (jot-ask-toggle-mode)
    (should (eq (jot--popup-face) 'jot-popup-ask-project))
    (jot-toggle)
    (jot-toggle)
    (should-not jot--asking)))

(provide 'jot-ask-test)
;;; jot-ask-test.el ends here
