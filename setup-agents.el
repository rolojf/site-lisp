;;; setup-agents.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require-package 'acp)
(require-package 'shell-maker)
(require-package 'agent-shell)
(with-eval-after-load 'agent-shell
  (setq agent-shell-anthropic-authentication (agent-shell-anthropic-make-authentication :login t)
        agent-shell-file-completion-enabled t
        agent-shell-prefer-viewport-interaction t
        ))

;; claude plugins marketplaces update xenodium-emacs-skills
;; para actualizar skills

(provide 'setup-agents)
;;; setup-agents.el ends here
