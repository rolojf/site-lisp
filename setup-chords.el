(require 'key-chord)
(use-package use-package-chords
             :straight t
             :config (key-chord-mode 1)
             )

(key-chord-mode 1)
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
(key-chord-define-global "xb" 'consult-buffer) ;;ivy-switch-buffer

(setq key-chord-two-keys-delay 0.10)
(setq key-chord-one-key-delay 0.0)

(provide 'setup-chords)
