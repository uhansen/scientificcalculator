(module
  (memory (export "memory") 1)

  ;; Legacy Canonical ABI: records flatten to four f64 parameters.
  ;; Two result fields exceed MAX_FLAT_RESULTS (1), so return a pointer.
  (func (export "buildbyhansen:complex-calculator/complex@0.1.0#add")
    (param $a-re f64) (param $a-im f64)
    (param $b-re f64) (param $b-im f64)
    (result i32)
    ;; Static return area: 16 bytes, aligned to 8, re at 0 and im at 8.
    (f64.store (i32.const 0)
      (f64.add (local.get $a-re) (local.get $b-re)))
    (f64.store offset=8 (i32.const 0)
      (f64.add (local.get $a-im) (local.get $b-im)))
    (i32.const 0)
  )
)
