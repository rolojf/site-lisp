;;; setup-agents.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

;; (require-package 'acp)
;; (require-package 'shell-maker)
;; (require-package 'agent-shell)
;; (with-eval-after-load 'agent-shell
;;  (setq agent-shell-anthropic-authentication (agent-shell-anthropic-make-authentication :login t)
;;         agent-shell-file-completion-enabled t
;;        agent-shell-prefer-viewport-interaction t
;;         ))

;; (global-set-key (kbd "C-c s") #'agent-shell)
;; (global-unset-key (kbd "M-Z"))
;; claude plugins marketplaces update xenodium-emacs-skills
;; para actualizar skills

(require-package 'pi-coding-agent)

(defalias 'pi 'pi-coding-agent)

;; (with-eval-after-load 'tramp
;;   (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

(with-eval-after-load 'tramp
  (setq tramp-remote-path
        '("/.sprite/languages/node/nvm/versions/node/v24.18.0/bin"
          "/.sprite/languages/go/current/bin"
          "/.sprite/languages/ruby/rbenv/bin"
          "/.sprite/languages/ruby/rbenv/shims"
          "/.sprite/languages/rust/cargo/bin"
          "/.sprite/languages/bun/bin"
          "/.sprite/languages/deno/bin"
          "/.sprite/languages/python/pyenv/bin"
          "/.sprite/languages/python/pyenv/shims"
          "/home/sprite/.local/bin"
          tramp-default-remote-path
          "/.sprite/bin")))

(defconst my-sprite-tercero-path
  "/ssh:sprite@localhost#4000:/home/sprite/"
  "Ruta TRAMP al Sprite tercero.")

(defun my-tercero ()
  "Abrir el directorio principal del Sprite tercero."
  (interactive)
  (find-file my-sprite-tercero-path))

(with-eval-after-load 'pi-coding-agent-ui
  (setq pi-coding-agent-executable
        '("/.sprite/languages/node/nvm/versions/node/v24.18.0/bin/node"
          "/.sprite/languages/node/nvm/versions/node/v24.18.0/bin/pi")))

;; (global-set-key (kbd "C-c s 3") #'my-open-sprite-tercero)

(provide 'setup-agents)
;;; setup-agents.el ends here
