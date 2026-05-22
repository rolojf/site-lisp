;;; setup-spelling.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(setenv "LANG" "es_MX, en_US")
;; Activate Hunspell
;;
(when (executable-find "hunspell")
  (setq-default ispell-program-name "/usr/bin/hunspell")
  (setq ispell-really-hunspell t))
;;
(setq ispell-local-dictionary-alist
        '(
            ("es_MX"
             "[[:alpha:]]" "[^[:alpha:]]" "[']"
             nil ("-d" "es_MX")
             nil utf-8)
;;
            ("en_US"
             "[[:alpha:]]" "[^[:alpha:]]" "[']"
             nil ("-d" "en_US")
             nil utf-8)
          )
)
(setq ispell-dictionary "es_MX")
(setq ispell-local-dictionary "es_MX")
(setq ispell-alternate-dictionary "/usr/share/hunspell/en_US.aff")
;;
;; Activate flyspell
;;
(add-hook 'text-mode-hook 'flyspell-mode)
(add-hook 'message-mode-hook 'flyspell-mode)
(setq flyspell-issue-message-flag nil)
;;(mapcar (lambda (mode-hook) (add-hook mode-hook 'flyspell-prog-mode))
;;    '(c-mode-common-hook R-mode-hook emacs-lisp-mode-hook))
(add-hook 'org-mode-hook 'turn-on-flyspell)

;; Debounce flyspell so it runs on idle rather than on every keystroke.
(when (maybe-require-package 'flyspell-lazy)
  (with-eval-after-load 'flyspell
    (flyspell-lazy-mode 1)))
;;
(defun fd-switch-dictionary()
      (interactive)
      (let* ((dic ispell-current-dictionary)
      (change (if (string= dic "en_US") "es_MX" "en_US")))
        (ispell-change-dictionary change)
        (message "Dictionary switched from %s to %s" dic change)))
(global-set-key (kbd "<f8>")   'fd-switch-dictionary)

;; Auto-detect language per paragraph and switch the ispell dictionary.
(when (maybe-require-package 'guess-language)
  (with-eval-after-load 'guess-language
    (setq guess-language-languages '(en es))
    (setq guess-language-min-paragraph-length 35)
    (setq guess-language-langcodes
          '((en . ("en_US" "English" "en" "English"))
            (es . ("es_MX" nil       "es" "Spanish")))))
  (add-hook 'text-mode-hook #'guess-language-mode)
  (add-hook 'org-mode-hook  #'guess-language-mode))

(provide 'setup-spelling)

;;; setup-spelling.el ends here
