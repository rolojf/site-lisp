;;; setup-markdown.el --- Personal Markdown support -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require 'package-vc)

(add-to-list 'package-vc-selected-packages
             '(md-mode :url "https://github.com/yibie/md-mode"))
(add-to-list 'package-vc-selected-packages
             '(textui :url "https://github.com/yibie/textui"))

(package-vc-install-selected-packages)

(when (and (require-package 'textui)
           (require-package 'md-mode))
  (add-auto-mode 'md-mode "\\.md\\'")
  (with-eval-after-load 'whitespace-cleanup-mode
    (add-to-list 'whitespace-cleanup-mode-ignore-modes 'md-mode)))


(provide 'setup-markdown)
;;; setup-markdown.el ends here
