;;; run-diario-tests.el --- Guarded diario fixture runner -*- lexical-binding: t; -*-

;;; Commentary:
;; Load through emacsclient -s diario-tests, then call `my-diario-tests'.
;; Run only in that disposable, clean daemon, never the user's working Emacs.
;; This does not load setup-journaling or migrate live files.  Unexpected
;; prompts fail a fixture instead of waiting for input.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'org)

(defconst my-dt--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Personal configuration directory containing the diario modules.")

(defconst my-dt--selector "^\\(?:my-diario-\\|my-dpt-\\)"
  "ERT names owned by the three-list diario workflow.")

(defun my-dt--unexpected (&rest arguments)
  "Fail a fixture that attempts unhandled interactive input with ARGUMENTS."
  (error "Unexpected interactive prompt in diario fixture: %S"
         (car arguments)))

(defun my-diario-tests (&optional selector modules)
  "Run isolated diario fixtures matching SELECTOR, or the workflow suite.
MODULES optionally names only the module/test pairs to load.  Return counts
and failed-test conditions.  Require the disposable diario-tests daemon;
fixtures use temporary files and unexpected prompts fail synchronously.
Run no other Emacs test session concurrently."
  (unless (and (boundp 'server-name) (equal server-name "diario-tests"))
    (user-error "Run fixture tests only in the disposable diario-tests daemon"))
  (let ((load-path (cons my-dt--root load-path))
        (org-mode-hook nil)
        (find-file-hook nil)
        (kill-buffer-hook nil)
        (kill-buffer-query-functions nil)
        (before-save-hook nil)
        (after-save-hook nil)
        (org-trigger-hook nil)
        (org-after-todo-state-change-hook nil)
        (org-after-promote-entry-hook nil)
        (org-after-demote-entry-hook nil)
        (org-log-done nil)
        (org-log-reschedule nil)
        (create-lockfiles nil)
        (ert-quiet t)
        (selector (or selector my-dt--selector)))
    (dolist (name (or modules
                      '("diario-match" "diario-rollover" "diario-focus" "diario-migrate"
                        "diario-import" "diario-priads" "diario-commands"
                        "diario-priad-commands")))
      (load (expand-file-name (concat name ".el") my-dt--root) nil t)
      (load (expand-file-name (concat "tests/test-" name ".el") my-dt--root)
            nil t))

    ;; Cross-command scenarios reuse the bounded fixtures from the full suite.
    (unless modules
      (load (expand-file-name "tests/test-diario-integration.el" my-dt--root)
            nil t))

    (cl-letf (((symbol-function 'ask-user-about-supersession-threat)
               #'my-dt--unexpected)
              ((symbol-function 'ask-user-about-lock) #'my-dt--unexpected)
              ((symbol-function 'yes-or-no-p) #'my-dt--unexpected)
              ((symbol-function 'y-or-n-p) #'my-dt--unexpected)
              ((symbol-function 'read-from-minibuffer) #'my-dt--unexpected)
              ((symbol-function 'read-key) #'my-dt--unexpected)
              ((symbol-function 'read-event) #'my-dt--unexpected))
      (let ((stats (ert-run-tests-batch selector))
            failures)
        (dolist (test (ert-select-tests selector t))
          (let ((result (ert-test-most-recent-result test)))
            (when (ert-test-failed-p result)
              (push (list (ert-test-name test)
                          (ert-test-result-with-condition-condition result))
                    failures))))
        (list :completed (ert-stats-completed stats)
              :unexpected (ert-stats-completed-unexpected stats)
              :failures (nreverse failures))))))

(provide 'run-diario-tests)
;;; run-diario-tests.el ends here
