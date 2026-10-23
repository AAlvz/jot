;;; demo-init.el --- Throwaway Emacs for recording the README GIF -*- lexical-binding: t -*-

;;; Commentary:

;; Loaded by demo.tape through `emacs -Q -nw -l demo/demo-init.el'.  It uses
;; the vterm installed in ~/.emacs.d but nothing else from the user's setup,
;; and a fresh notepad file, so every recording starts from the same state.

;;; Code:

(defconst jot-demo-dir (file-name-directory (or load-file-name buffer-file-name)))

(setq package-user-dir (expand-file-name "~/.emacs.d/elpa"))
(package-initialize)
(add-to-list 'load-path (expand-file-name ".." jot-demo-dir))
(require 'jot)
(require 'jot-ask)
(require 'vterm)

(setq inhibit-startup-screen t
      jot-file (expand-file-name "jot.md" (make-temp-file "jot-demo" t))
      ring-bell-function #'ignore)
(menu-bar-mode -1)
(load-theme 'modus-vivendi t)

(global-set-key (kbd "C-c j") #'jot-toggle)
(global-set-key (kbd "C-c J") #'jot-paste)
(global-set-key (kbd "C-c a") #'jot-ask)

;; Real questions to Claude, but from a throwaway folder and without the
;; recording user's own ~/.claude configuration, so the answer in a public
;; GIF depends on nothing but the question.
(setq jot-ask-quick-directory (make-temp-file "jot-demo-ask" t)
      jot-ask-command-function
      (lambda (prompt mode)
        (let ((cmd (jot-ask-claude-command prompt mode)))
          (append (butlast cmd 2) '("--setting-sources" "project,local")
                  (last cmd 2)))))

;; A one-line keycast in the tab bar, so the GIF shows which key did what.
(defvar jot-demo--keys "")

(defun jot-demo--record ()
  "Remember the keys behind the jot and copy-mode commands just run."
  (when (memq this-command '(jot-toggle jot-hide jot-paste jot-ask jot-ask-send
                                        vterm-copy-mode))
    (setq jot-demo--keys (format "  %s   %s  "
                                 (key-description (this-command-keys-vector))
                                 this-command))
    (force-mode-line-update t)))
(add-hook 'post-command-hook #'jot-demo--record)

(defun jot-demo--tab-bar ()
  "Tab bar contents: the title, then the last key pressed and its command."
  `((title menu-item ,(concat (propertize " jot " 'face '(:weight bold :inverse-video t))
                              "  "
                              (propertize jot-demo--keys 'face 'success))
           ignore)))
(setq tab-bar-format (list #'jot-demo--tab-bar))
(tab-bar-mode 1)

(setenv "ZDOTDIR" (expand-file-name "zdot" jot-demo-dir))
(setenv "JOT_DEMO_DIR" jot-demo-dir)
(let ((vterm-shell "/bin/zsh"))
  (vterm "*assistant*"))
(delete-other-windows)

;;; demo-init.el ends here
