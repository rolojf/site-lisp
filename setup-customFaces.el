;;; setup-customFaces.el --- Custom face settings -*- lexical-binding: t -*-

;; 1. Font Definitions (Keep these as they were)
(set-face-attribute 'default nil :family "Iosevka SS05 Light" :height 170)
(set-face-attribute 'variable-pitch nil :family "Fira Sans Light" :height 1.0)
(set-face-attribute 'fixed-pitch nil :family (face-attribute 'default :family))

;; 2. Ensure package is installed
(require-package 'modus-themes)

;; 3. SET VARIABLES BEFORE LOADING THE THEME
;;    Modus themes reads these variables during load.
(setq modus-themes-italic-constructs t
      modus-themes-bold-constructs nil
      modus-themes-org-blocks 'tinted-background
      ;; modus-themes-mixed-fonts t
      line-spacing 0.15
      modus-themes-paren-match '(bold intense)
      modus-themes-completions
      '((matches . (extrabold background intense))
        (selection . (semibold accented intense))
        (popup . (accented)))
      ;; modus-themes-headings
      ;; (quote ((0 . (monospaced light 1.0))
      ;;         (1 . (monospaced 1.4))
      ;;         (2 . (monospaced semibold 1.2))
      ;;         (3 . (monospaced semibold 1.15))
      ;;         (t . (monospaced semibold  1.1))))
      )

;; 4. DEFINE KEYBINDINGS GLOBALLY
;;    This ensures <f5> works immediately, even if the theme isn't active yet.
(define-key global-map (kbd "<f5>") #'modus-themes-toggle)

;; 5. DEFINE CUSTOM FUNCTION (The Brute Force Fix)
(defun my-enforce-org-headings ()
  "Apply Fixed Pitch + Size/Style explicitly to Org headings."
  ;; Level 0: Document Title (Light, 1.0 height)
  (set-face-attribute 'org-document-title nil
                      :inherit 'fixed-pitch
                      :height 1.0
                      :weight 'light)

  ;; Level 1: (Overline, 1.4 height)
  (set-face-attribute 'org-level-1 nil
                      :inherit 'fixed-pitch
                      :height 1.3
                      :overline t
                      :weight 'semibold) ;; standard bold for level 1 usually looks best with overline

  ;; Level 2: (Semibold, 1.2 height)
  (set-face-attribute 'org-level-2 nil
                      :inherit 'fixed-pitch
                      :height 1.2
                      :weight 'medium)

  ;; Level 3: (Semibold, 1.15 height)
  (set-face-attribute 'org-level-3 nil
                      :inherit 'fixed-pitch
                      :height 1.15
                      :weight 'medium)

  ;; Levels 4-8: (Semibold, 1.1 height)
  (dolist (face '(org-level-4 org-level-5 org-level-6 org-level-7 org-level-8))
    (set-face-attribute face nil
                        :inherit 'fixed-pitch
                        :height 1.1
                        :weight 'light))
  )
;; 6. ADD HOOKS
;;    This ensures your custom function runs every time the theme reloads/toggles.
(add-hook 'modus-themes-after-load-theme-hook #'my-enforce-org-headings)
(add-hook 'text-mode-hook #'variable-pitch-mode)
;; (add-hook 'org-mode-hook #'variable-pitch-mode)

;; 7. FINALLY, LOAD THE THEME
;;    (The 't' at the end prevents Emacs from asking for confirmation)
(load-theme 'modus-vivendi t t)
(load-theme 'modus-vivendi t t)

;; Enable the preferred one
(enable-theme 'modus-operandi)


(provide 'setup-customFaces)
