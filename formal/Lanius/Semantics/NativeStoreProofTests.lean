import Lanius.Semantics.NativeStoreProof

namespace Lanius.Semantics.NativeStoreProofTests

open Lanius.Core Lanius.Memory

private def program : Program := {
  structures := [{ id := 3, fields := [.scalar (.signed .i32), .scalar .bool] }]
  enumerations := [{ id := 4, variants := [[], [.structure 3]] }] }

theorem pair (number : Int32) (flag : Bool) :
    NativeStoreSpec 8 program (.structure 3) (.structure 3 [.signed .i32 number.toInt, .boolean flag]) 16 := by
  native_store

theorem wrapped (number : Int32) (flag : Bool) :
    NativeStoreSpec 8 program (.enumeration 4)
      (.enumeration 4 1 [.structure 3 [.signed .i32 number.toInt, .boolean flag]]) 24 := by
  native_store

example : NativeStoreSpec 8 program (.enumeration 4) (.enumeration 4 0 []) 24 := by native_store

theorem slice (pointer length : Nat) (pointerFits : pointer < 2 ^ 64) (lengthFits : length < 2 ^ 64) :
    NativeStoreSpec 8 program (.slice (.scalar (.signed .i32)))
      (.rawSlice (.scalar (.signed .i32)) pointer length) 16 := by native_store

-- Arity, nominal identity, native width and recursion depth cannot be waived.
example (number : Int32) : True := by
  fail_if_success have : NativeStoreSpec 8 program (.structure 3) (.structure 3 [.boolean true]) 16 := by native_store
  fail_if_success have : NativeStoreSpec 8 program (.structure 3) (.structure 9 [.signed .i32 number.toInt, .boolean true]) 16 := by native_store
  fail_if_success have : NativeStoreSpec 8 program (.structure 3) (.structure 3 [.signed .i32 number.toInt, .boolean true]) 4 := by native_store
  fail_if_success have : NativeStoreSpec 1 program (.structure 3) (.structure 3 [.signed .i32 number.toInt, .boolean true]) 16 := by native_store
  fail_if_success
    have wrong : NativeStoreSpec 8 program (.slice (.scalar (.signed .i32)))
        (.rawSlice (.scalar (.signed .i32)) (2 ^ 64) 0) 16 := by native_store
  fail_if_success
    have wrong : NativeStoreSpec 8 program (.slice (.scalar (.signed .i32)))
        (.rawSlice (.scalar (.signed .i32)) 0 (2 ^ 64)) 16 := by native_store
  fail_if_success (have : NativeStoreSpec 8 program (.slice .unit) (.rawSlice .unit 0 0) 16 := by native_store)
  trivial

#print axioms pair
#print axioms wrapped
#print axioms slice
#print axioms NativeStoreSpec.record

end Lanius.Semantics.NativeStoreProofTests
