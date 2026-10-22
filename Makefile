EMACS ?= emacs
BATCH = $(EMACS) -Q --batch -L .

.PHONY: all test test-vterm compile lint demo clean

all: compile lint test

test:
	$(BATCH) -L test -l test/jot-test.el -l test/jot-ask-test.el -f ert-run-tests-batch-and-exit

# Same suite, plus the vterm test, using the packages from your own ~/.emacs.d.
test-vterm:
	$(BATCH) -L test --eval '(package-initialize)' -l test/jot-test.el -l test/jot-ask-test.el -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile jot.el jot-ask.el

# package-lint comes from MELPA; it is fetched into a throwaway directory.
lint:
	$(BATCH) --eval '(progn (checkdoc-file "jot.el") (checkdoc-file "jot-ask.el"))'
	$(BATCH) --eval "(progn \
	  (setq package-user-dir (expand-file-name \".lint-elpa\")) \
	  (require 'package) \
	  (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t) \
	  (package-initialize) \
	  (unless (package-installed-p 'package-lint) \
	    (package-refresh-contents) (package-install 'package-lint)) \
	  (require 'package-lint) \
	  (setq package-lint-main-file \"jot.el\"))" \
	  -f package-lint-batch-and-exit jot.el jot-ask.el

# Re-record the README GIF.  See demo/demo.tape.
demo:
	vhs demo/demo.tape
	gifsicle -O3 --lossy=30 --colors 64 -b demo/jot.gif

clean:
	rm -rf *.elc test/*.elc .lint-elpa
