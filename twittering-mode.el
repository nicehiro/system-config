;;; -*- indent-tabs-mode: t; tab-width: 8; coding: utf-8 -*-
;;;
;;; twittering-mode.el --- Major mode for Twitter

;; Copyright (C) 2007, 2009, 2010 Yuto Hayamizu.
;;               2008 Tsuyoshi CHO

;; Author: Y. Hayamizu <y.hayamizu@gmail.com>
;;         Tsuyoshi CHO <Tsuyoshi.CHO+develop@Gmail.com>
;;         Alberto Garcia  <agarcia@igalia.com>
;; Created: Sep 4, 2007
;; Version: HEAD
;; Keywords: twitter web
;; URL: http://twmode.sf.net/

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; twittering-mode.el is a major mode for Twitter.
;; You can check friends timeline, and update your status on Emacs.

;;; Feature Request:

;; URL : http://code.nanigac.com/source/view/419
;; * update status for region

;;; Code:

(eval-when-compile (require 'cl))
(require 'xml)
(require 'parse-time)
(when (> 22 emacs-major-version)
  (setq load-path
        (append (mapcar (lambda (dir)
                          (expand-file-name
                           dir
                           (if load-file-name
                               (or (file-name-directory load-file-name)
                                   ".")
                             ".")))
                        '("url-emacs21" "emacs21"))
                load-path))
  (and (require 'un-define nil t)
       ;; the explicitly require 'unicode to update a workaround with
       ;; navi2ch. see a comment of `twittering-ucs-to-char' for more
       ;; details.
       (require 'unicode nil t)))
(require 'url)

(defconst twittering-mode-version "HEAD")

(defun twittering-mode-version ()
  "Display a message for twittering-mode version."
  (interactive)
  (let ((version-string
         (format "twittering-mode-v%s" twittering-mode-version)))
    (if (interactive-p)
        (message "%s" version-string)
      version-string)))

;;;
;;; User Customizable
;;;

(defgroup twittering nil
  "Twitter client."
  :prefix "twittering-"
  :group 'applications)

(defcustom twittering-number-of-tweets-on-retrieval 20
  "*The number of tweets which will be retrieved in one request.
The upper limit is `twittering-max-number-of-tweets-on-retrieval'."
  :type 'integer
  :group 'twittering)

(defcustom twittering-timer-interval 90
  "The interval of auto reloading.
You should use 60 or more seconds for this variable because the number of API
call is limited by the hour."
  :type 'integer
  :group 'twittering)

(defcustom twittering-username nil
  "*An username of your Twitter account."
  :type 'string
  :group 'twittering)

(defcustom twittering-password nil
  "*A password of your Twitter account. Leave it blank is the
recommended way because writing a password in .emacs file is so
dangerous."
  :type 'string
  :group 'twittering)

(defcustom twittering-initial-timeline-spec-string ":home@twitter"
  "*The initial timeline spec string. If the value of the variable is a
list of timeline spec strings, the timelines are rendered on their own
buffers."
  :type 'string
  :group 'twittering)

(defcustom twittering-status-format "%FACE[twittering-zebra-1-face,twittering-zebra-2-face]{%i %s,  %@:\n%FILL{  %t %m // from %f%L%r%R}}\n "
  "Format string for rendering statuses.
Ex. \"%i %s,  %@:\\n%FILL{  %t // from %f%L%r%R}\n \"

Items:
 %s - screen_name
 %S - name
 %i - profile_image
 %d - description
 %l - location
 %L - \" [location]\"
 %m - (sina) comment and retweet count, if any. (FIXME: this needs to be updated
      quite often to record correct value.)
 %r - \" sent to user\" (use on direct_messages{,_sent})
 %r - \" in reply to user\" (use on other standard timeline)
 %R - \" (retweeted by user)\"
 %RT{...} - strings rendered only when the tweet is a retweet.
            The braced strings are rendered with the information of the
            retweet itself instead of that of the retweeted original tweet.
            For example, %s for a retweet means who posted the original
            tweet, but %RT{%s} means who retweeted it.
 %u - url
 %j - user.id
 %p - protected?
 %c - created_at (raw UTC string)
 %g - format %c using `gnus-user-date' (Note: this assumes you will not keep
      latest statuses for more than a week)
 %C{time-format-str} - created_at (formatted with time-format-str)
 %@ - X seconds ago
 %T - (sina) thumbnail picture in a tweet
 %t - text filled as one paragraph
 %' - truncated
 %FACE[face-name]{...} - strings decorated with the specified face. You can
                      provide two faces, separated by colon, to create a
                      zebra-like background.
 %FILL[prefix]{...} - strings filled as a paragraph. The prefix is optional.
                      You can use any other specifiers in braces.
 %FOLD[prefix]{...} - strings folded within the frame width.
                      The prefix is optional. This keeps newlines and does not
                      squeeze a series of white spaces.
                      You can use any other specifiers in braces.
 %f - source
 %# - id
"
  :type 'string
  :group 'twittering)

(defcustom twittering-my-status-format nil
  "Specific format for my posts.
See `twittering-status-format'. "
  :type 'string
  :group 'twittering)

(defcustom twittering-retweet-format "RT: %t (via @%s)"
  "Format string for retweet.

Items:
 %s - screen_name
 %t - text
 %% - %
"
  :type 'string
  :group 'twittering)

(defcustom twittering-fill-column nil
  "*The fill-column used for \"%FILL{...}\" in `twittering-status-format'.
If nil, the fill-column is automatically calculated."
  :type 'integer
  :group 'twittering)

(defcustom twittering-my-fill-column nil
  "Similar to `twittering-fill-column', specially for tweets sent by myself."
  :type 'integer
  :group 'twittering)

(defcustom twittering-show-replied-tweets t
  "*The number of replied tweets which will be showed in one tweet.

If the value is not a number and is non-nil, show all replied tweets
which is already fetched.
If the value is nil, doesn't show replied tweets."
  :type 'symbol
  :group 'twittering)

(defcustom twittering-default-show-replied-tweets nil
  "*The number of default replied tweets which will be showed in one tweet.
This value will be used only when showing new tweets.

See `twittering-show-replied-tweets' for more details."
  :type 'symbol
  :group 'twittering)

(defcustom twittering-use-show-minibuffer-length t
  "*Show current length of minibuffer if this variable is non-nil.

We suggest that you should set to nil to disable the showing function
when it conflict with your input method (such as AquaSKK, etc.)"
  :type 'symbol
  :group 'twittering)

(defcustom twittering-notify-successful-http-get t
  "Non-nil will notify successful http GET in minibuffer."
  :type 'symbol
  :group 'twittering)

(defcustom twittering-use-ssl t
  "Use SSL connection if this variable is non-nil.

SSL connections use 'curl' command as a backend."
  :type 'symbol
  :group 'twittering)

(defcustom twittering-timeline-most-active-spec-strings '(":home" ":replies")
  "See `twittering-timeline-spec-most-active-p'."
  :type 'list
  :group 'twittering)

(defcustom twittering-request-confirmation-on-posting nil
  "*If *non-nil*, confirmation will be requested on posting a tweet edited in
pop-up buffer."
  :type 'symbol
  :group 'twittering)

(defcustom twittering-timeline-spec-alias nil
  "*Alist for aliases of timeline spec.
Each element is (NAME . SPEC-STRING), where NAME is a string and
SPEC-STRING is a string or a function that returns a timeline spec string.

The alias can be referred as \"$NAME\" or \"$NAME(ARG)\" in timeline spec
string. If SPEC-STRING is a string, ARG is simply ignored.
If SPEC-STRING is a function, it is called with a string argument.
For the style \"$NAME\", the function is called with nil.
For the style \"$NAME(ARG)\", the function is called with a string ARG.

For example, if you specify
 '((\"FRIENDS\" . \"(USER1+USER2+USER3)\")
   (\"to_me\" . \"(:mentions+:retweets_of_me+:direct_messages)\")
   (\"related-to\" .
            ,(lambda (username)
               (if username
                   (format \":search/to:%s OR from:%s OR @%s/\"
                           username username username)
                 \":home\")))),
then you can use \"$to_me\" as
\"(:mentions+:retweets_of_me+:direct_messages)\"."
  :type 'list
  :group 'twittering)

(defcustom twittering-convert-fix-size 48
  "Size of user icon.

When nil, don't convert, simply use original size.

Most default profile_image_url in status is already an
avatar(48x48).  So normally we don't have to convert it at all."
  :type 'number
  :group 'twittering)

(defcustom twittering-new-tweets-count-excluding-me nil
  "Non-nil will exclude my own tweets when counting received new tweets."
  :type 'boolean
  :group 'twittering)

(defcustom twittering-new-tweets-count-excluding-replies-in-home nil
  "Non-nil will exclude replies in home timeline when counting received new
tweets."
  :type 'boolean
  :group 'twittering)

;; (defcustom (twittering-get-accounts 'auth) 'oauth
;;   "*Authentication method for `twittering-mode'.
;; The symbol `basic' means Basic Authentication. The symbol `oauth' means
;; OAuth Authentication. The symbol `xauth' means xAuth Authentication.
;; OAuth Authentication requires `(twittering-lookup-service-method-table 'oauth-consumer-key)' and
;; `(twittering-lookup-service-method-table 'oauth-consumer-secret)'. Additionally, it requires an external
;; command `curl' or another command included in `tls-program', which may be
;; `openssl' or `gnutls-cli', for SSL."
;;   :type 'symbol
;;   :group 'twittering)

;;;
;;; Internal Variables
;;;

(defvar twittering-account-authorization '()
  "State of account authorization for `twittering-username' and
`twittering-password'.  The value is one of the following symbols:
nil -- The account have not been authorized yet.
queried -- The authorization has been queried, but not finished yet.
authorized -- The account has been authorized.")

(defun twittering-get-account-authorization ()
  (cadr (assq (twittering-extract-service)
	      twittering-account-authorization)))

(defun twittering-update-account-authorization (auth)
  (setq twittering-account-authorization
        `((,(twittering-extract-service) ,auth)
          ,@(assq-delete-all twittering-service-method
                            twittering-account-authorization))))

(defvar twittering-oauth-invoke-browser nil
  "*Whether to invoke a browser on authorization of access key automatically.")

(defconst twittering-max-number-of-tweets-on-retrieval 200
  "The maximum number of `twittering-number-of-tweets-on-retrieval'.")

(defvar twittering-tinyurl-service 'tinyurl
  "*The service to shorten URI.
This must be one of key symbols of `twittering-tinyurl-services-map'.
To use 'bit.ly or 'j.mp, you have to configure `twittering-bitly-login' and
`twittering-bitly-api-key'.")

(defvar twittering-tinyurl-services-map
  '((bit.ly twittering-make-http-request-for-bitly
            (lambda (service reply)
              (if (string-match "\n\\'" reply)
                  (substring reply 0 (match-beginning 0))
                reply)))
    (goo.gl
     (lambda (service longurl)
       (twittering-make-http-request-from-uri
        "POST" '(("Content-Type" . "application/json"))
        "https://www.googleapis.com/urlshortener/v1/url"
        (concat "{\"longUrl\": \"" longurl "\"}")))
     (lambda (service reply)
       (when (string-match "\"id\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\""
                           reply)
         (match-string 1 reply))))
    (is.gd . "http://is.gd/create.php?format=simple&url=")
    (j.mp twittering-make-http-request-for-bitly
          (lambda (service reply)
            (if (string-match "\n\\'" reply)
                (substring reply 0 (match-beginning 0))
              reply)))
    (tinyurl . "http://tinyurl.com/api-create.php?url=")
    (toly
     (lambda (service longurl)
       (twittering-make-http-request-from-uri
        "POST" nil
        "http://to.ly/api.php"
        (concat "longurl=" (twittering-percent-encode longurl))))))
  "Alist of URL shortening services.
The key is a symbol specifying the service.
The value is a string or a list consisting of two elements at most.

If the value is a string, `(concat THE-FIRST-ELEMENT longurl)' is used as the
URL invoking the service.
If the value is a list, it is interpreted as follows.
The first element specifies how to make a HTTP request for shortening a URL.
If the first element is a string, `(concat THE-FIRST-ELEMENT longurl)' is
used as the URL invoking the service.
If the first element is a function, it is called as `(funcall THE-FIRST-ELEMENT
service-symbol longurl)' to obtain a HTTP request alist for invoking the
service, which must be generated by `twittering-make-http-request'.

The second element specifies how to post-process a HTTP reply by the HTTP
request.
If the second element is nil, the reply is directly used as a shortened URL.
If the second element is a function, it is called as `(funcall
THE-SECOND-ELEMENT service-symbol HTTP-reply-string)' and its result is used
as a shortened URL.")

(defvar twittering-bitly-login nil
  "*The login name for URL shortening service bit.ly and j.mp.")
(defvar twittering-bitly-api-key nil
  "*The API key for URL shortening service bit.ly and j.mp.")

(defvar twittering-mode-map (make-sparse-keymap))
(defvar twittering-mode-menu-on-uri-map (make-sparse-keymap "Twittering Mode"))
(defvar twittering-mode-on-uri-map (make-sparse-keymap))

(defvar twittering-tweet-history nil)
(defvar twittering-user-history nil)
(defvar twittering-timeline-history nil)
(defvar twittering-hashtag-history nil)
(defvar twittering-search-history nil)

(defvar twittering-current-hashtag nil
  "A hash tag string currently set. You can set it by calling
`twittering-set-current-hashtag'.")

(defvar twittering-timer nil
  "Timer object for timeline refreshing will be stored here.
DO NOT SET VALUE MANUALLY.")

(defvar twittering-timer-for-redisplaying nil
  "Timer object for timeline redisplay statuses will be stored here.
DO NOT SET VALUE MANUALLY.")

(defvar twittering-timer-interval-for-redisplaying 5.0
  "The interval of auto redisplaying statuses.
Each time Emacs remains idle for the interval, twittering-mode updates parts
requiring to be redrawn.")

(defvar twittering-timeline-spec nil
  "The timeline spec for the current buffer.")

(defvar twittering-timeline-spec-string ""
  "The timeline spec string for the current buffer.")

(defvar twittering-current-timeline-spec-string nil
  "The current timeline spec string. This variable should not be referred
directly. Use `twittering-current-timeline-spec-string' or
`twittering-current-timeline-spec'.")

(defvar twittering-get-simple-retrieved nil)

(defvar twittering-process-info-alist nil
  "Alist of active process and timeline spec retrieved by the process.")

(defvar twittering-server-info-alist nil
  "Alist of server information.")

(defvar twittering-new-tweets-count 0
  "Number of new tweets when `twittering-new-tweets-hook' is run.")

(defvar twittering-new-tweets-spec nil
  "Timeline spec, which new tweets belong to, when
`twittering-new-tweets-hook' is run.")
(defvar twittering-new-tweets-statuses nil
  "New tweet status messages, when
`twittering-new-tweets-hook' is run.")

(defvar twittering-new-tweets-hook nil
  "*Hook run when new tweets are received.

You can read `twittering-new-tweets-count' or `twittering-new-tweets-spec'
to get the number of new tweets received when this hook is run.")

(defvar twittering-active-mode nil
  "Non-nil if new statuses should be retrieved periodically.
Do not modify this variable directly. Use `twittering-activate-buffer',
`twittering-deactivate-buffer', `twittering-toggle-activate-buffer' or
`twittering-set-active-flag-for-buffer'.")
(defvar twittering-scroll-mode nil)

(defvar twittering-jojo-mode nil)
(defvar twittering-reverse-mode nil
  "*Non-nil means tweets are aligned in reverse order of `http://twitter.com/'.")
(defvar twittering-display-remaining nil
  "*If non-nil, display remaining of rate limit on the mode-line.")
(defvar twittering-display-connection-method t
  "*If non-nil, display the current connection method on the mode-line.")

(defvar twittering-allow-insecure-server-cert nil
  "*If non-nil, twittering-mode allows insecure server certificates.")

(defvar twittering-curl-program nil
  "Cache a result of `twittering-find-curl-program'.
DO NOT SET VALUE MANUALLY.")
(defvar twittering-curl-program-https-capability nil
  "Cache a result of `twittering-start-http-session-curl-https-p'.
DO NOT SET VALUE MANUALLY.")

(defvar twittering-wget-program nil
  "Cache a result of `twittering-find-wget-program'.
DO NOT SET VALUE MANUALLY.")

(defvar twittering-tls-program nil
  "*List of strings containing commands to start TLS stream to a host.
Each entry in the list is tried until a connection is successful.
%h is replaced with server hostname, %p with port to connect to.
Also see `tls-program'.
If nil, this is initialized with a list of valied entries extracted from
`tls-program'.")

(defvar twittering-connection-type-order
  '(curl wget urllib-http native urllib-https))
  "*A list of connection methods in the preferred order."

(defvar twittering-connection-type-table
  '((native (check . t)
            (https . twittering-start-http-session-native-tls-p)
            (send-http-request . twittering-send-http-request-native)
            (pre-process-buffer . twittering-pre-process-buffer-native))
    (curl (check . twittering-start-http-session-curl-p)
          (https . twittering-start-http-session-curl-https-p)
          (send-http-request . twittering-send-http-request-curl)
          (pre-process-buffer . twittering-pre-process-buffer-curl))
    (wget (check . twittering-start-http-session-wget-p)
          (https . t)
          (send-http-request . twittering-send-http-request-wget)
          (pre-process-buffer . twittering-pre-process-buffer-wget))
    (urllib-http
     (display-name . "urllib")
     (check . twittering-start-http-session-urllib-p)
     (https . nil)
     (send-http-request . twittering-send-http-request-urllib)
     (pre-process-buffer . twittering-pre-process-buffer-urllib))
    (urllib-https
     (display-name . "urllib")
     (check . twittering-start-http-session-urllib-p)
     (https . twittering-start-http-session-urllib-https-p)
     (send-http-request . twittering-send-http-request-urllib)
     (pre-process-buffer . twittering-pre-process-buffer-urllib)))
  "A list of alist of connection methods.")

(defvar twittering-format-status-function-source ""
  "The status format string that has generated the current
`twittering-format-status-function'.")
(defvar twittering-format-status-function nil
  "The formating function generated from `twittering-format-status-function-source'.")

(defvar twittering-format-my-status-function-source "")
(defvar twittering-format-my-status-function nil)

(defvar twittering-timeline-data-table (make-hash-table :test 'equal))

(defvar twittering-username-face 'twittering-username-face)
(defvar twittering-uri-face 'twittering-uri-face)

(defvar twittering-zebra-1-face 'twittering-zebra-1-face)
(defvar twittering-zebra-2-face 'twittering-zebra-2-face)

(defface twittering-zebra-1-face `((t (:background "#e6e6fa"))) "" :group 'faces)
(defface twittering-zebra-2-face `((t (:background "#ffe4e1"))) "" :group 'faces)

(defvar twittering-use-native-retweet nil
  "Post retweets using native retweets if this variable is non-nil.
This is default value, you can also set it separately for each service in
`twittering-accounts', like (retweet organic) or (retweet native).")

(defvar twittering-update-status-function
  'twittering-update-status-from-pop-up-buffer
  "The function used to posting a tweet. It takes two arguments:
the first argument INIT-STR is initial text to be edited and the
second argument REPLY-TO-ID is a user ID of a tweet to which you
are going to reply.

Twittering-mode provides two functions for updating status:
* `twittering-update-status-from-minibuffer': edit tweets in minibuffer
* `twittering-update-status-from-pop-up-buffer': edit tweets in pop-up buffer")

(defvar twittering-invoke-buffer nil
  "The buffer where we invoke `twittering-get-and-render-timeline'.

If we invoke `twittering-get-and-render-timeline' from a twittering buffer, then
do not display unread notifier on mode line.")

(defvar twittering-use-master-password nil
  "*Wheter to store private information encrypted with a master password.")
(defvar twittering-private-info-file
  (expand-file-name "~/.twittering-mode.gpg")
  "*File for storing encrypted private information when
`twittering-use-master-password' is non-nil.")
(defvar twittering-variables-stored-with-encryption
  '(twittering-oauth-access-token-alist))

(defvar twittering-oauth-use-ssl t
  "*Whether to use SSL on authentication via OAuth. Twitter requires SSL
on authorization via OAuth.")
(defvar twittering-oauth-access-token-alist '())

;; buffer local.
(defvar twittering-service-method nil
  "*Service method for `twittering-mode'.
Following methods are supported:
  'twitter   -- http://www.twitter.com
  'statusnet -- http://status.net
  'sina      -- http://t.sina.com.cn")

(defcustom twittering-service-method-table
  `((twitter (api "api.twitter.com")
             (search "search.twitter.com")
             (web "twitter.com")

             (api-prefix "1/")
             (search-method "search")

             (oauth-request-token-url-without-scheme
              "://api.twitter.com/oauth/request_token")
             (oauth-authorization-url-base-without-scheme
              "://api.twitter.com/oauth/authorize?oauth_token=")
             (oauth-access-token-url-without-scheme
              "://api.twitter.com/oauth/access_token")
             (oauth-consumer-key
              ,(base64-decode-string
                "RWJqWHNtdllhQzJwMHhyRDBMa0Jldw=="))
             (oauth-consumer-secret
              ,(base64-decode-string
                "ZEpVRzJoVzJtV1l1eTRZd0VscHdiQjBpY0JCb3NwOXZ2NTFmdmZ0c09F"))

             (status-url twittering-get-status-url-twitter)
             (search-url twittering-get-search-url-twitter))

    (sina (api "api.t.sina.com.cn")
          (web "t.sina.com.cn")
          ;; search is not restricted by sina..

          (oauth-request-token-url-without-scheme
           "://api.t.sina.com.cn/oauth/request_token")
          (oauth-authorization-url-base-without-scheme
           "://api.t.sina.com.cn/oauth/authorize?oauth_token=")
          (oauth-access-token-url-without-scheme
           "://api.t.sina.com.cn/oauth/access_token")
          (oauth-consumer-key
           ,(base64-decode-string "Mzk0NDQ3MzYyOA=="))
          (oauth-consumer-secret
           ,(base64-decode-string
             "NzM0YzFkNDlmMGM2MjJhZGY1NTFiNDljNjIzOGU5ODI="))

          (status-url twittering-get-status-url-sina)
          (search-url twittering-get-search-url-twitter))

    (statusnet (status-url twittering-get-status-url-statusnet)
               (search-url twittering-get-search-url-statusnet)))
  "A list of alist of service methods."
  :type 'list
  :group 'twittering)

(defun twittering-lookup-service-method-table (attr)
  "Lookup ATTR value for `twittering-service-method'."
  (or (cadr (assq attr (assqref (twittering-extract-service)
                                twittering-service-method-table)))
      ""))

(defun twittering-lookup-oauth-access-token-alist ()
  (assqref (twittering-extract-service) twittering-oauth-access-token-alist))

(defun twittering-update-oauth-access-token-alist (alist)
  (setq twittering-oauth-access-token-alist
        `((,(twittering-extract-service) ,@alist)
          ,@(assq-delete-all (twittering-extract-service)
                             twittering-oauth-access-token-alist))))

(defcustom twittering-accounts '()
  "Account settings service by service.

    ((service-method
         (username \"FOO\")
         (password \"PASSWORD\")

         ;; optional
         (auth basic)      ; Authentication method: `oauth', `basic'.
         (retweet organic) ; Default Retweet style: `native', `organic'.

     ...)"
  :type 'list
  :group 'twittering-mode)

(defcustom twittering-enabled-services '(twitter)
  "See `twittering-service-method-table' for supported services."
  :type 'list
  :group 'twittering-mode)

(defun twittering-get-accounts (attr)
  (cadr (assq attr
              (assqref (twittering-extract-service) twittering-accounts))))

;;;;
;;;; Macro and small utility function
;;;;

(defun assocref (item alist)
  (cdr (assoc item alist)))

(defun assqref (item alist)
  (cdr (assq item alist)))

(defmacro list-push (value listvar)
  `(setq ,listvar (cons ,value ,listvar)))

(defmacro case-string (str &rest clauses)
  `(cond
    ,@(mapcar
       (lambda (clause)
         (let ((keylist (car clause))
               (body (cdr clause)))
           `(,(if (listp keylist)
                  `(or ,@(mapcar (lambda (key) `(string-equal ,str ,key))
                                 keylist))
                't)
             ,@body)))
       clauses)))

;;;;
;;;; Utility for portability
;;;;

(defun twittering-remove-duplicates (list)
  "Return a copy of LIST with all duplicate elements removed.
This is non-destructive version of `delete-dups' which is not
defined in Emacs21."
  (if (fboundp 'delete-dups)
      (delete-dups (copy-sequence list))
    (let ((rest list)
          (result nil))
      (while rest
        (unless (member (car rest) result)
          (setq result (cons (car rest) result)))
        (setq rest (cdr rest)))
      (nreverse result))))

(defun twittering-completing-read (prompt collection &optional predicate require-match initial-input hist def inherit-input-method)
  "Read a string in the minibuffer, with completion.
This is a modified version of `completing-read' and accepts candidates
as a list of a string on Emacs21."
  ;; completing-read() of Emacs21 does not accepts candidates as
  ;; a list. Candidates must be given as an alist.
  (let* ((collection (twittering-remove-duplicates collection))
         (collection
          (if (and (> 22 emacs-major-version)
                   (listp collection)
                   (stringp (car collection)))
              (mapcar (lambda (x) (cons x nil)) collection)
            collection)))
    (completing-read prompt collection predicate require-match
                     initial-input hist def inherit-input-method)))

(defun twittering-add-to-history (history-var elt &optional maxelt keep-all)
  (if (functionp 'add-to-history)
      (add-to-history history-var elt maxelt keep-all)
    (let* ((added (cons elt
                        (if (and (not keep-all)
                                 (boundp 'history-delete-duplicates)
                                 history-delete-duplicates)
                            (delete elt (symbol-value history-var))
                          (symbol-value history-var))))
           (maxelt (or maxelt history-length))
           (len (length added)))
      (set history-var
            (if (<= len maxelt)
                added
              (butlast added (- len maxelt)))))))

;;;;
;;;; Debug mode
;;;;

(defvar twittering-debug-mode nil)
(defvar twittering-debug-buffer "*debug*")

(defun twittering-get-or-generate-buffer (buffer)
  (if (bufferp buffer)
      (if (buffer-live-p buffer)
          buffer
        (generate-new-buffer (buffer-name buffer)))
    (if (stringp buffer)
        (or (get-buffer buffer)
            (generate-new-buffer buffer)))))

(defun twittering-debug-buffer ()
  (twittering-get-or-generate-buffer twittering-debug-buffer))

(defmacro debug-print (obj)
  (let ((obsym (gensym)))
    `(let ((,obsym ,obj))
       (if twittering-debug-mode
           (with-current-buffer (twittering-debug-buffer)
             (insert "[debug] " (prin1-to-string ,obsym))
             (newline)
             ,obsym)
         ,obsym))))

(defun debug-printf (fmt &rest args)
  (when twittering-debug-mode
    (with-current-buffer (twittering-debug-buffer)
      (insert "[debug] " (apply 'format fmt args))
      (newline))))

(defun twittering-debug-mode ()
  (interactive)
  (setq twittering-debug-mode
        (not twittering-debug-mode))
  (message (if twittering-debug-mode "debug mode:on" "debug mode:off")))

;;;;
;;;; Proxy setting / functions
;;;;

(defvar twittering-proxy-use nil)

(defvar twittering-proxy-server nil
  "*Proxy server for `twittering-mode'.
If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.

To use individual proxies for HTTP and HTTPS, both `twittering-proxy-server'
and `twittering-proxy-port' must be nil.")
(defvar twittering-proxy-port nil
  "*Port number for `twittering-mode'.
If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.

To use individual proxies for HTTP and HTTPS, both `twittering-proxy-server'
and `twittering-proxy-port' must be nil.")
(defvar twittering-proxy-keep-alive nil)
(defvar twittering-proxy-user nil
  "*Username for `twittering-proxy-server'.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-proxy-password nil
  "*Password for `twittering-proxy-server'.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")

(defvar twittering-http-proxy-server nil
  "*HTTP proxy server for `twittering-mode'.
If nil, it is initialized on entering `twittering-mode'.
The port number is specified by `twittering-http-proxy-port'.
For HTTPS connection, the proxy specified by `twittering-https-proxy-server'
and `twittering-https-proxy-port' is used.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-http-proxy-port nil
  "*Port number of a HTTP proxy server for `twittering-mode'.
If nil, it is initialized on entering `twittering-mode'.
The server is specified by `twittering-http-proxy-server'.
For HTTPS connection, the proxy specified by `twittering-https-proxy-server'
and `twittering-https-proxy-port' is used.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-http-proxy-keep-alive nil
  "*If non-nil, the Keep-alive is enabled. This is experimental.")
(defvar twittering-http-proxy-user nil
  "*Username for `twittering-http-proxy-server'.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-http-proxy-password nil
  "*Password for `twittering-http-proxy-server'.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")

(defvar twittering-https-proxy-server nil
  "*HTTPS proxy server for `twittering-mode'.
If nil, it is initialized on entering `twittering-mode'.
The port number is specified by `twittering-https-proxy-port'.
For HTTP connection, the proxy specified by `twittering-http-proxy-server'
and `twittering-http-proxy-port' is used.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-https-proxy-port nil
  "*Port number of a HTTPS proxy server for `twittering-mode'.
If nil, it is initialized on entering `twittering-mode'.
The server is specified by `twittering-https-proxy-server'.
For HTTP connection, the proxy specified by `twittering-http-proxy-server'
and `twittering-http-proxy-port' is used.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-https-proxy-keep-alive nil
  "*If non-nil, the Keep-alive is enabled. This is experimental.")
(defvar twittering-https-proxy-user nil
  "*Username for `twittering-https-proxy-server'.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")
(defvar twittering-https-proxy-password nil
  "*Password for `twittering-https-proxy-server'.

NOTE: If both `twittering-proxy-server' and `twittering-proxy-port' are
non-nil, the variables `twittering-proxy-*' have priority over other
variables `twittering-http-proxy-*' or `twittering-https-proxy-*'
regardless of HTTP or HTTPS.")

(defcustom twittering-uri-regexp-to-proxy ".*"
  "Matched uri this will be retrieved via proxy.
See also `twittering-proxy-use', `twittering-proxy-server' and
`twittering-proxy-port'."
  :type 'string
  :group 'twittering)

(defun twittering-proxy-use-match (uri)
  (and twittering-proxy-use
       (string-match twittering-uri-regexp-to-proxy uri)))

(defun twittering-normalize-proxy-vars ()
  "Normalize the type of `twittering-http-proxy-port' and
`twittering-https-proxy-port'."
  (mapc (lambda (sym)
          (let ((value (symbol-value sym)))
            (cond
             ((null value)
              nil)
             ((integerp value)
              nil)
             ((stringp value)
              (set sym (string-to-number value)))
             (t
              (set sym nil)))))
        '(twittering-proxy-port
          twittering-http-proxy-port
          twittering-https-proxy-port)))

(defun twittering-proxy-info (scheme &optional item)
  "Return an alist for proxy configuration registered for SCHEME.
SCHEME must be a string \"http\", \"https\" or a symbol 'http or 'https.
The server name is a string and the port number is an integer."
  (twittering-normalize-proxy-vars)
  (let ((scheme (if (symbolp scheme)
                    (symbol-name scheme)
                  scheme))
        (info-list
         `((("http" "https")
            . ((server . ,twittering-proxy-server)
               (port . ,twittering-proxy-port)
               (keep-alive . ,twittering-proxy-keep-alive)
               (user . ,twittering-proxy-user)
               (password . ,twittering-proxy-password)))
           (("http")
            . ((server . ,twittering-http-proxy-server)
               (port . ,twittering-http-proxy-port)
               (keep-alive . ,twittering-http-proxy-keep-alive)
               (user . ,twittering-http-proxy-user)
               (password . ,twittering-http-proxy-password)))
           (("https")
            . ((server . ,twittering-https-proxy-server)
               (port . ,twittering-https-proxy-port)
               (keep-alive . ,twittering-https-proxy-keep-alive)
               (user . ,twittering-https-proxy-user)
               (password . ,twittering-https-proxy-password))))))
    (let ((info
           (car (remove nil
                        (mapcar
                         (lambda (entry)
                           (when (member scheme (car entry))
                             (let ((info (cdr entry)))
                               (when (and (assqref 'server info)
                                          (assqref 'port info))
                                 info))))
                         info-list)))))
      (if item
          (assqref item info)
        info))))

(defun twittering-url-proxy-services ()
  "Return the current proxy configuration for `twittering-mode' in the format
of `url-proxy-services'."
  (remove nil (mapcar
               (lambda (scheme)
                 (let ((server (twittering-proxy-info scheme 'server))
                       (port (twittering-proxy-info scheme 'port)))
                   (when (and server port)
                     `(,scheme . ,(format "%s:%s" server port)))))
               '("http" "https"))))

(defun twittering-find-proxy (scheme)
  "Find proxy server and its port from the environmental variables and return
a cons pair of them.
SCHEME must be \"http\" or \"https\"."
  (cond
   ((require 'url-methods nil t)
    (url-scheme-register-proxy scheme)
    (let* ((proxy-service (assoc scheme url-proxy-services))
           (proxy (if proxy-service (cdr proxy-service) nil)))
      (if (and proxy
               (string-match "^\\([^:]+\\):\\([0-9]+\\)$" proxy))
          (let ((host (match-string 1 proxy))
                (port (string-to-number (match-string 2 proxy))))
            (cons host port))
        nil)))
   (t
    (let* ((env-var (concat scheme "_proxy"))
           (env-proxy (or (getenv (upcase env-var))
                          (getenv (downcase env-var))))
           (default-port (if (string= "https" scheme) "443" "80")))
      (if (and env-proxy
               (string-match
                "^\\(https?://\\)?\\([^:/]+\\)\\(:\\([0-9]+\\)\\)?/?$"
                env-proxy))
          (let* ((host (match-string 2 env-proxy))
                 (port-str (or (match-string 4 env-proxy) default-port))
                 (port (string-to-number port-str)))
            (cons host port))
        nil)))))

(defun twittering-setup-proxy ()
  (when (require 'url-methods nil t)
    ;; If `url-scheme-registry' is not initialized,
    ;; `url-proxy-services' will be reset by calling
    ;; `url-insert-file-contents' or `url-retrieve-synchronously', etc.
    ;; To avoid it, initialize `url-scheme-registry' by calling
    ;; `url-scheme-get-property' before calling such functions.
    (url-scheme-get-property "http" 'name)
    (url-scheme-get-property "https" 'name))
  (unless (and twittering-http-proxy-server
               twittering-http-proxy-port)
    (let ((info (twittering-find-proxy "http")))
      (setq twittering-http-proxy-server (car-safe info))
      (setq twittering-http-proxy-port (cdr-safe info))))
  (unless (and twittering-https-proxy-server
               twittering-https-proxy-port)
    (let ((info (twittering-find-proxy "https")))
      (setq twittering-https-proxy-server (car-safe info))
      (setq twittering-https-proxy-port (cdr-safe info))))
  (if (and twittering-proxy-use
           (null (twittering-proxy-info "http"))
           (null (twittering-proxy-info "https")))
      (progn
        (error "Proxy enabled, but lack of configuration"))
    t))

(defun twittering-toggle-proxy ()
  (interactive)
  ;; (setq twittering-proxy-use
  ;;       (not twittering-proxy-use))
  ;; (if (twittering-setup-proxy)
  ;;     (message (if twittering-proxy-use "Use Proxy:on" "Use Proxy:off")))
  ;; (twittering-update-mode-line)
  (error "Not implemented yet"))

;;;;
;;;; Functions for URL library
;;;;

(defvar twittering-url-show-status nil
  "*Whether to show a running total of bytes transferred.")

(defadvice url-retrieve (around hexify-multibyte-string activate)
  (let ((url (ad-get-arg 0)))
    (if (twittering-multibyte-string-p url)
        (let ((url-unreserved-chars
               (append '(?: ?/ ??) url-unreserved-chars)))
          (ad-set-arg 0 (url-hexify-string url))
          ad-do-it)
      ad-do-it)))

(defun twittering-url-wrapper (func &rest args)
  (let ((url-proxy-services
	 (when (twittering-proxy-use-match (car args))
	   (twittering-url-proxy-services)))
	(url-show-status twittering-url-show-status))
    (if (eq func 'url-retrieve)
	(let ((buffer (apply func args)))
	  (when (buffer-live-p buffer)
	    (with-current-buffer buffer
	      (set (make-local-variable 'url-show-status)
		   twittering-url-show-status)))
	  buffer)
      (apply func args))))

(defun twittering-url-retrieve-synchronously (url)
  (twittering-url-wrapper 'url-retrieve-synchronously url))

  ;; (let ((request (twittering-make-http-request-from-uri
  ;; 		  "GET" nil url))
  ;; 	(additional-info `((url . ,url))))
  ;;   (lexical-let ((result 'queried))
  ;;     (twittering-send-http-request
  ;;      request additional-info
  ;;      (lambda (proc status connection-info header-info)
  ;; 	 (let ((status-line (cdr (assq 'status-line header-info)))
  ;; 	       (status-code (cdr (assq 'status-code header-info))))
  ;; 	   (case-string
  ;; 	    status-code
  ;; 	    (("200")
  ;; 	     (setq result (buffer-string))
  ;; 	     nil)
  ;; 	    (t
  ;; 	     (setq result nil)
  ;; 	     (format "Response: %s" status-line)))))
  ;;      (lambda (proc status connection-info)
  ;; 	 (when (and (memq status '(nil closed exit failed signal))
  ;; 		    (eq result 'queried))
  ;; 	   (setq result nil))))
  ;;     (while (eq result 'queried)
  ;; 	(sit-for 0.1))
  ;;     (if result
  ;; 	  result
  ;; 	(error "Failed to retrieve `%s'" url)
  ;; 	nil))))

;;;;
;;;; CA certificate
;;;;

(defvar twittering-cert-file nil)

(defun twittering-delete-ca-cert-file ()
  (when (and twittering-cert-file
             (file-exists-p twittering-cert-file))
    (delete-file twittering-cert-file)
    (setq twittering-cert-file nil)))

;; FIXME: file name is hard-coded. More robust way is desired.
;; https://www.geotrust.com/resources/root_certificates/certificates/Equifax_Secure_Certificate_Authority.cer
(defun twittering-ensure-ca-cert ()
  "Create a CA certificate file if it does not exist, and return
its file name. The certificate is retrieved from
`https://www.geotrust.com/resources/root_certificates/certificates/Equifax_Secure_Certificate_Authority.cer'."
  (if twittering-cert-file
      twittering-cert-file
    (let ((file-name (make-temp-file "twmode-cacert")))
      (with-temp-file file-name
        (insert "-----BEGIN CERTIFICATE-----
MIIDIDCCAomgAwIBAgIENd70zzANBgkqhkiG9w0BAQUFADBOMQswCQYDVQQGEwJV
UzEQMA4GA1UEChMHRXF1aWZheDEtMCsGA1UECxMkRXF1aWZheCBTZWN1cmUgQ2Vy
dGlmaWNhdGUgQXV0aG9yaXR5MB4XDTk4MDgyMjE2NDE1MVoXDTE4MDgyMjE2NDE1
MVowTjELMAkGA1UEBhMCVVMxEDAOBgNVBAoTB0VxdWlmYXgxLTArBgNVBAsTJEVx
dWlmYXggU2VjdXJlIENlcnRpZmljYXRlIEF1dGhvcml0eTCBnzANBgkqhkiG9w0B
AQEFAAOBjQAwgYkCgYEAwV2xWGcIYu6gmi0fCG2RFGiYCh7+2gRvE4RiIcPRfM6f
BeC4AfBONOziipUEZKzxa1NfBbPLZ4C/QgKO/t0BCezhABRP/PvwDN1Dulsr4R+A
cJkVV5MW8Q+XarfCaCMczE1ZMKxRHjuvK9buY0V7xdlfUNLjUA86iOe/FP3gx7kC
AwEAAaOCAQkwggEFMHAGA1UdHwRpMGcwZaBjoGGkXzBdMQswCQYDVQQGEwJVUzEQ
MA4GA1UEChMHRXF1aWZheDEtMCsGA1UECxMkRXF1aWZheCBTZWN1cmUgQ2VydGlm
aWNhdGUgQXV0aG9yaXR5MQ0wCwYDVQQDEwRDUkwxMBoGA1UdEAQTMBGBDzIwMTgw
ODIyMTY0MTUxWjALBgNVHQ8EBAMCAQYwHwYDVR0jBBgwFoAUSOZo+SvSspXXR9gj
IBBPM5iQn9QwHQYDVR0OBBYEFEjmaPkr0rKV10fYIyAQTzOYkJ/UMAwGA1UdEwQF
MAMBAf8wGgYJKoZIhvZ9B0EABA0wCxsFVjMuMGMDAgbAMA0GCSqGSIb3DQEBBQUA
A4GBAFjOKer89961zgK5F7WF0bnj4JXMJTENAKaSbn+2kmOeUJXRmm/kEd5jhW6Y
7qj/WsjTVbJmcVfewCHrPSqnI0kBBIZCe/zuf6IWUrVnZ9NA2zsmWLIodz2uFHdh
1voqZiegDfqnc1zqcPGUIWVEX/r87yloqaKHee9570+sB3c4
-----END CERTIFICATE-----
"))
      (add-hook 'kill-emacs-hook 'twittering-delete-ca-cert-file)
      (setq twittering-cert-file file-name))))

;;;;
;;;; User agent
;;;;

(defvar twittering-user-agent-function 'twittering-user-agent-default-function)

(defun twittering-user-agent-default-function ()
  "Twittering mode default User-Agent function."
  (format "Emacs/%d.%d Twittering-mode/%s"
          emacs-major-version emacs-minor-version
          twittering-mode-version))

(defun twittering-user-agent ()
  "Return User-Agent header string."
  (funcall twittering-user-agent-function))

;;;;
;;;; Basic HTTP functions (general)
;;;;

(defun twittering-percent-encode (str &optional coding-system)
  "Encode STR according to Percent-Encoding defined in RFC 3986."
  (twittering-oauth-url-encode str coding-system))

(defun twittering-lookup-connection-type (use-ssl &optional order table)
  "Return available entry extracted fron connection type table.
TABLE is connection type table, which is an alist of type symbol and its
item alist, such as
 '((native (check . t)
           (https . twittering-start-http-session-native-tls-p)
           (start . twittering-start-http-session-native))
   (curl (check . twittering-start-http-session-curl-p)
         (https . twittering-start-http-session-curl-https-p)
         (start . twittering-start-http-session-curl))) .
ORDER means the priority order of type symbols.
If USE-SSL is nil, the item `https' is ignored.
When the type `curl' has priority and is available for the above table,
the function returns
 '((check . twittering-start-http-session-curl-p)
   (https . twittering-start-http-session-curl-https-p)
   (start . twittering-start-http-session-curl)) ."
  (let ((rest (or order twittering-connection-type-order))
        (table (or table twittering-connection-type-table))
        (result nil))
    (while (and rest (null result))
      (let* ((candidate (car rest))
             (entry (cons `(symbol . ,candidate)
                          (assqref candidate table)))
             (entry (if (assq 'display-name entry)
                        entry
                      (cons `(display-name . ,(symbol-name candidate))
                            entry)))
             (validate (lambda (item)
                         (let ((v (assqref item entry)))
                           (or (null v) (eq t v) (functionp v)))))
             (confirm (lambda (item)
                        (let ((v (assqref item entry)))
                          (cond
                           ((null v) nil)
                           ((eq t v) t)
                           ((functionp v) (funcall v)))))))
        (if (and (funcall validate 'check)
                 (or (not use-ssl) (funcall validate 'https)))
            (cond
             ((and (funcall confirm 'check)
                   (or (not use-ssl) (funcall confirm 'https)))
              (setq rest nil)
              (setq result entry))
             (t
              (setq rest (cdr rest))))
          (message "The configuration for conncetion type `%s' is invalid."
                   candidate)
          (setq rest nil))))
    result))

(defun twittering-get-connection-method-name (use-ssl)
  "Return a name of the preferred connection method.
If USE-SSL is non-nil, return a connection method for HTTPS.
If USE-SSL is nil, return a connection method for HTTP."
  (assqref 'display-name (twittering-lookup-connection-type use-ssl)))

(defun twittering-lookup-http-start-function (&optional order table)
  "Decide a connection method from currently available methods."
  (let ((entry
         (twittering-lookup-connection-type twittering-use-ssl order table)))
    (assqref 'send-http-request entry)))

(defun twittering-ensure-connection-method (&optional order table)
  "Ensure a connection method with a compromise.
Return nil if no connection methods are available with a compromise."
  (let* ((use-ssl (or twittering-use-ssl twittering-oauth-use-ssl))
         (entry (twittering-lookup-connection-type use-ssl order table)))
    (cond
     (entry
      t)
     ((and (null entry) use-ssl
           (yes-or-no-p "HTTPS(SSL) is unavailable. Use HTTP instead? "))
      ;; Fall back on connection without SSL.
      (setq twittering-use-ssl nil)
      (setq twittering-oauth-use-ssl nil)
      (twittering-update-mode-line)
      (twittering-ensure-connection-method order table)
      t)
     (t
      nil))))

(defun twittering-make-http-request (method header-list host port path query-parameters post-body use-ssl)
  "Returns an alist specifying a HTTP request.
METHOD specifies HTTP method. It must be \"GET\" or \"POST\".
HEADER-LIST is a list of (field-name . field-value) specifying HTTP header
fields. The fields \"Host\", \"User-Agent\" and \"Content-Length\" are
automatically filled if necessary.
HOST specifies the host.
PORT specifies the port. This must be an integer.
PATH specifies the absolute path in URI (without query string).
QUERY-PARAMTERS is a string or an alist.
If QUERY-PARAMTERS is a string, it is treated as an encoded query string.
If QUERY-PARAMTERS is an alist, it represents a list of cons pairs of
string, (query-key . query-value).
POST-BODY specifies the post body sent when METHOD equals to \"POST\".
If POST-BODY is nil, no body is posted.
If USE-SSL is non-nil, the request is performed with SSL.

The result alist includes the following keys, where a key is a symbol.
  method: HTTP method such as \"GET\" or \"POST\".
  scheme: the scheme name. \"http\" or \"https\".
  host: the host to which the request is sent.
  port: the port to which the request is sent (integer).
  path: the absolute path string. Note that it does not include query string.
  query-string: the query string.
  encoded-query-alist: the alist consisting of pairs of encoded query-name and
    encoded query-value.
  uri: the URI. It includes the query string.
  uri-without-query: the URI without the query string.
  header-list: an alist specifying pairs of a parameter and its value in HTTP
    header field.
  post-body: the entity that will be posted."
  (let* ((scheme (if use-ssl "https" "http"))
         (default-port (if use-ssl 443 80))
         (port (if port port default-port))
         (query-string
          (cond
           ((stringp query-parameters)
            query-parameters)
           ((consp query-parameters)
            (mapconcat (lambda (pair)
                         (cond
                          ((stringp pair)
                           (twittering-percent-encode pair))
                          ((consp pair)
                           (format
                            "%s=%s"
                            (twittering-percent-encode (car pair))
                            (twittering-percent-encode (cdr pair))))
                          (t
                           nil)))
                       query-parameters
                       "&"))
           (t
            nil)))
         (encoded-query-alist
          (cond
           ((stringp query-parameters)
            ;; Query name and its value must be already encoded.
            (mapcar (lambda (str)
                      (if (string-match "=" str)
                          (let ((key (substring str 0 (match-beginning 0)))
                                (value (substring str (match-end 0))))
                            `(,key . ,value))
                        `(,str . nil)))
                    (split-string query-parameters "&")))
           ((consp query-parameters)
            (mapcar (lambda (pair)
                      (cond
                       ((stringp pair)
                        (cons (twittering-percent-encode pair) nil))
                       ((consp pair)
                        (cons (twittering-percent-encode (car pair))
                              (twittering-percent-encode (cdr pair))))
                       (t
                        nil)))
                    query-parameters))
           (t
            nil)))
         (uri-without-query
          (concat scheme "://"
                  host
                  (when (and port (not (= port default-port)))
                    (format ":%d" port))
                  path))
         (uri
          (if query-string
              (concat uri-without-query "?" query-string)
            uri-without-query))
         (header-list
          `(,@(when (and (string= method "POST")
                         (not (assoc "Content-Length" header-list)))
                `(("Content-Length" . ,(format "%d" (length post-body)))))
            ,@(unless (assoc "Host" header-list)
                `(("Host" . ,host)))
            ,@(unless (assoc "User-Agent" header-list)
                `(("User-Agent" . ,(twittering-user-agent))))
            ,@header-list)))
    (cond
     ((not (member method '("POST" "GET")))
      (error "Unknown HTTP method: %s" method)
      nil)
     ((not (string-match "^/" path))
      (error "Invalid HTTP path: %s" path)
      nil)
     (t
      `((method . ,method)
        (scheme . ,scheme)
        (host . ,host)
        (port . ,port)
        (path . ,path)
        (query-string . ,query-string)
        (encoded-query-alist . ,encoded-query-alist)
        (uri . ,uri)
        (uri-without-query . ,uri-without-query)
        (header-list . ,header-list)
        (post-body . ,post-body))))))

(defun twittering-make-http-request-from-uri (method header-list uri &optional post-body)
  "Returns an alist specifying a HTTP request.
The result alist has the same form as an alist generated by
`twittering-make-http-request'.

METHOD specifies HTTP method. It must be \"GET\" or \"POST\".
HEADER-LIST is a list of (field-name . field-value) specifying HTTP header
fields. The fields \"Host\" and \"User-Agent\" are automatically filled
if necessary.
URI specifies the URI including query string.
POST-BODY specifies the post body sent when METHOD equals to \"POST\".
If POST-BODY is nil, no body is posted."
  (let* ((parts-alist
          (let ((parsed-url (url-generic-parse-url uri)))
            ;; This is required for the difference of url library
            ;; distributed with Emacs 22 and 23.
            (cond
             ((and (fboundp 'url-p) (url-p parsed-url))
              ;; Emacs 23 and later.
              `((scheme . ,(url-type parsed-url))
                (host . ,(url-host parsed-url))
                (port . ,(url-portspec parsed-url))
                (path . ,(url-filename parsed-url))))
             ((vectorp parsed-url)
              ;; Emacs 22.
              `((scheme . ,(aref parsed-url 0))
                (host . ,(aref parsed-url 3))
                (port . ,(aref parsed-url 4))
                (path . ,(aref parsed-url 5))))
             (t
              nil))))
         (path (let ((path (assqref 'path parts-alist)))
                 (if (string-match "\\`\\(.*\\)\\?" path)
                     (match-string 1 path)
                   path)))
         (query-string (let ((path (assqref 'path parts-alist)))
                         (if (string-match "\\?\\(.*\\)\\'" path)
                             (match-string 1 path)
                           nil))))
    (twittering-make-http-request method header-list
                                  (assqref 'host parts-alist)
                                  (assqref 'port parts-alist)
                                  path
                                  query-string
                                  post-body
                                  (string= "https"
                                           (assqref 'scheme parts-alist)))))

(defun twittering-make-connection-info (request &optional additional order table)
  "Make an alist specifying the information of connection for REQUEST.
REQUEST must be an alist that has the same keys as that generated by
`twittering-make-http-request'.

ADDITIONAL is appended to the tail of the result alist.
Following ADDITIONAL, an entry in TABLE is also appended to the result alist,
where `twittering-lookup-connection-type' determines the entry according to
the priority order ORDER.
If ORDER is nil, `twittering-connection-type-order' is used in place of ORDER.
If TABLE is nil, `twittering-connection-type-table' is used in place of TABLE.

The parameter symbols are following:
  use-ssl: whether SSL is enabled or not.
  allow-insecure-server-cert: non-nil if an insecure server certificate is
    allowed on SSL.
  cacert-fullpath: the full-path of the certificate authorizing a server
    certificate on SSL.
  use-proxy: non-nil if using a proxy.
  proxy-server: a proxy server or nil.
  proxy-port: a port for connecting the proxy (integer) or nil.
  proxy-user: a username for connecting the proxy or nil.
  proxy-password: a password for connecting the proxy or nil.
  request: an alist specifying a HTTP request."
  (let* ((order (or order twittering-connection-type-order))
         (table (or table twittering-connection-type-table))
         (scheme (assqref 'scheme request))
         (use-ssl (string= "https" scheme))
	 (use-proxy (twittering-proxy-use-match (assqref 'host request)))
         (entry (twittering-lookup-connection-type use-ssl order table)))
    `((use-ssl . ,use-ssl)
      (allow-insecure-server-cert
       . ,twittering-allow-insecure-server-cert)
      (cacert-fullpath
       . ,(when use-ssl (twittering-ensure-ca-cert)))
      (use-proxy . ,use-proxy)
      ,@(when use-proxy
          `((proxy-server . ,(twittering-proxy-info scheme 'server))
            (proxy-port . ,(twittering-proxy-info scheme 'port))
            (proxy-user . ,(if use-ssl
                               twittering-https-proxy-user
                             twittering-http-proxy-user))
            (proxy-password . ,(if use-ssl
                                   twittering-https-proxy-password
                                 twittering-http-proxy-password))))
      (request . ,request)
      ,@additional
      ,@entry)))

(defun twittering-get-response-header (buffer)
  "Extract HTTP response header from HTTP response.
BUFFER may be a buffer or the name of an existing buffer which contains the HTTP response."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (if (search-forward-regexp "\r?\n\r?\n" nil t)
          (buffer-substring (point-min) (match-end 0))
        nil))))

(defun twittering-make-header-info-alist (header-str)
  "Make HTTP header alist from HEADER-STR.
The alist consists of pairs of field-name and field-value, such as
'((\"Content-Type\" . \"application/xml\; charset=utf-8\")
  (\"Content-Length\" . \"2075\"))."
  (let* ((lines (split-string header-str "\r?\n"))
         (status-line (car lines))
         (header-lines (cdr lines)))
    (when (string-match
           "^\\(HTTP/1\.[01]\\) \\([0-9][0-9][0-9]\\) \\(.*\\)$"
           status-line)
      (append `((status-line . ,status-line)
                (http-version . ,(match-string 1 status-line))
                (status-code . ,(match-string 2 status-line))
                (reason-phrase . ,(match-string 3 status-line)))
              (remove nil
                      (mapcar
                       (lambda (line)
                         (when (string-match "^\\([^: ]*\\): *\\(.*\\)$" line)
                           (cons (match-string 1 line) (match-string 2 line))))
                       header-lines))))))

(defun twittering-send-http-request-internal (request additional-info sentinel &optional order table)
  "Open a connection and return a subprocess object for the connection.
REQUEST must be an alist that has the same keys as that generated by
`twittering-make-http-request'.
SENTINEL is called as a function when the process changes state.
It gets three arguments: the process, a string describing the change, and
the connection-info, which is generated by `twittering-make-connection-info'
and also includes an alist ADDITIONAL-INFO.

How to perform the request is selected from TABLE according to the priority
order ORDER. ORDER and TABLE are directly sent to
`twittering-make-connection-info'.
If ORDER is nil, `twittering-connection-type-order' is used in place of ORDER.
If TABLE is nil, `twittering-connection-type-table' is used in place of TABLE.
"
  (let* ((order (or order twittering-connection-type-order))
         (table (or table twittering-connection-type-table))
         (connection-info
          (twittering-make-connection-info request additional-info
                                           order table))
         (func (assqref 'send-http-request connection-info))
         (temp-buffer (generate-new-buffer "*twmode-http-buffer*")))
    (when (and func (functionp func))
      (funcall func "*twmode-generic*" temp-buffer
               connection-info
               (when (and sentinel (functionp sentinel))
                 (lexical-let ((sentinel sentinel)
                               (connection-info connection-info))
                   (lambda (proc status)
                     (apply sentinel proc status connection-info nil))))))))

(defun twittering-send-http-request (request additional-info func &optional clean-up-func)
  "Send a HTTP request and return a subprocess object for the connection.
REQUEST must be an alist that has the same keys as that generated by
`twittering-make-http-request'.

FUNC is called when a HTTP response has been received without errors.
It is called with the current buffer containing the HTTP response (without
HTTP headers). FUNC is called with four arguments: the process, a symbol
describing the status of the process, a connection-info generated by
`twittering-make-connection-info', and a header-info generated by
`twittering-get-response-header'.
The connection-info also includes an alist ADDITIONAL-INFO.
If FUNC returns non-nil and `twittering-buffer-related-p' is non-nil, the
returned value is displayed as a message.

CLEAN-UP-FUNC is called whenever the sentinel of the subprocess for the
connection is called (as `set-process-sentinel').
It is called with three arguments: the process, a symbol describing the status
of the proess, and a connection-info generated by
`twittering-make-connection-info'.
They are the same as arguments for FUNC.
When a HTTP response has been received, FUNC is called in advance of
CLEAN-UP-FUNC. CLEAN-UP-FUNC can overwrite the message displayed by FUNC.

If the subprocess has exited, the buffer bound to it is automatically killed
after calling CLEAN-UP-FUNC.

The method to perform the request is determined from
`twittering-connection-type-table' according to the priority order
`twittering-connection-type-order'."
  (lexical-let ((func func)
                (clean-up-func clean-up-func)
		(twittering-service-method twittering-service-method))
    (twittering-send-http-request-internal
     request additional-info
     (lambda (proc status-str connection-info)
       (let ((status (cond
                      ((string= status-str "urllib-finished") 'exit)
                      ((processp proc) (process-status proc))
                      (t nil)))
             (buffer (process-buffer proc))
             (exit-status (cond
                           ((string= status-str "urllib-finished") 0)
                           ((processp proc) (process-exit-status proc))
                           (t 1)))
             (command (process-command proc))
             (pre-process-func
              (assqref 'pre-process-buffer connection-info))
             (mes nil))
         (unwind-protect
             (setq mes
                   (cond
                    ((null status)
                     (format "Failure: process %s does not exist." proc))
                    ((or (memq status '(run stop open listen connect))
                         (not (memq status '(exit signal closed failed))))
                     ;; If the process is running, FUNC is not called.
                     nil)
                    ((and command
                          (not (= 0 exit-status)))
                     ;; If the process abnormally exited,
                     (format "Failure: %s exited abnormally (exit-status=%s)."
                             (car command) exit-status))
                    ((not (buffer-live-p buffer))
                     (format "Failure: the buffer for %s is already killed."
                             proc))
                    (t
                     (when (functionp pre-process-func)
                       ;; Pre-process buffer.
                       (funcall pre-process-func proc buffer connection-info))
                     (let* ((header (twittering-get-response-header buffer))
                            (header-info
                             (and header
                                  (twittering-update-server-info header))))
                       (with-current-buffer buffer
                         (goto-char (point-min))
                         (when (search-forward-regexp "\r?\n\r?\n" nil t)
                           ;; delete HTTP headers.
                           (delete-region (point-min) (match-end 0)))
                         (apply func proc status connection-info
                                header-info nil))))))
           ;; unwind-forms
           (when (and mes (or (twittering-buffer-related-p)
			      ;; (twittering-account-authorization-queried-p)
			      ))
             ;; CLEAN-UP-FUNC can overwrite a message from the return value
             ;; of FUNC.
             (message "%s" mes))
           (when (functionp clean-up-func)
             (funcall clean-up-func proc status connection-info))
           (when (and (memq status '(exit signal closed failed))
                      (buffer-live-p buffer)
                      (not twittering-debug-mode))
             (kill-buffer buffer))))))))

;;;;
;;;; Basic HTTP functions with tls and Emacs builtins.
;;;;

(eval-when-compile (require 'tls nil t))
(defun twittering-start-http-session-native-tls-p ()
  (when (and (not twittering-proxy-use)
             (require 'tls nil t))
    (unless twittering-tls-program
      (let ((programs
             (remove nil
                     (mapcar (lambda (cmd)
                               (when (string-match "\\`\\([^ ]+\\) " cmd)
                                 (when (executable-find (match-string 1 cmd))
                                   cmd)))
                             tls-program))))
        (setq twittering-tls-program
              (if twittering-allow-insecure-server-cert
                  (mapcar
                   (lambda (str)
                     (cond
                      ((string-match "^\\([^ ]*/\\)?openssl s_client " str)
                       (concat (match-string 0 str) "-verify 0 "
                               (substring str (match-end 0))))
                      ((string-match "^\\([^ ]*/\\)?gnutls-cli " str)
                       (concat (match-string 0 str) "--insecure "
                               (substring str (match-end 0))))
                      (t
                       str)))
                   programs)
                programs))))
    (not (null twittering-tls-program))))

;; TODO: proxy
(defun twittering-send-http-request-native (name buffer connection-info sentinel)
  (let* ((request (assqref 'request connection-info))
         (method (assqref 'method request))
         (scheme (assqref 'scheme request))
         (host (assqref 'host request))
         (port (assqref 'port request))
         (path (assqref 'path request))
         (query-string (assqref 'query-string request))
         (header-list (assqref 'header-list request))
         (post-body (assqref 'post-body request))
         (use-proxy (assqref 'use-proxy connection-info))
         (proxy-server (assqref 'proxy-server connection-info))
         (proxy-port (assqref 'proxy-port connection-info))
         (proxy-user (assqref 'proxy-user connection-info))
         (proxy-password (assqref 'proxy-password connection-info))
         (use-ssl (assqref 'use-ssl connection-info))
         (allow-insecure-server-cert
          (assqref 'allow-insecure-server-cert connection-info))
         (cacert-fullpath (assqref 'cacert-fullpath connection-info))
         (cacert-dir (when cacert-fullpath
                       (file-name-directory cacert-fullpath)))
         (cacert-filename (when cacert-fullpath
                            (file-name-nondirectory cacert-fullpath)))
         (proxy-info
          (when (twittering-proxy-use-match host)
            (twittering-proxy-info scheme)))
         (connect-host (if proxy-info
                           (assqref 'server proxy-info)
                         host))
         (connect-port (if proxy-info
                           (assqref 'port proxy-info)
                         port))
         (request-str
          (format "%s %s%s HTTP/1.1\r\n%s\r\n\r\n%s\r\n"
                  method path
                  (if query-string
                      (concat "?" query-string)
                    "")
                  (mapconcat (lambda (pair)
                               (format "%s: %s" (car pair) (cdr pair)))
                             header-list "\r\n")
                  (or post-body "")))
         (coding-system-for-read 'binary)
         (coding-system-for-write 'binary)
         (tls-program twittering-tls-program)
         (proc
          (funcall (if use-ssl
                       'open-tls-stream
                     'open-network-stream)
                   "network-connection-process"
                   nil connect-host connect-port)))
    (when proc
      (set-process-buffer proc buffer)
      (set-process-sentinel proc sentinel)
      (process-send-string proc request-str)
      proc)))

(defun twittering-pre-process-buffer-native (proc buffer connection-info)
  (let ((use-ssl (assqref 'use-ssl connection-info))
        (args (process-command proc)))
    (cond
     ((and use-ssl args
           (car
            (remove nil
                    (mapcar (lambda (cmd)
                              (string-match "^\\(.*/\\)?gnutls-cli\\b" cmd))
                            args))))
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-max))
          (when (search-backward-regexp
                 "- Peer has closed the GNUTLS connection\r?\n\\'")
            (let ((beg (match-beginning 0))
                  (end (match-end 0)))
              (delete-region beg end))))))
     ((and use-ssl args
           (car
            (remove nil
                    (mapcar
                     (lambda (cmd)
                       (string-match "^\\(.*/\\)?openssl s_client\\b" cmd))
                     args))))
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-max))
          (when (search-backward-regexp "closed\r?\n\\'")
            (let ((beg (match-beginning 0))
                  (end (match-end 0)))
              (delete-region beg end))))))
     (t
      nil))))

;;;;
;;;; Basic HTTP functions with curl
;;;;

(defun twittering-find-curl-program ()
  "Returns an appropriate `curl' program pathname or nil if not found."
  (or (executable-find "curl")
      (let ((windows-p (memq system-type '(windows-nt cygwin)))
            (curl.exe
             (expand-file-name
              "curl.exe"
              (expand-file-name
               "win-curl"
               (file-name-directory (symbol-file 'twit))))))
        (and windows-p
             (file-exists-p curl.exe) curl.exe))))

(defun twittering-start-http-session-curl-p ()
  "Return t if curl was installed, otherwise nil."
  (unless twittering-curl-program
    (setq twittering-curl-program (twittering-find-curl-program)))
  (not (null twittering-curl-program)))

(defun twittering-start-http-session-curl-https-p ()
  "Return t if curl was installed and the curl support HTTPS, otherwise nil."
  (when (twittering-start-http-session-curl-p)
    (unless twittering-curl-program-https-capability
      (with-temp-buffer
        (call-process twittering-curl-program
                      nil (current-buffer) nil
                      "--version")
        (goto-char (point-min))
        (setq twittering-curl-program-https-capability
              (if (search-forward-regexp "^Protocols: .*https" nil t)
                  'capable
                'incapable))))
    (eq twittering-curl-program-https-capability 'capable)))

(defun twittering-send-http-request-curl (name buffer connection-info sentinel)
  (let* ((request        (assqref 'request        connection-info))
         (method         (assqref 'method         request))
         (uri            (assqref 'uri            request))
         (header-list    (assqref 'header-list    request))
         (post-body      (assqref 'post-body      request))
         (use-proxy      (assqref 'use-proxy      connection-info))
         (proxy-server   (assqref 'proxy-server   connection-info))
         (proxy-port     (assqref 'proxy-port     connection-info))
         (proxy-user     (assqref 'proxy-user     connection-info))
         (proxy-password (assqref 'proxy-password connection-info))
         (use-ssl        (assqref 'use-ssl        connection-info))
         (allow-insecure-server-cert
          (assqref 'allow-insecure-server-cert connection-info))
         (cacert-fullpath (assqref 'cacert-fullpath connection-info))
         (cacert-dir (when cacert-fullpath
                       (file-name-directory cacert-fullpath)))
         (cacert-filename (when cacert-fullpath
                            (file-name-nondirectory cacert-fullpath)))
         (header-list
          `(,@header-list
            ;; Make `curl' remove the HTTP header field "Expect" for
            ;; avoiding '417 Expectation Failed' HTTP response error.
            ;; The header field is automatically added for a HTTP request
            ;; exceeding 1024 byte. See
            ;; http://d.hatena.ne.jp/imait/20091228/1262004813 and
            ;; http://www.escafrace.co.jp/blog/09/10/16/1008
            ("Expect" . "")))
         (curl-args
          `("--include" "--silent"
            ,@(apply 'append
                     (mapcar
                      (lambda (pair)
                        ;; Do not overwrite internal headers `curl' would use.
                        ;; Thanks to William Xu.
                        ;; "cURL - How To Use"
                        ;; http://curl.haxx.se/docs/manpage.html
                        (unless (string= (car pair) "Host")
                          `("-H" ,(format "%s: %s" (car pair) (cdr pair)))))
                      header-list))
            ,@(when use-ssl `("--cacert" ,cacert-filename))
            ,@(when (and use-ssl allow-insecure-server-cert)
                `("--insecure"))
            ,@(when (and use-proxy proxy-server proxy-port)
                (append
                 `("-x" ,(format "%s:%s" proxy-server proxy-port))
                 (when (and proxy-user proxy-password)
                   `("-U" ,(format "%s:%s" proxy-user proxy-password)))))
            ,@(when (string= "POST" method)
                (let ((opt
                       (if (twittering-is-uploading-file-p post-body)
                           "-F"
                         "-d")))
                  ;; (or (mapcan (lambda (pair)
                  ;;               (let ((n (car pair))
                  ;;                     (v (cdr pair)))
                  ;;                 (when (string= opt "-d")
                  ;;                   (setq n (twittering-percent-encode n)
                  ;;                         v (twittering-percent-encode v)))
                  ;;                 (list opt (format "%s=%s" n v))))
                  ;;             post-body)

		  ;; Even if no data to post.. or it will fail for favorite,
		  ;; retweet, etc.  This is to ensure curl will use POST?
		  `(,opt ,(or post-body ""))))
            ,uri))
         (coding-system-for-read 'binary)
         (coding-system-for-write 'binary)
         (default-directory
           ;; If `use-ssl' is non-nil, the `curl' process
           ;; is executed at the same directory as the temporary cert file.
           ;; Without changing directory, `curl' misses the cert file if
           ;; you use Emacs on Cygwin because the path on Emacs differs
           ;; from Windows.
           ;; With changing directory, `curl' on Windows can find the cert
           ;; file if you use Emacs on Cygwin.
           (if use-ssl
               cacert-dir
             default-directory))
         (proc (apply 'start-process name buffer
                      twittering-curl-program curl-args)))
    (when (and proc (functionp sentinel))
      (set-process-sentinel proc sentinel))
    proc))

(defun twittering-pre-process-buffer-curl (proc buffer connection-info)
  (let ((use-ssl (assqref 'use-ssl connection-info))
        (use-proxy (assqref 'use-proxy connection-info)))
    (when (and use-ssl use-proxy)
      ;; When using SSL via a proxy with CONNECT method,
      ;; omit a successful HTTP response and headers if they seem to be
      ;; sent from the proxy.
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (let ((first-regexp
                 ;; successful HTTP response
                 "\\`HTTP/1\.[01] 2[0-9][0-9] .*?\r?\n")
                (next-regexp
                 ;; following HTTP response
                 "^\\(\r?\n\\)HTTP/1\.[01] [0-9][0-9][0-9] .*?\r?\n"))
            (when (and (search-forward-regexp first-regexp nil t)
                       (search-forward-regexp next-regexp nil t))
              (let ((beg (point-min))
                    (end (match-end 1)))
                (delete-region beg end)))))))))

;;;;
;;;; Basic HTTP functions with wget
;;;;

(defun twittering-find-wget-program ()
  "Returns an appropriate `wget' program pathname or nil if not found."
  (executable-find "wget"))

(defun twittering-start-http-session-wget-p ()
  "Return t if `wget' was installed, otherwise nil."
  (unless twittering-wget-program
    (setq twittering-wget-program (twittering-find-wget-program)))
  (not (null twittering-wget-program)))

(defun twittering-send-http-request-wget (name buffer connection-info sentinel)
  (let* ((request (assqref 'request connection-info))
         (method (assqref 'method request))
         (scheme (assqref 'scheme request))
         (uri (assqref 'uri request))
         (header-list (assqref 'header-list request))
         (post-body (assqref 'post-body request))
         (use-proxy (assqref 'use-proxy connection-info))
         (proxy-server (assqref 'proxy-server connection-info))
         (proxy-port (assqref 'proxy-port connection-info))
         (proxy-user (assqref 'proxy-user connection-info))
         (proxy-password (assqref 'proxy-password connection-info))
         (use-ssl (assqref 'use-ssl connection-info))
         (allow-insecure-server-cert
          (assqref 'allow-insecure-server-cert connection-info))
         (cacert-fullpath (assqref 'cacert-fullpath connection-info))
         (cacert-dir (when cacert-fullpath
                       (file-name-directory cacert-fullpath)))
         (cacert-filename (when cacert-fullpath
                            (file-name-nondirectory cacert-fullpath)))
         (args
          `("--save-headers"
            "--quiet"
            "--output-document=-"
            ,@(remove nil
                      (mapcar
                       (lambda (pair)
                         (unless (string= (car pair) "Host")
                           (format "--header=%s: %s" (car pair) (cdr pair))))
                       header-list))
            ,@(when use-ssl
                `(,(format "--ca-certificate=%s" cacert-filename)))
            ,@(when (and use-ssl allow-insecure-server-cert)
                `("--no-check-certificate"))
            ,@(cond
               ((not use-proxy)
                '("--no-proxy"))
               ((and use-proxy proxy-server proxy-port
                     proxy-user proxy-password)
                `(,(format "--proxy-user=%s" proxy-user)
                  ,(format "--proxy-password=%s" proxy-password)))
               (t
                nil))
            ,@(when (string= "POST" method)
                `(,(concat "--post-data=" (or post-body ""))))
            ,uri))
         (coding-system-for-read 'binary)
         (coding-system-for-write 'binary)
         (default-directory
           ;; If `use-ssl' is non-nil, the `wget' process
           ;; is executed at the same directory as the temporary cert file.
           ;; Without changing directory, `wget' misses the cert file if
           ;; you use Emacs on Cygwin because the path on Emacs differs
           ;; from Windows.
           ;; With changing directory, `wget' on Windows can find the cert
           ;; file if you use Emacs on Cygwin.
           (if use-ssl
               cacert-dir
             default-directory))
         (process-environment
          `(,@(when (and use-proxy proxy-server proxy-port)
                `(,(format "%s_proxy=%s://%s:%s/" scheme
                           scheme proxy-server proxy-port)))
            ,@process-environment))
         (proc
          (apply 'start-process name buffer twittering-wget-program args)))
    (when (and proc (functionp sentinel))
      (set-process-sentinel proc sentinel))
    proc))

(defun twittering-pre-process-buffer-wget (proc buffer connection-info)
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (search-forward-regexp "\\`[^\n]*?\r\r\n" (point-max) t)
        ;; When `wget.exe' writes HTTP response in text mode,
        ;; CRLF may be converted into CRCRLF.
        (goto-char (point-min))
        (while (search-forward "\r\n" nil t)
          (replace-match "\n" nil t)))
      (goto-char (point-max))
      (when (search-backward-regexp "\nProcess [^\n]* finished\n\\'"
                                    (point-min) t)
        (replace-match "" nil t))
      )))

;;;;
;;;; Basic HTTP functions with url library
;;;;

(defun twittering-start-http-session-urllib-p ()
  "Return t if url library is available, otherwise nil."
  (require 'url nil t))

(defun twittering-start-http-session-urllib-https-p ()
  "Return t if url library can be used for HTTPS, otherwise nil."
  (and (not twittering-proxy-use)
       (require 'url nil t)
       (cond
        ((<= 22 emacs-major-version)
         ;; On Emacs22 and later, `url' requires `tls'.
         (twittering-start-http-session-native-tls-p))
        ((require 'ssl nil t)
         ;; On Emacs21, `url' requires `ssl'.
         t)
        ((or (and (fboundp 'open-ssl-stream)
                  ;; Since `url-gw' (required by `url') defines autoload of
                  ;; `open-ssl-stream' from "ssl",
                  ;; (fboundp 'open-ssl-stream) will be non-nil even if
                  ;; "ssl" cannot be loaded and `open-ssl-stream' is
                  ;; unavailable.
                  ;; Here, the availability is confirmed by `documentation'.
                  (documentation 'open-ssl-stream))
             ;; On Emacs21, `url' requires `ssl' in order to use
             ;; `open-ssl-stream', which is included in `ssl.el'.
             ;; Even if `ssl' cannot be loaded, `open-tls-stream' can be
             ;; used as an alternative of the function.
             (and (twittering-start-http-session-native-tls-p)
                  (defalias 'open-ssl-stream 'open-tls-stream)))
         (provide 'ssl)
         t)
        (t
         nil))))

(defun twittering-send-http-request-urllib (name buffer connection-info sentinel)
  (let* ((request (assqref 'request connection-info))
         (method (assqref 'method request))
         (scheme (assqref 'scheme request))
         (uri (assqref 'uri request))
         (header-list (assqref 'header-list request))
         (post-body (assqref 'post-body request))
         (use-proxy (assqref 'use-proxy connection-info))
         (proxy-server (assqref 'proxy-server connection-info))
         (proxy-port (assqref 'proxy-port connection-info))
         (coding-system-for-read 'binary)
         (coding-system-for-write 'binary)
         (url-proxy-services
          (when use-proxy
            `((,scheme . ,(format "%s:%s" proxy-server proxy-port)))))
         (url-request-method method)
         (url-request-extra-headers
          ;; Remove some headers that should be configured by url library.
          ;; They may break redirections by url library because
          ;; `url-request-extra-headers' overwrites the new headers
          ;; that are adapted to redirected connection.
          (apply 'append
                 (mapcar (lambda (pair)
                           (if (member (car pair)
                                       '("Host" "Content-Length"))
                               nil
                             `(,pair)))
                         header-list)))
         (url-request-data post-body)
         (url-show-status twittering-url-show-status)
         (url-http-attempt-keepalives nil)
         (tls-program twittering-tls-program)
         (coding-system-for-read 'binary)
         (coding-system-for-write 'binary))
    (lexical-let ((sentinel sentinel)
                  (buffer buffer))
      (let ((result-buffer
             (url-retrieve
              uri
              (lambda (&rest args)
                (let ((proc url-http-process)
                      (url-buffer (current-buffer))
                      (status-str
                       (if (and (< emacs-major-version 22)
                                (boundp 'url-http-end-of-headers)
                                url-http-end-of-headers)
                           "urllib-finished"
                         "finished")))
                  ;; Callback may be called multiple times.
                  ;; (as filter and sentinel?)
                  (unless (local-variable-if-set-p 'twittering-retrieved)
                    (set (make-local-variable 'twittering-retrieved)
                         'not-completed)
                    (with-current-buffer buffer
                      (set-buffer-multibyte nil)
                      (insert-buffer-substring url-buffer))
                    (set-process-buffer proc buffer)
                    (unwind-protect
                        (apply sentinel proc status-str nil)
                      (set-process-buffer proc url-buffer)
                      (if (eq twittering-retrieved 'exited)
                          (url-mark-buffer-as-dead url-buffer)
                        (setq twittering-retrieved 'completed))))
                  (when (memq (process-status proc)
                              '(nil closed exit failed signal))
                    ;; Mark `url-buffer' as dead when the process exited
                    ;; and `sentinel' is completed.
                    ;; If this `lambda' is evaluated via a filter, the
                    ;; process may exit before it is finished to evaluate
                    ;; `(apply sentinel ...)'. In the case, `buffer' should
                    ;; not be killed. It should be killed after the
                    ;; evaluation of `sentinel'.
                    (if (eq twittering-retrieved 'completed)
                        (url-mark-buffer-as-dead url-buffer)
                      (setq twittering-retrieved 'exited))))))))
        (when (buffer-live-p result-buffer)
          (with-current-buffer result-buffer
            (set (make-local-variable 'url-show-status)
                 twittering-url-show-status)
            ;; Make `url-http-attempt-keepalives' buffer-local
            ;; in order to send the current value of the variable
            ;; to the sentinel invoked for HTTP redirection,
            (make-local-variable 'url-http-attempt-keepalives))
          (get-buffer-process result-buffer))))))

(defun twittering-pre-process-buffer-urllib (proc buffer connection-info)
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (cond
       ((search-backward-regexp
         "- Peer has closed the GNUTLS connection\r?\n\\'"
         nil t)
        (let ((beg (match-beginning 0))
              (end (match-end 0)))
          (delete-region beg end)))
       ((search-backward-regexp "closed\r?\n\\'" nil t)
        (let ((beg (match-beginning 0))
              (end (match-end 0)))
          (delete-region beg end)))
       (t nil)))))

;;;;
;;;; HTTP functions for twitter-like serivce
;;;;

(defun twittering-http-application-headers (&optional method headers)
  "Return an assoc list of HTTP headers for twittering-mode."
  (unless method
    (setq method "GET"))

  (let ((headers headers))
    (push (cons "User-Agent" (twittering-user-agent)) headers)
    (when (string= "GET" method)
      (push (cons "Accept"
                  (concat
                   "text/xml"
                   ",application/xml"
                   ",application/xhtml+xml"
                   ",application/html;q=0.9"
                   ",text/plain;q=0.8"
                   ",image/png,*/*;q=0.5"))
            headers)
      (push (cons "Accept-Charset" "utf-8;q=0.7,*;q=0.7")
            headers))
    (when (string= "POST" method)
      (push (cons "Content-Type" "text/plain") headers))
    ;; This makes update-profile-image fail.
    ;; (when (string= "POST" method)
    ;;   (push (cons "Content-Length" "0") headers)
    ;;   (push (cons "Content-Type" "text/plain") headers))
    (when twittering-proxy-use
      (let* ((scheme (if twittering-use-ssl "https" "http"))
             (keep-alive (twittering-proxy-info scheme 'keep-alive))
             (user (twittering-proxy-info scheme 'user))
             (password (twittering-proxy-info scheme 'password)))
        (when (twittering-proxy-info scheme 'keep-alive)
          (push (cons "Proxy-Connection" "Keep-Alive")
                headers))
        (when (and user password)
          (push (cons
                 "Proxy-Authorization"
                 (concat "Basic "
                         (base64-encode-string (concat user ":" password))))
                headers))))
    headers
    ))

(defun twittering-add-application-header-to-http-request (request)
  (let* ((method (assqref 'method request))
         (auth-str
          (cond
           ((eq (twittering-get-accounts 'auth) 'basic)
            (concat "Basic "
                    (base64-encode-string
                     (concat (twittering-get-accounts 'username)
                             ":" (twittering-get-accounts 'password)))))
           ((memq (twittering-get-accounts 'auth) '(oauth xauth))
            (let ((access-token
                   (assocref "oauth_token" (twittering-lookup-oauth-access-token-alist)))
                  (access-token-secret
                   (assocref "oauth_token_secret" (twittering-lookup-oauth-access-token-alist))))
              (twittering-oauth-auth-str-access
               method
               (assqref 'uri-without-query request)
               (assqref 'encoded-query-alist request)
               (twittering-lookup-service-method-table 'oauth-consumer-key)
               (twittering-lookup-service-method-table 'oauth-consumer-secret)
               access-token
               access-token-secret)))
           (t
            nil)))
         (application-headers
          `(,@(twittering-http-application-headers method)
            ("Authorization" . ,auth-str))))
    (mapcar (lambda (entry)
              (if (eq (car entry) 'header-list)
                  `(header-list
                    . ,(append (cdr entry) application-headers))
                entry))
            request)))

(defun twittering-get-error-message (header-info buffer)
  "Return an error message generated from HEADER-INFO and BUFFER.
HEADER-INFO must be an alist generated by `twittering-get-response-header'.
BUFFER must be a HTTP response body, which includes error messages from
the server when the HTTP status code equals to 400 or 403."
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info)))
    (cond
     ((and (buffer-live-p buffer)
           (member status-code '("400" "403")))
      ;; Twitter returns an error message as a HTTP response body if
      ;; HTTP status is "400 Bad Request" or "403 Forbidden".
      ;; See "HTTP Response Codes and Errors | dev.twitter.com"
      ;; http://dev.twitter.com/pages/responses_errors .
      (let* ((xmltree
              (with-current-buffer buffer
                (twittering-xml-parse-region (point-min) (point-max))))
             (error-mes
              (car (cddr (assq 'error (or (assq 'errors xmltree)
                                          (assq 'hash xmltree)))))))
        (if error-mes
            (format "%s (%s)" status-line error-mes)
          status-line)))
     (t
      status-line))))

(defun twittering-http-get (host method &optional parameters format additional-info sentinel clean-up-sentinel)
  (let* ((format (or format "xml"))
         (sentinel (or sentinel 'twittering-http-get-default-sentinel))
         (path (concat "/" method "." format))
         (headers nil)
         (port nil)
         (post-body "")
         (request
          (twittering-add-application-header-to-http-request
           (twittering-make-http-request "GET" headers host port path
                                         parameters post-body
                                         twittering-use-ssl))))
    (twittering-send-http-request request additional-info
                                  sentinel clean-up-sentinel)))

(defun twittering-http-get-default-sentinel (proc status connection-info header-info)
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info)))
    (case-string
     status-code
     (("200")
      (debug-printf "connection-info=%s" connection-info)
      (twittering-html-decode-buffer)
      (let* ((spec (assqref 'timeline-spec connection-info))
	     (spec-string (assqref 'timeline-spec-string connection-info))
	     (twittering-service-method (caar spec))
	     (statuses
	      (let ((xmltree
		     (twittering-xml-parse-region (point-min) (point-max))))
		(cond
		 ((null xmltree)
		  nil)
		 ((eq 'search (cadr spec))
		  (twittering-atom-xmltree-to-status xmltree))
		 (t
		  (twittering-xmltree-to-status xmltree))))))
	(when statuses
	  (let ((new-statuses
		 (twittering-add-statuses-to-timeline-data statuses spec))
		(buffer (twittering-get-buffer-from-spec spec)))
	    ;; FIXME: We should retrieve un-retrieved statuses until
	    ;; statuses is nil. twitter server returns nil as
	    ;; xmltree with HTTP status-code is "200" when we
	    ;; retrieved all un-retrieved statuses.
	    (when (and new-statuses buffer)
	      (twittering-render-timeline buffer t new-statuses))))
	(twittering-add-timeline-history spec-string)
	(when (and twittering-notify-successful-http-get
		   (not (assqref 'noninteractive connection-info)))
	  (format "Fetching %s.  Success." spec-string))))
     (t
      (format "Response: %s"
	      (twittering-get-error-message header-info (current-buffer)))))))

(defun twittering-http-get-list-index-sentinel (proc status connection-info header-info)
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info))
        (indexes nil)
        (mes nil))
    (case-string
     status-code
     (("200")
      (let ((xmltree (twittering-xml-parse-region (point-min) (point-max))))
        (when xmltree
          (setq indexes
                (mapcar
                 (lambda (c-node)
                   (caddr (assq 'slug c-node)))
                 (remove nil
                         (mapcar
                          (lambda (node)
                            (and (consp node) (eq 'list (car node))
                                 node))
                          (cdr-safe
                           (assq 'lists (assq 'lists_list xmltree))))
                         ))
                ))))
     (t
      (setq mes (format "Response: %s"
                        (twittering-get-error-message header-info
                                                      (current-buffer))))))
    (setq twittering-list-index-retrieved
          (or indexes
              mes
              "")) ;; set "" explicitly if user does not have a list.
    mes))

(defun twittering-http-post (host method &optional parameters format additional-info sentinel clean-up-sentinel)
  "Send HTTP POST request to api.twitter.com (or search.twitter.com)
HOST is hostname of remote side, api.twitter.com (or search.twitter.com).
METHOD must be one of Twitter API method classes
 (statuses, users or direct_messages).
PARAMETERS is alist of URI parameters.
 ex) ((\"mode\" . \"view\") (\"page\" . \"6\")) => <URI>?mode=view&page=6
FORMAT is a response data format (\"xml\", \"atom\", \"json\")"
  (let* ((format (or format "xml"))
         (sentinel (or sentinel 'twittering-http-post-default-sentinel))
         (path (concat "/" method "." format))
         (headers nil)
         (port nil)
         (post-body "")
         ;; TODO
         ;; "POST" url (and (not (twittering-is-uploading-file-p parameters))
         ;;                  parameters))))

         (request
          (twittering-add-application-header-to-http-request
           (twittering-make-http-request "POST" headers host port path
                                         parameters post-body
                                         twittering-use-ssl))))
    (twittering-send-http-request request additional-info
                                  sentinel clean-up-sentinel)))

(defun twittering-http-post-default-sentinel (proc status connection-info header-info)
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info)))
    (case-string
     status-code
     (("200")
      "Success: Post.")
     (t
      (format "Response: %s"
              (twittering-get-error-message header-info (current-buffer)))))))

;;;;
;;;; OAuth
;;;;

(defun twittering-oauth-url-encode (str &optional coding-system)
  "Encode string according to Percent-Encoding defined in RFC 3986."
  (let ((coding-system (or (when (and coding-system
                                      (coding-system-p coding-system))
                             coding-system)
                           'utf-8)))
    (mapconcat
     (lambda (c)
       (cond
        ((or (and (<= ?A c) (<= c ?Z))
             (and (<= ?a c) (<= c ?z))
             (and (<= ?0 c) (<= c ?9))
             (eq ?. c)
             (eq ?- c)
             (eq ?_ c)
             (eq ?~ c))
         (char-to-string c))
        (t (format "%%%02X" c))))
     (encode-coding-string str coding-system)
     "")))

(defun twittering-oauth-unhex (c)
  (cond
   ((and (<= ?0 c) (<= c ?9))
    (- c ?0))
   ((and (<= ?A c) (<= c ?F))
    (+ 10 (- c ?A)))
   ((and (<= ?a c) (<= c ?f))
    (+ 10 (- c ?a)))
   ))

(defun twittering-oauth-url-decode (str &optional coding-system)
  (let* ((coding-system (or (when (and coding-system
                                       (coding-system-p coding-system))
                              coding-system)
                            'utf-8))
         (substr-list (split-string str "%"))
         (head (car substr-list))
         (tail (cdr substr-list)))
    (decode-coding-string
     (concat
      head
      (mapconcat
       (lambda (substr)
         (if (string-match "\\`\\([0-9a-fA-F]\\)\\([0-9a-fA-F]\\)\\(.*\\)\\'"
                           substr)
             (let* ((c1 (string-to-char (match-string 1 substr)))
                    (c0 (string-to-char (match-string 2 substr)))
                    (tail (match-string 3 substr))
                    (ch (+ (* 16 (twittering-oauth-unhex c1))
                           (twittering-oauth-unhex c0))))
               (concat (char-to-string ch) tail))
           substr))
       tail
       ""))
     coding-system)))

(defun twittering-oauth-make-signature-base-string (method base-url parameters)
  ;; "OAuth Core 1.0a"
  ;; http://oauth.net/core/1.0a/#anchor13
  (let* ((sorted-parameters (copy-sequence parameters))
         (sorted-parameters
          (sort sorted-parameters
                (lambda (entry1 entry2)
                  (string< (car entry1) (car entry2))))))
    (concat
     method
     "&"
     (twittering-oauth-url-encode base-url)
     "&"
     (mapconcat
      (lambda (entry)
        (let ((key (car entry))
              (value (cdr entry)))
          (concat (twittering-oauth-url-encode key)
                  "%3D"
                  (twittering-oauth-url-encode value))))
      sorted-parameters
      "%26"))))

(defun twittering-oauth-make-random-string (len)
  (let* ((table
          (concat
           "0123456789"
           "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
           "abcdefghijklmnopqrstuvwxyz"))
         (n (length table))
         (l 0)
         (result (make-string len ?0)))
    (while (< l len)
      (aset result l (aref table (random n)))
      (setq l (1+ l)))
    result))

;;;
;; The below function is derived from `hmac-sha1' retrieved
;; from http://www.emacswiki.org/emacs/HmacShaOne.
;;;
(defun twittering-hmac-sha1 (key message)
  "Return an HMAC-SHA1 authentication code for KEY and MESSAGE.

KEY and MESSAGE must be unibyte strings.  The result is a unibyte
string.  Use the function `encode-hex-string' or the function
`base64-encode-string' to produce human-readable output.

See URL:<http://en.wikipedia.org/wiki/HMAC> for more information
on the HMAC-SHA1 algorithm.

The Emacs multibyte representation actually uses a series of
8-bit values under the hood, so we could have allowed multibyte
strings as arguments.  However, internal 8-bit values don't
correspond to any external representation \(at least for major
version 22).  This makes multibyte strings useless for generating
hashes.

Instead, callers must explicitly pick and use an encoding for
their multibyte data.  Most callers will want to use UTF-8
encoding, which we can generate as follows:

  (let ((unibyte-key   (encode-coding-string key   'utf-8 t))
        (unibyte-value (encode-coding-string value 'utf-8 t)))
    (twittering-hmac-sha1 unibyte-key unibyte-value))

For keys and values that are already unibyte, the
`encode-coding-string' calls just return the same string."
;; Return an HMAC-SHA1 authentication code for KEY and MESSAGE.
;;
;; KEY and MESSAGE must be unibyte strings.  The result is a unibyte
;; string.  Use the function `encode-hex-string' or the function
;; `base64-encode-string' to produce human-readable output.
;;
;; See URL:<http://en.wikipedia.org/wiki/HMAC> for more information
;; on the HMAC-SHA1 algorithm.
;;
;; The Emacs multibyte representation actually uses a series of
;; 8-bit values under the hood, so we could have allowed multibyte
;; strings as arguments.  However, internal 8-bit values don't
;; correspond to any external representation \(at least for major
;; version 22).  This makes multibyte strings useless for generating
;; hashes.
;;
;; Instead, callers must explicitly pick and use an encoding for
;; their multibyte data.  Most callers will want to use UTF-8
;; encoding, which we can generate as follows:
;;
;; (let ((unibyte-key   (encode-coding-string key   'utf-8 t))
;;       (unibyte-value (encode-coding-string value 'utf-8 t)))
;; (hmac-sha1 unibyte-key unibyte-value))
;;
;; For keys and values that are already unibyte, the
;; `encode-coding-string' calls just return the same string.
;;
;; Author: Derek Upham - sand (at) blarg.net
;;
;; Copyright: This code is in the public domain.
  (require 'sha1)
  (when (multibyte-string-p key)
    (error "key must be unibyte"))
  (when (multibyte-string-p message)
    (error "message must be unibyte"))

  ;; The key block is always exactly the block size of the hash
  ;; algorithm.  If the key is too small, we pad it with zeroes (or
  ;; instead, we initialize the key block with zeroes and copy the
  ;; key onto the nulls).  If the key is too large, we run it
  ;; through the hash algorithm and use the hashed value (strange
  ;; but true).

  (let ((+hmac-sha1-block-size-bytes+ 64)) ; SHA-1 uses 512-bit blocks
    (when (< +hmac-sha1-block-size-bytes+ (length key))
      (setq key (sha1 key nil nil t)))

    (let ((key-block (make-vector +hmac-sha1-block-size-bytes+ 0)))
      (dotimes (i (length key))
        (aset key-block i (aref key i)))

      (let ((opad (make-vector +hmac-sha1-block-size-bytes+ #x5c))
            (ipad (make-vector +hmac-sha1-block-size-bytes+ #x36)))
        (dotimes (i +hmac-sha1-block-size-bytes+)
          (aset ipad i (logxor (aref ipad i) (aref key-block i)))
          (aset opad i (logxor (aref opad i) (aref key-block i))))

        (when (fboundp 'unibyte-string)
          ;; `concat' of Emacs23 (and later?) generates a multi-byte
          ;; string from a vector of characters with eight bit.
          ;; Since `opad' and `ipad' must be unibyte, we have to
          ;; convert them by using `unibyte-string'.
          ;; We cannot use `string-as-unibyte' here because it encodes
          ;; bytes with the manner of UTF-8.
          (setq opad (apply 'unibyte-string (mapcar 'identity opad)))
          (setq ipad (apply 'unibyte-string (mapcar 'identity ipad))))
        (sha1 (concat opad
                      (sha1 (concat ipad message)
                            nil nil t))
              nil nil t)))))

(defun twittering-build-unique-prefix (str-list)
  "Create an unique shortest prefix to identify each element of STR-LIST.
The sequence of STR-LIST is not changed.  e.g.,
  '(\"abcdef\" \"ab\" \"c\" \"def\")
       => '(\"abc\" \"ab\" \"c\" \"d\")

Duplicated elements should not exist in STR-LIST."
  (mapcar
   (lambda (el)
     (let ((pre "\\`")
           (c "")
           (str el))
       (while (and str (not (string= str "")))
         (setq c (substring str 0 1)
               str (substring str 1)
               pre (concat pre c))
         (when (= (count-if (lambda (el) (string-match pre el))
                            str-list)
                  1)
           (setq str nil)))
       (substring pre 2)))
   str-list))

(defun twittering-decorate-zebra-background (object face1 face2)
  "Append zebra background to OBJECT.
The zebra face is decided by looking at adjacent face. "
  (let* ((start 0)
           (other-faces (get-text-property start 'face object))
           (end nil)
           (pos (twittering-get-current-status-head))
           (zebra-face (if (and pos
                              face2
                                (memq face1
                                      (let ((faces (get-text-property pos 'face)))
                                      (if (listp faces) faces (list faces)))))
                           face2
                         face1)))
    (while (setq end (next-single-property-change start 'face object))
      (put-text-property start end 'face (if (listp other-faces)
                                               (cons zebra-face other-faces)
                                             (list zebra-face other-faces))
                           object)
      (setq start end
              other-faces (get-text-property start 'face object)))
    (put-text-property start (length object) 'face zebra-face object)
    object))

(defun twittering-decorate-uri (object)
  "Decorate uri contained in OBJECT."
  (let ((points-str '()))
    (with-temp-buffer
      (insert object)
      (goto-char (point-min))
      (while (re-search-forward twittering-regexp-uri nil t 1)
        ;; FIXME: why need `-1' here?
        (setq points-str (cons (list (1- (match-beginning 1))
                                     (1- (match-end 1))
                                     (match-string 1))
                               points-str))))
    (mapc (lambda (p-s)
            (add-text-properties
             (nth 0 p-s) (nth 1 p-s)
             `(mouse-face highlight uri ,(nth 2 p-s) face twittering-uri-face)
             object))
          points-str)
    object))

(defun twittering-decorate-listname (listname &optional display-string)
  (unless display-string (setq display-string listname))
  (add-text-properties 0 (length display-string)
                       `(mouse-face
                         highlight
                         uri ,(twittering-get-status-url listname)
                         goto-spec
                         ,(twittering-string-to-timeline-spec
                           listname)
                         face twittering-username-face)
                       display-string)
  display-string)

(defun twittering-oauth-auth-str (method base-url query-parameters oauth-parameters key)
  "Generate the value for HTTP Authorization header on OAuth.
QUERY-PARAMETERS is an alist for query parameters, where name and value
must be encoded into the same as they will be sent."
  (let* ((parameters (append query-parameters oauth-parameters))
         (base-string
          (twittering-oauth-make-signature-base-string method base-url parameters))
         (key (if (multibyte-string-p key)
                  (string-make-unibyte key)
                key))
         (base-string (if (multibyte-string-p base-string)
                          (string-make-unibyte base-string)
                        base-string))
         (signature
          (base64-encode-string (twittering-hmac-sha1 key base-string))))
    (concat
     "OAuth "
     (mapconcat
      (lambda (entry)
        (concat (car entry) "=\"" (cdr entry) "\""))
      oauth-parameters
      ",")
     ",oauth_signature=\"" (twittering-oauth-url-encode signature) "\"")))

(defun twittering-multibyte-string-p (string)
  "Similar to `multibyte-string-p', but consider ascii only STRING not multibyte. "
  (and (multibyte-string-p string)
       (> (string-bytes string) (length string))))

(defun twittering-my-status-p (status)
  "Is STATUS sent by myself? "
  (or (string= (twittering-get-accounts 'username)
               (assqref 'user-screen-name status))
      (string= (assocref "user_id" (twittering-lookup-oauth-access-token-alist))
               (assqref 'user-id status))))

(defun twittering-is-replies-p (status)
  (string= (twittering-get-accounts 'username) (assqref 'in-reply-to-screen-name status)))

(defun twittering-take (n lst)
  "Take first N elements from LST."
  (and (> n 0)
       (car lst)
       (cons (car lst) (twittering-take (1- n) (cdr lst)))))

;;;
;;; Utility functions for portability
;;;

(defun twittering-oauth-auth-str-request-token (url query-parameters consumer-key consumer-secret &optional oauth-parameters)
  (let ((key (concat consumer-secret "&"))
        (oauth-params
         (or oauth-parameters
             `(("oauth_nonce" . ,(twittering-oauth-make-random-string 43))
               ("oauth_callback" . "oob")
               ("oauth_signature_method" . "HMAC-SHA1")
               ("oauth_timestamp" . ,(format-time-string "%s"))
               ("oauth_consumer_key" . ,consumer-key)
               ("oauth_version" . "1.0")))))
    (twittering-oauth-auth-str "POST" url query-parameters oauth-params key)))

(defun twittering-oauth-auth-str-exchange-token (url query-parameters consumer-key consumer-secret request-token request-token-secret verifier &optional oauth-parameters)
  (let ((key (concat consumer-secret "&" request-token-secret))
        (oauth-params
         (or oauth-parameters
             `(("oauth_consumer_key" . ,consumer-key)
               ("oauth_nonce" . ,(twittering-oauth-make-random-string 43))
               ("oauth_signature_method" . "HMAC-SHA1")
               ("oauth_timestamp" . ,(format-time-string "%s"))
               ("oauth_version" . "1.0")
               ("oauth_token" . ,request-token)
               ("oauth_verifier" . ,verifier)))))
    (twittering-oauth-auth-str "POST" url query-parameters oauth-params key)))

(defun twittering-oauth-auth-str-access (method url query-parameters consumer-key consumer-secret access-token access-token-secret &optional oauth-parameters)
  "Generate a string for Authorization in HTTP header on OAuth.
METHOD means HTTP method such as \"GET\", \"POST\", etc. URL means a simple
URL without port number and query parameters.
QUERY-PARAMETERS means an alist of query parameters such as
'((\"status\" . \"test%20tweet\")
  (\"in_reply_to_status_id\" . \"12345678\")),
where name and value must be encoded into the same as they will be sent.
CONSUMER-KEY and CONSUMER-SECRET specifies the consumer.
ACCESS-TOKEN and ACCESS-TOKEN-SECRET must be authorized before calling this
function."
  (let ((key (concat consumer-secret "&" access-token-secret))
        (oauth-params
         (or oauth-parameters
             `(("oauth_consumer_key" . ,consumer-key)
               ("oauth_nonce" . ,(twittering-oauth-make-random-string 43))
               ("oauth_signature_method" . "HMAC-SHA1")
               ("oauth_timestamp" . ,(format-time-string "%s"))
               ("oauth_version" . "1.0")
               ("oauth_token" . ,access-token)))))
    (twittering-oauth-auth-str method url query-parameters oauth-params key)))

;; "Using xAuth | dev.twitter.com"
;; http://dev.twitter.com/pages/xauth
(defun twittering-xauth-auth-str-access-token (url query-parameters consumer-key consumer-secret username password &optional oauth-parameters)
  (let ((key (concat consumer-secret "&"))
        (oauth-params
         (or oauth-parameters
             `(("oauth_nonce" . ,(twittering-oauth-make-random-string 43))
               ("oauth_signature_method" . "HMAC-SHA1")
               ("oauth_timestamp" . ,(format-time-string "%s"))
               ("oauth_consumer_key" . ,consumer-key)
               ("oauth_version" . "1.0"))))
        (query-params
         (append query-parameters
                 `(("x_auth_mode" . "client_auth")
                   ("x_auth_password"
                    . ,(twittering-oauth-url-encode password))
                   ("x_auth_username"
                    . ,(twittering-oauth-url-encode username))))))
    (twittering-oauth-auth-str "POST" url query-params oauth-params key)))

;; "OAuth Core 1.0a"
;; http://oauth.net/core/1.0a/#response_parameters
(defun twittering-oauth-make-response-alist (str)
  (mapcar
   (lambda (entry)
     (let* ((pair (split-string entry "="))
            (name-entry (car pair))
            (value-entry (cadr pair))
            (name (and name-entry (twittering-oauth-url-decode name-entry)))
            (value (and value-entry
                        (twittering-oauth-url-decode value-entry))))
       `(,name . ,value)))
   (split-string str "&")))

(defun twittering-oauth-get-response-alist (buffer)
  (with-current-buffer buffer
    (goto-char (point-min))
    (when (search-forward-regexp
           "\\`\\(\\(HTTP/1\.[01]\\) \\([0-9][0-9][0-9]\\) \\(.*?\\)\\)\r?\n"
           nil t)
      (let ((status-line (match-string 1))
            (http-version (match-string 2))
            (status-code (match-string 3))
            (reason-phrase (match-string 4)))
        (cond
         ((not (string-match "2[0-9][0-9]" status-code))
          (message "Response: %s" status-line)
          nil)
         ((search-forward-regexp "\r?\n\r?\n" nil t)
          (let ((beg (match-end 0))
                (end (point-max)))
            (twittering-oauth-make-response-alist (buffer-substring beg end))))
         (t
          (message "Response: %s" status-line)
          nil))))))

(defun twittering-oauth-get-token-alist-url (url auth-str post-body)
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          `(("Authorization" . ,auth-str)
            ("Accept-Charset" . "us-ascii")
            ("Content-Type" . "application/x-www-form-urlencoded")
            ("Content-Length" . ,(format "%d" (length post-body)))))
         (url-request-data post-body)
         (coding-system-for-read 'utf-8-unix))
    (lexical-let ((result 'queried))
      (let ((buffer
             (url-retrieve
              url
              (lambda (&rest args)
                (let* ((status (if (< 21 emacs-major-version)
                                   (car args)
                                 nil))
                       (callback-args (if (< 21 emacs-major-version)
                                          (cdr args)
                                        args))
                       (response-buffer (current-buffer)))
                  (setq result
                        (twittering-oauth-get-response-alist response-buffer))
                  )))))
        (while (eq result 'queried)
          (sit-for 0.1))
        (unless twittering-debug-mode
          (kill-buffer buffer))
        result))))

(defun twittering-oauth-get-token-alist (url auth-str &optional post-body)
  (let ((request
         (twittering-make-http-request-from-uri
          "POST"
          `(("Authorization" . ,auth-str)
            ("Accept-Charset" . "us-ascii")
            ("Content-Type" . "application/x-www-form-urlencoded"))
          url post-body)))
    (lexical-let ((result 'queried))
      (twittering-send-http-request
       request nil
       (lambda (proc status connection-info header-info)
         (let ((status-line (assqref 'status-line header-info))
               (status-code (assqref 'status-code header-info)))
           (case-string
            status-code
            (("200")
             (when twittering-debug-mode
               (let ((buffer (current-buffer)))
                 (with-current-buffer (twittering-debug-buffer)
                   (insert-buffer-substring buffer))))
             (setq result
                   (twittering-oauth-make-response-alist (buffer-string)))
             nil)
            (t
             (setq result nil)
             (format "Response: %s" status-line)))))
       (lambda (proc status connection-info)
         (when (and (memq status '(nil closed exit failed signal))
                    (eq result 'queried))
           (setq result nil))))
      (while (eq result 'queried)
        (sit-for 0.1))
      result)))

(defun twittering-oauth-get-request-token (url consumer-key consumer-secret)
  (let ((auth-str
         (twittering-oauth-auth-str-request-token
          url nil consumer-key consumer-secret)))
    (twittering-oauth-get-token-alist url auth-str)))

(defun twittering-oauth-exchange-request-token (url consumer-key consumer-secret request-token request-token-secret verifier)
  (let ((auth-str
         (twittering-oauth-auth-str-exchange-token
          url nil
          consumer-key consumer-secret
          request-token request-token-secret verifier)))
    (twittering-oauth-get-token-alist url auth-str)))

(defun twittering-oauth-get-access-token (request-token-url authorize-url-func access-token-url consumer-key consumer-secret consumer-name)
  "Return an alist of authorized access token.
The function retrieves a request token from the site specified by
REQUEST-TOKEN-URL. Then, The function asks a WWW browser to authorize the
token by calling `browse-url'. The URL for authorization is calculated by
calling AUTHORIZE-URL-FUNC with the request token as an argument.
AUTHORIZE-URL-FUNC is called as `(funcal AUTHORIZE-URL-FUNC request-token)',
where the request-token is a string.
After calling `browse-url', the function waits for user to input the PIN code
that is displayed in the browser. The request token is authorized by the
PIN code, and then it is exchanged for the access token on the site
specified by ACCESS-TOKEN-URL.
CONSUMER-KEY and CONSUMER-SECRET specify the consumer.
CONSUMER-NAME is displayed at the guide of authorization.

The access token is returned as a list of a cons pair of name and value
like following:
 ((\"oauth_token\"
  . \"819797-Jxq8aYUDRmykzVKrgoLhXSq67TEa5ruc4GJC2rWimw\")
  (\"oauth_token_secret\"
   . \"J6zix3FfA9LofH0awS24M3HcBYXO5nI1iYe8EfBA\")
  (\"user_id\" . \"819797\")
  (\"screen_name\" . \"episod\"))
."
  (let* ((request-token-alist
          (twittering-oauth-get-request-token
           request-token-url consumer-key consumer-secret))
         (request-token (assocref "oauth_token" request-token-alist))
         (request-token-secret
          (assocref "oauth_token_secret" request-token-alist))
         (authorize-url (funcall authorize-url-func request-token))
         (str
          (concat
           (propertize "Authorization via OAuth\n" 'face 'bold)
           "\n"
           "1.Allow access by " consumer-name " on the below site.\n"
           "\n  "
           (propertize authorize-url 'url authorize-url 'face 'bold)
           "\n"
           "\n"
           (when twittering-oauth-invoke-browser
             (concat
              "  Emacs invokes your browser by the function `browse-url'.\n"
              "  If the site is not opened automatically, you have to open\n"
              "  the site manually.\n"
              "\n"))
           "2.After allowing access, the site will display the PIN code."
           "\n"
           "  Input the PIN code "
           (propertize "at the below minibuffer." 'face 'bold))))
    (when request-token-alist
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (let* ((str-height (length (split-string str "\n")))
               (height (max 0 (- (/ (- (window-text-height) 1) 2)
                                 (/ str-height 2)))))
          (insert (make-string height ?\n) str)
          (if twittering-oauth-invoke-browser
              (browse-url authorize-url)
            (when (y-or-n-p "Open authorization URL with browser? (using `browse-url')")
              (browse-url authorize-url)))
          (let* ((pin
                  (block pin-input-block
                    (while t
                      (let ((pin-input (read-string "Input PIN code: ")))
                        (when (string-match "^\\s-*\\([0-9]+\\)\\s-*$" pin-input)
                          (return-from pin-input-block
                            (match-string 1 pin-input)))))))
                 (verifier pin))
            (twittering-oauth-exchange-request-token
             access-token-url
             consumer-key consumer-secret
             request-token request-token-secret verifier)))))))

(defun twittering-xauth-get-access-token (access-token-url consumer-key consumer-secret username password)
  (let ((auth-str
         (twittering-xauth-auth-str-access-token
          access-token-url nil consumer-key consumer-secret
          username password))
        (post-body
         (mapconcat (lambda (pair)
                      (format "%s=%s" (car pair)
                              (twittering-oauth-url-encode (cdr pair))))
                    `(("x_auth_mode" . "client_auth")
                      ("x_auth_password" . ,password)
                      ("x_auth_username" . ,username))
                    "&")))
    (twittering-oauth-get-token-alist access-token-url auth-str post-body)))

(defvar twittering-regexp-uri
  "\\(https?://[-_.!~*'()a-zA-Z0-9;/?:@&=+$,%#]+\\)")

;;;;
;;;; Private storage
;;;;

(defun twittering-load-private-info ()
  (let* ((file twittering-private-info-file)
         (decrypted-str (twittering-read-from-encrypted-file file))
         (loaded-alist
          (when decrypted-str
            (condition-case nil
                (read decrypted-str)
              (error
               nil)))))
    (when loaded-alist
      (remove
       nil
       (mapcar
        (lambda (pair)
          (when (consp pair)
            (let ((sym (car pair))
                  (value (cdr pair)))
              (cond
               ((memq sym twittering-variables-stored-with-encryption)
                (set sym value)
                sym)
               (t
                nil)))))
        loaded-alist)))))

(defun twittering-load-private-info-with-guide ()
  (let ((str (concat
              "Loading authorized access token for OAuth from\n"
              (format "%s.\n" twittering-private-info-file)
              "\n"
              (propertize "Please input the master password.\n" 'face 'bold)
              "\n"
              "To cancel it, you may need to press C-g multiple times.\n"
              )))
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (let* ((str-height (length (split-string str "\n")))
             (height (max 0 (- (/ (- (window-text-height) 1) 2)
                               (/ str-height 2)))))
        (insert (make-string height ?\n) str)
        (set-buffer-modified-p nil)
        (twittering-load-private-info)))))

(defun twittering-save-private-info ()
  (let* ((obj (mapcar (lambda (sym)
                        `(,sym . ,(symbol-value sym)))
                      twittering-variables-stored-with-encryption))
         (str (with-output-to-string (pp obj)))
         (file twittering-private-info-file))
    (when (twittering-write-and-encrypt file str)
      (set-file-modes file #o600))))

(defun twittering-save-private-info-with-guide ()
  (let ((str (concat
              "Saving authorized access token for OAuth to "
              (format "%s.\n" twittering-private-info-file)
              "\n"
              (propertize "Please input a master password twice."
                          'face 'bold))))
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (let* ((str-height (length (split-string str "\n")))
             (height (max 0 (- (/ (- (window-text-height) 1) 2)
                               (/ str-height 2)))))
        (insert (make-string height ?\n) str)
        (set-buffer-modified-p nil)
        (twittering-save-private-info)))))

(defun twittering-capable-of-encryption-p ()
  (and (or (require 'epa nil t) (require 'alpaca nil t))
       (executable-find "gpg")))

(eval-when-compile
  (require 'epa nil t)
  (require 'alpaca nil t))
(defun twittering-read-from-encrypted-file (file)
  (cond
   ((require 'epa nil t)
    (let ((context (epg-make-context epa-protocol)))
      (epg-context-set-passphrase-callback
       context #'epa-passphrase-callback-function)
      (epg-context-set-progress-callback
       context
       (cons #'epa-progress-callback-function
             (format "Decrypting %s..." (file-name-nondirectory file))))
      (message "Decrypting %s..." (file-name-nondirectory file))
      (condition-case err
          (epg-decrypt-file context file nil)
        (error
         (message "%s" (cdr err))
         nil))))
   ((require 'alpaca nil t)
    (with-temp-buffer
      (let ((buffer-file-name file)
            (alpaca-regex-suffix ".*")
            (temp-buffer (current-buffer)))
        (insert-file-contents-literally file)
        (set-buffer-modified-p nil)
        (condition-case nil
            (progn
              (alpaca-after-find-file)
              (if (eq temp-buffer (current-buffer))
                  (buffer-string)
                ;; `alpaca-after-find-file' kills the current buffer
                ;; if the decryption is failed.
                nil))
          (error
           (when (eq temp-buffer (current-buffer))
             (delete-region (point-min) (point-max)))
           nil)))))
   (t
    nil)))

(defun twittering-write-and-encrypt (file str)
  (cond
   ((require 'epg nil t)
    (let ((context (epg-make-context epa-protocol)))
      (epg-context-set-passphrase-callback
       context #'epa-passphrase-callback-function)
      (epg-context-set-progress-callback
       context (cons #'epa-progress-callback-function "Encrypting..."))
      (message "Encrypting...")
      (condition-case err
          (unwind-protect
              ;; In order to prevent `epa-file' to encrypt the file double,
              ;; `epa-file-name-regexp' is temorarily changed into the null
              ;; regexp that never matches any string.
              (let ((epa-file-name-regexp "\\`\\'")
                    (coding-system-for-write 'binary))
                (when (fboundp 'epa-file-name-regexp-update)
                  (epa-file-name-regexp-update))
                (with-temp-file file
                  (set-buffer-multibyte nil)
                  (delete-region (point-min) (point-max))
                  (insert (epg-encrypt-string context str nil))
                  (message "Encrypting...wrote %s" file)
                  t))
            (when (fboundp 'epa-file-name-regexp-update)
              (epa-file-name-regexp-update)))
        (error
         (message "%s" (cdr err))
         nil))))
   ((require 'alpaca nil t)
    ;; Create the file.
    ;; This is required because `alpaca-save-buffer' checks its timestamp.
    (with-temp-file file)
    (with-temp-buffer
      (let ((buffer-file-name file)
            (coding-system-for-write 'binary))
        (insert str)
        (condition-case nil
            (if (alpaca-save-buffer)
                t
              (delete-file file)
              nil)
          (error
           (when (file-exists-p file)
             (delete-file file))
           nil)))))
   (t
    nil)))

;;;;
;;;; Asynchronous retrieval
;;;;

(defvar twittering-url-data-hash (make-hash-table :test 'equal))
(defvar twittering-url-request-list nil)
(defvar twittering-url-request-sentinel-hash (make-hash-table :test 'equal))
(defvar twittering-internal-url-queue nil)
(defvar twittering-url-request-resolving-p nil)
(defvar twittering-url-request-retry-limit 3)
(defvar twittering-url-request-sentinel-delay 1.0
  "*Delay from completing retrieval to invoking associated sentinels.
Sentinels registered by `twittering-url-retrieve-async' will be invoked
after retrieval is completed and Emacs remains idle a certain time, which
this variable specifies. The unit is second.")

(defun twittering-remove-redundant-queries (queue)
  (remove nil
          (mapcar
           (lambda (url)
             (let ((current (gethash url twittering-url-data-hash)))
               (when (or (null current)
                         (and (integerp current)
                              (< current twittering-url-request-retry-limit)))
                 url)))
           (twittering-remove-duplicates queue))))

(defun twittering-resolve-url-request ()
  "Resolve requests of asynchronous URL retrieval."
  (unless twittering-url-request-resolving-p
    (setq twittering-url-request-resolving-p t)
    ;; It is assumed that the following part is not processed
    ;; in parallel.
    (setq twittering-internal-url-queue
          (append twittering-internal-url-queue twittering-url-request-list))
    (setq twittering-url-request-list nil)
    (setq twittering-internal-url-queue
          (twittering-remove-redundant-queries twittering-internal-url-queue))
    (if (null twittering-internal-url-queue)
        (setq twittering-url-request-resolving-p nil)
      (let* ((url (car twittering-internal-url-queue))
             (request (twittering-make-http-request-from-uri "GET" nil url))
             (additional-info `((uri . ,url))))
        (twittering-send-http-request
         request additional-info
         'twittering-url-retrieve-async-sentinel
         'twittering-url-retrieve-async-clean-up-sentinel)))))

(defun twittering-url-retrieve-async-sentinel (proc status connection-info header-info)
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info))
        (uri (assqref 'uri (assq 'request connection-info))))
    (when (string= status-code "200")
      (let ((body (string-as-unibyte (buffer-string))))
        (puthash uri body twittering-url-data-hash)
        (setq twittering-internal-url-queue
              (remove uri twittering-internal-url-queue))
        (let ((sentinels (gethash uri twittering-url-request-sentinel-hash)))
          (when sentinels
            (remhash uri twittering-url-request-sentinel-hash))
          (twittering-run-on-idle twittering-url-request-sentinel-delay
                                  (lambda (sentinels uri body)
                                    (mapc (lambda (func)
                                            (funcall func uri body))
                                          sentinels)
                                    ;; Resolve the rest of requests.
                                    (setq twittering-url-request-resolving-p
                                          nil)
                                    (twittering-resolve-url-request))
                                  sentinels uri body)
          ;;  Without the following nil, it seems that the value of
          ;; `sentinels' is displayed.
          nil)))))

(defun twittering-url-retrieve-async-clean-up-sentinel (proc status connection-info)
  (when (memq status '(exit signal closed failed))
    (let* ((uri (assqref 'uri connection-info))
           (current (gethash uri twittering-url-data-hash)))
      (when (or (null current) (integerp current))
        ;; Increment the counter on failure and then retry retrieval.
        (puthash uri (1+ (or current 0)) twittering-url-data-hash)
        (setq twittering-url-request-resolving-p nil)
        (twittering-resolve-url-request)))))

(defun twittering-url-retrieve-async (url &optional sentinel)
  "Retrieve URL asynchronously and call SENTINEL with the retrieved data.
The request is placed at the last of queries queue. When the data has been
retrieved and Emacs remains idle a certain time specified by
`twittering-url-request-sentinel-delay', SENTINEL will be called as
 (funcall SENTINEL URL url-data).
The retrieved data can be referred as (gethash URL twittering-url-data-hash)."
  (let ((data (gethash url twittering-url-data-hash)))
    (cond
     ((or (null data) (integerp data))
      (add-to-list 'twittering-url-request-list url t)
      (when sentinel
        (let ((current (gethash url twittering-url-request-sentinel-hash)))
          (unless (member sentinel current)
            (puthash url (cons sentinel current)
                     twittering-url-request-sentinel-hash))))
      (twittering-resolve-url-request)
      nil)
     (t
      ;; URL has been already retrieved.
      (twittering-run-on-idle twittering-url-request-sentinel-delay
                              sentinel url data)
      data))))

;;;;
;;;; XML parser
;;;;

(defun twittering-ucs-to-char-internal (code-point)
  ;; Check (featurep 'unicode) is a workaround with navi2ch to avoid
  ;; error "error in process sentinel: Cannot open load file:
  ;; unicode".
  ;;
  ;; Details: navi2ch prior to 1.8.3 (which is currently last release
  ;; version as of 2010-01-18) always define `ucs-to-char' as autoload
  ;; file "unicode(.el)" (which came from Mule-UCS), hence it breaks
  ;; `ucs-to-char' under non Mule-UCS environment. The problem is
  ;; fixed in navi2ch dated 2010-01-16 or later, but not released yet.
  (if (and (featurep 'unicode) (functionp 'ucs-to-char))
      (ucs-to-char code-point)
    ;; Emacs21 have a partial support for UTF-8 text, so it can decode
    ;; only parts of a text with Japanese.
    (decode-char 'ucs code-point)))

(defvar twittering-unicode-replacement-char
  ;; "Unicode Character 'REPLACEMENT CHARACTER' (U+FFFD)"
  (or (twittering-ucs-to-char-internal #xFFFD)
      ??)
  "*Replacement character returned by `twittering-ucs-to-char' when it fails
to decode a code.")

(defun twittering-ucs-to-char (code-point)
  "Return a character specified by CODE-POINT in Unicode.
If it fails to decode the code, return `twittering-unicode-replacement-char'."
  (or (twittering-ucs-to-char-internal code-point)
      twittering-unicode-replacement-char))

(defadvice decode-char (after twittering-add-fail-over-to-decode-char)
  (when (null ad-return-value)
    (setq ad-return-value twittering-unicode-replacement-char)))

(defun twittering-xml-parse-region (&rest args)
  "Wrapped `xml-parse-region' in order to avoid decoding errors.
After activating the advice `twittering-add-fail-over-to-decode-char',
`xml-parse-region' is called. This prevents `xml-parse-region' from
exiting abnormally by decoding unknown numeric character reference."
  (let ((activated (ad-is-active 'decode-char)))
    (ad-enable-advice
     'decode-char 'after 'twittering-add-fail-over-to-decode-char)
    (ad-activate 'decode-char)
    (unwind-protect
        (apply 'xml-parse-region args)
      (ad-disable-advice 'decode-char 'after
                         'twittering-add-fail-over-to-decode-char)
      (if activated
          (ad-activate 'decode-char)
        (ad-deactivate 'decode-char)))))

(defun twittering-html-decode-buffer (&optional buffer)
  "Decode html BUFFER(default is current buffer).
Usually used in buffer retrieved by `url-retrieve'. If no charset info
is specified in html tag, default is 'utf-8."
  (unless buffer
    (setq buffer (current-buffer)))
  (with-current-buffer buffer
    (let ((coding 'utf-8))
      (when (save-excursion
              (goto-char (point-min))
              (re-search-forward "<meta http-equiv.*charset=[[:blank:]]*\\([a-zA-Z0-9_-]+\\)" nil t 1))
        (setq coding (intern (downcase (match-string 1)))))
      (set-buffer-multibyte t)
      (decode-coding-region (point-min) (point-max) coding))))

;;;;
;;;; Window configuration
;;;;

(defun twittering-set-window-end (window pos)
  (let* ((height (window-text-height window))
         (n (- (- height 1))))
    (while (progn (setq n (1+ n))
                  (set-window-start
                   window
                   (with-current-buffer (window-buffer window)
                     (save-excursion
                       (goto-char pos)
                       (line-beginning-position n))))
                  (not (pos-visible-in-window-p pos window))))))

(defun twittering-current-window-config (window-list)
  "Return window parameters of WINDOW-LIST."
  (mapcar (lambda (win)
            (let ((start (window-start win))
                  (point (window-point win)))
              `(,win ,start ,point)))
          window-list))

(defun twittering-restore-window-config-after-modification (config beg end)
  "Restore window parameters changed by modification on given region.
CONFIG is window parameters made by `twittering-current-window-config'.
BEG and END mean a region that had been modified."
  (mapc (lambda (entry)
          (let ((win (elt entry 0))
                (start (elt entry 1))
                (point (elt entry 2)))
            (when (and (< beg start) (< start end))
              (set-window-start win start))
            (when (and (< beg point) (< point end))
              (set-window-point win point))))
        config))

;;;;
;;;; URI shortening
;;;;

(defun twittering-tinyurl-get (longurl &optional service)
  "Shorten LONGURL with the service specified by `twittering-tinyurl-service'."
  (let* ((service (or service twittering-tinyurl-service))
         (api (cdr (assq service twittering-tinyurl-services-map)))
         (request-generator (when (listp api) (elt api 0)))
         (post-process (when (listp api) (elt api 1)))
         (encoded-url (twittering-percent-encode longurl))
         (request
          (cond
           ((stringp api)
            (twittering-make-http-request-from-uri
             "GET" nil (concat api encoded-url)))
           ((stringp request-generator)
            (twittering-make-http-request-from-uri
             "GET" nil (concat request-generator encoded-url)))
           ((functionp request-generator)
            (funcall request-generator service longurl))
           (t
            (error "%s is invalid. try one of %s"
                   (symbol-name service)
                   (mapconcat (lambda (x) (symbol-name (car x)))
                              twittering-tinyurl-services-map ", "))
            nil)))
         (additional-info `((longurl . ,longurl))))
    (cond
     ((null request)
      (error "Failed to generate a HTTP request for shortening %s with %s"
             longurl (symbol-name service))
      nil)
     (t
      (lexical-let ((result 'queried))
        (twittering-send-http-request
         request additional-info
         (lambda (proc status connection-info header-info)
           (let ((status-line (cdr (assq 'status-line header-info)))
                 (status-code (cdr (assq 'status-code header-info))))
             (case-string
              status-code
              (("200")
               (setq result (buffer-string))
               nil)
              (t
               (setq result nil)
               (format "Response: %s" status-line)))))
         (lambda (proc status connection-info)
           (when (and (memq status '(nil closed exit failed signal))
                      (eq result 'queried))
             (setq result nil))))
        (while (eq result 'queried)
          (sit-for 0.1))
        (let ((processed-result (if (and result (functionp post-process))
                                    (funcall post-process service result)
                                  result)))
          (if processed-result
              processed-result
            (error "Failed to shorten a URL %s with %s"
                   longurl (symbol-name service))
            nil)))))))

(defun twittering-tinyurl-replace-at-point ()
  "Replace the url at point with a tiny version."
  (interactive)
  (let ((url-bounds (bounds-of-thing-at-point 'url)))
    (when url-bounds
      (let ((url (twittering-tinyurl-get (thing-at-point 'url))))
        (when url
          (save-restriction
            (narrow-to-region (car url-bounds) (cdr url-bounds))
            (delete-region (point-min) (point-max))
            (insert url)))))))

(defun twittering-make-http-request-for-bitly (service longurl)
  "Make a HTTP request for URL shortening service bit.ly or j.mp.
Before calling this, you have to configure `twittering-bitly-login' and
`twittering-bitly-api-key'."
  (let* ((query-string
          (mapconcat
           (lambda (entry)
             (concat (car entry) "=" (cdr entry)))
           `(("login" . ,twittering-bitly-login)
             ("apiKey" . ,twittering-bitly-api-key)
             ("format" . "txt")
             ("longUrl" . ,(twittering-percent-encode longurl)))
           "&"))
         (prefix
          (cdr (assq service '((bit.ly . "http://api.bit.ly/v3/shorten?")
                               (j.mp . "http://api.j.mp/v3/shorten?")))))
         (uri (concat prefix query-string)))
    (twittering-make-http-request-from-uri "GET" nil uri)))

;;;;
;;;; Timeline spec
;;;;

;; Timeline spec as S-expression
;; - ((SERVICE-METHOD) user USER): timeline of the user whose name is USER. USER is a string.
;; - ((SERVICE-METHOD) list USER LIST):
;;     the list LIST of the user USER. LIST and USER are strings.
;;     specially,
;;       ((SERVICE-METHOD) list USER following): friends that USER is following.
;;       ((SERVICE-METHOD) list USER followers): followers of USER.
;;
;; - ((SERVICE-METHOD) direct_messages): received direct messages.
;; - ((SERVICE-METHOD) direct_messages_sent): sent direct messages.
;; - ((SERVICE-METHOD) friends): friends timeline.
;; - ((SERVICE-METHOD) home): home timeline.
;; - ((SERVICE-METHOD) mentions): mentions timeline.
;;     mentions ((SERVICE-METHOD) status containing @username) for the authenticating user.
;; - ((SERVICE-METHOD) public): public timeline.
;; - ((SERVICE-METHOD) replies): replies.
;; - ((SERVICE-METHOD) retweeted_by_me): retweets posted by the authenticating user.
;; - ((SERVICE-METHOD) retweeted_to_me): retweets posted by the authenticating user's friends.
;; - ((SERVICE-METHOD) retweets_of_me):
;;     tweets of the authenticated user that have been retweeted by others.
;;
;; - ((SERVICE-METHOD) search STRING): the result of searching with query STRING.
;; - ((SERVICE-METHOD) merge SPEC1 SPEC2 ...): result of merging timelines SPEC1 SPEC2 ...
;; - ((SERVICE-METHOD) filter REGEXP SPEC): timeline filtered with REGEXP.
;;

;; Timeline spec string
;;
;; SPEC ::= {PRIMARY | COMPOSITE} "@" SERVICE-METHOD
;; PRIMARY ::= USER | LIST | DIRECT_MESSSAGES | DIRECT_MESSSAGES_SENT
;;             | FRIENDS | HOME | MENTIONS | PUBLIC | REPLIES
;;             | RETWEETED_BY_ME | RETWEETED_TO_ME | RETWEETS_OF_ME
;;             | FOLLOWING | FOLLOWERS
;;             | SEARCH
;; COMPOSITE ::= MERGE | FILTER
;;
;; USER                  ::= /[a-zA-Z0-9_-]+/
;; LIST                  ::= USER "/" LISTNAME
;; LISTNAME              ::= /[a-zA-Z0-9_-]+/
;; DIRECT_MESSSAGES      ::= ":direct_messages"
;; DIRECT_MESSSAGES_SENT ::= ":direct_messages_sent"
;; FRIENDS               ::= ":friends"
;; HOME                  ::= ":home" | "~"
;; MENTIONS              ::= ":mentions"
;; PUBLIC                ::= ":public"
;; REPLIES               ::= ":replies" | "@"
;; RETWEETED_BY_ME       ::= ":retweeted_by_me"
;; RETWEETED_TO_ME       ::= ":retweeted_to_me"
;; RETWEETS_OF_ME        ::= ":retweets_of_me"
;; FOLLOWING             ::= USER "/following"
;; FOLLOWERS             ::= USER "/followers"
;;
;; SEARCH       ::= ":search/" QUERY_STRING "/"
;; QUERY_STRING ::= any string, where "/" is escaped by a backslash.
;; MERGE        ::= "(" MERGED_SPECS ")"
;; MERGED_SPECS ::= SPEC | SPEC "+" MERGED_SPECS
;; FILTER       ::= ":filter/" REGEXP "/" SPEC
;;

(defvar twittering-regexp-hash
  (let ((full-width-number-sign (twittering-ucs-to-char #xff03)))
    ;; Unicode Character 'FULLWIDTH NUMBER SIGN' (U+FF03)
    (concat "\\(?:#\\|" (char-to-string full-width-number-sign) "\\)")))

(defvar twittering-regexp-atmark
  (let ((full-width-commercial-at (twittering-ucs-to-char #xff20)))
    ;; Unicode Character 'FULLWIDTH COMMERCIAL AT' (U+FF20)
    (concat "\\(?:@\\|" (char-to-string full-width-commercial-at) "\\)")))

(defun twittering-timeline-spec-to-string (timeline-spec &optional shorten)
  "Convert TIMELINE-SPEC into a string.
If SHORTEN is non-nil, the abbreviated expression will be used."
  (unless (assq (twittering-extract-service) timeline-spec)
    (setq timeline-spec `((,(twittering-extract-service)) ,@timeline-spec)))

  (let* ((service (caar timeline-spec))
         (timeline-spec (cdr timeline-spec))
         (type (car timeline-spec))
         (value (cdr timeline-spec)))
    (format
     "%s@%S"
     (cond
      ;; user
      ((eq type 'user) (car value))
      ;; list
      ((eq type 'list) (concat (car value) "/" (cadr value)))
      ;; simple
      ((eq type 'direct_messages)       ":direct_messages")
      ((eq type 'direct_messages_sent)  ":direct_messages_sent")
      ((eq type 'friends)               ":friends")
      ((eq type 'home)                  (if shorten "~" ":home"))
      ((eq type 'mentions)              ":mentions")
      ((eq type 'public)                ":public")
      ((eq type 'replies)               (if shorten "@" ":replies"))
      ((eq type 'retweeted_by_me)       ":retweeted_by_me")
      ((eq type 'retweeted_to_me)       ":retweeted_to_me")
      ((eq type 'retweets_of_me)        ":retweets_of_me")

      ((eq type 'search)
       (let ((query (car value)))
         (concat ":search/"
                 (replace-regexp-in-string "/" "\\/" query nil t)
                 "/")))
      ;; composite
      ((eq type 'filter)
       (let ((regexp (car value))
             (spec (cadr value)))
         (concat ":filter/"
                 (replace-regexp-in-string "/" "\\/" regexp nil t)
                 "/"
                 (twittering-timeline-spec-to-string spec))))
      ((eq type 'merge)
       (concat "("
               (mapconcat 'twittering-timeline-spec-to-string value "+")
               ")")))

     service)))

(defun twittering-extract-timeline-spec (str &optional unresolved-aliases)
  "Extract one timeline spec from STR.
Return cons of the spec and the rest string."
  (let ((re "@\\([a-zA-Z0-9_-]+\\)"))        ; service method
    (cond
     ((null str)
      (error "STR is nil"))

     ((string-match (concat "^\\([a-zA-Z0-9_-]+\\)/\\([a-zA-Z0-9_-]+\\)" re) str)
      (let ((user (match-string 1 str))
            (listname (match-string 2 str))
            (service (intern (match-string 3 str)))
            (rest (substring str (match-end 0))))
        `(((,service) list ,user ,listname) . ,rest)))

     ((string-match (concat "^\\([a-zA-Z0-9_-]+\\)" re) str)
      (let ((user (match-string 1 str))
            (service (intern (match-string 2 str)))
            (rest (substring str (match-end 0))))
        `(((,service) user ,user) . ,rest)))

     ((string-match (concat "^~" re) str)
      (let ((service (intern (match-string 1 str)))
            (rest (substring str (match-end 0))))
        `(((,service) home) . ,rest)))

     ;; Disable this as @ is used for separating timeline name and service
     ;; name. (xwl)
     ;; ((string-match (concat "^" twittering-regexp-atmark) str)
     ;;  `((replies) . ,(substring str (match-end 0))))

     ((string-match (concat "^" twittering-regexp-hash "\\([a-zA-Z0-9_-]+\\)" re)
                    str)
      (let* ((tag (match-string 1 str))
             (service (intern (match-string 2 str)))
             (query (concat "#" tag))
             (rest (substring str (match-end 0))))
        `(((,service) search ,query) . ,rest)))

     ((string-match (concat "^:\\([a-z_/-]+\\)" re) str)
      (let ((type (match-string 1 str))
            (service (intern (match-string 2 str)))
            (following (substring str (match-end 0)))
            (alist '(("direct_messages"      direct_messages)
                     ("direct_messages_sent" direct_messages_sent)
                     ("friends"              friends)
                     ("home"                 home)
                     ("mentions"             mentions)
                     ("public"               public)
                     ("replies"              replies)
                     ("retweeted_by_me"      retweeted_by_me)
                     ("retweeted_to_me"      retweeted_to_me)
                     ("retweets_of_me"       retweets_of_me))))
        (cond
         ((assoc type alist)
          (let ((first-spec (assocref type alist)))
            `(((,service) ,@first-spec) . ,following)))
         ((string-match (concat ;; "^:search/\\(\\(.*?[^\\]\\)??\\(\\\\\\\\\\)*\\)??/"
                         "^:search/\\([^/]+\\)/"
                         re)
                        str)
          (let* ((escaped-query (or (match-string 1 str) ""))
                 (service (intern (match-string 2 str)))
                 (query (replace-regexp-in-string
                         "\\\\/" "/" escaped-query nil t))
                 (rest (substring str (match-end 0))))
            (if (not (string= "" escaped-query))
                `(((,service) search ,query) . ,rest)
              (error "\"%s\" has no valid regexp" str)
              nil)))
         ((string-match (concat "^:filter/\\(\\(.*?[^\\]\\)??\\(\\\\\\\\\\)*\\)??/" re)
                        str)
          (let* ((escaped-regexp (or (match-string 1 str) ""))
                 (service (intern (match-string 3 str)))
                 (regexp (replace-regexp-in-string
                          "\\\\/" "/" escaped-regexp nil t))
                 (following (substring str (match-end 0)))
                 (pair (twittering-extract-timeline-spec
                        following unresolved-aliases))
                 (spec (car pair))
                 (rest (cdr pair)))
            `(((,service) filter ,regexp ,spec) . ,rest)))
         ;; (error "\"%s\" has no valid regexp" str)
         ;; nil))
         (t
          (error "\"%s\" is invalid as a timeline spec" str)
          nil))))

     ;; TODO, check you later. (xwl)
     ((string-match "^\\$\\([a-zA-Z0-9_-]+\\)\\(?:(\\([^)]*\\))\\)?" str)
      (let* ((name (match-string 1 str))
             (rest (substring str (match-end 0)))
             (value (cdr-safe (assoc name twittering-timeline-spec-alias)))
             (arg (match-string 2 str)))
        (if (member name unresolved-aliases)
            (error "Alias \"%s\" includes a recursive reference" name)
          (cond
           ((stringp value)
            (twittering-extract-timeline-spec
             (concat value rest)
             (cons name unresolved-aliases)))
           ((functionp value)
            (twittering-extract-timeline-spec
             (funcall value arg)
             (cons name unresolved-aliases)))
           (t
            (error "Alias \"%s\" is undefined" name))))))
     ((string-match "^(" str)
      (let ((rest (concat "+" (substring str (match-end 0))))
            (result '()))
        (while (and rest (string-match "^\\+" rest))
          (let* ((spec-string (substring rest (match-end 0)))
                 (pair (twittering-extract-timeline-spec
                        spec-string unresolved-aliases))
                 (spec (car pair))
                 (next-rest (cdr pair)))
            (setq result (cons spec result))
            (setq rest next-rest)))
        (if (and rest (string-match "^)" rest))
            (let ((spec-list
                   (apply 'append
                          (mapcar (lambda (x) (if (eq 'merge (car x))
                                                  (cdr x)
                                                (list x)))
                                  (reverse result)))))
              (if (= 1 (length spec-list))
                  `(,(car spec-list) . ,(substring rest 1))
                `((merge ,@spec-list) . ,(substring rest 1))))
          (if rest
              ;; The string following the opening parenthesis `('
              ;; can be interpreted without errors,
              ;; but there is no corresponding closing parenthesis.
              (error "\"%s\" lacks a closing parenthesis" str))
          ;; Does not display additional error messages if an error
          ;; occurred on interpreting the string following
          ;; the opening parenthesis `('.
          nil)))

     ;; (sina) Treat all chinese string as USER. Put this match at back.
     ((string-match (concat "^\\([^@]+\\)" re) str)
      (let ((user (match-string 1 str))
            (service (intern (match-string 2 str)))
            (rest (substring str (match-end 0))))
        `(((,service) user ,user) . ,rest)))
     (t
      (error "\"%s\" is invalid as a timeline spec" str)))))

(defun twittering-extract-service (&optional spec)
  (let ((service (cond ((stringp spec)
			(when (string-match "@\\(.+\\)" spec)
			  (intern (match-string 1 spec))))
		       ((consp spec)
			(when (consp (car spec))
			  (caar spec))))))
    (unless service
      (when (twittering-current-timeline-spec)
	(setq service (caar (twittering-current-timeline-spec)))))

    ;; Fall back to twittering-service-method under `let'.
    (unless service
      (setq service twittering-service-method))

    (unless service
      (error "Null service!"))

    service))

(defun twittering-string-to-timeline-spec (spec-str)
  "Convert SPEC-STR into a timeline spec.
Return nil if SPEC-STR is invalid as a timeline spec."
  (unless (string-match "@" spec-str)
    (setq spec-str (format "%s@%S" spec-str (twittering-extract-service))))
  (let ((result-pair (twittering-extract-timeline-spec spec-str)))
    (when (and result-pair (string= "" (cdr result-pair)))
      (car result-pair))))

(defun twittering-timeline-spec-primary-p (spec)
  "Return non-nil if SPEC is a primary timeline spec.
`primary' means that the spec is not a composite timeline spec such as
`filter' and `merge'."
  (let* ((spec (cdr spec))
         (primary-spec-types
          '(user list
                 direct_messages direct_messages_sent
                 friends home mentions public replies
                 search
                 retweeted_by_me retweeted_to_me retweets_of_me))
         (type (car spec)))
    (memq type primary-spec-types)))

(defun twittering-timeline-spec-user-p (spec)
  "Return non-nil if SPEC is a user timeline spec."
  (let ((spec (cdr spec)))
    (and spec (eq (car spec) 'user))))

(defun twittering-timeline-spec-list-p (spec)
  "Return non-nil if SPEC is a list timeline spec."
  (let ((spec (cdr spec)))
    (and spec (eq (car spec) 'list))))

(defun twittering-timeline-spec-direct-messages-p (spec)
  "Return non-nil if SPEC is a timeline spec which is related of
direct_messages."
  (let ((spec (cdr spec)))
    (and spec
         (memq (car spec) '(direct_messages direct_messages_sent)))))

(defun twittering-timeline-spec-user-methods-p (spec)
  "Return non-nil if SPEC belongs to `User Methods' API."
  (let ((spec (cdr spec)))
    (and spec
         (eq (car spec) 'list)
         (member (car (last spec)) '("following" "followers")))))

(defun twittering-timeline-spec-most-active-p (spec)
  "Return non-nil if SPEC is a very active timeline spec.

For less active spec, do not update it every
`twittering-timer-interval', rather, at the start of each hour.
Or we could easily exceed requests limit of Twitter API,
currently 150/hour.  SPEC is such as '(home).  The complete list
is specified in `twittering-timeline-most-active-spec-strings'."
  (and spec
       (string-match
        (regexp-opt twittering-timeline-most-active-spec-strings)
        (twittering-timeline-spec-to-string spec))))

(defun twittering-equal-string-as-timeline (spec-str1 spec-str2)
  "Return non-nil if SPEC-STR1 equals SPEC-STR2 as a timeline spec."
  (if (and (stringp spec-str1) (stringp spec-str2))
      (let ((spec1 (twittering-string-to-timeline-spec spec-str1))
            (spec2 (twittering-string-to-timeline-spec spec-str2)))
        (equal spec1 spec2))
    nil))

;;;;
;;;; Retrieved statuses (timeline data)
;;;;

(defun twittering-current-timeline-id-table (&optional spec)
  (let ((spec (or spec (twittering-current-timeline-spec))))
    (if spec
        (elt (gethash spec twittering-timeline-data-table) 0)
      nil)))

(defun twittering-current-timeline-referring-id-table (&optional spec)
  "Return the hash from a ID to the ID of the first observed status
referring the former ID."
  (let ((spec (or spec (twittering-current-timeline-spec))))
    (if spec
        (elt (gethash spec twittering-timeline-data-table) 1)
      nil)))

(defun twittering-current-timeline-data (&optional spec)
  (let ((spec (or spec (twittering-current-timeline-spec))))
    (if spec
        (elt (gethash spec twittering-timeline-data-table) 2)
      nil)))

(defun twittering-remove-timeline-data (&optional spec)
  (let ((spec (or spec (twittering-current-timeline-spec))))
    (remhash spec twittering-timeline-data-table)))

(defun twittering-find-status (id)
  (let ((result nil))
    (maphash
     (lambda (spec pair)
       (let* ((id-table (car pair))
              (entry (gethash id id-table)))
         ;; Take the most detailed status.
         (when (and entry
                    (or (null result) (< (length result) (length entry))))
           (setq result entry))))
     twittering-timeline-data-table)
    result))

(defun twittering-delete-status-from-data-table (id)
  (let ((modified-spec nil))
    (maphash
     (lambda (spec data)
       (let* ((id-table (elt data 0))
              (referring-id-table (elt data 1))
              (timeline-data (elt data 2))
              (status (gethash id id-table)))
         (when status
           (remhash id id-table)
           ;; Here, `referring-id-table' is not modified.
           ;; Therefore, the retweet observed secondly will not appear even
           ;; if the retweet observed first for the same tweet is deleted.
           (setq modified-spec
                 (cons `(,spec
                         ,id-table
                         ,referring-id-table
                         ,(remove status timeline-data))
                       modified-spec)))))
     twittering-timeline-data-table)
    (mapc
     (lambda (data)
       (let* ((spec (car data))
              (buffer (twittering-get-buffer-from-spec spec)))
         (puthash spec (cdr data) twittering-timeline-data-table)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (save-excursion
               (twittering-for-each-property-region
                'id
                (lambda (beg end value)
                  (when (twittering-status-id= id value)
                    (let ((buffer-read-only nil)
                          (separator-pos (min (point-max) (1+ end))))
                      (delete-region beg separator-pos)
                      (goto-char beg))))
                buffer))))))
     modified-spec)))

(defun twittering-get-replied-statuses (id &optional count)
  "Return a list of replied statuses starting from the status specified by ID.
Statuses are stored in ascending-order with respect to their IDs."
  (let ((result nil)
        (status (twittering-find-status id)))
    (while
        (and (if (numberp count)
                 (<= 0 (setq count (1- count)))
               t)
             (let ((replied-id (or (assqref 'in-reply-to-status-id status) "")))
               (unless (string= "" replied-id)
                 (let ((replied-status (twittering-find-status replied-id)))
                   (when replied-status
                     (setq result (cons replied-status result))
                     (setq status replied-status)
                     t))))))
    result))

(defun twittering-have-replied-statuses-p (id)
  (let ((status (twittering-find-status id)))
    (when status
      (let ((replied-id (assqref 'in-reply-to-status-id status)))
        (and replied-id (not (string= "" replied-id)))))))

(defun twittering-add-statuses-to-timeline-data (statuses &optional spec)
  (let* ((spec (or spec (twittering-current-timeline-spec)))
         (id-table
          (or (twittering-current-timeline-id-table spec)
              (make-hash-table :test 'equal)))
         (referring-id-table
          (or (twittering-current-timeline-referring-id-table spec)
              (make-hash-table :test 'equal)))
         (timeline-data (twittering-current-timeline-data spec)))
    (let ((new-statuses
           (remove nil
                   (mapcar
                    (lambda (status)
                      (let ((id (assqref 'id status))
                            (retweeted-id (assqref 'retweeted-id status)))
                        (unless (or (not retweeted-id)
                                    (gethash retweeted-id referring-id-table))
                          ;; Store the id of the first observed tweet
                          ;; that refers `retweeted-id'.
                          (puthash retweeted-id id referring-id-table))
                        (if (gethash id id-table)
                            nil
                          (puthash id status id-table)
                          (puthash id id referring-id-table)
                          `((source-spec . ,spec)
                            ,@status))))
                    statuses))))
      (when new-statuses
        (puthash spec `(,id-table
                        ,referring-id-table
                        ;; Decreasingly by `id' except `followers', which is
                        ;; sorted by recency one starts following me.
                        ,(append new-statuses timeline-data))
                 twittering-timeline-data-table)
        (when (twittering-jojo-mode-p spec)
          (mapc (lambda (status)
                  (twittering-update-jojo (assqref 'user-screen-name status)
                                          (assqref 'text status)))
                new-statuses))
        (let* ((twittering-new-tweets-spec spec)
               (twittering-new-tweets-statuses new-statuses)
               (spec-string (twittering-timeline-spec-to-string spec))
               (twittering-new-tweets-count
                (if (twittering-timeline-spec-user-methods-p spec)
                    (twittering-count-unread-for-user-methods spec statuses)
                  (count-if (lambda (st) (twittering-is-unread-status-p st spec))
                            new-statuses))))
          (when (member spec-string twittering-cache-spec-strings)
            (let ((latest
                   (if (twittering-timeline-spec-user-methods-p spec)
                       (substring-no-properties
                        (assqref 'user-screen-name (car statuses)))
                     (substring-no-properties
                      (assqref 'id (car new-statuses))))))
              (setq twittering-cache-lastest-statuses
                    `((,spec-string . ,latest)
                      ,@(remove-if (lambda (entry) (equal spec-string (car entry)))
                                   twittering-cache-lastest-statuses)))))
          (run-hooks 'twittering-new-tweets-hook)
          (if (and (twittering-timeline-spec-user-methods-p spec)
                   ;; Insert all when buffer is empty.
                   (> (buffer-size) 0))
              (twittering-take twittering-new-tweets-count statuses)
            new-statuses))))))

(defun twittering-timeline-data-collect (&optional spec timeline-data)
  "Collect visible statuses for `twittering-render-timeline'."
  (let* ((spec (or spec (twittering-current-timeline-spec)))
         (referring-id-table
          (twittering-current-timeline-referring-id-table spec))
         (timeline-data
          (or timeline-data (twittering-current-timeline-data spec))))
    (remove
     nil
     (mapcar
      (lambda (status)
        (let ((id (assqref 'id status))
              (retweeted-id (assqref 'retweeted-id status)))
          (cond
           ((twittering-timeline-spec-user-methods-p spec)
            status)
           ((not retweeted-id)
            ;; `status' is not a retweet.
            status)
           ((and retweeted-id
                 (twittering-status-id=
                  id (gethash retweeted-id referring-id-table)))
            ;; `status' is the first retweet.
            status)
           (t
            nil))))
      timeline-data))))

(defun twittering-timeline-data-is-previous-p (timeline-data)
  "Are TIMELINE-DATA previous statuses?
This is done by comparing statues in current buffer with TIMELINE-DATA."
  (let ((status (car timeline-data)))
    (if (twittering-timeline-spec-user-methods-p
         (twittering-current-timeline-spec))
        (let* ((previous-cursor (cdr-safe (assq 'previous-cursor status)))
               (new-follower-p (string= previous-cursor "0")))
          (not new-follower-p))
      (let* ((buf-id (get-text-property
                      (twittering-get-current-status-head
                       (if twittering-reverse-mode (point-min) (point-max)))
                      'id))
             (id (assqref 'id status)))
        (and buf-id (twittering-status-id< id buf-id))))))

(defun twittering-is-unread-status-p (status &optional spec)
  (let ((spec-string
         (twittering-timeline-spec-to-string
          (or spec (setq spec (twittering-current-timeline-spec))))))
    (cond
     ((or (and twittering-new-tweets-count-excluding-me
               (twittering-my-status-p status)
               (not (equal spec '(retweets_of_me))))
          (and twittering-new-tweets-count-excluding-replies-in-home
               (equal spec '(home))
               (twittering-is-replies-p status)))
      nil)
     ((member spec-string twittering-cache-spec-strings)
      (twittering-status-id<
       (assocref spec-string twittering-cache-lastest-statuses)
       (assqref 'id status)))
     (t
      t))))

(defun twittering-count-unread-for-user-methods (spec new-statuses)
  (let ((latest-username
         (or (with-current-buffer (twittering-get-buffer-from-spec spec)
               (goto-char (funcall (if twittering-reverse-mode 'point-max 'point-min)))
               (get-text-property (twittering-get-current-status-head) 'username))
             (let ((spec-string (twittering-timeline-spec-to-string spec)))
               (when (member spec-string twittering-cache-spec-strings)
                 (assocref spec-string twittering-cache-lastest-statuses))))))
    (if (not latest-username)
        (length new-statuses)
      (let ((statuses new-statuses)
            (count 0))
        (while (and statuses
                    (not (string= latest-username
                                  (assqref 'user-screen-name (car statuses)))))
          (setq count (1+ count)
                statuses (cdr statuses)))
        count))))

;;;;
;;;; URIs related to a tweet
;;;;

(defun twittering-get-status-url (username &optional id)
  "Generate a URL of a user or a specific status."
  (funcall (twittering-lookup-service-method-table 'status-url) username id))

(defun twittering-get-status-url-twitter (username &optional id)
  "Generate status URL for Twitter."
  (if id
      (format "http://%s/%s/status/%s" (twittering-lookup-service-method-table 'web) username id)
    (format "http://%s/%s" (twittering-lookup-service-method-table 'web) username)))

(defun twittering-get-status-url-statusnet (username &optional id)
  "Generate status URL for StatusNet."
  (if id
      (format "http://%s/%s/notice/%s"
              (twittering-lookup-service-method-table 'web)
              (twittering-lookup-service-method-table 'web-prefix)
              id)
    (format "http://%s/%s/%s"
            (twittering-lookup-service-method-table 'web)
            (twittering-lookup-service-method-table 'web-prefix)
            username)))

(defun twittering-get-status-url-sina (username &optional id)
  "Generate status URL for Sina."
  (if id
      ;; (twittering-get-simple-sync 'query-mid
      ;;                                   `((username . ,username)
      ;;                                     (id . ,id)))
      (format "http://api.t.sina.com.cn/%s/statuses/%s?s=6cm7D0"
              username
              id)
    (format "http://%s/%s"
            (twittering-lookup-service-method-table 'web)
            username)))

(defun twittering-get-search-url (query-string)
  "Generate a URL for searching QUERY-STRING."
  (funcall (twittering-lookup-service-method-table 'search-url)
           query-string))

(defun twittering-get-search-url-twitter (query-string)
  (format "http://%s/search?q=%s"
          (twittering-lookup-service-method-table 'web) (twittering-percent-encode query-string)))

(defun twittering-get-search-url-statusnet (query-string)
  (if (string-match "^#\\(.+\\)" query-string)
      (format "http://%s/%s/tag/%s"
              (twittering-lookup-service-method-table 'web)
              (twittering-lookup-service-method-table 'web-prefix)
              (twittering-percent-encode (match-string 1 query-string)))
    (format "http://%s/search?q=%s"
            (twittering-lookup-service-method-table 'web) (twittering-percent-encode query-string))))

(defun twittering-switch-to-unread-timeline ()
  (interactive)
  (when twittering-unread-status-info
    (switch-to-buffer (caar twittering-unread-status-info))))

;;;;
;;;; Comparison of status IDs
;;;;

(defun twittering-status-id< (id1 id2)
  (let ((len1 (length id1))
        (len2 (length id2)))
    (cond
     ((= len1 len2) (string< id1 id2))
     ((< len1 len2) t)
     (t nil))))

(defun twittering-status-id= (id1 id2)
  (equal id1 id2))

;;;;
;;;; Process info
;;;;

(defun twittering-register-process (proc spec &optional str)
  (let ((str (or str (twittering-timeline-spec-to-string spec))))
    (add-to-list 'twittering-process-info-alist `(,proc ,spec ,str))))

(defun twittering-release-process (proc)
  (let ((pair (assoc proc twittering-process-info-alist)))
    (when pair
      (setq twittering-process-info-alist
            (delq pair twittering-process-info-alist)))))

(defun twittering-get-timeline-spec-from-process (proc)
  (let ((entry (assoc proc twittering-process-info-alist)))
    (if entry
        (elt entry 1)
      nil)))

(defun twittering-get-timeline-spec-string-from-process (proc)
  (let ((entry (assoc proc twittering-process-info-alist)))
    (if entry
        (elt entry 2)
      nil)))

(defun twittering-find-processes-for-timeline-spec (spec)
  (apply 'append
         (mapcar
          (lambda (pair)
            (let ((proc (car pair))
                  (spec-info (cadr pair)))
              (if (equal spec-info spec)
                  `(,proc)
                nil)))
          twittering-process-info-alist)))

(defun twittering-remove-inactive-processes ()
  (let ((inactive-statuses '(nil closed exit failed signal)))
    (setq twittering-process-info-alist
          (apply 'append
                 (mapcar
                  (lambda (pair)
                    (let* ((proc (car pair))
                           (info (cdr pair))
                           (status (process-status proc)))
                      (if (memq status inactive-statuses)
                          nil
                        `((,proc ,@info)))))
                  twittering-process-info-alist)))))

(defun twittering-process-active-p (&optional spec)
  (twittering-remove-inactive-processes)
  (if spec
      (twittering-find-processes-for-timeline-spec spec)
    twittering-process-info-alist))

;;;;
;;;; Server info
;;;;

(defun twittering-update-server-info (header-str)
  (let* ((header-info (twittering-make-header-info-alist header-str))
         (new-entry-list (mapcar 'car header-info)))
    (when (remove t (mapcar
                     (lambda (entry)
                       (equal (assoc entry header-info)
                              (assoc entry twittering-server-info-alist)))
                     new-entry-list))
      (setq twittering-server-info-alist
            (append header-info
                    (remove nil (mapcar
                                 (lambda (entry)
                                   (if (member (car entry) new-entry-list)
                                       nil
                                     entry))
                                 twittering-server-info-alist))))
      (when twittering-display-remaining
        (mapc (lambda (buffer)
                (with-current-buffer buffer
                  (twittering-update-mode-line)))
              (twittering-get-buffer-list))))
    header-info))

(defun twittering-get-server-info (field)
  (let* ((table
          '((ratelimit-remaining . "X-RateLimit-Remaining")
            (ratelimit-limit . "X-RateLimit-Limit")
            (ratelimit-reset . "X-RateLimit-Reset")))
         (numeral-field '(ratelimit-remaining ratelimit-limit))
         (unix-epoch-time-field '(ratelimit-reset))
         (field-name (assqref field table))
         (field-value (assocref field-name twittering-server-info-alist)))
    (when (and field-name field-value)
      (cond
       ((memq field numeral-field)
        (string-to-number field-value))
       ((memq field unix-epoch-time-field)
        (seconds-to-time (string-to-number (concat field-value ".0"))))
       (t
        nil)))))

(defun twittering-get-ratelimit-remaining ()
  (or (twittering-get-server-info 'ratelimit-remaining)
      0))

(defun twittering-get-ratelimit-limit ()
  (or (twittering-get-server-info 'ratelimit-limit)
      0))

;;;;
;;;; Abstract layer for Twitter API
;;;;

(defun twittering-api-path (&rest params)
  (mapconcat 'identity `(,(twittering-lookup-service-method-table 'api-prefix)
                         ,@params) ""))

(defun twittering-call-api (command args-alist &optional additional-info)
  "Call Twitter API and return the process object for the request.
COMMAND is a symbol specifying API. ARGS-ALIST is an alist specifying
arguments for the API corresponding to COMMAND. Each key of ARGS-ALIST is a
symbol.
ADDITIONAL-INFO is used as an argument ADDITIONAL-INFO of
`twittering-send-http-request'. Sentinels associated to the returned process
receives it as the fourth argument. See also the function
`twittering-send-http-request'.

The valid symbols as COMMAND follows:
retrieve-timeline -- Retrieve a timeline.
  Valid key symbols in ARGS-ALIST:
    timeline-spec -- the timeline spec to be retrieved.
    timeline-spec-string -- the string representation of the timeline spec.
    number -- (optional) how many tweets are retrieved. It must be an integer.
      If nil, `twittering-number-of-tweets-on-retrieval' is used instead.
      The maximum for search timeline is 100, and that for other timelines is
      `twittering-max-number-of-tweets-on-retrieval'.
      If the given number exceeds the maximum, the maximum is used instead.
    max_id -- (optional) the maximum ID of retrieved tweets.
    since_id -- (optional) the minimum ID of retrieved tweets.
    clean-up-sentinel -- (optional) the clean-up sentinel that post-processes
      the buffer associated to the process. This is used as an argument
      CLEAN-UP-SENTINEL of `twittering-send-http-request' via
      `twittering-http-get'.
    page -- (optional and valid only for favorites timeline) which page will
      be retrieved.
get-list-index -- Retrieve list names owned by a user.
  Valid key symbols in ARGS-ALIST:
    username -- the username.
    sentinel -- the sentinel that processes retrieved strings. This is used
      as an argument SENTINEL of `twittering-send-http-request'
      via `twittering-http-get'.
    clean-up-sentinel -- (optional) the clean-up sentinel that post-processes
      the buffer associated to the process. This is used as an argument
      CLEAN-UP-SENTINEL of `twittering-send-http-request' via
      `twittering-http-get'.
create-friendships -- Follow a user.
  Valid key symbols in ARGS-ALIST:
    username -- the username which will be followed.
destroy-friendships -- Unfollow a user.
  Valid key symbols in ARGS-ALIST:
    username -- the username which will be unfollowed.
create-favorites -- Mark a tweet as a favorite.
  Valid key symbols in ARGS-ALIST:
    id -- the ID of the target tweet.
destroy-favorites -- Remove a mark of a tweet as a favorite.
  Valid key symbols in ARGS-ALIST:
    id -- the ID of the target tweet.
update-status -- Post a tweet.
  Valid key symbols in ARGS-ALIST:
    status -- the string to be posted.
    in-reply-to-status-id -- (optional) the ID of a status that this post is
      in reply to.
destroy-status -- Destroy a tweet posted by the authenticated user itself.
  Valid key symbols in ARGS-ALIST:
    id -- the ID of the target tweet.
retweet -- Retweet a tweet.
  Valid key symbols in ARGS-ALIST:
    id -- the ID of the target tweet.
verify-credentials -- Verify the current credentials.
  Valid key symbols in ARGS-ALIST:
    sentinel -- the sentinel that processes returned information. This is used
      as an argument SENTINEL of `twittering-send-http-request'
      via `twittering-http-get'.
    clean-up-sentinel -- the clean-up sentinel that post-processes the buffer
      associated to the process. This is used as an argument CLEAN-UP-SENTINEL
      of `twittering-send-http-request' via `twittering-http-get'.
send-direct-message -- Send a direct message.
  Valid key symbols in ARGS-ALIST:
    username -- the username who the message is sent to.
    status -- the sent message.
block -- Block a user.
  Valid key symbols in ARGS-ALIST:
    user-id -- the user-id that will be blocked.
    username -- the username who will be blocked.
  This command requires either of the above key. If both are given, `user-id'
  will be used in REST API.
block-and-report-as-spammer -- Block a user and report him or her as a spammer.
  Valid key symbols in ARGS-ALIST:
    user-id -- the user-id that will be blocked.
    username -- the username who will be blocked.
  This command requires either of the above key. If both are given, `user-id'
  will be used in REST API."
  (unless additional-info
    (setq additional-info
            `((timeline-spec . ,(twittering-current-timeline-spec))
              (timeline-spec-string . ,(twittering-current-timeline-spec-string)))))

  (let ((api-host (twittering-lookup-service-method-table 'api))
        (spec (assqref 'timeline-spec args-alist))
        (id (assqref 'id args-alist))
        (username (assqref 'username args-alist))
        (sentinel (assqref 'sentinel args-alist))
        (sina? (eq (twittering-extract-service) 'sina)))
    (case command
      ((retrieve-timeline)
       ;; Retrieve a timeline.
       (let* ((spec-string (assqref 'timeline-spec-string args-alist))
              (spec-type (cadr spec))
              (max-number (if (eq 'search spec-type)
                              100 ;; FIXME: refer to defconst.
                            twittering-max-number-of-tweets-on-retrieval))
              (number
               (let ((number
                      (or (assqref 'number args-alist)
                          (let* ((default-number 20)
                                 (n twittering-number-of-tweets-on-retrieval))
                            (cond
                             ((integerp n) n)
                             ((string-match "^[0-9]+$" n) (string-to-number n 10))
                             (t default-number))))))
                 (min (max 1 number) max-number)))
              (number-str (number-to-string number))
              (max_id (assqref 'max_id args-alist))
              (since_id (assqref 'since_id args-alist))
              (cursor (assqref 'cursor args-alist))
              (word (when (eq 'search spec-type)
                      (caddr spec)))
              (parameters
               `(,@(when max_id `(("max_id" . ,max_id)))
                 ,@(when since_id `(("since_id" . ,since_id)))
                 ,@(when cursor `(("cursor" . ,cursor)))
                 ,@(cond
                    ((eq spec-type 'search)
                     `(("q" . ,word)
                       ("rpp" . ,number-str)))
                    ((eq spec-type 'list)
                     (let ((username (elt (cdr spec) 1))
                           (list-name (elt (cdr spec) 2)))
                       (if (member list-name '("following" "followers"))
                           `(("count" . ,number-str)
                             ("screen_name" . ,username))
                         `(("per_page" . ,number-str)))))
                    ((memq spec-type '(user friends mentions public))
                     `(("count" . ,number-str)
                       ("include_rts" . "true")))
                    (t
                     `(("count" . ,number-str))))))
              (format (if (eq spec-type 'search)
                          "atom"
                        "xml"))
              (simple-spec-list
               `((direct_messages      . "direct_messages")
                 (direct_messages_sent . "direct_messages/sent")

                 (friends         . "statuses/friends_timeline")
                 (home            . "statuses/home_timeline")
                 (mentions        . "statuses/mentions")
                 (public          . "statuses/public_timeline")
                 (replies         . ,(if (eq (twittering-extract-service) 'sina)
                                         "statuses/comments_timeline"
                                       "statuses/replies"))
                 (retweeted_by_me . "statuses/retweeted_by_me")
                 (retweeted_to_me . "statuses/retweeted_to_me")
                 (retweets_of_me  . "statuses/retweets_of_me")

                 (search . "search")))
              (host (cond ((eq spec-type 'search) (twittering-lookup-service-method-table 'search))
                          (t api-host)))
              (method
               (cond
                ((eq spec-type 'user)
                 (let ((username (elt (cdr spec) 1)))
                   (if (eq (twittering-extract-service) 'sina)
                       (progn
                         (setq parameters `(,@parameters ("id" . ,username)))
                         (twittering-api-path "statuses/user_timeline"))
                     (twittering-api-path "statuses/user_timeline/" username))))
                ((eq spec-type 'list)
                 (let ((u (elt (cdr spec) 1))
                       (l (elt (cdr spec) 2)))
                   (twittering-api-path
                    (cond
                     ((string= l "followers") "statuses/followers")
                     ((string= l "following") "statuses/friends")
                     ((string= l "favorites") (concat "favorites/" u))
                     (t (concat "" u "/lists/" l "/statuses"))))))
                ((eq spec-type 'search)
                 (twittering-lookup-service-method-table 'search-method))
                ((assq spec-type simple-spec-list)
                 (twittering-api-path (assqref spec-type simple-spec-list)))
                (t nil)))
              (clean-up-sentinel (assqref 'clean-up-sentinel args-alist)))
         (if (and host method)
             (twittering-http-get host method parameters format
                                  additional-info nil clean-up-sentinel)
           (error "Invalid timeline spec"))))

      ;; List methods
      ((get-list-index)                        ; Get list names.
       (let ((clean-up-sentinel (assqref 'clean-up-sentinel args-alist)))
         (twittering-http-get api-host
                              (twittering-api-path username "/lists")
                              t nil additional-info sentinel clean-up-sentinel)))
      ((get-list-subscriptions)
       (twittering-http-get api-host
                            (twittering-api-path username "/lists/subscriptions")
                            t nil additional-info sentinel))

      ((get-list-memberships)
       (twittering-http-get api-host
                            (twittering-api-path username "/lists/memberships")
                            t nil additional-info sentinel))

      ;; Friendship Methods
      ((create-friendships)
       (twittering-http-post api-host
                             (twittering-api-path "friendships/create")
                             `(("screen_name" . ,username))
                             nil
                             additional-info))
      ((destroy-friendships)
       (twittering-http-post api-host
                             (twittering-api-path "friendships/destroy")
                             `(("screen_name" . ,username))
                             nil
                             additional-info))
      ((show-friendships)
       (twittering-http-get api-host
                            (twittering-api-path "friendships/show")
                            `(("target_screen_name" . ,username))
                            nil
                            additional-info
                            sentinel))

      ;; Favorite Methods
      ((create-favorites)
       (twittering-http-post api-host
                             (twittering-api-path "favorites/create/" id)
                             nil nil additional-info))
      ((destroy-favorites)
       (twittering-http-post api-host
                             (twittering-api-path "favorites/destroy/" id)
                             nil nil additional-info))

      ;; List Subscribers Methods
      ((subscribe-list)
       (twittering-http-post api-host
                             (twittering-api-path
                              (apply 'format "%s/%s/subscribers" (cddr spec)))
                             nil nil additional-info))
      ((unsubscribe-list)
       (twittering-http-post api-host
                             (twittering-api-path
                              (apply 'format "%s/%s/subscribers" (cddr spec)))
                             '(("_method" . "DELETE"))
                             nil additional-info))

      ;; List Members Methods
      ((add-list-members)
       (twittering-http-post api-host
                             (twittering-api-path
                              (apply 'format "%s/%s/members" (cddr spec)))
                             `(("id" . ,id))
                             nil additional-info))
      ((delete-list-members)
       (twittering-http-post api-host
                             (twittering-api-path
                              (apply 'format "%s/%s/members" (cddr spec)))
                             `(("id" . ,id)
                               ("_method" . "DELETE"))
                             nil additional-info))

      ((update-status)
       ;; Post a tweet.
       (let* ((status (assqref 'status args-alist))
              (id (assqref 'in-reply-to-status-id args-alist))
              (retweeting? (assqref 'retweeting? args-alist))
              (st (twittering-find-status id))
              (in-reply-to-status (assqref 'in-reply-to-status st))
              (original-id (assqref 'id in-reply-to-status))
              (retweeted-status  (assqref 'retweeted-status st))
              (comment? (and sina? id (not retweeting?)))
              (parameters
               `((,(if comment? "comment" "status") . ,status)
                 ,@(when (eq (twittering-get-accounts 'auth) 'basic)
                     '(("source" . "twmode")))
                 ,@(when id
                     (if sina?
                         (cond
                          (original-id        ; comment to comment
                           `(("id" . ,original-id)
                             ("cid" . ,id)))
                          (retweeting? ; retweet with comments
                           `(("in_reply_to_status_id" . ,id)))
                          (t                ; comment
                           `(("id" . ,id))))
                       `(("in_reply_to_status_id" . ,id)))))))
         (twittering-http-post api-host
                               (twittering-api-path "statuses/"
                                                    (if comment? "comment" "update"))
                               parameters
                               nil
                               additional-info)))
      ((destroy-status)
       (twittering-http-post api-host
                             (twittering-api-path "statuses/destroy" id)
                             nil nil additional-info))
      ((retweet)
       (twittering-http-post api-host
                             (twittering-api-path "statuses/retweet/" id)
                             nil
                             nil
                             additional-info))

      ;; Account Resources
      ((verify-credentials)                ; Verify the account.
       (let ((clean-up-sentinel (assqref 'clean-up-sentinel args-alist)))
         (twittering-http-get api-host
                              (twittering-api-path "account/verify_credentials")
                              nil nil additional-info sentinel clean-up-sentinel)))

      ((update-profile-image)
       (let* ((image (assqref 'image args-alist))
              (image-type (image-type-from-file-header image)))
         (twittering-http-post api-host
                               (twittering-api-path "account/update_profile_image")
                               `(("image" . ,(format "@%s;type=image/%s" image image-type)))
                               nil additional-info)))

      ((send-direct-message)
       ;; Send a direct message.
       (let ((parameters
              `(("screen_name" . ,(assqref 'username args-alist))
                ("text" . ,(assqref 'status args-alist)))))
         (twittering-http-post api-host
                               (twittering-api-path "direct_messages/new")
                               parameters
                               nil
                               additional-info)))

      ;; Tweet Methods
      ((show)
       (twittering-http-get api-host
                            (twittering-api-path "statuses/show/" id)
                            nil nil additional-info))

      ((block)
       ;; Block a user.
       (let* ((user-id (assqref 'user-id args-alist))
              (parameters (if user-id
                              `(("user_id" . ,user-id))
                            `(("screen_name" . ,username)))))
         (twittering-http-post api-host
                               (twittering-api-path "blocks/create")
                               parameters
                               nil
                               additional-info)))

      ((block-and-report-as-spammer)
       ;; Report a user as a spammer and block him or her.
       (let* ((user-id (cdr (assq 'user-id args-alist)))
              (parameters (if user-id
                              `(("user_id" . ,user-id))
                            `(("screen_name" . ,username)))))
         (twittering-http-post api-host
                               (twittering-api-path "report_spam")
                               parameters
                               nil
                               additional-info)))


      ;; Sina Weibo Specific Methods
      ;; ---------------------------
      ((counts)
       (twittering-http-get api-host
                            (twittering-api-path "statuses/counts")
                            ;; USERNAME treated as IDS here
                            `(("ids" . ,username))
                            nil
                            additional-info
                            sentinel))

      ((emotions)
       (twittering-http-get api-host
                            (twittering-api-path "emotions")
                            nil
                            nil
                            additional-info
                            sentinel))

      ;; mid<->id
      ;;   http://api.t.sina.com.cn/queryid.json?mid=5KD0TZiyL24&isBase62=1&type=1
      ;;   http://api.t.sina.com.cn/querymid.json?id=6401236707&type=1
      ;; the other way (id->mid)
      ;;   http://api.t.sina.com.cn/$uid/statuses/$tid?s=6cm7D0"

      ;; ((get-tweet-url)                        ; FIXME: doesn't work??
      ;;  (twittering-http-get (twittering-lookup-service-method-table 'api)
      ;;                             (twittering-api-path username "/statuses/" id)
      ;;                             nil
      ;;                             nil
      ;;                             additional-info
      ;;                             sentinel))

      ;; ((query-mid)
      ;;  (twittering-http-get (twittering-lookup-service-method-table 'api)
      ;;                             (twittering-api-path "querymid")
      ;;                             `(("id" . ,id)
      ;;                               ("type" . "1"))
      ;;                             nil
      ;;                             additional-info
      ;;                             sentinel))
      ;; ((query-id)
      ;;  (twittering-http-get (twittering-lookup-service-method-table 'api)
      ;;                             (twittering-api-path "id")
      ;;                             `(("id" . ,id)
      ;;                               ("type" . "1")
      ;;                               ("isBase62" . "1"))
      ;;                             nil
      ;;                             additional-info
      ;;                             sentinel))

      )))

;;;;
;;;; Account authorization
;;;;

(defun twittering-get-username ()
  twittering-username)

(defun twittering-account-authorized-p ()
  (eq (twittering-get-account-authorization) 'authorized))
(defun twittering-account-authorization-queried-p ()
  (eq (twittering-get-account-authorization) 'queried))

(defun twittering-prepare-account-info ()
  "Return a pair of username and password.
If `twittering-username' is nil, read it from the minibuffer.
If `twittering-password' is nil, read it from the minibuffer."
  (let* ((username (or (twittering-get-accounts 'username)
                       (read-string "your twitter username: ")))
         (password (or (twittering-get-accounts 'password)
                       (read-passwd (format "%s's twitter password: "
                                            username)))))
    `(,username . ,password)))

(defun twittering-has-oauth-access-token-p ()
  (let ((required-entries '("oauth_token" "oauth_token_secret"))
         (any-entries '("user_id" "screen_name"))
         (pred (lambda (key)
                 (assocref key (twittering-lookup-oauth-access-token-alist)))))
    (and (every pred required-entries) (some pred any-entries))))

(defvar twittering-private-info-file-loaded-p nil)

(defun twittering-verify-credentials ()
  (cond
   ((or (twittering-account-authorized-p)
        (twittering-account-authorization-queried-p))
    nil)
   ((and (memq (twittering-get-accounts 'auth) '(oauth xauth))
         (or (null (twittering-lookup-service-method-table 'oauth-consumer-key))
             (null (twittering-lookup-service-method-table 'oauth-consumer-secret))))
    (message "Consumer for OAuth is not specified.")
    nil)
   ((and twittering-use-master-password
         (not (twittering-capable-of-encryption-p)))
    (message "You need GnuPG and (EasyPG or alpaca.el) for master password!")
    nil)

   ((memq (twittering-get-accounts 'auth) '(oauth xauth))
    (let ((ok nil))
      (when (and (not twittering-private-info-file-loaded-p) ; file not yet loaded
                 twittering-use-master-password
                 (twittering-capable-of-encryption-p)
                 (file-exists-p twittering-private-info-file))
        (setq twittering-private-info-file-loaded-p t)
        (when (and (twittering-load-private-info-with-guide)
                   (twittering-has-oauth-access-token-p))
          (message "The authorized token is loaded.")
          (twittering-update-account-authorization 'queried)
          (let ((proc
                 (twittering-call-api
                  'verify-credentials
                  `((sentinel
                     . twittering-http-get-verify-credentials-sentinel)
                    (clean-up-sentinel
                     . twittering-http-get-verify-credentials-clean-up-sentinel))
                  `(,(if (eq (twittering-extract-service) 'sina)
                        `(user_id . ,(assocref "user_id" (twittering-lookup-oauth-access-token-alist)))
                      `(username . ,(assocref "screen_name" (twittering-lookup-oauth-access-token-alist))))
                    (password . nil)
		    (service . ,(twittering-extract-service))))))
            (cond
             ((null proc)
              (twittering-update-account-authorization nil)
              (message "Authorization failed. Type M-x twit to retry.")
              (twittering-update-oauth-access-token-alist '()))
             (t
              ;; wait for verification to finish.
              (while (twittering-account-authorization-queried-p)
                (sit-for 0.1))
              (setq ok t))))))

      (unless ok
        ;; (message "Failed to load an authorized token from \"%s\".  Renewing token..."
        ;;          twittering-private-info-file)
        ;; (sit-for 0.5))
        (setq ok (twittering-has-oauth-access-token-p))
        (cond
         ((eq (twittering-get-accounts 'auth) 'oauth)
          (unless ok
            (let* ((scheme (if twittering-oauth-use-ssl
                               "https"
                             "http"))
                   (request-token-url
                    (concat scheme (twittering-lookup-service-method-table
                                    'oauth-request-token-url-without-scheme)))
                   (access-token-url
                    (concat scheme (twittering-lookup-service-method-table
                                    'oauth-access-token-url-without-scheme)))
                   (token-alist
                    (twittering-oauth-get-access-token
                     request-token-url
                     (lambda (token)
                       (concat scheme
                               (twittering-lookup-service-method-table
                                'oauth-authorization-url-base-without-scheme)
                               token))
                     access-token-url
                     (twittering-lookup-service-method-table 'oauth-consumer-key)
                     (twittering-lookup-service-method-table 'oauth-consumer-secret)
                     "twittering-mode")))
              (cond
               ((and (assoc "oauth_token" token-alist)
                     (assoc "oauth_token_secret" token-alist)
                     (or (assoc "screen_name" token-alist)
                         (assoc "user_id" token-alist)))
                (let ((username (cdr (or (assoc "screen_name" token-alist)
                                         (assoc "user_id" token-alist)))))
                  (twittering-update-oauth-access-token-alist token-alist)
                  (setq twittering-username username)
                  ;; (twittering-update-account-authorization 'authorized)
                  ;; (twittering-start)
                  (setq ok t)
                  (message "Authorization for the account \"%s\" succeeded."
                           username)
                  (when (and twittering-use-master-password
                             (twittering-capable-of-encryption-p))
                    ;; Only save when we authenticate all enabled services.
                    (when (>= (length twittering-oauth-access-token-alist)
                              (length twittering-enabled-services))
                      ;; (when (and (file-exists-p twittering-private-info-file)
                      ;;                  (not (y-or-n-p (format "Delete previous `%s' first? "
                      ;;                                         twittering-private-info-file))))
                      ;;         (error "File `%s' already exists, try removing it first"
                      ;;                twittering-private-info-file))
                      (twittering-save-private-info-with-guide)))))
               (t
                (message "Authorization via OAuth failed. Type M-x twit to retry.")))))

          (when ok
            (twittering-update-account-authorization 'authorized)
            (twittering-start)))

         ;; TODO, handle you later (xwl)
         ((eq (twittering-get-accounts 'auth) 'xauth)
          (let* ((account-info (twittering-prepare-account-info))
                 (scheme (if twittering-oauth-use-ssl
                             "https"
                           "http"))
                 (access-token-url
                  (concat scheme (twittering-lookup-service-method-table
                                  'oauth-access-token-url-without-scheme)))
                 (token-alist
                  (twittering-xauth-get-access-token
                   access-token-url
                   (twittering-lookup-service-method-table 'oauth-consumer-key) (twittering-lookup-service-method-table 'oauth-consumer-secret)
                   (car account-info)
                   (cdr account-info))))
            ;; Dispose of password as recommended by Twitter.
            ;; http://dev.twitter.com/pages/xauth
            (setcdr account-info nil)
            (cond
             ((and token-alist
                   (assoc "oauth_token" token-alist)
                   (assoc "oauth_token_secret" token-alist))
              ;; set `twittering-username' only if the account is valid.
              (setq twittering-username (car account-info))
              (twittering-update-oauth-access-token-alist token-alist)
              (twittering-update-account-authorization 'authorized)
              (message "Authorization for the account \"%s\" succeeded."
                       (twittering-get-accounts 'username))
              (when (and twittering-use-master-password
                         (twittering-capable-of-encryption-p)
                         (not (file-exists-p twittering-private-info-file)))
                (twittering-save-private-info-with-guide))
              (twittering-start))
             (t
              (message "Authorization via xAuth failed. Type M-x twit to retry.")))))))))

   ((eq (twittering-get-accounts 'auth) 'basic)
    (twittering-update-account-authorization 'queried)
    (let* ((account-info (twittering-prepare-account-info))
           ;; Bind account information locally to ensure that
           ;; the variables are reset when the verification fails.
           (twittering-username (car account-info))
           (twittering-password (cdr account-info))
           (proc
            (twittering-call-api
             'verify-credentials
             `((sentinel . twittering-http-get-verify-credentials-sentinel)
               (clean-up-sentinel
                . twittering-http-get-verify-credentials-clean-up-sentinel))
             `((username . ,(car account-info))
               (password . ,(cdr account-info))
	       (service . ,(twittering-extract-service))))))
      (cond
       ((null proc)
        (twittering-update-account-authorization nil)
        (message "Authorization for the account \"%s\" failed. Type M-x twit to retry."
                 (car account-info))
        (setq twittering-username nil)
        (setq twittering-password nil))
       (t
        ;; wait for verification to finish.
        (while (twittering-account-authorization-queried-p)
          (sit-for 0.1))))))
   (t
    (message "%s is invalid as an authorization method."
             (twittering-get-accounts 'auth))))
  (twittering-account-authorized-p))

(defun twittering-http-get-verify-credentials-sentinel (proc status connection-info header-info)
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info))
	(twittering-service-method (assqref 'service connection-info)))
    (case-string
     status-code
     (("200")
      (cond
       ((eq (twittering-get-accounts 'auth) 'basic)
        (setq twittering-username (assqref 'username connection-info))
        (setq twittering-password (assqref 'password connection-info)))
       (t
        (setq twittering-username (assqref 'username connection-info))))
      (twittering-update-account-authorization 'authorized)
      (twittering-start)
      (format "Authorization for the account \"%s\" succeeded."
              (twittering-get-accounts 'username)))
     (t
      (twittering-update-account-authorization nil)
      (let ((error-mes
             (format "Authorization for the account \"%s\" failed. Type M-x twit to retry."
                     (twittering-get-accounts 'username))))
        (cond
         ((memq (twittering-get-accounts 'auth) '(oauth xauth))
          (twittering-update-oauth-access-token-alist nil))
         ((eq (twittering-get-accounts 'auth) 'basic)
          (setq twittering-username nil)
          (setq twittering-password nil)))
        error-mes)))))

(defun twittering-http-get-verify-credentials-clean-up-sentinel (proc status connection-info)
  (let ((twittering-service-method (assqref 'service connection-info)))
    (when (and (memq status '(exit signal closed failed))
	       (eq (twittering-get-account-authorization) 'queried))
      (twittering-update-account-authorization nil)
      (message "Authorization failed. Type M-x twit to retry.")
      (setq twittering-username nil)
      (setq twittering-password nil))))

;;;;
;;;; Status retrieval
;;;;

(defun twittering-add-timeline-history (spec-string)
  (when (or (null twittering-timeline-history)
            (not (string= spec-string (car twittering-timeline-history))))
    (twittering-add-to-history 'twittering-timeline-history spec-string)))

(defun twittering-atom-xmltree-to-status-datum (atom-xml-entry)
  (let ((id-str (car (cddr (assq 'id atom-xml-entry))))
        (time-str (car (cddr (assq 'updated atom-xml-entry))))
        (author-str (car (cddr (assq 'name (assq 'author atom-xml-entry))))))
    `((created-at
       ;; ISO 8601
       ;; Twitter -> "2010-05-08T05:59:41Z"
       ;; StatusNet -> "2010-05-08T08:44:39+00:00"
       . ,(if (string-match "\\(.*\\)T\\(.*\\)\\(Z\\|\\([-+][0-2][0-9]\\):?\\([0-5][0-9]\\)\\)" time-str)
              ;; time-str is formatted as
              ;; "Combined date and time in UTC:" in ISO 8601.
              (let ((timezone (match-string 3 time-str)))
                (format "%s %s %s"
                        (match-string 1 time-str) (match-string 2 time-str)
                        (if (string= "Z" timezone)
                            "+0000"
                          (concat (match-string 4 time-str)
                                  (match-string 5 time-str)))))
            ;; unknown format?
            time-str))
      (id . ,(progn
               (string-match ":\\([0-9]+\\)$" id-str)
               (match-string 1 id-str)))
      ,@(let ((source (twittering-decode-html-entities
                       (car (cddr (assq 'twitter:source atom-xml-entry))))))
          `(,@(if (string-match "<a href=\"\\(.*?\\)\".*?>\\(.*\\)</a>"
                                source)
                  (let ((uri (match-string-no-properties 1 source))
                        (caption (match-string-no-properties 2 source)))
                    `((source . ,caption)
                      (source-uri . ,uri)))
                `((source . ,source)
                  (source-uri . "")))))
      (text . ,(twittering-decode-html-entities
                (car (cddr (assq 'title atom-xml-entry)))))
      ,@(cond
         ((and (eq (twittering-extract-service) 'statusnet)
               (string-match "^\\([^ ]+\\)\\( (\\(.*\\))\\)?$" author-str))
          ;; StatusNet
          `((user-screen-name . ,(match-string 1 author-str))
            (user-name . ,(or (match-string 3 author-str) ""))))
         ((string-match "^\\([^ ]+\\) (\\(.*\\))$" author-str)
          ;; Twitter (default)
          `((user-screen-name . ,(match-string 1 author-str))
            (user-name . ,(match-string 2 author-str))))
         (t
          '((user-screen-name . "PARSING FAILED!!")
            (user-name . ""))))
      (user-profile-image-url
       . ,(let* ((link-items
                  (mapcar
                   (lambda (item)
                     (when (eq 'link (car-safe item))
                       (cadr item)))
                   atom-xml-entry))
                 (image-urls
                  (mapcar
                   (lambda (item)
                     (cond
                      ((and (eq (twittering-extract-service) 'statusnet)
                            (member '(rel . "related") item))
                       ;; StatusNet
                       (assqref 'href item))
                      ((member '(rel . "image") item)
                       ;; Twitter (default)
                       (assqref 'href item))
                      (t
                       nil)))
                   link-items)))
            (car-safe (remq nil image-urls)))))))

(defun twittering-atom-xmltree-to-status (atom-xmltree)
  (let ((entry-list
         (apply 'append
                (mapcar (lambda (x)
                           (if (eq (car-safe x) 'entry) `(,x) nil))
                        (cdar atom-xmltree)))))
    (mapcar 'twittering-atom-xmltree-to-status-datum
            entry-list)))

(defvar twittering-emotions-phrase-url-alist nil)
(defvar twittering-is-getting-emotions-p nil)

(defun twittering-normalize-raw-status (raw-status &optional ignore-retweet)
  (let* ((status-data (cddr raw-status))
         (raw-retweeted-status (assq 'retweeted_status status-data))
         (raw-replied-status (assq 'status status-data))
         (raw-replied-comment (assq 'reply_comment status-data)))
    (remove-if
     (lambda (entry) 
       (let ((value (cdr entry)))
	 (or (null value)
	     (and (stringp value) (string= value "")))))
     (cond
      ((and (or raw-retweeted-status raw-replied-status raw-replied-comment)
	    (not ignore-retweet))
       (let* ((retweeted-status
	       (when raw-retweeted-status
		 (twittering-normalize-raw-status raw-retweeted-status t)))
	      (replied-status
	       (when raw-replied-status
		 (twittering-normalize-raw-status raw-replied-status t)))
	      (replied-comment
	       (when raw-replied-comment
		 (twittering-normalize-raw-status raw-replied-comment t)))
	      (quoted-status (or retweeted-status replied-comment replied-status))

	      ;; The one who is currently retweeting, replying or commenting.
	      (author-status
	       (twittering-normalize-raw-status raw-status t))

	      (items-overwritten-by-retweet
	       '(id)))

	 `(,@(mapcar
	      (lambda (entry)
		(let ((sym (car entry))
		      (value (cdr entry)))
		  (cond ((memq sym items-overwritten-by-retweet)
			 (let ((value-on-retweet (assqref sym author-status)))
			   ;; Replace the value in `retweeted-status' with
			   ;; that in `author-status'.
			   `(,sym . ,value-on-retweet)))
			((eq sym 'text)
			 (let ((text (assqref sym author-status))
			       (quoted-text (assqref sym quoted-status)))
			   (if (or (and text
					(not (or (string-match
						  (regexp-opt
						   `(,(replace-regexp-in-string
						       (format "^RT @%s: \\|[.[:blank:]]+$"
							       (assqref 'user-screen-name quoted-status))
						       ""
						       text)))
						  value)
						 (string= text "转发微博")
						 (string= text "转发微博。"))))
				   (assqref sym (or replied-comment replied-status)))
			       (setq text (apply 'format "『%s』\n\n    %s"
						 (if text
						     (list value text)
                                                   (list quoted-text value))))
			     (setq text value))
			   `(text . ,text)))
			(t
			 `(,sym . ,value)))))
	      quoted-status)

	   ,@(apply 'append
		    (mapcar
		     (lambda (status-prefix)
		       (let ((status (car status-prefix))
			     (prefix (cdr status-prefix)))
			 (when status
			   (mapcar
			    (lambda (entry)
			      (let ((sym (car entry))
				    (value (cdr entry)))
				`(,(intern (concat prefix (symbol-name sym)))
				  . ,value)))
			    status))))
		     ;; Make it compatible with upstream.
		     `((,retweeted-status . "retweeted-")
		       (,author-status . "retweeting-")
		       ;; (,replied-status . "replied-status-")
		       ;; (,replied-comment . "replied-comment-")
		       )))

	   (is-retweeting . ,(not (null raw-retweeted-status)))

	   (author-status . ,author-status)
	   (in-reply-to-status . ,replied-status)
	   (in-reply-to-comment . ,replied-comment))))
      (t
       (flet ((assq-get (item seq)
			;; (car (cddr (assq item seq)))))
			(cadr
			 (remove-if
			  (lambda (el)
			    (unless (consp el)
			      (or (null el)
				  (and (stringp el)
				       (string-match "^[[:space:]]+$" el)))))
			  (assq item seq)))))
	 `(,@(mapcar
	      (lambda (entry)
		(let* ((sym (elt entry 0))
		       (sym-in-data (elt entry 1))
		       (encoded (elt entry 2))
		       (data (assq-get sym-in-data status-data)))
		  (when encoded
		    (setq data (twittering-decode-html-entities data))
		    ;; (sina) Recognize and mark emotions, we will show them in
		    ;; twittering-redisplay-status-on-each-buffer.
		    (when (and (eq (twittering-extract-service) 'sina)
			       (eq sym 'text))
		      (setq data
			    (replace-regexp-in-string "\\(\\[[^][]+\\]\\)" "[\\1]" data))))
		  `(,sym . ,data)))
	      '( ;; Raw entries.
		(created-at            created_at)
		(id                    id)
		(recipient-screen-name recipient_screen_name)
		(truncated             truncated)
		(thumbnail-pic         thumbnail_pic)
		(bmiddle-pic           bmiddle_pic)
		(original-pic          original_pic)

		;; Encoded entries.
		(in-reply-to-screen-name in_reply_to_screen_name t)
		(in-reply-to-status-id in_reply_to_status_id t)
		(text text t)
		))
	   ;; Source.
	   ,@(let ((source (assq-get 'source status-data)))
	       (if (stringp source)
		   (progn
		     (setq source (twittering-decode-html-entities source))
		     (if (and source
			      (string-match "<a href=\"\\(.*?\\)\".*?>\\(.*\\)</a>"
					    source))
			 (let ((uri (match-string-no-properties 1 source))
			       (caption (match-string-no-properties 2 source)))
			   `((source . ,caption)
			     (source-uri . ,uri)))
		       `((source . ,source)
			 (source-uri . ""))))
		 ;; Sina Weibo source
		 `((source . ,(car (last source)))
		   (source-uri . ,(cdaadr source)))))

	   ;; Items related to the user that posted the tweet.
	   ,@(let ((user-data (cddr (assq 'user status-data))))
	       (mapcar
		(lambda (entry)
		  (let* ((sym (elt entry 0))
			 (sym-in-user-data (elt entry 1))
			 (encoded (elt entry 2))
			 (value (assq-get sym-in-user-data user-data)))
		    `(,sym . ,(if encoded
				  (twittering-decode-html-entities value)
				value))))
		'( ;; Raw entries.
		  (user-id                id)
		  (user-profile-image-url profile_image_url)
		  (user-url               url)
		  (user-protected         protected)
		  (user-followers-count   followers_count)
		  (user-friends-count     friends_count)
		  (user-statuses-count    statuses_count)
		  (user-favourites-count  favourites_count)
		  (user-created-at        created_at)

		  (previous-cursor previous_cursor)
		  (next-cursor     next_cursor)

		  ;; Encoded entries.
		  (user-name name t)
		  (user-screen-name screen_name t)
		  (user-location location t)
		  (user-description description t)))))))))))

(defun twittering-xmltree-to-status (xmltree)
  (let ((type (caar xmltree)))
    (setq xmltree
          (case type
            ((direct-messages)
             `(,@(mapcar
                  (lambda (c-node)
                    `(status nil
                             (created_at
                              nil ,(caddr (assq 'created_at c-node)))
                             (id nil ,(caddr (assq 'id c-node)))
                             (text nil ,(caddr (assq 'text c-node)))
                             (source nil ,(format "%s" (car c-node))) ;; fake
                             (truncated nil "false")
                             (in_reply_to_status_id nil)
                             (in_reply_to_user_id
                              nil ,(caddr (assq 'recipient_id c-node)))
                             (favorited nil "false")
                             (recipient_screen_name
                              nil ,(caddr (assq 'recipient_screen_name c-node)))
                             (user nil ,@(cdddr (assq 'sender c-node)))))
                  (remove nil
                          (mapcar
                           (lambda (node)
                             (and (consp node) (eq 'direct_message (car node))
                                  node))
                           (cdr-safe (assq 'direct-messages xmltree)))))))

            ((users users_list)                ; following, followers
             (let ((previous_cursor (assq 'previous_cursor (car xmltree)))
                   (next_cursor (assq 'next_cursor (car xmltree))))
               `(,@(mapcar
                    (lambda (c-node)
                      ;; Reconstruct to satisfy
                      ;; `twittering-status-to-status-datum', and remove
                      ;; 'retweeted_status here.
                      (let* ((user (append
                                    (remove-if (lambda (entry)
                                                 (eq (car-safe entry) 'status))
                                               c-node)
                                    (list previous_cursor next_cursor)))
                             (status (or
                                      (remove-if (lambda (entry)
                                                   (eq (car-safe entry) 'retweeted_status))
                                                 (assq 'status c-node))
                                      ;; Fake 'status for people with zero
                                      ;; tweets...
                                      (cons 'status (cdr user)))))
                        (append status (list user))))
                    (remove nil
                            (mapcar
                             (lambda (node)
                               (and (consp node) (eq 'user (car node)) node))
                             (cdr-safe (assq 'users (or (assq 'users_list xmltree) xmltree)))))))))

            ((statuses comments)        ; comments is comments_timeline for sina.
             (cddr (car xmltree)))

            ((status)                        ; `statues/show', replied statuses
             xmltree)

            (t
             (error "Unknown format: %S" type)))))

  (mapcar #'twittering-normalize-raw-status
           ;; quirk to treat difference between xml.el in Emacs21 and Emacs22
           ;; On Emacs22, there may be blank strings
          (remove nil (mapcar (lambda (x)
                                (if (consp x) x))
                              xmltree))))

(defun twittering-decode-html-entities (encoded-str)
  (if (consp encoded-str)
      encoded-str
    (if encoded-str
      (let ((cursor 0)
            (found-at nil)
            (result '()))
        (while (setq found-at
                     (string-match "&\\(#\\([0-9]+\\)\\|\\([a-zA-Z]+\\)\\);"
                                   encoded-str cursor))
          (when (> found-at cursor)
            (list-push (substring encoded-str cursor found-at) result))
          (let ((number-entity (match-string-no-properties 2 encoded-str))
                (letter-entity (match-string-no-properties 3 encoded-str)))
            (cond (number-entity
                   (list-push
                    (char-to-string
                     (twittering-ucs-to-char
                      (string-to-number number-entity))) result))
                  (letter-entity
                   (cond ((string= "gt" letter-entity) (list-push ">" result))
                         ((string= "lt" letter-entity) (list-push "<" result))
                         ((string= "quot" letter-entity) (list-push "\"" result))
                         (t (list-push "?" result))))
                  (t (list-push "?" result)))
            (setq cursor (match-end 0))))
        (list-push (substring encoded-str cursor) result)
        (apply 'concat (nreverse result)))
    "")))

;;;;
;;;; List info retrieval
;;;;

(defun twittering-get-list-index (username)
  (twittering-call-api
   'get-list-index
   `((username . ,username)
     (sentinel . twittering-http-get-list-index-sentinel))))

(defun twittering-get-list-index-sync (username)
  (setq twittering-list-index-retrieved nil)
  (let ((proc (twittering-get-list-index username)))
    (when proc
      (while (and (not twittering-list-index-retrieved)
                  (not (memq (process-status proc)
                             '(exit signal closed failed nil))))
        (sit-for 0.1))))
  (cond
   ((null twittering-list-index-retrieved)
    nil)
   ((stringp twittering-list-index-retrieved)
    (if (string= "" twittering-list-index-retrieved)
        (message "%s does not have a list." username)
      (message "%s" twittering-list-index-retrieved))
    nil)
   ((listp twittering-list-index-retrieved)
    twittering-list-index-retrieved)))

;;;;
;;;; Buffer info
;;;;

(defvar twittering-buffer-info-list nil
  "List of buffers managed by `twittering-mode'.")

(defun twittering-get-buffer-list ()
  "Return buffers managed by `twittering-mode'."
  (twittering-unregister-killed-buffer)
  twittering-buffer-info-list)

(defun twittering-get-active-buffer-list ()
  "Return active buffers managed by `twittering-mode', where statuses are
retrieved periodically."
  (twittering-unregister-killed-buffer)
  (remove nil
          (mapcar (lambda (buffer)
                    (if (twittering-buffer-active-p buffer)
                        buffer
                      nil))
                  twittering-buffer-info-list)))

(defun twittering-buffer-p (&optional buffer)
  "Return t if BUFFER is managed by `twittering-mode'.
BUFFER defaults to the the current buffer."
  (let ((buffer (or buffer (current-buffer))))
    (and (buffer-live-p buffer)
         (memq buffer twittering-buffer-info-list))))

(defun twittering-buffer-related-p ()
  "Return t if current buffer relates to `twittering-mode'."
  (or (twittering-buffer-p)
      (eq major-mode 'twittering-edit-mode)
      (string= (buffer-name (current-buffer))
               twittering-debug-buffer)))

(defun twittering-buffer-active-p (&optional buffer)
  "Return t if BUFFER is an active buffer managed by `twittering-mode'.
BUFFER defaults to the the current buffer."
  (let ((buffer (or buffer (current-buffer))))
    (and (twittering-buffer-p buffer)
         (with-current-buffer buffer
           twittering-active-mode))))

(defun twittering-get-buffer-from-spec (spec)
  "Return the buffer bound to SPEC. If no buffers are bound to SPEC,
return nil."
  (let* ((spec-string (twittering-timeline-spec-to-string spec))
         (buffers
          (remove
           nil
           (mapcar
            (lambda (buffer)
              (if (twittering-equal-string-as-timeline
                   spec-string
                   (twittering-get-timeline-spec-string-for-buffer buffer))
                  buffer
                nil))
            (twittering-get-buffer-list)))))
    (if buffers
        ;; We assume that the buffer with the same spec is unique.
        (car buffers)
      nil)))

(defun twittering-get-buffer-from-spec-string (spec-string)
  "Return the buffer bound to SPEC-STRING. If no buffers are bound to it,
return nil."
  (let ((spec (twittering-string-to-timeline-spec spec-string)))
    (and spec (twittering-get-buffer-from-spec spec))))

(defun twittering-get-timeline-spec-for-buffer (buffer)
  "Return the timeline spec bound to BUFFER. If BUFFER is not managed by
`twittering-mode', return nil."
  (when (twittering-buffer-p buffer)
    (with-current-buffer buffer
      twittering-timeline-spec)))

(defun twittering-get-timeline-spec-string-for-buffer (buffer)
  "Return the timeline spec string bound to BUFFER. If BUFFER is not managed
by `twittering-mode', return nil."
  (when (twittering-buffer-p buffer)
    (with-current-buffer buffer
      twittering-timeline-spec-string)))

(defun twittering-current-timeline-spec ()
  "Return the timeline spec bound to the current buffer. If it is not managed
by `twittering-mode', return nil."
  (twittering-get-timeline-spec-for-buffer (current-buffer)))

(defun twittering-current-timeline-spec-string ()
  "Return the timeline spec string bound to the current buffer. If it is not
managed by `twittering-mode', return nil."
  (twittering-get-timeline-spec-string-for-buffer (current-buffer)))

(defun twittering-unregister-buffer (buffer &optional keep-timer)
  "Unregister BUFFER from `twittering-buffer-info-list'.
If BUFFER is the last managed buffer and KEEP-TIMER is nil, call
`twittering-stop' to stop timers."
  (when (memq buffer twittering-buffer-info-list)
    (setq twittering-buffer-info-list
          (delq buffer twittering-buffer-info-list))
    (when (and (null twittering-buffer-info-list)
               (not keep-timer))
      (twittering-stop))))

(defun twittering-unregister-killed-buffer ()
  "Unregister buffers which has been killed."
  (mapc (lambda (buffer)
          (unless (buffer-live-p buffer)
            (twittering-unregister-buffer buffer)))
        twittering-buffer-info-list))

(defun twittering-replace-spec-string-for-buffer (buffer spec-string)
  "Replace the timeline spec string for BUFFER with SPEC-STRING when
BUFFER is managed by `twittering-mode' and SPEC-STRING is equivalent
to the current one."
  (when (twittering-buffer-p buffer)
    (let ((current (twittering-get-timeline-spec-string-for-buffer buffer)))
      (when (and (not (string= current spec-string))
                 (twittering-equal-string-as-timeline current spec-string))
        (with-current-buffer buffer
          (rename-buffer spec-string t)
          (setq twittering-timeline-spec-string spec-string))))))

(defun twittering-set-active-flag-for-buffer (buffer active)
  "Set ACTIVE to active-flag for BUFFER."
  (when (twittering-buffer-p buffer)
    (let ((current (twittering-buffer-active-p buffer)))
      (when (or (and active (not current))
                (and (not active) current))
        (twittering-toggle-activate-buffer buffer)))))

(defun twittering-toggle-activate-buffer (&optional buffer)
  "Toggle whether to retrieve timeline for the current buffer periodically."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (when (twittering-buffer-p buffer)
      (with-current-buffer buffer
        (let* ((new-mode (not twittering-active-mode))
               (active-buffer-list (twittering-get-active-buffer-list))
               (start-timer (and new-mode (null active-buffer-list))))
          (setq twittering-active-mode new-mode)
          (when start-timer
            (twittering-start))
          (twittering-update-mode-line))))))

(defun twittering-activate-buffer (&optional buffer)
  "Activate BUFFER to retrieve timeline for it periodically."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (twittering-set-active-flag-for-buffer buffer t)))

(defun twittering-deactivate-buffer (&optional buffer)
  "Deactivate BUFFER not to retrieve timeline for it periodically."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (twittering-set-active-flag-for-buffer buffer nil)))

(defun twittering-kill-buffer (&optional buffer)
  "Kill BUFFER managed by `twittering-mode'."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (when (twittering-buffer-p buffer)
      (twittering-deactivate-buffer buffer)
      (kill-buffer buffer)
      (twittering-unregister-killed-buffer))))

(defun twittering-get-managed-buffer (spec)
  "Return the buffer bound to SPEC.
If no buffers are bound to SPEC, return newly generated buffer.
SPEC may be a timeline spec or a timeline spec string."
  (let* ((original-spec spec)
         (spec-string (if (stringp spec)
                          spec
                        (twittering-timeline-spec-to-string spec)))
         ;; `spec-string' without text properties is required because
         ;; Emacs21 displays `spec-string' with its properties on mode-line.
         ;; In addition, copying `spec-string' keeps timeline-data from
         ;; being modified by `minibuf-isearch.el'.
         (spec-string (copy-sequence spec-string))
         (spec (if (stringp spec-string)
                   (twittering-string-to-timeline-spec spec-string)
                 nil)))
    (when (null spec)
      (error "\"%s\" is invalid as a timeline spec"
             (or spec-string original-spec)))
    (let ((twittering-service-method (caar spec)))
      (set-text-properties 0 (length spec-string) nil spec-string)
      (let ((buffer (twittering-get-buffer-from-spec spec)))
	(if buffer
	    (progn
	      (twittering-replace-spec-string-for-buffer buffer spec-string)
	      (twittering-render-timeline buffer t)
	      buffer)
	  (let ((buffer (generate-new-buffer spec-string))
		(start-timer (null twittering-buffer-info-list)))
	    ;; (add-to-list 'twittering-buffer-info-list buffer t)
	    (with-current-buffer buffer
	      (twittering-mode-setup spec-string)
	      (twittering-verify-credentials)
	      (twittering-render-timeline buffer)
	      (when (twittering-account-authorized-p)
		(when twittering-active-mode
		  (twittering-get-and-render-timeline))
		(when start-timer
		  ;; If `buffer' is the first managed buffer,
		  ;; call `twittering-start' to start timers.
		  (twittering-start))))
	    buffer))))))

;;;;
;;;; Icon mode
;;;;

(defvar twittering-icon-mode nil
  "You MUST NOT CHANGE this variable directly.
You should change through function `twittering-icon-mode'.")

(defun twittering-icon-mode (&optional arg)
  "Toggle display of icon images on timelines.
With a numeric argument, if the argument is positive, turn on
icon mode; otherwise, turn off icon mode."
  (interactive "P")
  (let ((prev-mode twittering-icon-mode))
    (setq twittering-icon-mode
          (if (null arg)
              (not twittering-icon-mode)
            (< 0 (prefix-numeric-value arg))))
    (unless (eq prev-mode twittering-icon-mode)
      (twittering-update-mode-line)
      (twittering-render-timeline (current-buffer)))))

(defvar twittering-icon-prop-hash (make-hash-table :test 'equal)
  "Hash table for storing display properties of icon. The key is the size of
icon and the value is a hash. The key of the child hash is URL and its value
is the display property for the icon.")

(defvar twittering-convert-program (executable-find "convert"))
(defvar twittering-convert-fix-size 48)
(defvar twittering-use-convert (not (null twittering-convert-program))
  "*This variable makes a sense only if `twittering-convert-fix-size'
is non-nil. If this variable is non-nil, icon images are converted by
invoking \"convert\". Otherwise, cropped images are displayed.")

(defvar twittering-use-profile-image-api nil
  "*Whether to use `profile_image' API for retrieving scaled icon images.
NOTE: This API is rate limited.")

(defvar twittering-icon-storage-file
  (expand-file-name "~/.twittering-mode-icons.gz")
  "*The file to which icon images are stored.
`twittering-icon-storage-limit' determines the number icons stored in the
file.
The file is loaded with `with-auto-compression-mode'.")

(defvar twittering-use-icon-storage nil
  "*Whether to use the persistent icon storage.
If this variable is non-nil, icon images are stored to the file specified
by `twittering-icon-storage-file'.")

(defvar twittering-icon-storage-recent-icons nil
  "List of recently rendered icons.")

(defvar twittering-icon-storage-limit 500
  "*How many icons are stored in the persistent storage.
If `twittering-use-icon-storage' is nil, this variable is ignored.
If a positive integer N, `twittering-save-icon-properties' saves N icons that
have been recently rendered.
If nil, the function saves all icons.")

(defconst twittering-error-icon-data-pair
  '(xpm . "/* XPM */
static char * yellow3_xpm[] = {
\"16 16 2 1\",
\"         c None\",
\".        c #FF0000\",
\"................\",
\".              .\",
\". .          . .\",
\".  .        .  .\",
\".   .      .   .\",
\".    .    .    .\",
\".     .  .     .\",
\".      ..      .\",
\".      ..      .\",
\".     .  .     .\",
\".    .    .    .\",
\".   .      .   .\",
\".  .        .  .\",
\". .          . .\",
\".              .\",
\"................\"};
")
  "Image used when the valid icon cannot be retrieved.")

(defun twittering-update-icon-storage-recent-icons (size image-url spec)
  (unless (null twittering-icon-storage-limit)
    (let ((dummy-icon-properties (twittering-make-display-spec-for-icon
                                  twittering-error-icon-data-pair)))
      (unless (equal spec dummy-icon-properties)
        (let ((history-delete-duplicates t))
          (twittering-add-to-history 'twittering-icon-storage-recent-icons
                                     (list size image-url)
                                     twittering-icon-storage-limit))))))

(defun twittering-get-display-spec-for-icon (image-url)
  (let ((hash
         (gethash twittering-convert-fix-size twittering-icon-prop-hash)))
    (when hash
      (let ((spec (gethash image-url hash))
            (size twittering-convert-fix-size))
        (when spec
          (twittering-update-icon-storage-recent-icons size image-url spec)
          spec)))))

(defun twittering-convert-image-data (image-data dest-type &optional src-type)
  "Convert IMAGE-DATA into XPM format and return it. If it fails to convert,
return nil."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (buffer-disable-undo)
    (let ((coding-system-for-read 'binary)
          (coding-system-for-write 'binary)
          (require-final-newline nil))
      (insert image-data)
      (let* ((args
              `(,(if src-type (format "%s:-" src-type) "-")
                ,@(when (integerp twittering-convert-fix-size)
                    `("-resize"
                      ,(format "%dx%d" twittering-convert-fix-size
                               twittering-convert-fix-size)))
                ,(format "%s:-" dest-type)))
             (exit-status
              (apply 'call-process-region (point-min) (point-max)
                     twittering-convert-program t t nil args)))
        (if (equal 0 exit-status)
            (buffer-string)
          ;; failed to convert the image.
          nil)))))

(defun twittering-create-image-pair (image-data)
  "Return a pair of image type and image data.
IMAGE-DATA is converted by `convert' if the image type of IMAGE-DATA is not
available and `twittering-use-convert' is non-nil."
  (let* ((image-type (and image-data (image-type-from-data image-data)))
         (image-pair `(,image-type . ,image-data))
         (converted-size
          `(,twittering-convert-fix-size . ,twittering-convert-fix-size)))
    (cond
     ((null image-data)
      twittering-error-icon-data-pair)
     ((and (image-type-available-p image-type)
           (or (not (integerp twittering-convert-fix-size))
               (equal (image-size (create-image image-data image-type t) t)
                      converted-size)))
      image-pair)
     (twittering-use-convert
      ;; When GIF contains animations, it will be converted to couples of XPM
      ;; files, which is not what we want.
      (let* ((dest-type (if (eq image-type 'gif) 'gif 'xpm))
             (converted-data
              (twittering-convert-image-data image-data dest-type image-type)))
        (if converted-data
            `(xpm . ,converted-data)
          twittering-error-icon-data-pair)))
     (t
      ;; twittering-error-icon-data-pair
      image-pair))))

(defun twittering-register-image-spec (image-url spec size)
  (let ((hash (gethash size twittering-icon-prop-hash)))
    (unless hash
      (setq hash (make-hash-table :test 'equal))
      (puthash size hash twittering-icon-prop-hash))
    (puthash image-url spec hash)))

(defun twittering-register-image-data (image-url image-data &optional size)
  (let ((image-pair (twittering-create-image-pair image-data))
        (size (or size twittering-convert-fix-size)))
    (when image-pair
      (let ((spec (twittering-make-display-spec-for-icon image-pair)))
        (twittering-register-image-spec image-url spec size)
        spec))))

(defun twittering-make-slice-spec (image-spec)
  "Return slice property for reducing the image size by cropping it."
  (let* ((size (image-size image-spec t))
         (width (car size))
         (height (cdr size))
         (fixed-length twittering-convert-fix-size)
         (half-fixed-length (/ fixed-length 2)))
    (if (or (< fixed-length width) (< fixed-length height))
        `(slice ,(max 0 (- (/ width 2) half-fixed-length))
                ,(max 0 (- (/ height 2) half-fixed-length))
                ,fixed-length ,fixed-length)
      `(slice 0 0 ,fixed-length ,fixed-length))))

(defun twittering-make-display-spec-for-icon (image-pair)
  "Return the specification for `display' text property, which
limits the size of an icon image IMAGE-PAIR up to FIXED-LENGTH. If
the type of the image is not supported, nil is returned.

If the size of the image exceeds FIXED-LENGTH, the center of the
image are displayed."
  (let* ((type (car-safe image-pair))
         (data (cdr-safe image-pair))
         (raw-image-spec ;; without margins
          (create-image data type t))
         (slice-spec
          (when (and twittering-convert-fix-size (not twittering-use-convert))
            (twittering-make-slice-spec raw-image-spec)))
         (image-spec
          (if (fboundp 'create-animated-image) ;; Emacs24 or later
              (create-animated-image data type t :margin 2 :ascent 'center)
            (create-image data type t :margin 2 :ascent 'center))))
    (if slice-spec
        `(display (,image-spec ,slice-spec))
      `(display ,image-spec))))

(defun twittering-make-icon-string (beg end image-url &optional sync)
  (let ((display-spec (twittering-get-display-spec-for-icon image-url))
        (image-data (gethash image-url twittering-url-data-hash))
        (properties (and beg (text-properties-at beg)))
        (icon-string (copy-sequence ".")))
    (when properties
      (add-text-properties 0 (length icon-string) properties icon-string))
    (cond
     (display-spec
      (let ((icon-string (apply 'propertize "_"
                                (append properties display-spec))))
        ;; Remove the property required no longer.
        (remove-text-properties 0 (length icon-string)
                                '(need-to-be-updated nil)
                                icon-string)
        icon-string))
     ((and (integerp image-data)
           (<= twittering-url-request-retry-limit image-data))
      ;; Try to retrieve the image no longer.
      (twittering-register-image-data image-url nil)
      (twittering-make-icon-string beg end image-url))
     ((and image-data (not (integerp image-data)))
      (twittering-register-image-data image-url image-data)
      (twittering-make-icon-string beg end image-url))
     (t
      (put-text-property 0 (length icon-string)
                         'need-to-be-updated
                         `((lambda (&rest args)
                             (let ((twittering-convert-fix-size
                                    ,twittering-convert-fix-size))
                               (apply 'twittering-make-icon-string
                                      (append args (list ,image-url))))))
                         icon-string)
      ;; (if sync
      ;; 	  (progn
      ;; 	    (let ((result (twittering-url-retrieve-synchronously image-url)))
      ;; 	      (twittering-register-image-data image-url result)
      ;; 	      (twittering-make-icon-string beg end image-url)))
      ;;   (twittering-url-retrieve-async image-url 'twittering-register-image-data)
      ;;   icon-string)))))

      (if sync
          (let* ((buf (twittering-url-retrieve-synchronously image-url))
                 (header-info (twittering-make-header-info-alist
                               (twittering-get-response-header buf)))
                 (status-code (assqref 'status-code header-info)))
            (when (string= status-code "200")
              (with-current-buffer buf
                (goto-char (point-min))
                (when (search-forward-regexp "\r?\n\r?\n" nil t)
                  (twittering-register-image-data image-url
                                                  (buffer-substring (match-end 0) (point-max)))
                  (twittering-make-icon-string beg end image-url sync)))))
        (twittering-url-retrieve-async image-url 'twittering-register-image-data)
        icon-string)))))


(defun twittering-make-original-icon-string (beg end image-url &optional sync)
  (let ((twittering-convert-fix-size nil))
    (twittering-make-icon-string beg end image-url sync)))

(defun twittering-toggle-thumbnail (thumbnail-pic bmiddle-pic &optional initial)
  (let ((uri (get-text-property (point) 'uri))
        next-uri)
    (when (or uri initial)
      (if initial
          (setq uri thumbnail-pic
                next-uri bmiddle-pic)
        (if (string= uri bmiddle-pic)
            (setq next-uri thumbnail-pic)
          (setq next-uri bmiddle-pic)))

      (let ((s (twittering-make-original-icon-string nil nil uri (not initial)))
	    (common-properties (twittering-get-common-properties (point))))
        (add-text-properties 0 (length s)
                             `(,@common-properties
			       mouse-face 
                               highlight 
                               uri ,next-uri
                               keymap
                               ,(let ((map (make-sparse-keymap))
                                      (func `(lambda ()
                                               (interactive)
                                               (twittering-toggle-thumbnail ,uri ,next-uri))))
                                  (define-key map (kbd "<mouse-1>") func)
                                  (define-key map (kbd "RET") func)
                                  map))
                             s)
        (if initial
            s
          (let ((inhibit-read-only t))
            (save-excursion
              (delete-char (length s))
              (insert s))))))))

(defun twittering-http-get-simple-sentinel (proc status connection-info
						 header-info 
						 &optional args suc-msg)
  (let ((status-line (assqref 'status-line header-info))
        (status-code (assqref 'status-code header-info))
        ret mes)
    (twittering-html-decode-buffer)
    (cond
     ((string= status-code "200")
      (let ((xmltree
             (twittering-xml-parse-region (point-min) (point-max))))
        (when xmltree
          (case (caar xmltree)
            ;; show-friendships
            ((relationship)
             (let ((checker
                    (lambda (tag)
                      (string= (car
                                (last
                                 (assq tag (assq 'source (car xmltree)))))
                               "true"))))
               (setq ret `((following . ,(funcall checker 'following))
                           (followed-by . ,(funcall checker 'followed_by))))))
            ;; get-list-index, get-list-subscriptions, get-list-memberships
            ((lists_list)
             (setq ret
                   (mapconcat
                    (lambda (c-node)
                      (substring (caddr (assq 'full_name c-node)) 1))
                    (remove
                     nil
                     (mapcar
                      (lambda (node)
                        (and (consp node) (eq 'list (car node)) node))
                      (cdr-safe
                       (assq 'lists (assq 'lists_list xmltree)))))
                    " ")))
            ((counts)                        ; Assume just one ID.
             (setq ret `(,(remove nil (assq 'comments (assqref 'count (car xmltree))))
                         ,(remove nil (assq 'rt       (assqref 'count (car xmltree)))))))

            ((emotions)
             (setq ret
                   (remove nil
                           (mapcar
                            (lambda (e)
                              (when (and (consp e) (eq 'emotion (car e)))
                                `(,(car (last (assq 'phrase e)))
                                  . ,(car (last (assq 'url e))))))
                            (car xmltree))))
             (setq twittering-emotions-phrase-url-alist ret))

            ;; ((query-mid)
            ;;  (setq ret (assqref 'mid (car xmltree))))

            )

          (puthash `(,(assqref 'username args) ,(assqref 'method args))
                   (or ret "")
                   twittering-simple-hash))))
     (t
      (let ((error-mes (twittering-get-error-message header-info (process-buffer proc))))
        (if error-mes
            (setq mes (format "Response: %s (%s)" status-line error-mes))
          (setq mes (format "Response: %s" status-line))))))
    (setq twittering-get-simple-retrieved
          (or ret
              mes
              "")) ;; set "" explicitly if user does not have a list.
    nil))

(defun twittering-save-icon-properties (&optional filename)
  (let ((filename (or filename twittering-icon-storage-file))
        (stored-data
         (cond
          ((null twittering-icon-storage-limit)
           (let ((result nil)
                 (dummy-icon-properties (twittering-make-display-spec-for-icon
                                         twittering-error-icon-data-pair)))
             (maphash
              (lambda (size hash)
                (maphash (lambda (url properties)
                           (unless (equal properties dummy-icon-properties)
                             (setq result (cons (cons size url) result))))
                         hash))
              twittering-icon-prop-hash)
             result))
          (t
           (reverse twittering-icon-storage-recent-icons)))))
    (when (require 'jka-compr nil t)
      (with-auto-compression-mode
        (with-temp-file filename
          (insert "( 2 ")
          (prin1 (cons 'emacs-version emacs-version) (current-buffer))
          (insert "(icon-list ")
          (mapc (lambda (entry)
                  (let* ((size (elt entry 0))
                         (url (elt entry 1))
                         (properties
                          (gethash url
                                   (gethash size twittering-icon-prop-hash))))
                    (insert (format "(%d " size))
                    (prin1 url (current-buffer))
                    (insert " ")
                    (prin1 properties (current-buffer))
                    (insert ")\n")))
                stored-data)
          (insert "))"))))))

(defun twittering-load-icon-properties (&optional filename)
  (let* ((filename (or filename twittering-icon-storage-file))
         (data
          (with-temp-buffer
            (condition-case err
                (cond
                 ((and (require 'jka-compr)
                       (file-exists-p filename))
                  (with-auto-compression-mode (insert-file-contents filename))
                  (read (current-buffer)))
                 (t
                  nil))
              (error
               (message "Failed to load icon images. %s" (cdr err))
               nil)))))
    (cond
     ((equal 2 (car data))
      (let ((version (cdr (assq 'emacs-version data))))
        (cond
         ((or (equal version emacs-version)
              (y-or-n-p
               (format "%s is generated by Emacs %s! Use it?"
                       filename version)))
          (mapc (lambda (entry)
                  (let ((size (elt entry 0))
                        (url (elt entry 1))
                        (properties (elt entry 2)))
                    (twittering-update-icon-storage-recent-icons size url
                                                                 properties)
                    (twittering-register-image-spec url properties size)))
                (cdr (assq 'icon-list data))))
         (t
          (message "Stopped loading icons")))))
     (t
      (mapc (lambda (entry)
              (let ((size (car entry))
                    (prop-alist (cdr entry)))
                (mapc (lambda (entry)
                        (let ((url (car entry))
                              (properties (cdr entry)))
                          (twittering-update-icon-storage-recent-icons
                           size url properties)
                          (twittering-register-image-spec url properties
                                                          size)))
                      prop-alist)))
            data)))))

;;;;
;;;; Mode-line
;;;;

;;; SSL
(defconst twittering-ssl-indicator-image
  (when (image-type-available-p 'xpm)
    '(image :type xpm
            :ascent center
            :data
            "/* XPM */
/*
 * Copyright (C) 2003 Yuuichi Teranishi <teranisi@gohome.org>
 * Copyright (C) 2003 Kazu Yamamoto <kazu@Mew.org>
 * Copyright (C) 2004 Yoshifumi Nishida <nishida@csl.sony.co.jp>
 * Copyright notice is the same as Mew's one.
 */
static char * yellow3_xpm[] = {
\"14 14 7 1\",
\"         c None\",
\".        c #B07403\",
\"+        c #EFEE38\",
\"@        c #603300\",
\"#        c #D0A607\",
\"$        c #FAFC90\",
\"%        c #241100\",
\"    .++++@    \",
\"   .+@...+@   \",
\"  .+@    .+@  \",
\"  .+@    .+@  \",
\"  .+@    .+@  \",
\"++########@@@@\",
\"+$$++++++++#@@\",
\"+$++++%@+++#@@\",
\"+$+++%%%@++#@@\",
\"+$+++%%%@++#@@\",
\"+$++++%@+++#@@\",
\"+$++++%@+++#@@\",
\"+$+++++++++#@@\",
\"++@@@@@@@@@@@@\"};
"
;; The above image is copied from `mew-lock.xpm' distributed with Mew.
;; The copyright of the image is below, which is copied from `mew.el'.

;; Copyright Notice:

;; Copyright (C) 1994-2009 Mew developing team.
;; All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;;
;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;; 2. Redistributions in binary form must reproduce the above copyright
;;    notice, this list of conditions and the following disclaimer in the
;;    documentation and/or other materials provided with the distribution.
;; 3. Neither the name of the team nor the names of its contributors
;;    may be used to endorse or promote products derived from this software
;;    without specific prior written permission.
;;
;; THIS SOFTWARE IS PROVIDED BY THE TEAM AND CONTRIBUTORS ``AS IS'' AND
;; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
;; PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE TEAM OR CONTRIBUTORS BE
;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
;; BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
;; OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
;; IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
            ))
  "Image for indicator of SSL state.")

(defconst twittering-modeline-ssl
  (if twittering-ssl-indicator-image
      (propertize "SSL"
                  'display twittering-ssl-indicator-image
                  'help-echo "SSL is enabled.")
    "SSL"))

;; ACTIVE/INACTIVE
(defconst twittering-active-indicator-image
  (when (image-type-available-p 'xpm)
    '(image :type xpm
            :ascent center
            :data
            "/* XPM */
static char *plugged[] = {
\"32 12 8 1\",
\"  c None\",
\". c #a6caf0\",
\"# c #8fa5cf\",
\"a c #717171\",
\"b c #5d5d97\",
\"c c #8488ca\",
\"d c #9f9f9f\",
\"e c #7f8080\",
\"            ...                 \",
\"           .ccb....             \",
\"           accb####.            \",
\"          .accb#####..          \",
\"   eeeeeeeeaccb#####.eeeeeeee   \",
\"   dddddddcaccb#####.dedddddd   \",
\"   dddddddcaccb#####.dedddddd   \",
\"   eeeeeeeeaccb#####.eeeeeeee   \",
\"          aaccb####aaa          \",
\"           accbaaaaa            \",
\"           aaaaaaaa             \",
\"            aaa                 \"
};
"))
  "Image for indicator of active state."
;; The above image is copied from `plugged.xpm' distributed with Wanderlust
;; by Yuuichi Teranishi <teranisi@gohome.org>.
;; The copyright of the image is below, which is copied from `COPYING' of
;; Wanderlust 2.14.
;; Copyright (C) 1998-2001 Yuuichi Teranishi <teranisi@gohome.org>
;;
;;    This program is free software; you can redistribute it and/or modify
;;    it under the terms of the GNU General Public License as published by
;;    the Free Software Foundation; either version 2, or (at your option)
;;    any later version.
;;
;;    This program is distributed in the hope that it will be useful,
;;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;    GNU General Public License for more details.
;;
;;    You should have received a copy of the GNU General Public License
;;    along with GNU Emacs; see the file COPYING.  If not, write to the
;;    Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;    Boston, MA 02111-1307, USA.
)

(defconst twittering-inactive-indicator-image
  (when (image-type-available-p 'xpm)
    '(image :type xpm
            :ascent center
            :data
            "/* XPM */
static char * unplugged_xpm[] = {
\"32 12 9 1\",
\"         s None        c None\",
\".        c tomato\",
\"X        c #a6caf0\",
\"o        c #8488ca\",
\"O        c #5d5d97\",
\"+        c #8fa5cf\",
\"@        c #717171\",
\"#        c #7f8080\",
\"$        c #9f9f9f\",
\"          XXX......             \",
\"           ...    ...           \",
\"          ..O     ....X         \",
\"         ..oO    ...+..XX       \",
\"   ######.ooO   ...+++.X#####   \",
\"   $$$$$o.ooO  ...@+++.X$#$$$   \",
\"   $$$$$o.ooO ... @+++.X$#$$$   \",
\"   ######.ooO...  @+++.X#####   \",
\"         ..o...   @++..@@       \",
\"          ....    @@..@         \",
\"           ...    ...@          \",
\"             ......             \"
};
"))
  "Image for indicator of inactive state."
;; The above image is copied from `unplugged.xpm' distributed with Wanderlust
;; by Yuuichi Teranishi <teranisi@gohome.org>.
;; The copyright of the image is below, which is copied from `COPYING' of
;; Wanderlust 2.14.
;; Copyright (C) 1998-2001 Yuuichi Teranishi <teranisi@gohome.org>
;;
;;    This program is free software; you can redistribute it and/or modify
;;    it under the terms of the GNU General Public License as published by
;;    the Free Software Foundation; either version 2, or (at your option)
;;    any later version.
;;
;;    This program is distributed in the hope that it will be useful,
;;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;    GNU General Public License for more details.
;;
;;    You should have received a copy of the GNU General Public License
;;    along with GNU Emacs; see the file COPYING.  If not, write to the
;;    Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;    Boston, MA 02111-1307, USA.
)

(defconst twittering-logo-image
  (when (image-type-available-p 'xpm)
    '(image :type xpm
            :ascent center
            :data
            "/* XPM */
static char * twitter_xpm[] = {
\"16 16 104 2\",
\"          c None\",
\".         c #A3A2A2\",
\"+         c #ADACAC\",
\"@         c #64CFFC\",
\"#         c #64D0FC\",
\"$         c #69D1FC\",
\"%         c #6AD1FC\",
\"&         c #6CD2FC\",
\"*         c #6DD2FC\",
\"=         c #6ED3FC\",
\"-         c #70D3FC\",
\";         c #71D3FC\",
\">         c #C2C1C1\",
\",         c #72D3FC\",
\"'         c #71D4FC\",
\")         c #72D4FC\",
\"!         c #73D4FC\",
\"~         c #C3C3C3\",
\"{         c #75D5FC\",
\"]         c #76D5FC\",
\"^         c #78D6FC\",
\"/         c #79D6FC\",
\"(         c #7BD6FC\",
\"_         c #7DD7FC\",
\":         c #7FD8FC\",
\"<         c #80D8FC\",
\"[         c #80D8FD\",
\"}         c #81D8FD\",
\"|         c #C9C8C8\",
\"1         c #CAC9C9\",
\"2         c #CCCAC9\",
\"3         c #85DAFD\",
\"4         c #89DBFD\",
\"5         c #8BDCFD\",
\"6         c #8CDCFD\",
\"7         c #91DDFD\",
\"8         c #92DDFD\",
\"9         c #D3D2D2\",
\"0         c #D7D7D6\",
\"a         c #A8E4FC\",
\"b         c #A5E5FF\",
\"c         c #A7E5FF\",
\"d         c #A6E6FF\",
\"e         c #A7E6FF\",
\"f         c #ABE6FE\",
\"g         c #AEE7FD\",
\"h         c #AFE8FF\",
\"i         c #E1DFDF\",
\"j         c #B9EAFD\",
\"k         c #B9EAFE\",
\"l         c #B8EBFF\",
\"m         c #E5E2E1\",
\"n         c #E6E2E1\",
\"o         c #C7EFFF\",
\"p         c #C8F0FF\",
\"q         c #ECE9E7\",
\"r         c #ECE9E8\",
\"s         c #EDECEB\",
\"t         c #D0F3FF\",
\"u         c #D3F3FF\",
\"v         c #EEEDED\",
\"w         c #D4F3FF\",
\"x         c #EFEDEC\",
\"y         c #D6F4FF\",
\"z         c #D8F6FF\",
\"A         c #D9F6FF\",
\"B         c #F3F0EE\",
\"C         c #F4F0EF\",
\"D         c #DBF6FF\",
\"E         c #DEF6FF\",
\"F         c #DFF6FF\",
\"G         c #E1F6FF\",
\"H         c #DFF7FF\",
\"I         c #DFF8FF\",
\"J         c #E1F8FF\",
\"K         c #E7F7FF\",
\"L         c #F7F4F3\",
\"M         c #F8F4F3\",
\"N         c #E4F9FF\",
\"O         c #EAF8FE\",
\"P         c #EBF8FE\",
\"Q         c #F9F6F5\",
\"R         c #EFFAFE\",
\"S         c #ECFBFF\",
\"T         c #FBF8F7\",
\"U         c #F9F9F9\",
\"V         c #FAF9F9\",
\"W         c #FDF9F8\",
\"X         c #FAFAFA\",
\"Y         c #F3FCFF\",
\"Z         c #FCFAFA\",
\"`         c #FDFAF9\",
\" .        c #F6FCFF\",
\"..        c #FCFBFA\",
\"+.        c #F2FEFF\",
\"@.        c #F8FDFF\",
\"#.        c #FDFCFB\",
\"$.        c #FDFCFC\",
\"%.        c #F9FDFF\",
\"&.        c #FFFCFA\",
\"*.        c #FFFEFC\",
\"=.        c #FFFEFD\",
\"-.        c #FDFFFF\",
\";.        c #FFFFFF\",
\"      0 q r                     \",
\"    v ;.H N ;.~                 \",
\"    =.o ! ( D M                 \",
\"    X b $ % k *.B Q L x         \",
\"    V e & = a G J F E S ;.9     \",
\"    V e * ! { ^ ^ ^ ] _ t `     \",
\"    V e * ! ' = = = = @ b $.    \",
\"    V e * ) / < : : _ 3 z T     \",
\"    V e & = g R P O O Y V .     \",
\"    U d & * j ;.;.;.;.;.>       \",
\"    Z h & = 7 K @. . .%...      \",
\"    W y , - ; [ 6 5 4 8 I `     \",
\"    1 ;.f & = = * * * # c #.    \",
\"      s -.l } ! ! ! ' { p &.    \",
\"        i ;.+.A u w u J ;.|     \",
\"            2 n B B C m +       \"};
"))
  "Image for twitter logo.")

(defconst twittering-modeline-properties
  (when (display-mouse-p)
    `(local-map
      ,(purecopy (make-mode-line-mouse-map
                  'mouse-2 #'twittering-toggle-activate-buffer))
      help-echo "mouse-2 toggles activate buffer")))

(defconst twittering-modeline-active
  (if twittering-active-indicator-image
      (apply 'propertize " "
             `(display ,twittering-active-indicator-image
                       ,@twittering-modeline-properties))
    " "))

(defconst twittering-modeline-inactive
  (if twittering-inactive-indicator-image
      (apply 'propertize "INACTIVE"
             `(display ,twittering-inactive-indicator-image
                       ,@twittering-modeline-properties))
    "INACTIVE"))

(defconst twittering-logo
    (if twittering-logo-image
        (apply 'propertize " "
               `(display ,twittering-logo-image))
      "tw"))

(defun twittering-mode-line-buffer-identification ()
  (let ((active-mode-indicator
         (if twittering-active-mode
             twittering-modeline-active
           twittering-modeline-inactive))
        (enabled-options
         `(,(if twittering-display-connection-method
                (concat
                 (when twittering-use-ssl (concat twittering-modeline-ssl ":"))
                 (twittering-get-connection-method-name twittering-use-ssl))
              (when twittering-use-ssl twittering-modeline-ssl))
           ,@(when twittering-jojo-mode '("jojo"))
           ,@(when twittering-icon-mode '("icon"))
           ,@(when twittering-reverse-mode '("reverse"))
           ,@(when twittering-scroll-mode '("scroll"))
           ,@(when twittering-proxy-use '("proxy")))))
    (concat active-mode-indicator
            (when twittering-display-remaining
              (format " %d/%d"
                      (twittering-get-ratelimit-remaining)
                      (twittering-get-ratelimit-limit)))
            (when enabled-options
              (concat "[" (mapconcat 'identity enabled-options " ") "]")))))

(defun twittering-update-mode-line ()
  "Update mode line."
  (force-mode-line-update))

;;;;
;;;; Format of a status
;;;;

(defun twittering-created-at-to-seconds (created-at)
  (let ((encoded-time (apply 'encode-time (parse-time-string created-at))))
    (+ (* (car encoded-time) 65536)
       (cadr encoded-time))))

(defun twittering-make-common-properties (status)
  "Generate a property list that tweets should have irrespective of format."
  (apply 'append
         `(field ,(twittering-make-field-id status))
         (mapcar (lambda (entry)
                   (let ((prop-sym (if (consp entry) (car entry) entry))
                         (status-sym (if (consp entry) (cdr entry) entry)))
                     (list prop-sym (assqref status-sym status))))
                 '(id retweeted-id source-spec
                      (username . user-screen-name) text))))

(defun twittering-get-common-properties (pos)
  "Get a common property list of the tweet rendered at POS.
The common property list is added to each rendered tweet irrespective
of format. The common properties follows:
 properites generated by `twittering-make-common-properties',
 `field' and `rendered-as' generated by `twittering-make-field-properties'."
  (apply 'append
         (mapcar (lambda (prop)
                   (let ((value (get-text-property pos prop)))
                     (when value
                       `(,prop ,value))))
                 '(field id rendered-as retweeted-id source-spec
                         text username face))))

(defun twittering-format-string (string prefix replacement-table)
  "Format STRING according to PREFIX and REPLACEMENT-TABLE.
PREFIX is a regexp. REPLACEMENT-TABLE is a list of (FROM . TO) pairs,
where FROM is a regexp and TO is a string or a 2-parameter function.

The pairs in REPLACEMENT-TABLE are stored in order of precedence.
First, search PREFIX in STRING from left to right.
If PREFIX is found in STRING, try to match the following string with
FROM of each pair in the same order of REPLACEMENT-TABLE. If FROM in
a pair is matched, replace the prefix and the matched string with a
string generated from TO.
If TO is a string, the matched string is replaced with TO.
If TO is a function, the matched string is replaced with the
return value of (funcall TO CONTEXT), where CONTEXT is an alist.
Each element of CONTEXT is (KEY . VALUE) and KEY is one of the
following symbols;
  'following-string  --the matched string following the prefix
  'match-data --the match-data for the regexp FROM.
  'prefix --PREFIX.
  'replacement-table --REPLACEMENT-TABLE.
  'from --FROM.
  'processed-string --the already processed string."
  (let ((current-pos 0)
        (result "")
        (case-fold-search nil))
    (while (and (string-match prefix string current-pos)
                (not (eq (match-end 0) current-pos)))
      (let ((found nil)
            (current-table replacement-table)
            (next-pos (match-end 0))
            (matched-string (match-string 0 string))
            (skipped-string
             (substring string current-pos (match-beginning 0))))
        (setq result (concat result skipped-string))
        (setq current-pos next-pos)
        (while (and (not (null current-table))
                    (not found))
          (let ((key (caar current-table))
                (value (cdar current-table))
                (following-string (substring string current-pos))
                (case-fold-search nil))
            (if (string-match (concat "\\`" key) following-string)
                (let ((next-pos (+ current-pos (match-end 0)))
                      (output
                       (if (stringp value)
                           value
                         (funcall value
                                  `((following-string . ,following-string)
                                    (match-data . ,(match-data))
                                    (prefix . ,prefix)
                                    (replacement-table . ,replacement-table)
                                    (from . ,key)
                                    (processed-string . ,result))))))
                  (setq found t)
                  (setq current-pos next-pos)
                  (setq result (concat result output)))
              (setq current-table (cdr current-table)))))
        (if (not found)
            (setq result (concat result matched-string)))))
    (let ((skipped-string (substring string current-pos)))
      (concat result skipped-string))
    ))

(defun twittering-make-string-with-user-name-property (str status)
  (if str
      (let* ((user-screen-name (assqref 'user-screen-name status))
             (uri (twittering-get-status-url
                    (if (eq (twittering-extract-service) 'sina)
                        (assqref 'user-id status)
                      user-screen-name)))
             (spec (twittering-string-to-timeline-spec user-screen-name)))
        (propertize str
                    'mouse-face 'highlight
                    'keymap twittering-mode-on-uri-map
                    'uri uri
                    'screen-name-in-text user-screen-name
                    'goto-spec spec
                    'face 'twittering-username-face))
    ""))

(defun twittering-make-string-with-source-property (str status)
  (if str
      (let ((uri (assqref 'source-uri status)))
        (propertize str
                    'mouse-face 'highlight
                    'keymap twittering-mode-on-uri-map
                    'uri uri
                    'face 'twittering-uri-face
                    'source str))
    ""))

(defun twittering-make-fontified-tweet-text (str)
  (let* ((regexp-list
          `(;; Hashtag
            (hashtag . ,(concat twittering-regexp-hash
                                (if (eq (twittering-extract-service) 'sina)
                                    (format "\\([^%s]+%s\\)"
                                            twittering-regexp-hash
                                            twittering-regexp-hash)
                                  "\\([a-zA-Z0-9_-]+\\)")))
            ;; @USER/LIST
            (list-name . ,(concat twittering-regexp-atmark
                                 "\\([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\\)"))
            ;; @USER
            (screen-name
             . ,(concat twittering-regexp-atmark
                        (if (eq (twittering-extract-service) 'sina)
                            ;; Exclude some common chinese punctuations.
                            (format "\\([^:,.?!：)）、，。？！…[:space:]%s]+\\)"
                                    twittering-regexp-atmark)
                          "\\([a-zA-Z0-9_-]+\\)")))
            ;; URI
            (uri . ,twittering-regexp-uri)))
         (regexp-str (mapconcat 'cdr regexp-list "\\|"))
         (pos 0)
         (str (copy-sequence str)))
    (while (string-match regexp-str str pos)
      (let* ((entry
              ;; Find matched entries.
              (let ((rest regexp-list)
                    (counter 1))
                (while (and rest (not (match-string counter str)))
                  (setq rest (cdr rest))
                  (setq counter (1+ counter)))
                (when rest
                  (list (caar rest)
                        (match-beginning counter)
                        (match-string counter str)))))
             (sym (elt entry 0))
             (matched-beg (elt entry 1))
             (matched-str (elt entry 2))
             (beg (if (memq sym '(list-name screen-name))
                      ;; Properties are added to the matched part only.
                      ;; The prefixes `twittering-regexp-atmark' will not
                      ;; be highlighted.
                      matched-beg
                    (match-beginning 0)))
             (end (match-end 0))
             (properties
              (cond
               ((eq sym 'hashtag)
                (let* ((hashtag matched-str)
                       (spec
                        (twittering-string-to-timeline-spec
                         (concat "#" hashtag)))
                       (url (twittering-get-search-url (concat "#" hashtag))))
                  (list
                   'mouse-face 'highlight
                   'keymap twittering-mode-on-uri-map
                   'uri url
                   'goto-spec spec
                   'face 'twittering-username-face)))
               ((eq sym 'list-name)
                (let ((list-name matched-str))
                  (list
                    'mouse-face 'highlight
                    'keymap twittering-mode-on-uri-map
                    'uri (twittering-get-status-url list-name)
                    'goto-spec (twittering-string-to-timeline-spec list-name)
                    'face 'twittering-username-face)))
               ((eq sym 'screen-name)
                (let ((screen-name matched-str))
                  (list
                   'mouse-face 'highlight
                   'keymap twittering-mode-on-uri-map
                   'uri (if (eq (twittering-extract-service) 'sina)
                            ;; TODO: maybe we can get its user_id
                            ;; at background.
                            (concat "http://t.sina.com.cn/search/user.php?search="
                                    screen-name)
                          (twittering-get-status-url screen-name))
                   'screen-name-in-text screen-name
                   'goto-spec (twittering-string-to-timeline-spec screen-name)
                   'face 'twittering-uri-face)))
               ((eq sym 'uri)
                (let ((uri matched-str))
                  (list
                   'mouse-face 'highlight
                   'keymap twittering-mode-on-uri-map
                   'uri uri
                   'face 'twittering-uri-face))))))
        (add-text-properties beg end properties str)
        (setq pos end)))
    str))

(defun twittering-generate-format-table (status-sym prefix-sym)
  `(("%" . "%")
    ("}" . "}")
    ("#" . (assqref 'id ,status-sym))
    ("'" . (when (string= "true" (assqref 'truncated ,status-sym))
             "..."))
    ("c" . (assqref 'created-at       ,status-sym))
    ("d" . (assqref 'user-description ,status-sym))
    ("f" .
     (twittering-make-string-with-source-property
      (assqref 'source ,status-sym) ,status-sym))
    ("i" .
     (when (and twittering-icon-mode window-system)
       (let ((url
              (cond
               ((and twittering-use-profile-image-api
                     (eq (twittering-extract-service) 'twitter)
                     (or (null twittering-convert-fix-size)
                         (member twittering-convert-fix-size '(48 73))))
                (let ((user (assqref 'user-screen-name ,status-sym))
                      (size
                       (if (or (null twittering-convert-fix-size)
                               (= 48 twittering-convert-fix-size))
                           "normal"
                         "bigger")))
                  (format "http://%s/%s/%s.xml?size=%s" (twittering-lookup-service-method-table 'api)
                          (twittering-api-path "users/profile_image") user size)))
               (t
                (assqref 'user-profile-image-url ,status-sym)))))
         (twittering-make-icon-string nil nil url))))
    ("j" . (assqref 'user-id ,status-sym))
    ("L" .
     (let ((location (or (assqref 'user-location ,status-sym) "")))
       (unless (string= "" location)
         (concat "[" location "]"))))
    ("l" . (assqref 'user-location ,status-sym))
    ;; FIXME: why "C" turns into timestamp?? (xwl)
    ("m" . (when (eq (twittering-extract-service) 'sina) ; comment counts.
             (twittering-get-simple nil nil (assqref 'id ,status-sym) 'counts)))
    ("p" . (when (string= "true" (assqref 'user-protected ,status-sym))
             "[x]"))
    ("r" .
     (let ((reply-id (or (assqref 'in-reply-to-status-id ,status-sym)
                         (assqref 'id
                                  (or
                                   (assqref 'in-reply-to-comment ,status-sym)
                                   (assqref 'in-reply-to-status ,status-sym)))
                         ""))

           (reply-name (or (assqref 'in-reply-to-screen-name ,status-sym)
                           (assqref 'user-screen-name
                                    (or
                                     (assqref 'in-reply-to-comment ,status-sym)
                                     (assqref 'in-reply-to-status ,status-sym)))
                           ""))

           (recipient-screen-name
            (assqref 'recipient-screen-name ,status-sym)))

       (let* ((pair
               (cond
		((or (assqref 'in-reply-to-comment ,status-sym)
		     (assqref 'in-reply-to-status ,status-sym))
		 (let* ((status (assqref 'author-status ,status-sym))
			(name (assqref 'user-screen-name status)))
		   (list (format " (replied by %s)"
				 (twittering-make-string-with-user-name-property name status)))))

                (recipient-screen-name
                 (cons (format " sent to %s" recipient-screen-name)
                       (twittering-get-status-url recipient-screen-name)))
                ((and (not (string= "" reply-id))
                      (not (string= "" reply-name)))
                 (cons (format " in reply to %s" reply-name)
                       (twittering-get-status-url reply-name reply-id)))
                (t nil)))
              (str (car pair))
              (url (cdr pair))
              (properties
               (list 'mouse-face 'highlight 'face 'twittering-uri-face
                     'keymap twittering-mode-on-uri-map
                     'uri url)))
         (when str 
	   (if url (apply 'propertize str properties) str)))))
    ("R" .
     (when (assqref 'is-retweeting ,status-sym)
       (concat " (retweeted by "
	       (twittering-make-string-with-user-name-property
		(assqref 'user-screen-name (assqref 'author-status ,status-sym))
		(assqref 'author-status ,status-sym))
	       ")")))
    ("S" .
     (twittering-make-string-with-user-name-property
      (assqref 'user-name ,status-sym) ,status-sym))
    ("s" .
     (twittering-make-string-with-user-name-property
      (assqref 'user-screen-name ,status-sym) ,status-sym))
    ("T" .
     (let ((s (if (and twittering-icon-mode window-system)
                  (let ((thumbnail-pic (assqref 'thumbnail-pic ,status-sym))
                        (bmiddle-pic (assqref 'bmiddle-pic ,status-sym)))
                    (when thumbnail-pic
                      (twittering-toggle-thumbnail thumbnail-pic bmiddle-pic t)))
                (assqref 'original-pic ,status-sym))))
       (when s
         (twittering-make-fontified-tweet-text
          (concat "\n" s)))))
    ("t" .
     (twittering-make-fontified-tweet-text
      (assqref 'text ,status-sym)))
    ("u" . (assqref 'user-url ,status-sym))))

(defun twittering-generate-formater-for-first-spec (format-str status-sym prefix-sym)
  (cond
   ((string-match "\\`}" format-str)
    ;; "}" at the first means the end of the current level.
    `(nil . ,(substring format-str (match-end 0))))
   ((string-match "\\`%" format-str)
    (let* ((following (substring format-str 1))
           (table (twittering-generate-format-table status-sym prefix-sym))
           (regexp (concat "\\`\\(" (mapconcat 'car table "\\|") "\\)"))
           (case-fold-search nil))
      (cond
       ((string-match "\\`\\(@\\|g\\)\\({\\([^}]*\\)}\\)?" following)
        (let ((time-format (if (string= (match-string 1 following) "g")
                               "%g"
                             (or (match-string 3 following)
                                 "%I:%M %p %B %d, %Y")))
              (rest (substring following (match-end 0))))
          `((let* ((created-at-str (assqref 'created-at ,status-sym))
                   ;; (created-at
                   ;;  (apply 'encode-time
                   ;;            (parse-time-string created-at-str)))
                   (in-reply-to-status (assqref 'in-reply-to-status ,status-sym))
                   (url
                    (twittering-get-status-url
                     (assqref 'user-id (or in-reply-to-status ,status-sym))
                     (or (assqref 'retweeted-id ,status-sym)
                         (assqref 'id (or in-reply-to-status ,status-sym)))))
                   (properties
                    (list 'mouse-face 'highlight 'face 'twittering-uri-face
                          'keymap twittering-mode-on-uri-map
                          'uri url)))
              (twittering-make-passed-time-string
               nil nil created-at-str ,time-format properties))
            . ,rest)))
       ((string-match "\\`C\\({\\([^}]*\\)}\\)?" following)
        (let ((time-format (or (match-string 2 following) "%H:%M:%S"))
              (rest (substring following (match-end 0))))
          `((let* ((created-at-str (assqref 'created-at ,status-sym))
                   (created-at (apply 'encode-time
                                      (parse-time-string created-at-str))))
              (format-time-string ,time-format created-at))
            . ,rest)))
       ((string-match "\\`FACE\\[\\([a-zA-Z0-9:-]+\\)\\(, *\\([a-zA-Z0-9:-]+\\)\\)?\\]{" following)
        (let* ((face-name-str-1 (match-string 1 following))
               (face-sym-1 (intern face-name-str-1))
               (face-name-str-2 (match-string 3 following))
               (face-sym-2 (and face-name-str-2 (intern face-name-str-2)))
               (str-after-brace (substring following (match-end 0)))
               (pair (twittering-generate-formater-for-current-level
                      str-after-brace status-sym prefix-sym))
               (braced-body (car pair))
               (rest (cdr pair)))
          `((twittering-decorate-zebra-background (concat ,@braced-body)
                                                  ,face-sym-1
                                                  ,face-sym-2)
            . ,rest)))
       ((string-match "\\`\\(FILL\\|FOLD\\)\\(\\[\\([^]]*\\)\\]\\)?{"
                      following)
        (let* ((str-after-brace (substring following (match-end 0)))
               (specifier (match-string 1 following))
               (prefix-str (match-string 3 following))
               (pair (twittering-generate-formater-for-current-level
                      str-after-brace status-sym prefix-sym))
               (filled-body (car pair))
               (formater
                `(lambda (,status-sym ,prefix-sym)
                   (let ((,prefix-sym (concat ,prefix-sym ,prefix-str)))
                     (concat ,@filled-body))))
               (keep-newline (string= "FOLD" specifier))
               (rest (cdr pair)))
          `((twittering-update-filled-string
             nil nil ,formater ,status-sym ,prefix-sym ,prefix-str
             ,keep-newline)
            . ,rest)))
       ((string-match "\\`RT{" following)
        (let* ((str-after-brace (substring following (match-end 0)))
               (pair (twittering-generate-formater-for-current-level
                      str-after-brace 'retweeting prefix-sym))
               (braced-body (car pair))
               (rest (cdr pair)))
          `((when (assq 'retweeted-id ,status-sym)
              (let ((retweeting
                     (mapcar (lambda (entry)
                               (let ((key-str (symbol-name (car entry)))
                                     (value (cdr entry)))
                                 (when (string-match "\\`retweeting-" key-str)
                                   (let ((new-key
                                          (intern (substring key-str
                                                             (match-end 0)))))
                                     (cons new-key value)))))
                             ,status-sym)))
                (concat ,@braced-body)))
            . ,rest)))
       ((string-match regexp following)
        (let ((specifier (match-string 1 following))
              (rest (substring following (match-end 0))))
          `(,(assocref specifier table) . ,rest)))
       (t
        `("%" . ,following)))))
   ((string-match "\\(%\\|}\\)" format-str)
    (let* ((sep (match-beginning 0))
           (first (substring format-str 0 sep))
           (last (substring format-str sep)))
      ;; Split before "%" or "}".
      `(,first . ,last)))
   (t
    `(,format-str . nil))))

(defun twittering-generate-formater-for-current-level (format-str status-sym prefix-sym)
  (let ((result nil)
        (rest format-str)
        (continue t))
    (while (and continue rest)
      (let* ((pair
              (twittering-generate-formater-for-first-spec
               rest status-sym prefix-sym))
             (current-result (car pair)))
        (if current-result
            (setq result (append result `(,current-result)))
          ;; If `result' is nil, it means the end of the current level.
          (setq continue nil))
        (setq rest (cdr pair))))
    `(,result . ,rest)))

(defun twittering-generate-format-status-function (format-str)
  (let* ((status-sym 'status)
         (prefix-sym 'prefix)
         (pair (twittering-generate-formater-for-current-level
                format-str status-sym prefix-sym))
         (body (car pair))
         (rest (cdr pair)))
    (cond
     ((null rest)
      `(lambda (status prefix)
         (let* ((common-properties (twittering-make-common-properties status))
                (col (and (twittering-my-status-p status) twittering-my-fill-column))
                (str (let ((twittering-fill-column (or col twittering-fill-column)))
                       (concat ,@body)))
                (str
                 (if col
                     (progn
                       ;; Padding spaces before icon placed at right.
                       ;; FIXME: matching against `:' is too ad-hoc.
                       (string-match "\\(\\`.*:\\)" str)
                       (let ((face (get-text-property (1- (length str)) 'face str))
                             (repl (format (format "%%-%ds" col) (match-string 1 str))))
                         (twittering-decorate-zebra-background
                          (replace-match repl nil nil str) face nil)))
                   str))
                (str (if prefix (replace-regexp-in-string "^" prefix str) str))
                (next (next-single-property-change 0 'need-to-be-updated str))
                (need-to-be-updated
                 (or (get-text-property 0 'need-to-be-updated str)
                     (and next (< next (length str))))))
           (add-text-properties 0 (length str) common-properties str)
           (when (and prefix need-to-be-updated)
             ;; With a prefix, redisplay the total status instead of
             ;; redisplaying partially.
             (remove-text-properties 0 (length str)
                                     '(need-to-be-updated nil) str)
             (put-text-property 0 (length str) 'need-to-be-updated
                                `(twittering-format-status-for-redisplay
                                  ,status ,prefix)
                                str))
           str)))
     (t
      (message "Failed to generate a status formater for `twittering-mode'.")
      nil))))

(defun twittering-update-status-format ()
  (mapc
   (lambda (fmt-src-func)
     (let ((fmt  (nth 0 fmt-src-func))
           (src  (nth 1 fmt-src-func))
           (func (nth 2 fmt-src-func)))
       (unless (string= (symbol-value fmt) (symbol-value src))
         (set src (symbol-value fmt))
         (let ((before (get-buffer "*Compile-Log*")))
           (set func
                (byte-compile
                 (twittering-generate-format-status-function
                  (symbol-value fmt))))
           (let ((current (get-buffer "*Compile-Log*")))
             (when (and (null before) current (= 0 (buffer-size current)))
               (kill-buffer current)))))))
   '((twittering-status-format
      twittering-format-status-function-source
      twittering-format-status-function)
     (twittering-my-status-format
      twittering-format-my-status-function-source
      twittering-format-my-status-function))))

(defun twittering-format-status (status &optional prefix)
  "Format a STATUS by using `twittering-format-status-function'.
Specification of FORMAT-STR is described in the document for the
variable `twittering-status-format'."
  (if (and twittering-my-status-format (twittering-my-status-p status))
      (funcall twittering-format-my-status-function status prefix)
    (funcall twittering-format-status-function status prefix)))

(defun twittering-format-status-for-redisplay (beg end status &optional prefix)
  (twittering-format-status status prefix))

;;;;
;;;; Rendering
;;;;

(defun twittering-field-id< (field1 field2)
  (string< field1 field2))

(defun twittering-field-id= (field1 field2)
  (string= field1 field2))

(defun twittering-make-field-id (status &optional base-id)
  "Generate a field property for STATUS.
Tweets are rendered in order of the field.

If BASE-ID is non-nil, generate a field id for a tweet rendered
as a popped ancestor tweet by `twittering-show-replied-statuses'.
In the case, BASE-ID means the ID of the descendant."
  (let ((id (cdr (assq 'id status)))
        (format-func (lambda (id) (format "%02d-%s" (length id) id))))
    (cond
     (base-id
      (format "O:%s:5:ancestor:%s"
              (funcall format-func base-id)
              (funcall format-func id)))
     (t
      (format "O:%s" (funcall format-func id))))))

(defun twittering-make-field-properties (status &optional rendered-as)
  (let* ((base-id (cdr (assq 'ancestor-of rendered-as)))
         (field-id (twittering-make-field-id status base-id)))
    (if rendered-as
        `(field ,field-id rendered-as ,rendered-as)
      `(field ,field-id))))

(defun twittering-make-field-properties-of-popped-ancestors (status base-id)
  (twittering-make-field-properties status `((ancestor-of . ,base-id))))

(defun twittering-rendered-as-ancestor-status-p (&optional pos)
  "Return non-nil if the status at POS is rendered as an ancestor.
Ancestor statuses are rendered by `twittering-show-replied-statuses'."
  (let ((pos (or pos (point))))
    (assq 'ancestor-of (get-text-property pos 'rendered-as))))

(defun twittering-get-base-id-of-ancestor-at (&optional pos)
  "Return the base ID of a popped ancestor status rendered at POS.
If the status at POS is not a popped ancestor status or no status is
rendered at POS, return nil."
  (let ((pos (or pos (point))))
    (cdr (assq 'ancestor-of (get-text-property pos 'rendered-as)))))

(defun twittering-fill-string (str &optional adjustment prefix keep-newline)
  (when (and (not (boundp 'kinsoku-limit))
             enable-kinsoku)
    ;; `kinsoku-limit' is defined on loading "international/kinsoku.el".
    ;; Without preloading, "kinsoku.el" will be loaded by auto-loading
    ;; triggered by `fill-region-as-paragraph'.
    ;; In that case, the local binding of `kinsoku-limit' conflicts the
    ;; definition by `defvar' in "kinsoku.el".
    ;; The below warning is displayed;
    ;; "Warning: defvar ignored because kinsoku-limit is let-bound".
    ;; So, we load "kinsoku.el" in advance if necessary.
    (load "international/kinsoku"))
  (let* ((kinsoku-limit 1)
         (adjustment (+ (or adjustment 0)
                        (if enable-kinsoku
                            kinsoku-limit
                          0)))
         (min-width
          (apply 'min
                 (or
                  (mapcar 'window-width
                          (get-buffer-window-list (current-buffer) nil t))
                  ;; Use `(frame-width)' if no windows display
                  ;; the current buffer.
                  `(,(frame-width)))))
         (temporary-fill-column (- (or twittering-fill-column (1- min-width))
                                   adjustment)))
    (with-temp-buffer
      (let ((fill-column temporary-fill-column)
            (fill-prefix (or prefix fill-prefix))
            (adaptive-fill-regexp ""))
        (if keep-newline
            (let* ((hard-newline (propertize "\n" 'hard t))
                   (str (mapconcat 'identity (split-string str "\n")
                                   (concat hard-newline fill-prefix))))
              (use-hard-newlines)
              (insert (concat prefix str))
              (fill-region (point-min) (point-max) nil t)
              (remove-text-properties (point-min) (point-max) '(hard nil)))
          (insert (concat prefix str))
          (fill-region-as-paragraph (point-min) (point-max)))
        (buffer-substring (point-min) (point-max))))))

(defun twittering-update-filled-string (beg end formater status prefix local-prefix &optional keep-newline)
  (let* ((str (twittering-fill-string (funcall formater status prefix)
                                      (length prefix) local-prefix
                                      keep-newline))
         (next (next-single-property-change 0 'need-to-be-updated str)))
    (if (or (get-text-property 0 'need-to-be-updated str)
            (and next (< next (length str))))
        (put-text-property 0 (length str) 'need-to-be-updated
                           `(twittering-update-filled-string
                             ,formater ,status ,prefix ,local-prefix
                             ,keep-newline)
                           str)
      ;; Remove the property required no longer.
      (remove-text-properties 0 (length str) '(need-to-be-updated nil) str))
    str))

(defun twittering-make-passed-time-string
  (beg end created-at-str time-format &optional additional-properties)
  (let* ((secs (time-to-seconds (time-since created-at-str)))
         (encoded (apply 'encode-time (parse-time-string created-at-str)))
         (time-string
          (cond
           ((string= time-format "%g")
            (if (< emacs-major-version 24)
                (require 'gnus-util)
              (require 'gnus-sum))
            (gnus-user-date created-at-str))

           ((< secs 5) "less than 5 seconds ago")
           ((< secs 10) "less than 10 seconds ago")
           ((< secs 20) "less than 20 seconds ago")
           ((< secs 30) "half a minute ago")
           ((< secs 60) "less than a minute ago")
           ((< secs 150) "1 minute ago")
           ((< secs 2400) (format "%d minutes ago"
                                  (/ (+ secs 30) 60)))
           ((< secs 5400) "about 1 hour ago")
           ((< secs 84600) (format "about %d hours ago"
                                   (/ (+ secs 1800) 3600)))
           (t (format-time-string time-format encoded))))
         (properties (append additional-properties
                             (and beg (text-properties-at beg)))))
    ;; Restore properties.
    (when properties
      (add-text-properties 0 (length time-string) properties time-string))
    (if (and (< secs 84600)
             (if (string= time-format "%g")
                 (= (time-to-day-in-year (current-time))
                    (time-to-day-in-year encoded))
               t))
        (put-text-property 0 (length time-string)
                           'need-to-be-updated
                           `(twittering-make-passed-time-string
                             ,created-at-str ,time-format)
                           time-string)
      ;; Remove the property required no longer.
      (remove-text-properties 0 (length time-string) '(need-to-be-updated nil)
                              time-string))
    time-string))

(defun twittering-render-timeline (buffer &optional additional timeline-data)
  (with-current-buffer buffer
    (save-excursion
      (let* ((spec (twittering-get-timeline-spec-for-buffer buffer))
             (timeline-data (twittering-timeline-data-collect spec timeline-data))
             (rendering-entire (or (null (twittering-get-first-status-head))
                                   (not additional)))
             (buffer-read-only nil))
        (let ((twittering-service-method (caar spec))) ; TODO: necessary?  (xwl)
	  (twittering-update-status-format)
	  (twittering-update-mode-line)
	  (when (and (twittering-timeline-spec-user-p spec) timeline-data)
	    (let ((locate-separator
		   (lambda ()
		     (let ((p (next-single-property-change (point-min) 'user-profile-separator)))
		       (when p (goto-char p))))))
	      (unless (funcall locate-separator)
		(twittering-render-user-profile timeline-data))
	      (funcall locate-separator)
	      (if twittering-reverse-mode
		  (narrow-to-region (point-min) (line-beginning-position))
		(forward-line 1)
		(narrow-to-region (point) (point-max)))))
	  (when rendering-entire
	    (delete-region (point-min) (point-max)))
	  (let* ((prev-p (twittering-timeline-data-is-previous-p timeline-data))
		 (get-insert-point
		  (if prev-p
		      (if twittering-reverse-mode 'point-min 'point-max)
		    (if twittering-reverse-mode 'point-max 'point-min))))
	    (mapc
	     (lambda (status)
	       (let ((formatted-status (twittering-format-status status))
		     (separator "\n"))
		 (add-text-properties 0 (length formatted-status)
				      `(belongs-spec ,spec)
				      formatted-status)
		 (goto-char (funcall get-insert-point))
		 (cond
		  ((eobp)
		   ;; Insert a status after the current position.
		   (insert formatted-status separator))
		  (t
		   ;; Use `insert-before-markers' in order to keep
		   ;; which status is pointed by each marker.
		   (insert-before-markers formatted-status separator)))
		 (when twittering-default-show-replied-tweets
		   (twittering-show-replied-statuses
		    twittering-default-show-replied-tweets))))
	     ;; Always insert most adjacent tweet first.
	     (if prev-p
		 timeline-data		; sorted decreasingly
	       (reverse timeline-data)))) ; sorted increasingly
	  (widen)
	  (debug-print buffer))))))


;; TODO: this is assuming the user has at least one tweet.
(defun twittering-render-user-profile (timeline-data)
  (if twittering-reverse-mode
      (goto-char (point-max))
    (goto-char (point-min)))
  (let ((insert-separator
         (lambda ()
           (let ((s " "))
             (put-text-property 0 (length s) 'user-profile-separator t s)
             (insert s "\n")))))
    (when twittering-reverse-mode
      (funcall insert-separator))

    (let* ((status (or (assqref 'author-status (car timeline-data))
                       (car timeline-data)))
           (user-name                  (assqref 'user-name             status))
           (user-screen-name          (assqref 'user-screen-name      status))
           (user-id                  (assqref 'user-id               status))
           (user-description          (assqref 'user-description      status))
           (user-location          (assqref 'user-location         status))
           (user-url                  (assqref 'user-url              status))
           (user-followers-count  (assqref 'user-followers-count  status))
           (user-friends-count          (assqref 'user-friends-count    status))
           (user-statuses-count          (assqref 'user-statuses-count   status))
           (user-favourites-count (assqref 'user-favourites-count status))
           (user-created-at          (assqref 'user-created-at       status))

           (u (substring-no-properties
               (if (eq (twittering-extract-service) 'sina) user-id user-screen-name)))

           (profile
            (concat
             (format "%s, @%s%s\n"
                     (twittering-make-string-with-user-name-property user-name status)
                     (twittering-make-string-with-user-name-property user-screen-name status)
                     ;; #%s
                     ;; (let ((tmp user-id)
                     ;;            (ret ""))
                     ;;   (while (> (length tmp) 3)
                     ;;          (setq ret (concat (substring tmp -3)
                     ;;                            (if (string= ret "") "" ",")
                     ;;                            ret)
                     ;;                tmp (substring tmp 0 -3)))
                     ;;   ret)
                     (if (string= user-screen-name (twittering-get-accounts 'username))
                         ""
                       (twittering-get-simple nil nil user-screen-name 'show-friendships)))

             ;; bio
             (if (string= user-description "")
                 "\n"
               (concat "\n"
                       (twittering-fill-string
			(if user-description 
			    (twittering-decorate-uri user-description)
			  ""))
                       "\n\n"))

             ;; location, web
             (format "location: %s\n" (or user-location ""))
             (progn
               (when user-url
                 (twittering-decorate-uri user-url))
               (format "     web: %s\n\n" (or user-url "")))

             ;; follow info
             (let ((len-list
                    (mapcar
                     (lambda (lst)
                       (apply 'max (mapcar 'length lst)))
                     (list
                      (list user-friends-count user-statuses-count)
                      (list user-followers-count user-favourites-count)))))

               (format
                (format
                 " %%%ds %%s, %%%ds %%s\n %%%ds tweets,    %%%ds %%s\n"
                 (car len-list) (cadr len-list) (car len-list) (cadr len-list))
                user-friends-count
                (twittering-decorate-listname (concat u "/following") "following")
                user-followers-count
                (twittering-decorate-listname (concat u "/followers") "followers")
                user-statuses-count
                user-favourites-count
                (twittering-decorate-listname (concat u "/favorites") "favorites")))

             ;; lists
             "\n"
             (let* ((prompts
                     (mapcar
                      (lambda (f) (format f user-screen-name))
                      '("%s's Lists: "
                        "Lists %s Follows: "
                        "Lists Following %s: "))))
               (mapconcat
                'identity
                (mapcar*
                 (lambda (prompt method)
                   (format
                    (format "%%%ds%%s"
                            (twittering-calculate-list-info-prefix-width
                             user-screen-name))
                    prompt
                    (if (eq (twittering-extract-service) 'sina) "(not supported yet)"
                      (twittering-get-simple nil nil user-screen-name method))))
                 prompts
                 '(get-list-index get-list-subscriptions get-list-memberships))
                "\n\n"))
             "\n"

             ;; join date
             (format "\nJoined on %s.\n"
                     (mapconcat (lambda (i)
                                  (aref (timezone-parse-date user-created-at) i))
                              '(0 1 2)
                              "-"))))

           ;; Note, twitter provides two sizes of icon:
           ;;   1) 48x48 avatar
           ;;   2) original full sized
           ;; The avatar is named by adding a `_normal' after the original filename, but
           ;; before the file extension, e.g., original filename is `foo.jpg', the avatar will
           ;; be named `foo_normal.jpg'."
           (icon-string
            (if (and twittering-icon-mode window-system)
                (let* ((url (cdr-safe (assq 'user-profile-image-url status)))
                       (orig-url (replace-regexp-in-string "_normal\\." "." url))
                       (s (let ((twittering-convert-fix-size nil))
                            (twittering-make-icon-string nil nil orig-url))))
                  (add-text-properties 0 (length s)
                                       `(mouse-face highlight uri ,orig-url)
                                       s)
                  s)
              "")))

      ;; FIXME: how to align image and multiple lines text side by side?
      (insert icon-string "\n" profile))

    (unless twittering-reverse-mode
      (funcall insert-separator))))

(defun twittering-calculate-list-info-prefix-width (username)
  (apply 'max (mapcar
               (lambda (f) (length (format f username)))
               '("%s's Lists: "
                 "Lists %s Follows: "
                 "Lists Following %s: "))))

(defun twittering-get-and-render-timeline (&optional noninteractive id)
  (let* ((spec (twittering-current-timeline-spec))
	 (spec-string (twittering-current-timeline-spec-string))
	 (twittering-service-method (caar spec)))
    (cond
     ((not (twittering-account-authorized-p))
      ;; ignore any requests if the account has not been authorized.
      (message "No account for Twitter has been authorized.")
      t)
     ((and noninteractive (twittering-process-active-p spec))
      ;; ignore non-interactive request if a process is waiting for responses.
      t)
     ((twittering-timeline-spec-primary-p spec)
      (let* ((is-search-spec (eq 'search (car (cdr spec))))
             (default-number 20)
             (max-number (if is-search-spec
                             100 ;; FIXME: refer to defconst.
                           twittering-max-number-of-tweets-on-retrieval))
             (number twittering-number-of-tweets-on-retrieval)
             (number (cond
                      ((integerp number) number)
                      ((string-match "^[0-9]+$" number)
                       (string-to-number number 10))
                      (t default-number)))
             (number (min (max 1 number) max-number))
             (latest-status
              ;; Assume that a list which was returned by
              ;; `twittering-current-timeline-data' is sorted.
              (car (twittering-current-timeline-data spec)))
             (since_id (cdr-safe (assq 'id latest-status)))
             (cursor (or (cdr-safe (assq id latest-status)) "-1"))
             (word (when is-search-spec (caddr spec)))
             (args
              `((timeline-spec . ,spec)
                (timeline-spec-string . ,spec-string)
                (number . ,number)
                ,@(when (and id (not (twittering-timeline-spec-user-methods-p spec)))
                    `((max_id . ,id)))
                ,@(cond
                   (is-search-spec `((word . ,word)))
                   ((twittering-timeline-spec-user-methods-p spec) `((cursor . ,cursor)))
                   ((and since_id (null id)) `((since_id . ,since_id)))
                   (t nil))
                (clean-up-sentinel
                 . ,(lambda (proc status connection-info)
                      (when (memq status '(exit signal closed failed))
                        (twittering-release-process proc))))))
             (additional-info
              `((noninteractive . ,noninteractive)
                (timeline-spec . ,spec)
                (timeline-spec-string . ,spec-string)))
             (proc
              (twittering-call-api 'retrieve-timeline args additional-info)))
        (when proc
          (twittering-register-process proc spec spec-string))))
     (t
      (let ((type (car spec)))
        (error "%s has not been supported yet" type))))))

;;;;
;;;; Map function for statuses on buffer
;;;;

(defun twittering-for-each-property-region (prop func &optional buffer interrupt)
  "Apply FUNC to each region, where property PROP is non-nil, on BUFFER.
If INTERRUPT is non-nil, the iteration is stopped if FUNC returns nil."
  (with-current-buffer (or buffer (current-buffer))
    (let ((beg (point-min))
          (end-marker (make-marker)))
      (set-marker-insertion-type end-marker t)
      (while
          (let ((value (get-text-property beg prop)))
            (if value
                (let* ((end (next-single-property-change beg prop))
                       (end (or end (point-max)))
                       (end-marker (set-marker end-marker end))
                       (func-result (funcall func beg end value))
                       (end (marker-position end-marker)))
                  (when (or (null interrupt) func-result)
                    (if (get-text-property end prop)
                        (setq beg end)
                      (setq beg (next-single-property-change end prop)))))
              (setq beg (next-single-property-change beg prop)))))
      (set-marker end-marker nil))))

;;;;
;;;; Automatic redisplay of statuses on buffer
;;;;

(defun twittering-redisplay-status-on-buffer ()
  (mapc (lambda (buffer)
          (unless (with-current-buffer buffer
                    (or (and (fboundp 'use-region-p) (use-region-p))
                        (and transient-mark-mode mark-active)))
            (twittering-redisplay-status-on-each-buffer buffer)))
        (twittering-get-buffer-list)))

(defun twittering-redisplay-status-on-each-buffer (buffer)
  (let ((deactivate-mark deactivate-mark)
        (window-list (get-buffer-window-list buffer nil t))
        (marker (with-current-buffer buffer (point-marker)))
        (result nil))
    (with-current-buffer buffer
      (save-excursion
	(twittering-for-each-property-region
	 'need-to-be-updated
	 (lambda (beg end value)
	   ;; `beg' and `end' may be changed unexpectedly when `func' inserts
	   ;; some texts at front, so store marker here.
	   (setq beg (copy-marker beg)
		 end (copy-marker end))

	   (let* ((func (car value))
		  (args (cdr value))
		  (current-str (buffer-substring beg end))
		  (updated-str (apply func beg end args))
		  (config (twittering-current-window-config window-list))
		  (buffer-read-only nil))
	     ;; Replace `current-str' if it differs to `updated-str' with
	     ;; ignoring properties. This is an ad-hoc solution.
	     ;; `current-str' is a part of the displayed status, but it has
	     ;; properties which are determined by the whole status.
	     ;; (For example, the `id' property.)
	     ;; Therefore, we cannot compare the strings with their
	     ;; properties.
	     (unless (string= current-str updated-str)
	       ;; If the region to be modified includes the current position,
	       ;; the point moves to the beginning of the region.
	       (when (and (< beg marker) (< marker end))
		 ;; This is required because the point moves to the center if
		 ;; the point becomes outside of the window by the effect of
		 ;; `set-window-start'.
		 (setq result beg))
	       (let ((common-properties (twittering-get-common-properties beg)))
		 ;; Restore common properties.
		 (delete-region beg end)
		 (goto-char beg)
		 (add-text-properties 0 (length updated-str) common-properties updated-str)
		 (insert updated-str))
	       (twittering-restore-window-config-after-modification
		config beg end))))
	 buffer)

	;; (sina) Display emotions.
	(goto-char (point-min))
	(while (re-search-forward "\\(\\[\\(\\[[^][]+\\]\\)\\]\\)" nil t 1)
	  (unless twittering-is-getting-emotions-p
	    (setq twittering-is-getting-emotions-p t)
	    (let ((twittering-service-method 'sina))
	      (save-match-data
		(twittering-get-simple nil nil nil 'emotions))))

	  (let* ((str (match-string 2))
		 (url (assocref str twittering-emotions-phrase-url-alist))
		 (inhibit-read-only t)
		 (common-properties (twittering-get-common-properties (point)))
		 (repl (if url 
			   (twittering-make-original-icon-string nil nil url)
			 str)))		; Not a emotion, restore. 

	    (when (consp twittering-emotions-phrase-url-alist)
	      (add-text-properties 0 (length repl) common-properties repl)
	      (replace-match repl)))))

      (set-marker marker nil)
      (when (and result (eq (window-buffer) buffer))
        (let ((win (selected-window)))
          (when (< result (window-start win))
            (set-window-start win result))
          (set-window-point win result))))))

;;;;
;;;; Display replied statuses
;;;;

(defun twittering-replied-statuses-visible-p ()
  (let* ((pos (twittering-get-current-status-head))
         (id (twittering-get-id-at pos))
         (prev (twittering-get-previous-status-head pos))
         (next (twittering-get-next-status-head pos)))
    (or
     (twittering-get-base-id-of-ancestor-at pos)
     (and prev
          (twittering-status-id=
           id (twittering-get-base-id-of-ancestor-at prev)))
     (and next
          (twittering-status-id=
           id (twittering-get-base-id-of-ancestor-at next))))))

(defun twittering-show-replied-statuses (&optional count interactive)
  (interactive)
  (if (twittering-replied-statuses-visible-p)
      (when interactive
        (message "The replied statuses were already showed."))
    (let* ((base-id (twittering-get-id-at))
           (statuses (twittering-get-replied-statuses base-id
                                                      (if (numberp count)
                                                          count)))
           (statuses (if twittering-reverse-mode
                         statuses
                       (reverse statuses))))
      (if statuses
          (let ((beg (if twittering-reverse-mode
                         (twittering-get-current-status-head)
                       (or (twittering-get-next-status-head)
                           (point-max))))
                (separator "\n")
                (prefix "  ")
                (buffer-read-only nil))
            (save-excursion
              (goto-char beg)
              (mapc
               (lambda (status)
                 (let ((id (assqref 'id status))
                       (formatted-status (twittering-format-status status
                                                                   prefix))
                       ;; Overwrite field property.
                       (field-properties
                        (twittering-make-field-properties-of-popped-ancestors
                         status base-id)))
                   (add-text-properties 0 (length formatted-status)
                                        field-properties formatted-status)
                   (if twittering-reverse-mode
                       (insert-before-markers formatted-status separator)
                     (insert formatted-status separator))))
               statuses)
              t))
        (when interactive
          (if (twittering-have-replied-statuses-p base-id)
              (if (y-or-n-p "The replied statuses were not fetched yet.  Fetch it now? ")
                  (save-excursion
                    (goto-char (twittering-get-current-status-head))
                    (goto-char (line-end-position))
                    (let ((buffer-read-only nil))
                      (insert
                       (twittering-make-replied-status-string
                        nil nil base-id (assqref 'in-reply-to-status-id
                                                 (twittering-find-status base-id))))))
                (message "The status this replies to has not been fetched yet."))
            (message "This status is not a reply.")))
        nil))))

(defun twittering-make-replied-status-string (beg end id replied-id &optional tries)
  (let ((text "")
        (tries (or tries 1)))
    (cond
     ((twittering-find-status replied-id)
      (save-excursion
        (goto-char beg)
        (twittering-show-replied-statuses)))
     ((< tries twittering-url-request-retry-limit)
      (twittering-call-api 'show `((id . ,replied-id)))
      (setq text (make-string (- twittering-url-request-retry-limit tries) ?.))
      (add-text-properties 0 (length text)
                           `(need-to-be-updated
                             (twittering-make-replied-status-string
                              ,id ,replied-id ,(1+ tries))
                             ;; common properties, See
                             ;; `twittering-generate-format-status-function'.
                             ;; TODO: maybe more to add.
                             id ,id)
                           text)))
    text))

(defun twittering-hide-replied-statuses (&optional interactive)
  (interactive)
  (cond
   ((twittering-replied-statuses-visible-p)
    (let* ((pos (twittering-get-current-status-head (point)))
           (base-id (or (twittering-get-base-id-of-ancestor-at pos)
                        (twittering-get-id-at pos)))
           (pointing-to-base-status
            (not (twittering-rendered-as-ancestor-status-p pos)))
           (beg
            (if (and pointing-to-base-status (not twittering-reverse-mode))
                (twittering-get-next-status-head pos)
              (let ((pos pos))
                (while
                    (let* ((prev (twittering-get-previous-status-head pos))
                           (prev-base-id
                            (when prev
                              (twittering-get-base-id-of-ancestor-at prev))))
                      (and prev
                           (twittering-status-id= base-id prev-base-id)
                           (setq pos prev))))
                (or pos (point-min)))))
           (end
            (if (and pointing-to-base-status twittering-reverse-mode)
                pos
              (let ((pos beg))
                (while
                    (let ((current-base-id
                           (twittering-get-base-id-of-ancestor-at pos)))
                      (and current-base-id
                           (twittering-status-id= base-id current-base-id)
                           (setq pos (twittering-get-next-status-head pos)))))
                (or pos (point-max)))))
           (buffer-read-only nil))
      (unless pointing-to-base-status
        (goto-char (if twittering-reverse-mode
                       beg
                     (or (twittering-get-previous-status-head beg)
                         (point-min)))))
      (delete-region beg end)))
   (interactive
    (message "The status this replies to was already hidden."))))

(defun twittering-toggle-show-replied-statuses ()
  (interactive)
  (if (twittering-replied-statuses-visible-p)
      (twittering-hide-replied-statuses (interactive-p))
    (twittering-show-replied-statuses twittering-show-replied-tweets
                                      (interactive-p))))

;;;;
;;;; Unread statuses info
;;;;

(defvar twittering-unread-status-info nil
  "A list of (buffer unread-statuses-counter), where `unread-statuses-counter'
means the number of statuses retrieved after the last visiting of the buffer.")

(defun twittering-reset-unread-status-info-if-necessary ()
  (when (twittering-buffer-p)
    (twittering-set-number-of-unread (current-buffer) 0)))

(defun twittering-set-number-of-unread (buffer number)
  (let* ((entry (assq buffer twittering-unread-status-info))
         (current (or (cadr entry) 0))
         (spec-string
          (twittering-get-timeline-spec-string-for-buffer buffer)))
    (when (and (zerop number)
               (or (not (= number current))
                   (not (zerop twittering-new-tweets-count)))
               (member spec-string twittering-cache-spec-strings))
      (twittering-cache-save spec-string))
    (unless (= number current)
      (setq twittering-unread-status-info
            (cons
             `(,buffer ,number)
             (if entry
                 (remq entry twittering-unread-status-info)
               twittering-unread-status-info)))
      (force-mode-line-update))))

(defun twittering-make-unread-status-notifier-string ()
  "Generate a string that displays unread statuses."
  (setq twittering-unread-status-info
        (remove nil
                (mapcar (lambda (entry)
                          (when (and (buffer-live-p (car entry))
                                     (not (zerop (cadr entry))))
                            entry))
                        twittering-unread-status-info)))
  (let ((sum (apply '+ (mapcar 'cadr twittering-unread-status-info))))
    (if (zerop sum)
        ""
      (format
       "%s(%s)"
       twittering-logo
       (mapconcat
        'identity
        (let* ((buffers (twittering-get-active-buffer-list))
               (partitioned-buffers
                (mapcar (lambda (sv)
                          (remove-if-not (lambda (b)
                                           (with-current-buffer b
                                             (eq (twittering-extract-service) sv)))
                                         buffers))
                        twittering-enabled-services))
               (partitioned-buffer-prefixes
                (mapcar* (lambda (sv lst)
                           (mapcar (lambda (p)
                                     (concat p "@" sv))
                                   (twittering-build-unique-prefix
                                    (mapcar 'buffer-name lst))))
                         (twittering-build-unique-prefix
                          (mapcar 'symbol-name twittering-enabled-services))
                         partitioned-buffers)))

          (mapcar (lambda (b-u)
                    (some (lambda (b p)
                            (when (eq (car b-u) b)
                              (twittering-decorate-unread-status-notifier
                               b (format "%s:%d" p (cadr b-u)))))
                          (apply 'append partitioned-buffers)
                          (apply 'append partitioned-buffer-prefixes)))
                  twittering-unread-status-info))
        ",")))))

(defun twittering-update-unread-status-info ()
  "Update `twittering-unread-status-info' with new tweets."
  (let* ((spec twittering-new-tweets-spec)
         (buffer (twittering-get-buffer-from-spec spec))
         (current (or (cadr (assq buffer twittering-unread-status-info)) 0))
         (result (+ current twittering-new-tweets-count)))
    (when buffer
      (when (eq buffer (current-buffer))
        (setq result 0))
      (twittering-set-number-of-unread buffer result))))

(defun twittering-enable-unread-status-notifier ()
  "Enable a notifier of unread statuses on `twittering-mode'."
  (interactive)
  (add-hook 'twittering-new-tweets-hook 'twittering-update-unread-status-info)
  (add-hook 'post-command-hook
            'twittering-reset-unread-status-info-if-necessary)
  (add-to-list 'global-mode-string
               '(:eval (twittering-make-unread-status-notifier-string))
               t))

(defun twittering-disable-unread-status-notifier ()
  "Disable a notifier of unread statuses on `twittering-mode'."
  (interactive)
  (setq twittering-unread-status-info nil)
  (remove-hook 'twittering-new-tweets-hook
               'twittering-update-unread-status-info)
  (remove-hook 'post-command-hook
               'twittering-reset-unread-status-info-if-necessary)
  (setq global-mode-string
        (remove '(:eval (twittering-make-unread-status-notifier-string))
                global-mode-string)))

(defun twittering-decorate-unread-status-notifier (buffer notifier)
  (let ((map (make-sparse-keymap)))
    (define-key map (vector 'mode-line 'mouse-2)
      `(lambda (e)
         (interactive "e")
         (save-selected-window
           (select-window (posn-window (event-start e)))
           (switch-to-buffer ,buffer)
           (twittering-set-number-of-unread ,buffer 0))))
    (define-key map (vector 'mode-line 'mouse-3)
      `(lambda (e)
         (interactive "e")
         (save-selected-window
           (select-window (posn-window (event-start e)))
           (switch-to-buffer-other-window ,buffer)
           (twittering-set-number-of-unread ,buffer 0))))
    (add-text-properties
     0 (length notifier)
     `(local-map ,map mouse-face mode-line-highlight help-echo
                 "mouse-2: switch to buffer, mouse-3: switch to buffer in other window")
     notifier)
    notifier))

;;;;
;;;; Timer
;;;;

(defvar twittering-idle-timer-for-redisplay nil)

(defun twittering-is-uploading-file-p (parameters)
  "Check whether there is a pair '(\"image\" . \"@...\") in PARAMETERS."
  (string-match "image=\\`@\\([^;&]+\\)" parameters))

  ;; (some (lambda (pair)
  ;;         (and (string= (car pair) "image")
  ;;              (when (string-match "image=\\`@\\([^;&]+\\)" (cdr pair))
  ;;                       (let ((f (match-string 1 (cdr pair))))
  ;;                         (or (file-exists-p f)
  ;;                             (error "%s doesn't exist" f))))))
  ;;       parameters))

;;;
;;; Statuses on buffer
;;;

(defun twittering-timer-action (func)
  (let ((buf (twittering-get-active-buffer-list)))
    (if (null buf)
        (twittering-stop)
      (funcall func)
      )))

(defun twittering-run-on-idle (idle-interval func &rest args)
  "Run FUNC the next time Emacs is idle for IDLE-INTERVAL.
Even if Emacs has been idle longer than IDLE-INTERVAL, run FUNC immediately.
Since immediate invocation requires `current-idle-time', it is available
on Emacs 22 and later.
FUNC is called as (apply FUNC ARGS)."
  (let ((sufficiently-idling
         (and (fboundp 'current-idle-time)
              (current-idle-time)
              (time-less-p (seconds-to-time idle-interval)
                           (current-idle-time)))))
    (if (not sufficiently-idling)
        (apply 'run-with-idle-timer idle-interval nil func args)
      (apply func args)
      nil)))

(defun twittering-run-repeatedly-on-idle (check-interval var idle-interval func &rest args)
  "Run FUNC every time Emacs is idle for IDLE-INTERVAL.
Even if Emacs remains idle longer than IDLE-INTERVAL, run FUNC every
CHECK-INTERVAL seconds. Since this behavior requires `current-idle-time',
invocation on long idle time is available on Emacs 22 and later.
VAR is a symbol of a variable to which the idle-timer is bound.
FUNC is called as (apply FUNC ARGS)."
  (apply 'run-at-time "0 sec"
         check-interval
         (lambda (var idle-interval func &rest args)
           (let ((registerd (symbol-value var))
                 (sufficiently-idling
                  (and (fboundp 'current-idle-time)
                       (current-idle-time)
                       (time-less-p (seconds-to-time idle-interval)
                                    (current-idle-time)))))
             (when (or (not registerd) sufficiently-idling)
               (when (and registerd sufficiently-idling)
                 (cancel-timer (symbol-value var))
                 (apply func args))
               (set var (apply 'run-with-idle-timer idle-interval nil
                               (lambda (var func &rest args)
                                 (set var nil)
                                 (apply func args))
                               var func args)))))
         var idle-interval func args))

(defun twittering-start (&optional action)
  (interactive)
  (if (null action)
      (setq action #'twittering-update-active-buffers))
  (unless twittering-timer
    (setq twittering-timer
          (run-at-time "0 sec"
                       twittering-timer-interval
                       #'twittering-timer-action action)))
  (unless twittering-timer-for-redisplaying
    (setq twittering-timer-for-redisplaying
          (twittering-run-repeatedly-on-idle
           (* 2 twittering-timer-interval-for-redisplaying)
           'twittering-idle-timer-for-redisplay
           twittering-timer-interval-for-redisplaying
           #'twittering-redisplay-status-on-buffer))))

(defun twittering-stop ()
  (interactive)
  (when twittering-timer
    (cancel-timer twittering-timer)
    (setq twittering-timer nil))
  (when twittering-timer-for-redisplaying
    (when twittering-idle-timer-for-redisplay
      (cancel-timer twittering-idle-timer-for-redisplay)
      (setq twittering-idle-timer-for-redisplay))
    (cancel-timer twittering-timer-for-redisplaying)
    (setq twittering-timer-for-redisplaying nil)))

(defun twittering-update-active-buffers (&optional noninteractive)
  "Invoke `twittering-get-and-render-timeline' for each active buffer
managed by `twittering-mode'."
  (mapc
   (lambda (buffer)
     (with-current-buffer buffer
       (let ((spec (twittering-get-timeline-spec-for-buffer buffer)))
	 (when (or (twittering-timeline-spec-most-active-p spec)
		   ;; first run
		   (not (member (twittering-timeline-spec-to-string spec)
				twittering-timeline-history))
		   ;; hourly TODO: make it customizable? (xwl)
		   (let ((min-and-sec
			  (+ (* (string-to-number
				 (format-time-string "%M" (current-time))) 60)
			     (string-to-number
			      (format-time-string "%S" (current-time))))))
		     (<= min-and-sec twittering-timer-interval)))
           (when (twittering-account-authorized-p)
             (twittering-get-and-render-timeline t))))))
   (twittering-get-active-buffer-list)))

;;;;
;;;; Keymap
;;;;

(if twittering-mode-map
    (let ((km twittering-mode-map))
      (define-key km (kbd "C-c C-f") 'twittering-friends-timeline)
      (define-key km (kbd "C-c C-r") 'twittering-replies-timeline)
      (define-key km (kbd "C-c C-u") 'twittering-user-timeline)
      (define-key km (kbd "C-c C-d") 'twittering-direct-messages-timeline)
      (define-key km (kbd "C-c C-s") 'twittering-update-status-interactive)
      (define-key km (kbd "C-c C-e") 'twittering-erase-old-statuses)
      (define-key km (kbd "C-c C-w") 'twittering-erase-all)
      (define-key km (kbd "C-c C-m") 'twittering-retweet)
      (define-key km (kbd "C-c C-t") 'twittering-set-current-hashtag)
      (define-key km (kbd "C-m") 'twittering-enter)
      (define-key km (kbd "C-c C-l") 'twittering-update-lambda)
      (define-key km (kbd "<mouse-1>") 'twittering-click)
      (define-key km (kbd "C-<down-mouse-3>") 'mouse-set-point)
      (define-key km (kbd "C-<mouse-3>") 'twittering-push-tweet-onto-kill-ring)
      (define-key km (kbd "C-c C-v") 'twittering-view-user-page)
      (define-key km (kbd "C-c D") 'twittering-delete-status)
      (define-key km (kbd "a") 'twittering-toggle-activate-buffer)
      (define-key km (kbd "g") 'twittering-current-timeline)
      (define-key km (kbd "u") 'twittering-update-status-interactive)
      (define-key km (kbd "U") 'twittering-push-uri-onto-kill-ring)
      (define-key km (kbd "d") 'twittering-direct-message)
      (define-key km (kbd "v") 'twittering-other-user-timeline)
      (define-key km (kbd "V") 'twittering-visit-timeline)
      (define-key km (kbd "L") 'twittering-other-user-list-interactive)
      (define-key km (kbd "f") 'twittering-switch-to-next-timeline)
      (define-key km (kbd "b") 'twittering-switch-to-previous-timeline)
      ;; (define-key km (kbd "j") 'next-line)
      ;; (define-key km (kbd "k") 'previous-line)
      (define-key km (kbd "j") 'twittering-goto-next-status)
      (define-key km (kbd "k") 'twittering-goto-previous-status)
      (define-key km (kbd "l") 'forward-char)
      (define-key km (kbd "h") 'backward-char)
      (define-key km (kbd "0") 'beginning-of-line)
      (define-key km (kbd "^") 'beginning-of-line-text)
      (define-key km (kbd "$") 'end-of-line)
      (define-key km (kbd "n") 'twittering-goto-next-status-of-user)
      (define-key km (kbd "p") 'twittering-goto-previous-status-of-user)
      (define-key km (kbd "C-i") 'twittering-goto-next-thing)
      (define-key km (kbd "M-C-i") 'twittering-goto-previous-thing)
      (define-key km (kbd "<backtab>") 'twittering-goto-previous-thing)
      (define-key km (kbd "<backspace>") 'twittering-scroll-down)
      (define-key km (kbd "M-v") 'twittering-scroll-down)
      (define-key km (kbd "SPC") 'twittering-scroll-up)
      (define-key km (kbd "C-v") 'twittering-scroll-up)
      (define-key km (kbd "G") 'end-of-buffer)
      (define-key km (kbd "H") 'twittering-goto-first-status)
      (define-key km (kbd "i") 'twittering-icon-mode)
      (define-key km (kbd "r") 'twittering-toggle-show-replied-statuses)
      (define-key km (kbd "s") 'twittering-scroll-mode)
      (define-key km (kbd "t") 'twittering-toggle-proxy)
      (define-key km (kbd "C-c C-p") 'twittering-toggle-proxy)
      (define-key km (kbd "q") 'twittering-kill-buffer)
      (define-key km (kbd "C-c C-q") 'twittering-search)
      nil))

(let ((km twittering-mode-menu-on-uri-map))
  (when km
    (define-key km [ct] '("Copy tweet" . twittering-push-tweet-onto-kill-ring))
    (define-key km [cl] '("Copy link" . twittering-push-uri-onto-kill-ring))
    (define-key km [ll] '("Load link" . twittering-click))
    (let ((km-on-uri twittering-mode-on-uri-map))
      (when km-on-uri
        (define-key km-on-uri (kbd "C-<down-mouse-3>") 'mouse-set-point)
        (define-key km-on-uri (kbd "C-<mouse-3>") km)))))

(defun twittering-keybind-message ()
  (let ((important-commands
         '(("Timeline" . twittering-friends-timeline)
           ("Replies" . twittering-replies-timeline)
           ("Update status" . twittering-update-status-interactive)
           ("Next" . twittering-goto-next-status)
           ("Prev" . twittering-goto-previous-status))))
    (mapconcat (lambda (command-spec)
                 (let ((descr (car command-spec))
                       (command (cdr command-spec)))
                   (format "%s: %s" descr (key-description
                                           (where-is-internal
                                            command
                                            overriding-local-map t)))))
               important-commands ", ")))

;; (run-with-idle-timer
;;  0.1 t
;;  '(lambda ()
;;     (when (equal (buffer-name (current-buffer)) twittering-buffer)
;;       (message (twittering-keybind-message)))))


;;;;
;;;; Initialization
;;;;

(defvar twittering-mode-hook nil
  "Twittering-mode hook.")

(defvar twittering-initialized nil)
(defvar twittering-mode-syntax-table nil "")

(unless twittering-mode-syntax-table
  (setq twittering-mode-syntax-table (make-syntax-table))
  ;; (modify-syntax-entry ?  "" twittering-mode-syntax-table)
  (modify-syntax-entry ?\" "w" twittering-mode-syntax-table)
  )

(defun twittering-initialize-global-variables-if-necessary ()
  "Initialize global variables for `twittering-mode' if they have not
been initialized yet."
  (unless twittering-initialized
    (defface twittering-username-face
      `((t ,(append '(:underline t)
                    (face-attr-construct
                     (if (facep 'font-lock-string-face)
                         'font-lock-string-face
                       'bold)))))
      "" :group 'faces)
    (defface twittering-uri-face `((t (:underline t))) "" :group 'faces)
    (twittering-update-status-format)
    (when twittering-use-convert
      (if (null twittering-convert-program)
          (setq twittering-use-convert nil)
        (with-temp-buffer
          (call-process twittering-convert-program nil (current-buffer) nil
                        "-version")
          (goto-char (point-min))
          (if (null (search-forward-regexp "\\(Image\\|Graphics\\)Magick"
                                           nil t))
              (setq twittering-use-convert nil)))))
    (twittering-setup-proxy)
    (when twittering-use-icon-storage
      (cond
       ((require 'jka-compr nil t)
        (twittering-load-icon-properties)
        (add-hook 'kill-emacs-hook 'twittering-save-icon-properties))
       (t
        (setq twittering-use-icon-storage nil)
        (error "Disabled icon-storage because it failed to load jka-compr."))))
    (setq twittering-initialized t)))

(defun twittering-mode-setup (spec-string)
  "Set up the current buffer for `twittering-mode'."
  (kill-all-local-variables)
  (setq major-mode 'twittering-mode)
  (setq buffer-read-only t)
  (buffer-disable-undo)
  (setq mode-name "twittering")
  (setq mode-line-buffer-identification
        `(,(default-value 'mode-line-buffer-identification)
          (:eval (twittering-mode-line-buffer-identification))))

  ;; Prevent `global-font-lock-mode' enabling `font-lock-mode'.
  ;; This technique is derived from `lisp/bs.el' distributed with Emacs 22.2.
  (make-local-variable 'font-lock-global-modes)
  (setq font-lock-global-modes '(not twittering-mode))

  (make-local-variable 'twittering-service-method)
  (make-local-variable 'twittering-timeline-spec)
  (make-local-variable 'twittering-timeline-spec-string)
  (make-local-variable 'twittering-active-mode)
  (make-local-variable 'twittering-icon-mode)
  (make-local-variable 'twittering-jojo-mode)
  (make-local-variable 'twittering-reverse-mode)
  (make-local-variable 'twittering-scroll-mode)

  (setq twittering-service-method (twittering-extract-service spec-string))
  (setq twittering-timeline-spec-string spec-string)
  (setq twittering-timeline-spec
        (twittering-string-to-timeline-spec spec-string))
  (setq twittering-active-mode t)
  (use-local-map twittering-mode-map)
  (twittering-update-mode-line)
  (set-syntax-table twittering-mode-syntax-table)
  (when (and (boundp 'font-lock-mode) font-lock-mode)
    (font-lock-mode -1))
  (add-to-list 'twittering-buffer-info-list (current-buffer) t)
  (run-hooks 'twittering-mode-hook))

(defun twittering-mode ()
  "Major mode for Twitter.
\\{twittering-mode-map}"
  (interactive)
  (twittering-cache-load)
  (mapc 'twittering-visit-timeline
        (if (listp twittering-initial-timeline-spec-string)
            twittering-initial-timeline-spec-string
          (list twittering-initial-timeline-spec-string))))

;;;;
;;;; Sign
;;;;

(defvar twittering-sign-simple-string nil)
(defvar twittering-sign-string-function 'twittering-sign-string-default-function)

(defun twittering-sign-string-default-function ()
  "Append sign string to tweet."
  (if twittering-sign-simple-string
      (format " [%s]" twittering-sign-simple-string)
    ""))

(defun twittering-sign-string ()
  "Return Tweet sign string."
  (funcall twittering-sign-string-function))

;;;;
;;;; Edit mode
;;;;

(defvar twittering-edit-buffer "*twittering-edit*")
(defvar twittering-pre-edit-window-configuration nil)
(defvar twittering-edit-history nil)
(defvar twittering-edit-local-history nil)
(defvar twittering-edit-local-history-idx nil)
(defvar twittering-help-overlay nil)
(defvar twittering-warning-overlay nil)

(define-derived-mode twittering-edit-mode text-mode "twmode-status-edit"
  (use-local-map twittering-edit-mode-map)

  (make-local-variable 'twittering-help-overlay)
  (setq twittering-help-overlay nil)
  (make-local-variable 'twittering-warning-overlay)
  (setq twittering-warning-overlay (make-overlay 1 1 nil nil nil))
  (overlay-put twittering-warning-overlay 'face 'font-lock-warning-face)

  (make-local-variable 'twittering-edit-local-history)
  (setq twittering-edit-local-history (cons (buffer-string)
                                            twittering-edit-history))
  (make-local-variable 'twittering-edit-local-history-idx)
  (setq twittering-edit-local-history-idx 0)

  (make-local-variable 'after-change-functions)
  (add-to-list 'after-change-functions 'twittering-edit-length-check)

  (make-local-variable 'twittering-service-method))

(when twittering-edit-mode-map
  (let ((km twittering-edit-mode-map))
    (define-key km (kbd "C-c C-c") 'twittering-edit-post-status)
    (define-key km (kbd "C-c C-k") 'twittering-edit-cancel-status)
    (define-key km (kbd "M-n") 'twittering-edit-next-history)
    (define-key km (kbd "M-p") 'twittering-edit-previous-history)
    (define-key km (kbd "<f4>") 'twittering-edit-replace-at-point)))

(defun twittering-edit-length-check (&optional beg end len)
  (let* ((status (twittering-edit-extract-status))
         (sign-str (twittering-sign-string))
         (maxlen (- 140 (length sign-str)))
         (length (length status)))
    (setq mode-name
          (format "twmode-status-edit[%d/%d/140]" length maxlen))
    (force-mode-line-update)
    (if (< maxlen length)
        (move-overlay twittering-warning-overlay (1+ maxlen) (1+ length))
      (move-overlay twittering-warning-overlay 1 1))))

(defun twittering-edit-extract-status ()
  (if (eq major-mode 'twittering-edit-mode)
      (buffer-substring-no-properties (point-min) (point-max))
    ""))

(defun twittering-edit-setup-help (&optional username spec)
  (let* ((item (if (twittering-timeline-spec-direct-messages-p spec)
                   (format "a direct message to %s" username)
                 "a tweet"))
         (help-str (format (substitute-command-keys "Keymap:
  \\[twittering-edit-post-status]: send %s
  \\[twittering-edit-cancel-status]: cancel %s
  \\[twittering-edit-next-history]: next history element
  \\[twittering-edit-previous-history]: previous history element
  \\[twittering-edit-replace-at-point]: shorten URL at point

---- text above this line is ignored ----
") item item))
         (help-overlay
          (or twittering-help-overlay
              (make-overlay 1 1 nil nil nil))))
    (add-text-properties 0 (length help-str) '(face font-lock-comment-face)
                         help-str)
    (overlay-put help-overlay 'before-string help-str)
    (setq twittering-help-overlay help-overlay)))

(defun twittering-edit-close ()
  (kill-buffer (current-buffer))
  (when twittering-pre-edit-window-configuration
    (set-window-configuration twittering-pre-edit-window-configuration)
    (setq twittering-pre-edit-window-configuration nil)))

(defvar twittering-reply-recipient nil)

(defun twittering-update-status-from-pop-up-buffer (&optional init-str reply-to-id username spec retweeting?)
  (interactive)
  (let ((buf (get-buffer twittering-edit-buffer))
        (twittering-service-method (twittering-extract-service spec)))
    (if buf
        (pop-to-buffer buf)
      (setq buf (twittering-get-or-generate-buffer twittering-edit-buffer))
      (setq twittering-pre-edit-window-configuration
            (current-window-configuration))
      ;; This is required because the new window generated by `pop-to-buffer'
      ;; may hide the region following the current position.
      (let ((win (selected-window)))
        (pop-to-buffer buf)
        (twittering-ensure-whole-of-status-is-visible win))
      (twittering-edit-mode)
      (unless (twittering-timeline-spec-direct-messages-p spec)
	(and (null init-str)
	     twittering-current-hashtag
	     (setq init-str (format " #%s " twittering-current-hashtag))))
      (message "%s to %S: C-c C-c to send, C-c C-k to cancel"
	       (if retweeting? "Retweet" "Post")
	       (twittering-extract-service spec))
      (when init-str
	(insert init-str)
	(set-buffer-modified-p nil))
      (make-local-variable 'twittering-reply-recipient)
      (setq twittering-reply-recipient `(,reply-to-id ,username ,spec ,retweeting?)))))

(defun twittering-ensure-whole-of-status-is-visible (&optional window)
  "Ensure that the whole of the tweet on the current point is visible."
  (interactive)
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (save-excursion
        (let* ((next-head (or (twittering-get-next-status-head) (point-max)))
               (current-tail (max (1- next-head) (point-min))))
          (when (< (window-end window t) current-tail)
            (twittering-set-window-end window current-tail)))))))

(defun twittering-edit-post-status ()
  (interactive)
  (let ((status (replace-regexp-in-string
                 "\n" "" (replace-regexp-in-string
                          "\\([[:ascii:]]\\) ?\n"
                          "\\1 \n"
                          (twittering-edit-extract-status))))
        (reply-to-id (nth 0 twittering-reply-recipient))
        (username (nth 1 twittering-reply-recipient))
        (spec (or (nth 2 twittering-reply-recipient)
                  `((,(twittering-extract-service)))))
        (retweeting? (nth 3 twittering-reply-recipient))
	(twittering-service-method twittering-service-method))
    (cond
     ((not (twittering-status-not-blank-p status))
      (message "Empty tweet!"))
     (t
      (when (< 140 (length status))
        (unless (y-or-n-p "Too long tweet!  Truncate trailing? ")
          (error "Abort"))
        (setq status (concat (substring status 0 138) "..")))

      (when (or (not twittering-request-confirmation-on-posting)
                (y-or-n-p "Send this tweet? "))
        (setq twittering-edit-history
              (cons status twittering-edit-history))
        (mapc
         (lambda (service)
           (let ((twittering-service-method service))
             (cond
              ((twittering-timeline-spec-direct-messages-p spec)
               (if username
                   (twittering-call-api 'send-direct-message
                                        `((username . ,username)
                                          (status . ,status)))
                 (message "No username specified")))
              (t
               (twittering-call-api
                'update-status
                `((status . ,status)
                  ,@(when reply-to-id
                      `((in-reply-to-status-id
                         . ,(format "%s" reply-to-id))))
                  (retweeting? . ,retweeting?)))))))
         (if (equal spec '((all))) twittering-enabled-services (car spec)))
        (twittering-edit-close))))))

(defun twittering-edit-cancel-status ()
  (interactive)
  (when (or (not (buffer-modified-p))
            (prog1 (if (y-or-n-p "Cancel this tweet? ")
                       (message "Request canceled")
                     (message nil))))
    (twittering-edit-close)))

(defun twittering-edit-next-history ()
  (interactive)
  (if (>= 0 twittering-edit-local-history-idx)
      (message "End of history.")
    (let ((current-history (nthcdr twittering-edit-local-history-idx
                                   twittering-edit-local-history)))
      (setcar current-history (buffer-string))
      (decf twittering-edit-local-history-idx)
      (erase-buffer)
      (insert (nth twittering-edit-local-history-idx
                   twittering-edit-local-history))
      ;; (twittering-edit-setup-help)
      (goto-char (point-min)))))

(defun twittering-edit-previous-history ()
  (interactive)
  (if (>= twittering-edit-local-history-idx
          (- (length twittering-edit-local-history) 1))
      (message "Beginning of history.")
    (let ((current-history (nthcdr twittering-edit-local-history-idx
                                   twittering-edit-local-history)))
      (setcar current-history (buffer-string))
      (incf twittering-edit-local-history-idx)
      (erase-buffer)
      (insert (nth twittering-edit-local-history-idx
                   twittering-edit-local-history))
      ;; (twittering-edit-setup-help)
      (goto-char (point-min))))
  )

(defun twittering-edit-replace-at-point ()
  (interactive)
  (when (eq major-mode 'twittering-edit-mode)
    (twittering-tinyurl-replace-at-point)
    (twittering-edit-length-check)))

;;;;
;;;; Edit a status on minibuffer
;;;;

(defun twittering-show-minibuffer-length (&optional beg end len)
  "Show the number of characters in minibuffer."
  (when (minibuffer-window-active-p (selected-window))
    (if (and transient-mark-mode deactivate-mark)
        (deactivate-mark))
    (let* ((deactivate-mark deactivate-mark)
           (status-len (- (buffer-size) (minibuffer-prompt-width)))
           (sign-len (length (twittering-sign-string)))
           (mes (if (< 0 sign-len)
                    (format "%d=%d+%d"
                            (+ status-len sign-len) status-len sign-len)
                  (format "%d" status-len))))
      (if (<= 23 emacs-major-version)
          (minibuffer-message mes) ;; Emacs23 or later
        (minibuffer-message (concat " (" mes ")")))
      )))

(defun twittering-setup-minibuffer ()
  (add-hook 'post-command-hook 'twittering-show-minibuffer-length t t))

(defun twittering-finish-minibuffer ()
  (remove-hook 'post-command-hook 'twittering-show-minibuffer-length t))

(defun twittering-status-not-blank-p (status)
  (with-temp-buffer
    (insert status)
    (goto-char (point-min))
    ;; skip user name
    (re-search-forward "\\`[[:space:]]*@[a-zA-Z0-9_-]+\\([[:space:]]+@[a-zA-Z0-9_-]+\\)*" nil t)
    (re-search-forward "[^[:space:]]" nil t)))

(defun twittering-update-status-from-minibuffer (&optional init-str reply-to-id username spec)
  (and (not (twittering-timeline-spec-direct-messages-p spec))
       (null init-str)
       twittering-current-hashtag
       (setq init-str (format " #%s " twittering-current-hashtag)))
  (let ((status init-str)
        (sign-str (if (twittering-timeline-spec-direct-messages-p spec)
                      nil
                    (twittering-sign-string)))
        (not-posted-p t)
        (prompt "status: ")
        (map minibuffer-local-map)
        (minibuffer-message-timeout nil))
    (define-key map (kbd "<f4>") 'twittering-tinyurl-replace-at-point)
    (when twittering-use-show-minibuffer-length
      (add-hook 'minibuffer-setup-hook 'twittering-setup-minibuffer t)
      (add-hook 'minibuffer-exit-hook 'twittering-finish-minibuffer t))
    (unwind-protect
        (while not-posted-p
          (setq status (read-from-minibuffer prompt status map nil 'twittering-tweet-history nil t))
          (let ((status-with-sign (concat status sign-str)))
            (if (< 140 (length status-with-sign))
                (setq prompt "status (too long): ")
              (setq prompt "status: ")
              (when (twittering-status-not-blank-p status)
                (cond
                 ((twittering-timeline-spec-direct-messages-p spec)
                  (if username
                      (twittering-call-api 'send-direct-message
                                           `((username . ,username)
                                             (status . ,status)))
                    (message "No username specified")))
                 (t
                  (let ((parameters `(("status" . ,status-with-sign)))
                        (as-reply
                         (and reply-to-id
                              username
                              (string-match
                               (concat "\\`@" username "\\(?:[\n\r \t]+\\)*")
                               status))))
                    ;; Add in_reply_to_status_id only when a posting
                    ;; status begins with @username.
                    (twittering-call-api
                     'update-status
                     `((status . ,status-with-sign)
                       ,@(when as-reply
                           `((in-reply-to-status-id
                              . ,(format "%s" reply-to-id))))))
                    )))
                (setq not-posted-p nil))
              )))
      ;; unwindforms
      (when (memq 'twittering-setup-minibuffer minibuffer-setup-hook)
        (remove-hook 'minibuffer-setup-hook 'twittering-setup-minibuffer))
      (when (memq 'twittering-finish-minibuffer minibuffer-exit-hook)
        (remove-hook 'minibuffer-exit-hook 'twittering-finish-minibuffer))
      )))

;;;
;;; Cache
;;;

(defcustom twittering-cache-file "~/.twittering_cache"
  "Filename for caching latest statu for `twittering-cache-spec-strings'."
  :type 'string
  :group 'twittering)

(defcustom twittering-cache-spec-strings '()
  "Spec string list whose latest status will be cached."
  :type 'list
  :group 'twittering)

;; '((spec latest-status-id)...)
(defvar twittering-cache-lastest-statuses '())
(defvar twittering-cache-saved-lastest-statuses '())

(defun twittering-cache-save (&optional spec-string)
  "Dump twittering-cache-lastest-statuses.
When SPEC-STRING is non-nil, just save lastest status for SPEC-STRING. "
  (if spec-string
      (setq twittering-cache-saved-lastest-statuses
            (cons (assoc spec-string twittering-cache-lastest-statuses)
                  (remove-if (lambda (entry) (equal spec-string (car entry)))
                             twittering-cache-saved-lastest-statuses)))
    (setq twittering-cache-saved-lastest-statuses
          twittering-cache-lastest-statuses))
  (with-temp-buffer
    (insert (format "\
;; automatically generated by twittering-mode -*- emacs-lisp -*-

%S
" twittering-cache-saved-lastest-statuses))
    (write-region (point-min) (point-max) twittering-cache-file nil 'silent)
    (kill-buffer)))

(defun twittering-cache-load ()
  (when (file-exists-p twittering-cache-file)
    (setq twittering-cache-lastest-statuses
          (with-temp-buffer
            (insert-file-contents twittering-cache-file)
            (read (current-buffer))))
    (setq twittering-cache-saved-lastest-statuses
          twittering-cache-lastest-statuses)))

;;;
;;; API methods
;;;

(defvar twittering-simple-hash (make-hash-table :test 'equal)
  "Hash table for storing results retrieved by `twittering-get-simple'.
The key is a list of username/id and method(such as get-list-index), the value is
string.")

(defun twittering-get-simple (beg end username method)
  (let ((retrieved (gethash (list username method) twittering-simple-hash))
        (s "."))                        ; hold 'need-to-be-updated
    (cond
     (retrieved
      (remove-text-properties 0 (length s) '(need-to-be-updated nil) s)
      (setq s
            (case method
              ((show-friendships)
               (concat (or (when (assqref 'following retrieved) " <") " ")
                       "--"
                       (or (when (assqref 'followed-by retrieved) ">") "")
                       " you"))

              ((get-list-index get-list-subscriptions get-list-memberships)
               (mapconcat (lambda (l) (concat "@" (twittering-decorate-listname l)))
                          (split-string retrieved)
                          (concat "\n" (make-string
                                        (twittering-calculate-list-info-prefix-width
                                         username)
                                        ? ))))

              ((counts)
               (let ((cm (car (assqref 'comments retrieved)))
                     (rt (car (assqref 'rt retrieved))))
                 (if (and (string= cm "0") (string= rt "0"))
                     ""
                   (concat "["
                           (mapconcat (lambda (s-id)
                                        (let ((s (car s-id)))
                                          (put-text-property 0 (length s) (cdr s-id) username s)
                                          s))
                                      `((,(concat "cm " cm) . comment-base-id)
                                        (,(concat "rt " cm) . retweet-base-id))
                                      ", ")
                           "]"))))
              (t
               retrieved)))
      ;; (when (eq method 'counts)
      ;;         (put-text-property 0 (length s)
      ;;                            'need-to-be-updated
      ;;                            `(twittering-get-simple ,username ,method)
      ;;                            s)
      ;;         (twittering-get-simple-1 method `((username . ,username))))
      )

     (t
      (put-text-property 0 (length s)
                         'need-to-be-updated
                         `(twittering-get-simple ,username ,method)
                         s)
      (twittering-get-simple-1 method `((username . ,username)))))
    s))

(defun twittering-get-simple-sync (method args-alist)
  (message "Getting %S..." method)
  (setq twittering-get-simple-retrieved nil)
  (let ((proc (twittering-get-simple-1 method args-alist)))
    (when proc
      (let ((start (current-time)))
        (while (and (not twittering-get-simple-retrieved)
                    (not (memq (process-status proc)
                               '(exit signal closed failed nil)))
                    ;; Wait just for 3 seconds. FIXME: why it would fail sometimes?
                    (< (cadr (time-subtract (current-time) start)) 30)
                    )
          (sit-for 0.1)))))
  (if (not twittering-get-simple-retrieved)
      (progn
        (setq twittering-get-simple-retrieved 'error)
        (message "twittering-get-simple-sync failed"))
    (case method
      ((get-list-index get-list-subscriptions get-list-memberships)
       (cond
        ((stringp twittering-get-simple-retrieved)
         (if (string= "" twittering-get-simple-retrieved)
             (message
              "%s does not have a %s."
              (assqref 'username args-alist)
              (assqref method
                       '((get-list-index         . "list")
                         (get-list-subscriptions . "list subscription")
                         (get-list-memberships   . "list membership"))))
           (message "%s" twittering-get-simple-retrieved))
         nil)
        ((listp twittering-get-simple-retrieved)
         twittering-get-simple-retrieved)))
      ((show-friendships)
       twittering-get-simple-retrieved)
      ((emotions)
       (setq twittering-emotions-phrase-url-alist
             twittering-get-simple-retrieved))
      (t
       twittering-get-simple-retrieved))))

(defun twittering-get-simple-1 (method args-alist)
  (twittering-call-api
   method
   `(,@args-alist
     (sentinel . (lambda (&rest args)
                   (apply 'twittering-http-get-simple-sentinel
                          (append args '(((method . ,method)
                                          ,@args-alist)))))))))

(defun twittering-followed-by-p (username)
  (twittering-get-simple-sync 'show-friendships `((username . ,username)))
  (and (stringp twittering-get-simple-retrieved)
       (string= twittering-get-simple-retrieved "true")))

;;;;
;;;; Reading username/listname with completion
;;;;

(defun twittering-get-usernames-from-timeline (&optional timeline-data)
  (let ((timeline-data (or timeline-data (twittering-current-timeline-data))))
    (twittering-remove-duplicates
     (mapcar
      (lambda (status)
        (let* ((base-str (assqref 'user-screen-name status))
               ;; `copied-str' is independent of the string in timeline-data.
               ;; This isolation is required for `minibuf-isearch.el',
               ;; which removes the text properties of strings in history.
               (copied-str (copy-sequence base-str)))
          ;; (set-text-properties 0 (length copied-str) nil copied-str)
          copied-str))
      timeline-data))))

(defun twittering-read-username-with-completion (prompt init-user &optional history)
  (let ((collection (append (twittering-get-all-usernames-at-pos)
                            twittering-user-history
                            (twittering-get-usernames-from-timeline))))
    (twittering-completing-read prompt collection nil nil init-user history)))

(defun twittering-read-list-name (username &optional list-index)
  (let* ((list-index (or list-index
                         (twittering-get-simple-sync
                          'get-list-index `((username . ,username)))))
         (username (prog1 (copy-sequence username)
                     (set-text-properties 0 (length username) nil username)))
         (prompt (format "%s's list: " username))
         (listname
          (if list-index
              (twittering-completing-read
               prompt
               (mapcar
                (lambda (l) (caddr (twittering-string-to-timeline-spec l)))
                list-index)
               nil
               t)
            nil)))
    (if (string= "" listname)
        nil
      listname)))

(defun twittering-read-timeline-spec-with-completion (prompt initial &optional as-string)
  "Return a timeline-spec string with 'goto-spec property."
  (let* ((dummy-hist
          (remove
           nil
           (append
            (twittering-get-all-usernames-at-pos)
            twittering-timeline-history
            (twittering-get-usernames-from-timeline)
            '(":direct_messages" ":direct_messages_sent" ":friends"
              ":home" ":mentions" ":public" ":replies"
              ":retweeted_by_me" ":retweeted_to_me" ":retweets_of_me")
            (mapcar (lambda (tl) (concat (twittering-get-accounts 'username) "/" tl))
                    '("followers" "following" "favorites"))
            )))
         (spec-string (twittering-completing-read
                       prompt dummy-hist nil nil initial 'dummy-hist))
         (spec-string
          (cond
           ((string-match "^:favorites/$" spec-string)
            (let ((username
                   (twittering-read-username-with-completion
                    "Whose favorites: " ""
                    (twittering-get-usernames-from-timeline))))
              (if username
                  (concat ":favorites/" username)
                nil)))
           ((string-match "^\\([a-zA-Z0-9_-]+\\)/$" spec-string)
            (let* ((username (match-string 1 spec-string))
                    (list-index (twittering-get-simple-sync
                                 'get-list-index `((username . ,username))))
                    (listname
                     (if list-index
                         (twittering-read-list-name username list-index)
                       nil)))
              (if listname
                   (concat username "/" listname)
                 nil)))
           (t
            spec-string)))

         (spec (if (stringp spec-string)
                   (condition-case error-str
                       (or (get-text-property 0 'goto-spec spec-string)
                           (twittering-string-to-timeline-spec spec-string))
                     (error
                      (message "Invalid timeline spec: %s" error-str)
                      nil))
                 nil)))
    (cond
     ((null spec) nil)
     (spec (if as-string
             ;;   (if (string-match "@.+" spec-string)
             ;;            spec-string
             ;;   (format "%s@%S" spec-string twittering-service-method))
             ;; `((,twittering-service-method) ,@spec)))
               spec-string spec))
     ((string= "" spec-string) (message "No timeline specs are specified.") nil)
     (t (message "\"%s\" is invalid as a timeline spec." spec-string) nil))))

;;;
;;; Commands
;;;

;;;; Commands for changing modes
(defun twittering-scroll-mode (&optional arg)
  (interactive "P")
  (let ((prev-mode twittering-scroll-mode))
    (setq twittering-scroll-mode
          (if (null arg)
              (not twittering-scroll-mode)
            (< 0 (prefix-numeric-value arg))))
    (unless (eq prev-mode twittering-scroll-mode)
      (twittering-update-mode-line))))

(defun twittering-jojo-mode (&optional arg)
  (interactive "P")
  (let ((prev-mode twittering-jojo-mode))
    (setq twittering-jojo-mode
          (if (null arg)
              (not twittering-jojo-mode)
            (< 0 (prefix-numeric-value arg))))
    (unless (eq prev-mode twittering-jojo-mode)
      (twittering-update-mode-line))))

(defun twittering-jojo-mode-p (spec)
  (let ((buffer (twittering-get-buffer-from-spec spec)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        twittering-jojo-mode))))

(defun twittering-toggle-reverse-mode (&optional arg)
  (interactive "P")
  (let ((prev-mode twittering-reverse-mode))
    (setq twittering-reverse-mode
          (if (null arg)
              (not twittering-reverse-mode)
            (< 0 (prefix-numeric-value arg))))
    (unless (eq prev-mode twittering-reverse-mode)
      (twittering-update-mode-line)
      (twittering-render-timeline (current-buffer)))))

(defun twittering-set-current-hashtag (&optional tag)
  (interactive)
  (unless tag
    (setq tag (twittering-completing-read "hashtag (blank to clear): #"
                                          twittering-hashtag-history
                                          nil nil
                                          twittering-current-hashtag
                                          'twittering-hashtag-history))
    (message
     (if (eq 0 (length tag))
         (progn (setq twittering-current-hashtag nil)
                "Current hashtag is not set.")
       (progn
         (setq twittering-current-hashtag tag)
         (format "Current hashtag is #%s" twittering-current-hashtag))))))

;;;; Commands for switching buffers
(defun twittering-switch-to-next-timeline ()
  (interactive)
  (when (twittering-buffer-p)
    (let* ((buffer-list (twittering-get-buffer-list))
           (following-buffers (cdr (memq (current-buffer) buffer-list)))
           (next (if following-buffers
                     (car following-buffers)
                   (car buffer-list))))
      (unless (eq (current-buffer) next)
        (switch-to-buffer next)))))

(defun twittering-switch-to-previous-timeline ()
  (interactive)
  (when (twittering-buffer-p)
    (let* ((buffer-list (reverse (twittering-get-buffer-list)))
           (preceding-buffers (cdr (memq (current-buffer) buffer-list)))
           (previous (if preceding-buffers
                         (car preceding-buffers)
                       (car buffer-list))))
      (unless (eq (current-buffer) previous)
        (switch-to-buffer previous)))))

;;;; Commands for visiting a timeline
(defun twittering-visit-timeline (&optional spec initial)
  (interactive)
  (unless spec 
    (setq spec (twittering-read-timeline-spec-with-completion
		"timeline: " initial t)))

  (let ((twittering-service-method (twittering-extract-service spec)))
    (cond
     ((stringp spec)
      (unless (string-match "@" spec)
	(setq spec (format "%s@%S" spec twittering-service-method))))
     ((consp spec)
      (unless (consp (car spec))
	(setq spec `((,twittering-service-method) ,@spec)))))

    (cond
     ((twittering-ensure-connection-method)
      (twittering-initialize-global-variables-if-necessary)
      (switch-to-buffer (twittering-get-managed-buffer spec)))
     (t
      (message "No connection methods are available.")
      nil))))

(defun twittering-friends-timeline ()
  (interactive)
  (twittering-visit-timeline '(friends)))

(defun twittering-home-timeline ()
  (interactive)
  (twittering-visit-timeline '(home)))

(defun twittering-replies-timeline ()
  (interactive)
  (twittering-visit-timeline '(replies)))

(defun twittering-public-timeline ()
  (interactive)
  (twittering-visit-timeline '(public)))

(defun twittering-user-timeline ()
  (interactive)
  (twittering-visit-timeline `(user ,(twittering-get-accounts 'username))))

(defun twittering-direct-messages-timeline ()
  (interactive)
  (twittering-visit-timeline '(direct_messages)))

(defun twittering-sent-direct-messages-timeline ()
  (interactive)
  (twittering-visit-timeline '(direct_messages_sent)))

(defun twittering-other-user-timeline ()
  (interactive)
  (let* ((username (get-text-property (point) 'username))
	 (goto-spec (get-text-property (point) 'goto-spec))
	 (screen-name-in-text
	  (get-text-property (point) 'screen-name-in-text))
	 (spec ;; Sequence is important.
	  (cond (goto-spec
                 goto-spec)	 ; FIXME: better get name for "retweeted by XXX"
                (screen-name-in-text
                 `((,(twittering-extract-service)) user ,screen-name-in-text))
                (username
                 `((,(twittering-extract-service)) user ,username)))))
    (if spec
	(twittering-visit-timeline spec)
      (message "No user selected"))))

(defun twittering-other-user-timeline-interactive ()
  (interactive)
  (let ((username (or (twittering-read-username-with-completion
                       "user: " nil
                       'twittering-user-history)
                      "")))
    (if (string= "" username)
        (message "No user selected")
      (twittering-visit-timeline `(user ,username)))))

(defun twittering-other-user-list-interactive ()
  (interactive)
  (let* ((username (copy-sequence (get-text-property (point) 'username)))
         (username (progn
                     (set-text-properties 0 (length username) nil username)
                     (or (twittering-read-username-with-completion
                          "Whose list: "
                          username
                          'twittering-user-history)
                         ""))))
    (if (string= "" username)
        (message "No user selected")
      (let* ((list-name (twittering-read-list-name username))
             (spec `(list ,username ,list-name)))
        (if list-name
            (twittering-visit-timeline spec)
          ;; Don't show message here to prevent an overwrite of a
          ;; message which is outputted by `twittering-read-list-name'.
          )))))

(defun twittering-search (&optional word)
  (interactive)
  (let ((word (or word
                  (read-from-minibuffer "search: " nil nil nil
                                        'twittering-search-history nil t)
                  "")))
    (if (string= "" word)
        (message "No query string")
      (let ((spec `(search ,word)))
        (twittering-visit-timeline spec)))))

;;;; Commands for retrieving statuses

(defun twittering-current-timeline-noninteractive ()
  (twittering-current-timeline t))

(defun twittering-current-timeline (&optional noninteractive)
  (interactive)
  (when (twittering-buffer-p)
    (twittering-get-and-render-timeline noninteractive)))

;;;; Commands for posting a status

(defun twittering-update-status-interactive (&optional ask)
  "Non-nil ASK will ask user to select a service from `twittering-enabled-services'. "
  (interactive "P")
  (let ((spec (twittering-current-timeline-spec)))
    (when (or ask (null spec))
      (setq spec
	    `((,(intern
		 (ido-completing-read
		  "Post to: "
		  `(,@(mapcar 'symbol-name twittering-enabled-services) "all")))))))
    
    (funcall twittering-update-status-function
             nil nil nil spec)))

(defun twittering-update-lambda ()
  (interactive)
  (when (and (string= "Japanese" current-language-environment)
             (or (< 21 emacs-major-version)
                 (eq 'utf-8 (terminal-coding-system))))
    (let ((text (mapconcat
                 'char-to-string
                 (mapcar 'twittering-ucs-to-char
                         '(955 12363 12431 12356 12356 12424 955)) "")))
      (twittering-call-api 'update-status `((status . ,text))))))

(defun twittering-update-jojo (usr msg)
  (when (and (not (string= usr (twittering-get-accounts 'username)))
             (string= "Japanese" current-language-environment)
             (or (< 21 emacs-major-version)
                 (eq 'utf-8 (terminal-coding-system))))
    (if (string-match
         (mapconcat
          'char-to-string
          (mapcar 'twittering-ucs-to-char
                  '(27425 12395 92 40 12362 21069 92 124 36020 27096
                          92 41 12399 12300 92 40 91 94 12301 93 43 92
                          41 12301 12392 35328 12358)) "")
         msg)
        (let ((text (concat "@" usr " "
                            (match-string-no-properties 2 msg)
                            (mapconcat
                             'char-to-string
                             (mapcar 'twittering-ucs-to-char
                                     '(12288 12399 12387 33 63)) ""))))
          (twittering-call-api 'update-status `((status . ,text)))))))

(defun twittering-direct-message (&optional ask)
  (interactive "P")
  (let ((username (or (and (not ask)
                           (get-text-property (point) 'username))
                      (twittering-read-username-with-completion
                       "Who would you like to receive the DM? "
                       (get-text-property (point) 'username)
                       'twittering-user-history)))
        (spec (or (get-text-property (point) 'source-spec)
                  `((,(twittering-extract-service)) direct_messages))))
    (if (string= "" username)
        (message "No user selected")
      (funcall twittering-update-status-function
               (concat "d " username " ") nil username spec))))

(defun twittering-reply-to-user (&optional quote)
  "Non-nil QUOTE will quote status using `twittering-generate-organic-retweet'."
  (interactive "P")
  (let* ((username (get-text-property (point) 'username))
         (id (get-text-property (point) 'id))
         (spec (get-text-property (point) 'belongs-spec))
         (status (twittering-find-status id))
         (reply-to-source nil)
         (init-str (if quote
                       (twittering-generate-organic-retweet)
                     (concat "@" username " "))))

    (when (eq (twittering-extract-service) 'sina)
      (when (assqref 'retweeted-status status)
        (setq username
              (ido-completing-read "Reply to: "
                                   `(,(assqref 'retweeting-user-name status)
                                     ,(assqref 'user-name status))))
        (when (string= username (assqref 'user-name status))
          (setq reply-to-source t
                id (assqref 'id (assqref 'retweeted-status status)))))

      (setq init-str (concat " // @" username))
      (unless reply-to-source
        ;; (sina) Quote by default.
        (let ((s (substring-no-properties
                  (assqref 'text (or (assqref 'author-status status) status)))))
          (setq init-str (concat init-str " " s))))
      (setq init-str ""))

    (if username
        (progn
          (funcall twittering-update-status-function init-str id username spec)
          (when (or quote (eq (twittering-extract-service spec) 'sina))
            (goto-char (line-beginning-position))))
      (message "No user selected"))))

(defun twittering-erase-all ()
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer)))

;;;; Commands for deleting a status

(defun twittering-delete-status (&optional id)
  (interactive)
  (let* ((id (get-text-property (point) 'id))
         (username (get-text-property (point) 'username))
         (text (copy-sequence (get-text-property (point) 'text)))
         (text (progn
                 (set-text-properties 0 (length text) nil text)
                 text))
         (width (max 40 ;; XXX
                     (- (frame-width)
                        1 ;; margin for wide characters
                        11 ;; == (length (concat "Delete \"" "\"? "))
                        9) ;; == (length "(y or n) ")
                     ))
         (mes (format "Delete \"%s\"? "
                      (if (< width (string-width text))
                          (concat
                           (truncate-string-to-width text (- width 3))
                           "...")
                        text))))
    (cond
     ((not (string= username (twittering-get-accounts 'username)))
      (message "The status is not yours!"))
     ((not id)
      (message "No status selected"))
     ((y-or-n-p mes)
      (twittering-call-api 'destroy-status `((id . ,id)))
      (twittering-delete-status-from-data-table id))
     (t
      (message "Request canceled")))))

;;;; Commands for retweet

;; TODO: cross-retweeting not working (xwl)
(defun twittering-retweet (&optional ask)
  (interactive "P")
  (let ((service (twittering-extract-service)))
    (when ask
      (setq service
            (intern
             (ido-completing-read
              "Post to: "
              `(,@(mapcar 'symbol-name twittering-enabled-services) "all")))))
    (mapc (lambda (s)
            (let* ((twittering-service-method s)
                   (style (twittering-get-accounts 'retweet)))
              (case style
                ((native)
                 (twittering-native-retweet))
                ((organic)
                 (twittering-organic-retweet))
                (t
                 (if twittering-use-native-retweet
                     (twittering-native-retweet)
                   (twittering-organic-retweet))))))
          (if (eq service 'all) twittering-enabled-services (list service)))))

(defun twittering-organic-retweet ()
  (interactive)
  (twittering-ensure-retweeting-allowed)
  (funcall twittering-update-status-function
           (twittering-generate-organic-retweet)
           (get-text-property (point) 'id)
           nil
           nil
           t)
  (goto-char (line-beginning-position)))

(defun twittering-native-retweet ()
  (interactive)
  (twittering-ensure-retweeting-allowed)
  (let ((id (or (get-text-property (point) 'retweeted-id)
                (get-text-property (point) 'id)))
        (text (copy-sequence (get-text-property (point) 'text)))
        (user (get-text-property (point) 'username))
        (width (max 40 ;; XXX
                    (- (frame-width)
                       1 ;; margin for wide characters
                       12 ;; == (length (concat "Retweet \"" "\"? "))
                       9) ;; == (length "(y or n) ")
                    )))
    (set-text-properties 0 (length text) nil text)
    (if id
        (if (not (string= user (twittering-get-accounts 'username)))
            (let ((mes (format "Retweet \"%s\"? "
                               (if (< width (string-width text))
                                   (concat
                                    (truncate-string-to-width text (- width 3))
                                    "...")
                                 text))))
              (if (y-or-n-p mes)
                  (twittering-call-api 'retweet `((id . ,id)))
                (message "Request canceled")))
          (message "Cannot retweet your own tweet"))
      (message "No status selected"))))

(defun twittering-generate-organic-retweet ()
  (let* ((username (get-text-property (point) 'username))
         (text (get-text-property (point) 'text))
         (id (get-text-property (point) 'id))
         (status (twittering-find-status id))
         (retweet-time (current-time))
         (format-str (or twittering-retweet-format "RT: %t (via @%s)")))
    (when username
      (if (eq (twittering-extract-service) 'sina)
          ;; use sina's format.
          (when (assqref 'author-status status)
            (format " // @%s:%s"
                    (assqref 'user-screen-name (assqref 'author-status status))
                    (assqref 'text (assqref 'author-status status))))
        (let ((prefix "%")
              (replace-table
               `(("%" . "%")
                 ("s" . ,username)
                 ("t" . ,text)
                 ("#" . ,id)
                 ("C{\\([^}]*\\)}" .
                  (lambda (context)
                    (let ((str (assqref 'following-string context))
                          (match-data (assqref 'match-data context)))
                      (store-match-data match-data)
                      (format-time-string (match-string 1 str) ',retweet-time)))))))
          (twittering-format-string format-str prefix replace-table))))))

(defun twittering-ensure-retweeting-allowed ()
  (let* ((id (twittering-get-id-at))
         (status (twittering-find-status (twittering-get-id-at))))
    (when (equal "true" (assocref 'user-protected status))
      (error "Cannot retweet protected tweets."))))

;;;; Commands for browsing information related to a status

(defun twittering-click ()
  (interactive)
  (let ((uri (get-text-property (point) 'uri)))
    (if uri
        (browse-url uri))))

(defun twittering-enter ()
  (interactive)
  (let ((username (get-text-property (point) 'username))
        (id (twittering-get-id-at (point)))
        (uri (get-text-property (point) 'uri))
        (spec (get-text-property (point) 'source-spec))
        (screen-name-in-text
         (get-text-property (point) 'screen-name-in-text)))
    (cond (screen-name-in-text
           (funcall twittering-update-status-function
                    (if (twittering-timeline-spec-direct-messages-p spec)
                        nil
                      (concat "@" screen-name-in-text " "))
                    id screen-name-in-text spec))
          (uri
           (browse-url uri))
          (username
           (funcall twittering-update-status-function
                    (if (twittering-timeline-spec-direct-messages-p spec)
                        nil
                      (concat "@" username " "))
                    id username spec)))))

(defun twittering-view-user-page ()
  (interactive)
  (let ((uri (get-text-property (point) 'uri)))
    (if uri
        (browse-url uri))))

;;;;
;;;; Commands corresponding to operations on Twitter
;;;;

(defun twittering-follow (&optional remove)
  "Follow a user or a list.

Non-nil optional REMOVE will do the opposite, unfollow. "
  (interactive "P")
  (let ((user-or-list (twittering-read-username-with-completion
                       "who: " "" 'twittering-user-history))
        prompt-format method args)
    (when (string= "" user-or-list)
      (error "No user or list selected"))
    ;; (set-text-properties 0 (length user-or-list) nil user-or-list)
    (if (string-match "/" user-or-list)
        (let ((spec (twittering-string-to-timeline-spec user-or-list)))
          (setq prompt-format (if remove "Unfollowing list `%s'? "
                                "Following list `%s'? ")
                method  (if remove 'unsubscribe-list 'subscribe-list)
                args `((timeline-spec . ,spec))))
      (setq prompt-format (if remove "Unfollowing `%s'? " "Following `%s'? ")
            method (if remove 'destroy-friendships 'create-friendships)
            args `((username . ,user-or-list))))
    (if (y-or-n-p (format prompt-format user-or-list))
        (twittering-call-api method args)
      (message "Request canceled"))))

(defun twittering-unfollow ()
  "Unfollow a user or a list."
  (interactive)
  (twittering-follow t))

(defun twittering-add-list-members (&optional remove)
  "Add a user to a list.

Non-nil optional REMOVE will do the opposite, remove a user from
a list. "
  (interactive "P")
  (let* ((username (twittering-read-username-with-completion
                    (if remove "Remove who from list: " "Add who to list: ")
                    "" 'twittering-user-history))
         (listname
          (unless (string= username "")
            (or (let ((s (twittering-current-timeline-spec-string)))
                  (when (and s
                             (twittering-timeline-spec-list-p
                              (twittering-current-timeline-spec))
                             (y-or-n-p (format "from list: `%s'? " s)))
                    s))
                (twittering-read-list-name (twittering-get-accounts 'username))
                (read-string
                 "Failed to retrieve your list, enter list name manually or retry: ")))))
    (when (or (string= username "") (string= listname ""))
      (error "No user or list selected"))
    (unless (string-match "/" listname)
      (setq listname (concat (twittering-get-accounts 'username) "/" listname)))
    (if (y-or-n-p (format (if remove "Remove `%s' from `%s'? " "Add `%s' to `%s'? ")
                          username listname))
        (twittering-call-api
         (if remove 'delete-list-members 'add-list-members)
         `((id . ,username)
           (timeline-spec . ,(twittering-string-to-timeline-spec listname))))
      (message "Request canceled"))))

(defun twittering-delete-list-members ()
  "Delete a user from a list. "
  (interactive)
  (twittering-add-list-members t))

(defun twittering-native-retweet ()
  (interactive)
  (let ((id (or (get-text-property (point) 'retweeted-id)
                (get-text-property (point) 'id)))
        (text (copy-sequence (get-text-property (point) 'text)))
        (user (get-text-property (point) 'username))
        (width (max 40 ;; XXX
                    (- (frame-width)
                       1 ;; margin for wide characters
                       12 ;; == (length (concat "Retweet \"" "\"? "))
                       9) ;; == (length "(y or n) ")
                    )))
    (set-text-properties 0 (length text) nil text)
    (if id
        (if (not (string= user (twittering-get-accounts 'username)))
            (let ((mes (format "Retweet \"%s\"? "
                               (if (< width (string-width text))
                                   (concat
                                    (truncate-string-to-width text (- width 3))
                                    "...")
                                 text))))
              (if (y-or-n-p mes)
                  (twittering-call-api 'retweet `((id . ,id)))
                (message "Request canceled")))
          (message "Cannot retweet your own tweet"))
      (message "No status selected"))))

(defun twittering-favorite (&optional remove)
  (interactive "P")
  (let ((id (get-text-property (point) 'id))
        (text (copy-sequence (get-text-property (point) 'text)))
        (width (max 40 ;; XXX
                    (- (frame-width)
                       1 ;; margin for wide characters
                       15 ;; == (length (concat "Unfavorite \"" "\"? "))
                       9) ;; == (length "(y or n) ")
                    ))
        (method (if remove 'destroy-favorites 'create-favorites)))
    (set-text-properties 0 (length text) nil text)
    (if id
        (let ((mes (format "%s \"%s\"? "
                           (if remove "Unfavorite" "Favorite")
                           (if (< width (string-width text))
                               (concat
                                (truncate-string-to-width text (- width 3))
                                "...")
                             text))))
          (if (y-or-n-p mes)
              (twittering-call-api method `((id . ,id)))
            (message "Request canceled")))
      (message "No status selected"))))

(defun twittering-unfavorite ()
  (interactive)
  (twittering-favorite t))

(defun twittering-update-profile-image (image)
  "Update a new profile image.

Note: the new image might not appear in your timeline immediately (this seems
some limitation of twitter API?), but you can see your new image from web
browser right away."
  (interactive "fUpdate profile image: ")
  (twittering-call-api 'update-profile-image `((image . ,image))))

(defun twittering-block ()
  "Block a user who posted the tweet at the current position."
  (interactive)
  (let* ((id (twittering-get-id-at))
         (status (when id (twittering-find-status id)))
         (username
          (cond
           ((assq 'retweeted-id status)
            (let* ((retweeting-username
                    (cdr (assq 'retweeting-user-screen-name status)))
                   (retweeted-username
                    (cdr (assq 'retweeted-user-screen-name status)))
                   (prompt "Who do you block? ")
                   (candidates (list retweeted-username retweeting-username)))
              (twittering-completing-read prompt candidates nil t)))
           (status
            (cdr (assq 'user-screen-name status)))
           (t
            nil))))
    (cond
     ((or (null username) (string= "" username))
      (message "No user selected"))
     ((yes-or-no-p (format "Really block \"%s\"? " username))
      (twittering-call-api 'block `((username . ,username))))
     (t
      (message "Request canceled")))))

(defun twittering-block-and-report-as-spammer ()
  "Report a user who posted the tweet at the current position as a spammer.
The user is also blocked."
  (interactive)
  (let* ((id (twittering-get-id-at))
         (status (when id (twittering-find-status id)))
         (username
          (cond
           ((assq 'retweeted-id status)
            (let* ((retweeting-username
                    (cdr (assq 'retweeting-user-screen-name status)))
                   (retweeted-username
                    (cdr (assq 'retweeted-user-screen-name status)))
                   (prompt "Who do you report as a spammer? ")
                   (candidates (list retweeted-username retweeting-username)))
              (twittering-completing-read prompt candidates nil t)))
           (status
            (cdr (assq 'user-screen-name status)))
           (t
            nil))))
    (cond
     ((or (null username) (string= "" username))
      (message "No user selected"))
     ((yes-or-no-p
       (format "Really block \"%s\" and report him or her as a spammer? "
               username))
      (twittering-call-api 'block-and-report-as-spammer
                           `((username . ,username))))
     (t
      (message "Request canceled")))))

;;;; Commands for clearing stored statuses.

(defun twittering-erase-old-statuses ()
  (interactive)
  (when (twittering-buffer-p)
    (let ((spec (twittering-current-timeline-spec)))
      (twittering-remove-timeline-data spec) ;; clear current timeline.
      (twittering-render-timeline (current-buffer)) ;; clear buffer.
      (twittering-get-and-render-timeline))))

;;;; Cursor motion

(defun twittering-get-id-at (&optional pos)
  "Return ID of the status at POS. If a separator is rendered at POS, return
the ID of the status rendered before the separator. The default value of POS
is `(point)'."
  (let ((pos (or pos (point))))
    (or (get-text-property pos 'id)
        (let ((prev (or (twittering-get-previous-status-head pos)
                        (point-min))))
          (and prev (get-text-property prev 'id))))))

(defun twittering-get-current-status-head (&optional pos)
  "Return the head position of the status at POS.
If POS is nil, the value of point is used for POS.
If a separator is rendered at POS, return the head of the status followed
by the separator.
Return POS if no statuses are rendered."
  (let* ((pos (or pos (point)))
         (field-id (get-text-property pos 'field))
         (head (field-beginning pos)))
    (cond
     ((null field-id)
      ;; A separator is rendered at `pos'.
      (if (get-text-property head 'field)
          ;; When `pos' points the head of the separator, `head' points
          ;; to the beginning of the status followed by the separator.
          head
        ;; In the case that `pos' points to a character of the separator,
        ;; but not to the head of the separator.
        (field-beginning head)))
     ((null (get-text-property head 'field))
      ;; When `head' points to a separator, `pos' points to the head
      ;; of a status.
      pos)
     (t
      head))))

(defun twittering-goto-first-status ()
  "Go to the first status."
  (interactive)
  (goto-char (or (twittering-get-first-status-head)
                 (point-min))))

(defun twittering-get-first-status-head ()
  "Return the head position of the first status in the current buffer.
Return nil if no statuses are rendered."
  (if (get-text-property (point-min) 'field)
      (point-min)
    (twittering-get-next-status-head (point-min))))

(defun twittering-goto-next-status ()
  "Go to next status."
  (interactive)
  (let ((pos (twittering-get-next-status-head)))
    (cond
     (pos
      (goto-char pos)
      (forward-char))
     (twittering-reverse-mode
      (message "The latest status."))
     (t
      (let ((id
             (cond
              ((twittering-timeline-spec-user-methods-p
                (twittering-current-timeline-spec))
               'previous-cursor)
              (t
               (or (get-text-property (point) 'id)
                   (let ((prev (twittering-get-previous-status-head)))
                     (when prev
                       (get-text-property prev 'id))))))))
        (when id
          (message "Get more previous timeline...")
          (twittering-get-and-render-timeline nil id)))))))

(defun twittering-get-next-status-head (&optional pos)
  "Search forward from POS for the nearest head of a status.
Return nil if there are no following statuses.
Otherwise, return a positive integer greater than POS."
  (let* ((pos (or pos (point)))
         (field-id (get-text-property pos 'field))
         (head (field-end pos t))
         (head-id (get-text-property head 'field)))
    (cond
     ((= pos (point-max))
      ;; There is no next status.
      nil)
     ((and (null field-id) head-id)
      ;; `pos' points to a separator and `head' points to a head
      ;; of a status.
      head)
     ((null head-id)
      ;; `head' points to a head of a separator.
      (let ((next-head (field-end head t)))
        (if (get-text-property next-head 'field)
            next-head
          ;; There is no next status.
          nil)))
     (t
      head))))

(defun twittering-goto-previous-status ()
  "Go to previous status."
  (interactive)
  (let ((prev-pos
         (twittering-get-previous-status-head (line-beginning-position))))
    (cond
     (prev-pos
      (goto-char prev-pos)
      (forward-char))
     (twittering-reverse-mode
      (let ((id
             (cond
              ((twittering-timeline-spec-user-methods-p
                (twittering-current-timeline-spec))
               'next-cursor)
              (t
               (or (get-text-property (point) 'id)
                   (let ((next (twittering-get-next-status-head)))
                     (when next
                       (get-text-property next 'id))))))))
        (when id
          (message "Get more previous timeline...")
          (twittering-get-and-render-timeline nil id))))
     (t
      (message "The latest status.")))))

(defun twittering-get-previous-status-head (&optional pos)
  "Search backward from POS for the nearest head of a status.
If POS points to a head of a status, return the head of the *previous* status.
If there are no preceding statuses, return nil.
Otherwise, return a positive integer less than POS."
  (let* ((pos (or pos (point)))
         (field-id (get-text-property pos 'field))
         (head (field-beginning pos t))
         (head-id (get-text-property head 'field)))
    (cond
     ((= pos (point-min))
      ;; There is no previous status.
      nil)
     ((and (null field-id) head-id)
      ;; `pos' points to a separator and `head' points to a head
      ;; of a status.
      head)
     ((null head-id)
      ;; `head' points to a head of a separator.
      (let ((prev-head (field-beginning head t)))
        (if (get-text-property prev-head 'field)
            prev-head
          ;; There is no previous status.
          nil)))
     (t
      head))))

(defun twittering-goto-next-status-of-user ()
  "Go to next status of user."
  (interactive)
  (let ((user-name (twittering-get-username-at-pos (point)))
        (pos (twittering-get-next-status-head (point))))
    (while (and (not (eq pos nil))
                (not (equal (twittering-get-username-at-pos pos) user-name)))
      (setq pos (twittering-get-next-status-head pos)))
    (if pos
        (progn
          (goto-char pos)
          (forward-char))
      (if user-name
          (message "End of %s's status." user-name)
        (message "Invalid user-name.")))))

(defun twittering-goto-previous-status-of-user ()
  "Go to previous status of user."
  (interactive)
  (let ((user-name (twittering-get-username-at-pos (point)))
        (prev-pos (point))
        (pos (twittering-get-previous-status-head
              (line-beginning-position))))
    (while (and (not (eq pos nil))
                (not (eq pos prev-pos))
                (not (equal (twittering-get-username-at-pos pos) user-name)))
      (setq prev-pos pos)
      (setq pos (twittering-get-previous-status-head pos)))
    (if (and pos
             (not (eq pos prev-pos))
             (equal (twittering-get-username-at-pos pos) user-name))
        (progn
          (goto-char pos)
          (forward-char))
      (if user-name
          (message "Start of %s's status." user-name)
        (message "Invalid user-name.")))))

(defun twittering-goto-next-thing (&optional backward)
  "Go to next interesting thing. ex) username, URI, ... "
  (interactive)
  (let* ((property-change-f (if backward
                               'previous-single-property-change
                             'next-single-property-change))
         (pos (funcall property-change-f (point) 'face)))
    (while (and pos
                (not
                 (let* ((current-face (get-text-property pos 'face))
                        (face-pred
                         (lambda (face)
                           (cond
                            ((listp current-face) (memq face current-face))
                            ((symbolp current-face) (eq face current-face))
                            (t nil)))))
                   (remove nil (mapcar face-pred '(twittering-username-face
                                                   twittering-uri-face))))))
      (setq pos (funcall property-change-f pos 'face)))
    (when pos
      (goto-char pos))))

(defun twittering-goto-previous-thing (&optional backward)
  "Go to previous interesting thing. ex) username, URI, ... "
  (interactive)
  (twittering-goto-next-thing (not backward)))

(defun twittering-get-username-at-pos (pos)
  (or (get-text-property pos 'username)
      (get-text-property (max (point-min) (1- pos)) 'username)
      (let* ((border (or (previous-single-property-change pos 'username)
                         (point-min)))
             (pos (max (point-min) (1- border))))
        (get-text-property pos 'username))))

(defun twittering-get-all-usernames-at-pos (&optional point)
  "Get all usernames contained in tweet at POINT.
If there is an username under POINT, make it as `car', else make
tweet author as the `car'.

See also `twittering-get-username-at-pos'. "
  (unless point (setq point (point)))
  (let ((start (twittering-get-current-status-head point))
        (end (or (twittering-get-next-status-head point) (point-max)))
        n names
        (top2
         (remove nil
                 (list (get-text-property (point) 'screen-name-in-text)
                       (twittering-get-username-at-pos point)))))
    (when (setq n (get-text-property start 'screen-name-in-text))
      (setq names (cons n names)))
    (while (and (setq start (next-single-property-change
                             start 'screen-name-in-text))
                (< start end))
      (when (setq n (get-text-property start 'screen-name-in-text))
        (setq names (cons n names))))
    (setq names (remove-duplicates names :test 'string=))
    (when top2
      (setq names (append top2 (delete-if (lambda (s) (member s top2))
                                          names))))
    ; (mapcar 'substring-no-properties names)
    names))

(defun twittering-scroll-up()
  "Scroll up if possible; otherwise invoke `twittering-goto-next-status',
which fetch older tweets on non reverse-mode."
  (interactive)
  (cond
   ((= (point) (point-max))
    (twittering-goto-next-status))
   ((= (window-end) (point-max))
    (goto-char (point-max)))
   (t
    (scroll-up))))

(defun twittering-scroll-down()
  "Scroll down if possible; otherwise invoke `twittering-goto-previous-status',
which fetch older tweets on reverse-mode."
  (interactive)
  (cond
   ((= (point) (point-min))
    (twittering-goto-previous-status))
   ((= (window-start) (point-min))
    (goto-char (point-min)))
   (t
    (scroll-down))))

;;;; Kill ring

(defun twittering-push-uri-onto-kill-ring ()
  "Push URI on the current position onto the kill ring.
If the character on the current position does not have `uri' property,
this function does nothing."
  (interactive)
  (let ((uri (get-text-property (point) 'uri)))
    (cond
     ((not (stringp uri))
      nil)
     ((and kill-ring (string= uri (current-kill 0 t)))
      (message "Already copied %s" uri)
      uri)
     (t
      (kill-new uri)
      (message "Copied %s" uri)
      uri))))

(defun twittering-push-tweet-onto-kill-ring ()
  "Copy the tweet (format: \"username: text\") to the kill-ring."
  (interactive)
  (let* ((username (get-text-property (point) 'username))
         (text (get-text-property (point) 'text))
         (copy (if (and username text)
                   (format "%s: %s" username text)
                 nil)))
    (cond
     ((null copy)
      nil)
     ((and kill-ring (string= copy (current-kill 0 t)))
      (message "Already copied %s" copy))
     (t
      (kill-new copy)
      (message "Copied %s" copy)
      copy))))

;;;; Suspend

(defun twittering-suspend ()
  "Suspend twittering-mode then switch to another buffer."
  (interactive)
  (switch-to-buffer (other-buffer)))

;;;; Other Commands

(defun twittering-refresh ()
  "Refresh current buffer.

This will invoke `twittering-redisplay-status-on-each-buffer' immediately on
current buffer."
  (interactive)
  (twittering-redisplay-status-on-each-buffer (current-buffer)))

;;;###autoload
(defun twit ()
  "Start twittering-mode."
  (interactive)
  (twittering-mode))

(provide 'twittering-mode)

;;; twittering.el ends here
