(component
  (core module $implementation
    (memory (export "memory") 1)
    ;; Same flat ABI and static return area as complex.core.wat.
    (func (export "add")
      (param $a-re f64) (param $a-im f64)
      (param $b-re f64) (param $b-im f64)
      (result i32)
      (f64.store (i32.const 0)
        (f64.add (local.get $a-re) (local.get $b-re)))
      (f64.store offset=8 (i32.const 0)
        (f64.add (local.get $a-im) (local.get $b-im)))
      (i32.const 0)
    )
  )
  (core instance $implementation (instantiate $implementation))
  (type $complex-number (record (field "re" f64) (field "im" f64)))
  (type $add (func
    (param "a" $complex-number) (param "b" $complex-number)
    (result $complex-number)))
  (func $add (type $add)
    (canon lift (core func $implementation "add")
      (memory $implementation "memory")))
  (instance $complex
    (export "complex-number" (type $complex-number))
    (export "add" (func $add)))
  (export "buildbyhansen:complex-calculator/complex@0.1.0" (instance $complex))
)
