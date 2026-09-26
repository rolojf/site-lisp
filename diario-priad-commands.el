;;; diario-priad-commands.el --- PRIAD/diario command bridge -*- lexical-binding: t; -*-

;;; Commentary:
;; Interactive routing and Denote discovery for the isolated import/refer
;; engines.  Loading this file installs no hooks, keys, or KB-side effects.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'diario-commands)
(require 'diario-import)
(require 'diario-priads)

(defvar denote-directory)
(defvar my-dpc--inhibit-import nil
  "Non-nil during internal buffer operations that must not import on close.")

(defun my-dpc--root-file-p (file)
  "Return non-nil for a real, direct root .org FILE in denote-directory."
  (and (stringp file)
       (string= (file-name-extension file) "org")
       (file-regular-p file)
       (not (file-symlink-p file))
       (equal (file-name-as-directory (file-name-directory
                                       (expand-file-name file)))
              (file-name-as-directory (expand-file-name denote-directory)))))

(defun my-dpc--candidates ()
  "Discover saved, active, keyword-bearing root PRIADS for referring."
  (unless (file-directory-p denote-directory)
    (user-error "No existe el directorio PRIADS: %s" denote-directory))
  (cl-remove-if-not
   (lambda (file)
     (and (my-dpc--root-file-p file)
          (cdr (my-dp--identity file))))
   (directory-files denote-directory t "\\.org\\'")))

(defun my-dpc--import (&optional policy)
  "Import current root PRIAD TODOs to the prepared diario under POLICY.
With no new eligible work, do not require a diario or ask for a category."
  (unless (my-dpc--root-file-p (buffer-file-name))
    (user-error "Abra un archivo PRIADS .org guardado en la raíz"))
  (when (my-diario-import-needed-p policy)
    (let ((target (my-diario-current)))
      (unless target (user-error "No se encontró archivo diario reciente"))
      (my-diario-import target policy))))

(defun my-dpc-copy (&optional policy)
  "Deliberately import the current PRIAD, then close it on success.
POLICY is `new-only' by default or `repeat' for an explicit repeat."
  (interactive (list (if current-prefix-arg 'repeat 'new-only)))
  (my-dpc--import policy)
  (let ((my-dpc--inhibit-import t))
    (kill-buffer (current-buffer))))

(defun my-dpc-maybe-on-kill ()
  "Import new work only for user-initiated PRIAD buffer close commands.
The guard also covers deliberate and background closes within this bridge."
  (when (and (not my-dpc--inhibit-import)
             (memq this-command '(kill-buffer kill-this-buffer))
             (my-dpc--root-file-p (buffer-file-name)))
    (let ((my-dpc--inhibit-import t))
      (my-dpc--import 'new-only)))
  t)

(defun my-dpc--create (base _full-tag)
  "Ask Denote to create a matching saved root PRIAD for BASE.
Return nil on cancellation.  Leave the source buffer, point, and window
configuration unchanged, even when Denote visits a newly created buffer."
  (unless (or (fboundp 'denote) (require 'denote nil t))
    (user-error "Denote no está disponible para crear un PRIAD"))
  (let* ((root (expand-file-name denote-directory))
         (prior-buffers (buffer-list))
         created-buffer
         (file (save-window-excursion
                 (save-current-buffer
                   (save-excursion
                     (let ((denote-directory root))
                       (prog1 (condition-case nil
                                  (call-interactively #'denote)
                                (quit nil))
                         (setq created-buffer (current-buffer)))))))))
    (when file
      ;; The Denote visitor may not yet exist on disk when automatic saving
      ;; is disabled.  Check identity and location without opening a file.
      (unless (and (stringp file) (file-name-absolute-p file)
                   (equal (file-name-as-directory (file-name-directory file))
                          (file-name-as-directory root))
                   (not (file-symlink-p file))
                   (member base (cdr (my-dp--identity file))))
        (user-error "Denote no creó un PRIAD activo para %s en la raíz" base))
      (let ((visitor (find-buffer-visiting file)))
        (unless (and visitor (eq visitor created-buffer)
                     (not (memq visitor prior-buffers))
                     (equal (expand-file-name (buffer-file-name visitor)) file))
          (user-error "Denote no devolvió un buffer nuevo para %s" base))
        (with-current-buffer visitor
          (when (buffer-modified-p) (save-buffer))
          (unless (and (my-dpc--root-file-p file)
                       (not (buffer-modified-p)))
            (user-error "Denote no guardó un PRIAD activo para %s" base))))
      file)))

(defun my-dpc-refer ()
  "Refer eligible OT/DEEP roots in the current diary point/subtree scope.
Confirm unsaved source edits; the engine itself refuses modified or stale
involved destination buffers.  Never visit discovery-only PRIAD buffers."
  (interactive)
  (unless (and (derived-mode-p 'org-mode)
               (my-dc--journal-p (buffer-file-name)))
    (user-error "Abra un diario Org guardado para referir pendientes"))
  (when (org-before-first-heading-p)
    (user-error "El cursor no está en ningún encabezado; no se procesó nada"))
  (let ((my-dpc--inhibit-import t))
    (when (buffer-modified-p)
      (unless (and (verify-visited-file-modtime (current-buffer))
                   (y-or-n-p "El diario no está guardado. ¿Guardarlo antes de referir? "))
        (user-error "Referir cancelado o el diario cambió en disco"))
      (save-buffer))
    (my-diario-refer (my-dpc--candidates) #'my-dpc--create)))

(provide 'diario-priad-commands)
;;; diario-priad-commands.el ends here
