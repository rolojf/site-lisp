;;; setup-customFaces.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:


(set-face-attribute 'default nil :family "Iosevka SS05 Light" :height 170)
(set-face-attribute 'variable-pitch nil :family "Fira Sans Light" :height 1.0)
(set-face-attribute 'fixed-pitch nil :family (face-attribute 'default :family))

(require 'modus-themes)
(with-eval-after-load 'modus-themes
  (load-theme 'modus-vivendi)
  (setq modus-themes-italic-constructs t
        modus-themes-bold-constructs nil
        modus-themes-org-blocks 'tinted-background
        modus-themes-mixed-fonts t
        line-spacing 0.15
        modus-themes-paren-match '(bold intense)
        )
  (setq modus-themes-completions
        '((matches . (extrabold background intense))
          (selection . (semibold accented intense))
          (popup . (accented))
          ))
  (setq modus-themes-headings
        '((0 . (fixed-pitch light 0.75))
          (1 . (overline fixed-pitch bold 1.1))
          (2 . (rainbow fixed-pitch semibold 1.1))
          (3 . (rainbow fixed-pitch semibold 1.05))
          (t . (monochrome fixed-pitch 1.05)))
        )
  (define-key global-map (kbd "<f5>") 'modus-themes-toggle)
  )

(add-hook 'text-mode-hook
          'variable-pitch-mode)


(provide 'setup-customFaces)
;;; setup-customFaces.el ends here
