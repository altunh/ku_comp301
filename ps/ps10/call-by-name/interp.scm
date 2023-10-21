(module interp (lib "eopl.ss" "eopl")
  
  ;; interpreter for the CALL-BY-NEED language.  

  (require "drscheme-init.scm")

  (require "lang.scm")
  (require "data-structures.scm")
  (require "environments.scm")
  (require "store.scm")
  (require "pairvals.scm")

  (provide value-of-program value-of instrument-newref instrument-let interpreter-name)

  ;;;;;;;;;;;;;;;; switches for instrument-let ;;;;;;;;;;;;;;;;

  (define instrument-let (make-parameter #t))

  ;; say (instrument-let #t) to turn instrumentation on.
  ;;     (instrument-let #f) to turn it off again.


  ;;;;;;;;;;;;;;;; the interpreter ;;;;;;;;;;;;;;;;

  (define interpreter-name 'CALL-BY-NAME)

  ;; value-of-program : Program -> ExpVal
  (define value-of-program 
    (lambda (pgm)
      (initialize-store!)             
      (cases program pgm
        (a-program (body)
                   (value-of body (init-env))))))

  ;; value-of : Exp * Env -> ExpVal
  ;; Page: 137 and 138
  (define value-of
    (lambda (exp env)
      (begin
        (eopl:printf "\n\n#############################################\n")
        (pretty-print exp)
        (eopl:printf "env = \n")
        (pretty-print (env->list env))
        (eopl:printf "store = \n")
        (pretty-print (store->readable (get-store-as-list)))
        (eopl:printf "\n"))

      (cases expression exp

        (const-exp (num) (num-val num))

        (var-exp (var) 
                 (let ((ref1 (apply-env env var)))
                   (let ((w (deref ref1)))
                     (if (expval? w)
                         w
                         (let ((v1 (value-of-thunk w)))
                           (begin
                             ;(setref! ref1 v1)   ;; Name it call by name
                             v1))))))

        (diff-exp (exp1 exp2)
                  (let ((val1
                         (expval->num
                          (value-of exp1 env)))
                        (val2
                         (expval->num
                          (value-of exp2 env))))
                    (num-val
                     (- val1 val2))))
        
        (zero?-exp (exp1)
                   (let ((val1 (expval->num (value-of exp1 env))))
                     (if (zero? val1)
                         (bool-val #t)
                         (bool-val #f))))

        (if-exp (exp0 exp1 exp2) 
                (if (expval->bool (value-of exp0 env))
                    (value-of exp1 env)
                    (value-of exp2 env)))

        ;; straightforward version of LET, without instrumentation
        ;; (let-exp (id rhs body)       
        ;;   (let ((val (value-of rhs env)))
        ;;     (value-of body
        ;;       (extend-env id (newref val) env))))

        ;; LET with instrumentation
        (let-exp (var exp1 body)       
                 (when (instrument-let)
                   (eopl:printf "entering let ~s~%" var))
                 (let ((val (value-of exp1 env)))
                   (let ((new-env (extend-env var (newref val) env)))
                     (when (instrument-let)
                       (begin
                         (eopl:printf "entering body of let ~s with env =~%" var)
                         (pretty-print (env->list new-env))
                         (eopl:printf "store =~%")
                         (pretty-print (store->readable (get-store-as-list)))
                         (eopl:printf "~%")
                         ))
                     (value-of body new-env))))
        
        (proc-exp (var body)
                  (proc-val
                   (procedure var body env)))

        (call-exp (rator rand)          
                  (let ((proc (expval->proc (value-of rator env)))
                        (arg  (value-of-operand rand env)))
                    (apply-procedure proc arg)))

        (letrec-exp (p-names b-vars p-bodies letrec-body)
                    (value-of letrec-body
                              (extend-env-rec* p-names b-vars p-bodies env)))

        (begin-exp (exp1 exps)
                   (letrec 
                       ((value-of-begins
                         (lambda (e1 es)
                           (let ((v1 (value-of e1 env)))
                             (if (null? es)
                                 v1
                                 (value-of-begins (car es) (cdr es)))))))
                     (value-of-begins exp1 exps)))

        (assign-exp (x e)
                    (begin
                      (setref!
                       (apply-env env x)
                       (value-of e env))
                      (num-val 27)))

        (newpair-exp (exp1 exp2)
                     (let ((v1 (value-of exp1 env))
                           (v2 (value-of exp2 env)))
                       (mutpair-val (make-pair v1 v2))))

        (left-exp (exp1)
                  (let ((v1 (value-of exp1 env)))
                    (let ((p1 (expval->mutpair v1)))
                      (left p1))))

        (setleft-exp (exp1 exp2)
                     (let ((v1 (value-of exp1 env))
                           (v2 (value-of exp2 env)))
                       (let ((p (expval->mutpair v1)))
                         (begin
                           (setleft p v2)
                           (num-val 82)))))

        (right-exp (exp1)
                   (let ((v1 (value-of exp1 env)))
                     (let ((p1 (expval->mutpair v1)))
                       (right p1))))

        (setright-exp (exp1 exp2)
                      (let ((v1 (value-of exp1 env))
                            (v2 (value-of exp2 env)))
                        (let ((p (expval->mutpair v1)))
                          (begin
                            (setright p v2)
                            (num-val 83)))))

        )))

  ;; apply-procedure : Proc * Ref -> ExpVal
  ;; uninstrumented version
  ;; Page: 132
  ;;   (define apply-procedure
  ;;     (lambda (proc1 val)
  ;;       (cases proc proc1
  ;;         (procedure (var body saved-env)
  ;;           (value-of body
  ;;             (extend-env var val saved-env))))))
  

  ;; apply-procedure : Proc * Ref -> ExpVal
  ;; instrumented version
  (define apply-procedure
    (lambda (proc1 val)
      (cases proc proc1
        (procedure (var body saved-env)
                   (let ((new-env (extend-env var val saved-env)))
                     (when (instrument-let)
                       (begin
                         (eopl:printf
                          "entering body of proc ~s with env =~%"
                          var)
                         (pretty-print (env->list new-env))
                         (eopl:printf "store =~%")
                         (pretty-print (store->readable (get-store-as-list)))
                         (eopl:printf "~%")))
                     (value-of body new-env))))))
  
  ;; value-of-operand : Exp * Env -> Ref
  ;; Page: 137
  (define value-of-operand
    (lambda (exp env)
      (cases expression exp
        (var-exp (var) (apply-env env var)) ; no deref!
        (else
         (newref (a-thunk exp env))))))

  ;; value-of-thunk : Thunk -> ExpVal
  (define value-of-thunk
    (lambda (th)
      (cases thunk th
        (a-thunk (exp1 saved-env)
                 (value-of exp1 saved-env)))))

     
  ;; store->readable : Listof(List(Ref,Expval)) 
  ;;                    -> Listof(List(Ref,Something-Readable))
  (define store->readable
    (lambda (l)
      (map
       (lambda (p)
         (list
          (car p)
          (if (expval? (cadr p))
              (expval->printable (cadr p))
              (thunk->printable (cadr p))
              )))
           
       l)))

   (trace value-of)

  )
  
        
        
        
        


  
