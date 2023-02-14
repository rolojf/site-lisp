(use-package pass
  :straight t)
(require 'epa-file)
;; This line is extremely important, since Emacs 25, gpg would not
;; prompt in the minibuffer for your passphase without this.
(setq epa-pinentry-mode 'loopback)

(provide 'setup-pass)
