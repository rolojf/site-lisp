(use-package copilot
  :straight (:host github :repo "zerolfx/copilot.el" :files ("dist" "*.el"))
  :ensure t
  :hook (prog-mode . copilot-mode)
  )

;; de la página: https://robert.kra.hn/posts/2023-02-22-copilot-emacs-setup/
(defvar rk/copilot-manual-mode nil
  "When `t' will only show completions when manually triggered, e.g. via M-f1.")

(defun rk/copilot-change-activation ()
  "Switch between three activation modes:
- automatic: copilot will automatically overlay completions
- manual: you need to press a key (M-C-f1) to trigger completions
- off: copilot is completely disabled."
  (interactive)
  (if (and copilot-mode rk/copilot-manual-mode)
      (progn
        (message "deactivating copilot")
        (global-copilot-mode -1)
        (setq rk/copilot-manual-mode nil))
    (if copilot-mode
        (progn
          (message "activating copilot manual mode")
          (setq rk/copilot-manual-mode t))
      (message "activating copilot mode")
      (global-copilot-mode))))

(define-key global-map (kbd "C-<f1>") #'rk/copilot-change-activation)


(defun rk/copilot-quit ()
  "Run `copilot-clear-overlay' or `keyboard-quit'. If copilot is
cleared, make sure the overlay doesn't come back too soon."
  (interactive)
  (condition-case err
      (when copilot--overlay
        (lexical-let ((pre-copilot-disable-predicates copilot-disable-predicates))
                     (setq copilot-disable-predicates (list (lambda () t)))
                     (copilot-clear-overlay)
                     (run-with-idle-timer
                      1.0
                      nil
                      (lambda ()
                        (setq copilot-disable-predicates pre-copilot-disable-predicates)))))
    (error handler)))

(advice-add 'keyboard-quit :before #'rk/copilot-quit)

(with-eval-after-load 'company
  ;; disable inline previews
  (delq 'company-preview-if-just-one-frontend company-frontends))

(define-key copilot-completion-map (kbd "<f1>") 'copilot-accept-completion)


;; you can utilize :map :hook and :config to customize copilot
(provide 'setup-copilot)
