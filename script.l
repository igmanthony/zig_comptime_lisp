(def num (fn n (if (less n 2) 1 (add (sub 3 4) (sub 4 7)))))
(def newnum (num 7))
(newnum)