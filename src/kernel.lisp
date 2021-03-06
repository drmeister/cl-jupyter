(in-package #:cl-jupyter)

(defclass kernel ()
  ((config :initarg :config :reader kernel-config)
   (ctx :initarg :ctx :reader kernel-ctx)
   (shell :initarg :shell :initform nil :reader kernel-shell)
   (control :initarg :control :initform nil :reader kernel-control)
   (iopub :initarg :iopub :initform nil :reader kernel-iopub)
   (session :initarg :session :reader kernel-session)
   (evaluator :initarg :evaluator :initform nil :reader kernel-evaluator))
  (:documentation "Kernel state representation."))

(defun make-kernel (config)
  (let ((ctx (pzmq:ctx-new))
	(session-id (format nil "~W" (uuid:make-v4-uuid))))
    (make-instance 'kernel
                   :config config
                   :ctx ctx
		   :session session-id)))

(defun get-argv ()
  ;; Borrowed from apply-argv, command-line-arguments.  Temporary solution (?)
  #+sbcl (cdr sb-ext:*posix-argv*)
  #+clozure CCL:*UNPROCESSED-COMMAND-LINE-ARGUMENTS*  ;(ccl::command-line-arguments)
  #+gcl si:*command-args*
  #+(or ecl clasp) (loop for i from 0 below (si:argc) collect (si:argv i))
  #+cmu extensions:*command-line-strings*
  #+allegro (sys:command-line-arguments)
  #+lispworks sys:*line-arguments-list*
  #+clisp ext:*args*
  #-(or sbcl clozure gcl ecl clasp cmu allegro lispworks clisp)
  (error "get-argv not supported for your implementation"))

(defun join (e l)
  (cond ((endp l) (list))
        ((endp (cdr l)) l)
        (t (cons (car l) (cons e (join e (cdr l)))))))

(example (join 1 '(a b c d e)) 
         => '(a 1 b 1 c 1 d 1 e))

(defun concat-all (kind term ls)
  (if (endp ls)
      term
      (concatenate kind (car ls) (concat-all kind term (cdr ls)))))

(example (concat-all 'string "" '("a" "b" "c" "d" "e"))
         => "abcde")
  
(defun banner ()
  (concat-all
   'string ""
   (join (format nil "~%")
         '("                                 __________       "
           "                                /         /.      "
           "     .-----------------.       /_________/ |      "
           "    /                 / |      |         | |      "
           "   /+================+\\ |      | |====|  | |      "
           "   ||cl-jupyter      || |      |         | |      "
           "   ||                || |      | |====|  | |      "
           "   ||* (fact 5)      || |      |         | |      "
           "   ||120             || |      |   ___   | |      "
           "   ||                || |      |  |166|  | |      "
           "   ||                ||/@@@    |   ---   | |      "
           "   \\+================+/    @   |_________|./.     "
           "                         @           ..  ....'    "
           "     ..................@      __.'. '  ''         "
           "    /oooooooooooooooo//      ///                  "
           "   /................//      /_/                   "
           "   ------------------                             "
           ""))))

;; (jformat t (banner))



(defclass kernel-config ()
  ((transport :initarg :transport :reader config-transport :type string)
   (ip :initarg :ip :reader config-ip :type string)
   (shell-port :initarg :shell-port :reader config-shell-port :type fixnum)
   (iopub-port :initarg :iopub-port :reader config-iopub-port :type fixnum)
   (control-port :initarg :control-port :reader config-control-port :type fixnum)
   (stdin-port :initarg :stdin-port :reader config-stdin-port :type fixnum)
   (hb-port :initarg :hb-port :reader config-hb-port :type fixnum)
   (signature-scheme :initarg :signature-scheme :reader config-signature-scheme :type string)
   (key :initarg :key :reader kernel-config-key)))

(defparameter *shell-thread* nil)

(defun kernel-start (&optional connection-file-name-arg)
  (let ((cmd-args (get-argv)))
					;(princ (banner))
    (write-line "")
    (jformat t "~A: an enhanced interactive Common Lisp REPL~%" +KERNEL-IMPLEMENTATION-NAME+)
    (jformat t "(Version ~A - Jupyter protocol v.~A)~%"
             +KERNEL-IMPLEMENTATION-VERSION+
             +KERNEL-PROTOCOL-VERSION+)
    (jformat t "--> (C) 2014-2015 Frederic Peschanski (cf. LICENSE)~%")
    (write-line "")
    (let ((connection-file-name (or connection-file-name-arg  (car (last cmd-args)))))
      (jformat t "connection file = ~A~%" connection-file-name)
      (unless (stringp connection-file-name)
        (error "Wrong connection file argument (expecting a string)"))
      (let ((config-alist (parse-json-from-string (concat-all 'string "" (read-file-lines connection-file-name)))))
        (jformat t "kernel configuration = ~A~%" config-alist)
        (let ((config
                (make-instance 'kernel-config
                               :transport (afetch "transport" config-alist :test #'equal)
                               :ip (afetch "ip" config-alist :test #'equal)
                               :shell-port (afetch "shell_port" config-alist :test #'equal)
                               :iopub-port (afetch "iopub_port" config-alist :test #'equal)
                               :control-port (afetch "control_port" config-alist :test #'equal)
                               :hb-port (afetch "hb_port" config-alist :test #'equal)
                               :signature-scheme (afetch "signature_scheme" config-alist :test #'equal)
                               :key (let ((str-key (afetch "key" config-alist :test #'equal)))
                                      (if (string= str-key "")
                                          nil
                                          (fredokun-utilities:string-to-octets str-key :encoding :ASCII))))))
          (when (not (string= (config-signature-scheme config) "hmac-sha256"))
            ;; XXX: only hmac-sha256 supported
            (error "Kernel only support signature scheme 'hmac-sha256' (provided ~S)" (config-signature-scheme config)))
          ;;(inspect config)
          (let* ((kernel (make-kernel config))
                 (evaluator (make-evaluator kernel))
                 (shell (make-shell-channel kernel))
                 (control (make-control-channel kernel))
                 (iopub (make-iopub-channel kernel)))
	    ;; Invoke the *kernel-start-hook* if available
	    (if cl-jupyter:*kernel-start-hook*
                (funcall cl-jupyter:*kernel-start-hook* kernel)
                (push kernel cl-jupyter:*started-kernels*))
	    ;; Launch the hearbeat thread
	    (let ((hb-socket (pzmq:socket (kernel-ctx kernel) :rep)))
	      (let ((hb-endpoint (format nil "~A://~A:~A"
				         (config-transport config)
				         (config-ip config)
				         (config-hb-port config))))
	        ;;(jformat t "heartbeat endpoint is: ~A~%" endpoint)
	        (pzmq:bind hb-socket hb-endpoint)
                (setq *shell-thread (bordeaux-threads:current-thread))
	        (let ((heartbeat-thread-id (start-heartbeat hb-socket))
                      (control-thread-id (start-control control (bordeaux-threads:current-thread))))
		  ;; main loop
		  (unwind-protect
		       (progn
		         (jformat t "[Kernel] Entering mainloop ...~%")
		         (shell-loop shell))
		    ;; clean up when exiting
		    (when cl-jupyter:*kernel-shutdown-hook* (funcall cl-jupyter:*kernel-shutdown-hook* kernel))
		    (bordeaux-threads:destroy-thread heartbeat-thread-id)
		    (bordeaux-threads:destroy-thread control-thread-id)
		    (pzmq:close hb-socket)
		    (pzmq:close (socket control))
		    (pzmq:close (socket iopub))
		    (pzmq:close (socket shell))
		    (pzmq:ctx-destroy (kernel-ctx kernel))
		    (jformat t "Bye bye.~%")))))))))))

(defun start-heartbeat (socket)
  (jformat t "[Hearbeat] starting...~%")
  (let ((thread-id (bordeaux-threads:make-thread
		    (lambda ()
		      (pzmq:proxy socket socket (cffi:null-pointer))))))

    ;; XXX: without proxy
    ;; (loop
    ;; 	 (pzmq:with-message msg
    ;; 	   (pzmq:msg-recv msg socket)
    ;; 			;;(jformat t "Heartbeat Received:~%")
    ;; 	   (pzmq:msg-send msg socket)
    ;; 			;;(jformat t "  | message: ~A~%" msg)
    ;; 	   ))))))
    thread-id))

(defun start-control (control shell-thread)
  (let ((thread-id (bordeaux-threads:make-thread
		    (lambda ()
                      (control-loop control shell-thread)))))
    (logg 2 "start-control started~%")

    ;; XXX: without proxy
    ;; (loop
    ;; 	 (pzmq:with-message msg
    ;; 	   (pzmq:msg-recv msg socket)
    ;; 			;;(jformat t "Heartbeat Received:~%")
    ;; 	   (pzmq:msg-send msg socket)
    ;; 			;;(jformat t "  | message: ~A~%" msg)
    ;; 	   ))))))
    thread-id))
