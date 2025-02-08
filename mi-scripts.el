;;; mi-scripts.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary: solo funciones que en algún momento me han servido
;;; Code:

(defun rolo2-extract-doc-comments ()
  "In Dired, extract text blocks between '{-|' and '-}' from marked files to '~/docs.md'."
  (interactive)
  (unless (derived-mode-p 'dired-mode)
    (error "This function must be called from a Dired buffer"))
  (let ((files (dired-get-marked-files))
        ;; Store the Dired directory before entering temp buffers
        (dired-directory default-directory)
        (output-file (expand-file-name "~/docs.md")))
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        ;; Compute relative file name based on Dired directory
        (let* ((relative-name (file-relative-name file dired-directory))
               ;; Remove file extension
               (sans-extension (file-name-sans-extension relative-name))
               ;; Split path into components
               (components (split-string sans-extension "/"))
               (len (length components))
               ;; Get last folder and base file name
               (last-folder (if (> len 1)
                                (nth (- len 2) components)
                              ""))
               (base-name (car (last components)))
               ;; Combine last folder and base name with a dot
               (formatted-name (if (string= last-folder "")
                                   base-name
                                 (concat last-folder "." base-name)))
               (has-inserted-filename nil))
          (while (search-forward "{-|" nil t)
            (let ((start (match-beginning 0)))
              (if (search-forward "-}" nil t)
                  (let* ((end (point))
                         (text (buffer-substring-no-properties start end)))
                    ;; Append to output file
                    (with-temp-buffer
                      ;; Insert file name only once per file
                      (unless has-inserted-filename
                        (insert "# " formatted-name "\n")
                        (setq has-inserted-filename t))
                      (insert text "\n\n")
                      (write-region (point-min) (point-max) output-file 'append)))
                (message "Unmatched '{-|' in file %s" file))))))
      (message "Done extracting text blocks to %s." output-file)))
  )

(defun join-marked-files-into-md ()
  "Ver2. Join marked files in Dired into 'joined.md' in the same directory.
If 'joined.md' already exists, it will be deleted and recreated.
Markdown files are included as-is, while other files are added
with a header and enclosed in triple backticks for code formatting."
  (interactive)
  (let* ((files (dired-get-marked-files))
         (dir (dired-current-directory))
         (output-file (expand-file-name "joined.md" dir)))
    ;; Delete 'joined.md' if it already exists
    (when (file-exists-p output-file)
      (delete-file output-file))
    ;; Process each marked file
    (dolist (file files)
      (with-temp-buffer
        (if (string-match-p "\\.md\\'" file)
            ;; If the file is a Markdown file, include its content as-is
            (progn
              (insert-file-contents file))
          ;; Otherwise, add a header and wrap content in triple backticks
          (progn
            (insert (format "# %s\n\n" (file-name-nondirectory file)))
            (insert "```\n")
            (insert-file-contents file)
            (insert "\n```\n")))
        ;; Append the content to 'joined.md'
        (append-to-file (point-min) (point-max) output-file)))))

(defun join-marked-files-into-md ()
  "V3 Join marked files in Dired into 'joined.md' in the same directory.
If 'joined.md' already exists, it will be deleted and recreated.
Markdown files are included as-is, while other files are added
with a header and enclosed in triple backticks for code formatting."
  (interactive)
  (let* ((files (dired-get-marked-files))
         (dir (dired-current-directory))
         (output-file (expand-file-name "joined.md" dir)))
    ;; Delete 'joined.md' if it already exists
    (when (file-exists-p output-file)
      (delete-file output-file))
    ;; Process each marked file
    (dolist (file files)
      (with-temp-buffer
        (if (string-match-p "\\.md\\'" file)
            ;; If the file is a Markdown file, include its content as-is
            (insert-file-contents file)
          ;; Otherwise, add a header and wrap content in triple backticks
          (progn
            (insert (format "### %s\n\n" file))
            (insert "```\n")
            ;; Remember the position before inserting file content
            (let ((content-start (point)))
              (insert-file-contents file))
            ;; Ensure the closing backticks are after the inserted content
            (goto-char (point-max))
            (insert "\n```\n")))
        ;; Append the content to 'joined.md'
        (append-to-file (point-min) (point-max) output-file)))))

(provide 'mi-scripts)
;;; mi-scripts.el ends here
