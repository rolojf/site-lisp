(add-hook 'origami-mode-hook
          '(lambda()
             (define-key origami-mode-map (kbd "--f") 'origami-recursively-toggle-node)
             (define-key origami-mode-map (kbd "--F") 'origami-toggle-all-nodes)
             (define-key origami-mode-map (kbd "--o") 'origami-open-node-recursively)
             ))

(provide 'setup-origami)
