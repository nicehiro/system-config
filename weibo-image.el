(defconst weibo-image-buffer-name "*weibo-image*")

(defun weibo-get-image-directory ()
  (let ((image-directory (expand-file-name "cache" weibo-directory)))
    (unless (file-exists-p image-directory)
      (make-directory image-directory t))
    image-directory))

(defun weibo-make-image-file-name (url)
  (expand-file-name (md5 url) (weibo-get-image-directory)))

(defun weibo-get-image-file (url)
  (let ((image-file (weibo-make-image-file-name url)))
    (unless (file-exists-p image-file)
      (with-current-buffer (url-retrieve-synchronously url)
	(goto-char (point-min))
	(let ((end (search-forward "\n\n" nil t)))
	  (when end
	    (delete-region (point-min) end)
	    (write-file image-file)))))
    (if (file-exists-p image-file) image-file nil)))

(defun weibo-insert-image (image-file)
  (condition-case err
      (progn
	(insert-image (create-image image-file))
	t)
    (error
     (when (file-exists-p image-file)
       (delete-file image-file))
     nil)))

(defun weibo-show-image (url)
  (switch-to-buffer-other-window weibo-image-buffer-name)
  (erase-buffer)
  (unless (weibo-insert-image (weibo-get-image-file url))
    (weibo-close-image)))

(provide 'weibo-image)