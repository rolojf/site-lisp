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


(provide 'setup-agents)
;;; setup-agents.el ends here
