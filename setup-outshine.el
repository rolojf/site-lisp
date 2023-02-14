(use-package outshine
  :straight t
  :init (defvar outline-minor-mode-prefix "\M-#")
  :hook elm-mode
  :config   (setq outline-regexp "^\s*--\s[*]+")
  (setq outshine-use-speed-commands t)
  )
(provide 'setup-outshine)
