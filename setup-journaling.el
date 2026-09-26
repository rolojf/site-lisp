;;; setup-journaling.el --- Daily diario, PRIADS workflow, and referir-pendientes -*- lexical-binding: t -*-
;;; Commentary:
;;; Custom journaling on top of Denote: a per-day "diario/" file, copy
;;; un-finished TODOs forward at the start of a new day, copy PRIADS TODOs
;;; into the diario, and the `my-referir-pendientes' flow that routes
;;; closed/SDM tasks back to their PRIADS files.  Depends on the basic
;;; Denote setup in `setup-denote' for `denote-directory'.

;;; Code:

(require 'setup-denote)
(require 'cl-lib)

(when (maybe-require-package 'denote-journal)
  (with-eval-after-load 'denote
    ;; :commands (denote-journal-new-entry denote-journal-new-or-existing-entry denote-journal-link-or-create-entry)
    (add-hook 'calendar-mode 'denote-journal-calendar-mode)
    ;; The `denote-journal-directory` is set globally below.
    (setq denote-journal-keyword "journal")
                                        ; Use default title format for custom functions.
    (setq denote-journal-title-format nil)))

(setq denote-journal-directory (expand-file-name "diario" denote-directory))

(require 'diario-commands)
(require 'diario-priad-commands)

;; Keep the prior referir workflow markers out of the one shared association
;; policy used by focus, import, and referring.
(setq my-diario-ignored-tags
      (delete-dups (append my-diario-ignored-tags
                           '("chulet" "adm" "alf" "techo"))))


;; --- FUNCTION DEFINITIONS ---
;; All custom functions are defined here, before they are called by other code.

(defun journals_to_org_agenda ()
  "Return only the current diario and LUEGO for the active-work agenda."
  (my-diario-agenda-files))

(defun journal-day-exists-p (target)
  "Return the absolute diario paths for YYYYMMDD TARGET."
  (my-dc--day-files target))

(defun find-previous-journal ()
  "Return the latest prior diario's filename, if any."
  (when-let* ((path (my-dc--previous (format-time-string "%Y%m%d"))))
    (file-name-nondirectory path)))

(defun my-refile-tasks (file)
  "Delegate an explicit source-to-FILE rollover to the verified engine."
  (interactive "FDiario destino: ")
  (unless (and (buffer-file-name) (my-dc--journal-p (buffer-file-name))
               (my-dc--journal-p file))
    (user-error "Abra un diario fuente y elija otro diario existente"))
  (my-dc--layout (buffer-file-name))
  (unless (my-diario--fresh-p (my-diario--read file))
    (my-dc--layout file))
  (my-diario-roll (expand-file-name (buffer-file-name)) (expand-file-name file)
                  (my-dc--later) (substring (file-name-nondirectory file) 0 8)))

(defun move-todos (todays-journal-path)
  "Delegate processing of TODAYS-JOURNAL-PATH without a second rollover."
  (my-dc--run (expand-file-name todays-journal-path)
              (substring (file-name-nondirectory todays-journal-path) 0 8)
              'existing))

(defun find-most-recent-journal ()
  "Find the current working diario's absolute path, if any."
  (my-diario-current))

(defun set-org-refile-targets-to-most-recent-journal ()
  "Delegate native Org refile destinations to the managed diario lists."
  (interactive)
  (my-diario-refile-targets))

(add-hook 'org-agenda-mode-hook #'set-org-refile-targets-to-most-recent-journal)
(add-hook 'org-mode-hook #'my-diario-activate-focus)


(defun my--programados-pull-due (target-journal target-date)
  "Delegate due retrieval into TARGET-JOURNAL on TARGET-DATE to the engine."
  (plist-get (my-diario-return (expand-file-name target-journal)
                               (my-dc--later) target-date)
             :returned))

(defun my-denote-journal-today ()
  "Create or open today's diario through the three-list/COLD commands."
  (interactive)
  (my-diario-today))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; COPIAR A TAREAS DIARIAS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my-copiar-a-tareas-diarias (&optional policy)
  "Import new PRIAD TODO roots into today's prepared diario, then close.
With a prefix, deliberately repeat exports previously sent to another day."
  (interactive (list (if current-prefix-arg 'repeat 'new-only)))
  (my-dpc-copy policy))

(defun my-copiar-a-tareas-diarias--maybe-on-kill ()
  "Delegate user-initiated PRIAD close imports to the guarded bridge."
  (my-dpc-maybe-on-kill))

(add-hook 'kill-buffer-query-functions
          #'my-copiar-a-tareas-diarias--maybe-on-kill)

;; New keybindings for the custom journaling workflow.
(let ((map global-map))
  (define-key map (kbd "C-c n j") #'my-denote-journal-today)
  (define-key map (kbd "C-c n c") #'my-copiar-a-tareas-diarias)
  (define-key map (kbd "C-c n e") #'my-referir-pendientes))
  ;; (define-key map (kbd "C-c n o") #'my-denote-journal-date))

(with-eval-after-load 'org
  (my-diario-refresh-agenda)
  (my-diario-refile-targets))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; REFERIR PENDIENTES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my-referir-pendientes ()
  "Refer only eligible OT/DEEP roots at point through the verified engine."
  (interactive)
  (my-dpc-refer))

(defun my-org-agenda-current-file ()
  "Mostrar la Agenda View solamente para el archivo Org actual."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Este comando debe ejecutarse desde un archivo Org"))
  (unless buffer-file-name
    (user-error "El buffer actual no está asociado con un archivo"))
  (org-agenda nil "a" 'buffer))

(global-set-key (kbd "C-c n a") #'my-org-agenda-current-file)



(provide 'setup-journaling)
;;; setup-journaling.el ends here
