;;; setup-chords.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary: usar key-chord
;;; Code:

(require-package 'key-chord)

(with-eval-after-load 'key-chord
  (key-chord-define-global "xk" 'kill-buffer)
  (key-chord-define-global "xf" 'find-file)
  (key-chord-define-global "xc" 'save-buffers-kill-terminal)
  (key-chord-define-global "xr" 'consult-ripgrep)
  (key-chord-define-global "xs" 'save-buffer)
  (key-chord-define-global "xg" 'magit-status)
  (key-chord-define-global "xo" 'other-window)
  (key-chord-define-global "x1" 'delete-other-windows)
  (key-chord-define-global "x2" 'split-window-below)
  (key-chord-define-global "x3" 'split-window-right)
  (key-chord-define-global "x0" 'delete-window)
  (key-chord-define-global "xb" 'consult-buffer)
  (key-chord-define-global "zp" 'prettier-prettify)
  (setq key-chord-two-keys-delay 0.10)
  (setq key-chord-one-key-delay 0.0)
  (setq key-chord-typing-detection t)
  )

(key-chord-mode 1)

(provide 'setup-chords)
;;; setup-chords.el ends here
