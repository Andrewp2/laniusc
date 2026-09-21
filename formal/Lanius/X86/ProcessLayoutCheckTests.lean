import Lanius.X86.ProcessLayoutCheck

namespace Lanius.X86.ProcessLayoutCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.StartupCheck
open Lanius.X86.ProcessLayoutCheck
open Lanius.X86.FunctionCheck

example : startupExitAddress =
    callAddress + BitVec.ofNat 64
      (callCode.length + returnResult.length + loadExit.length) :=
  startup_exit_address

example : jumpTarget (BitVec.ofNat 32 0) = functionEntry := by rfl

private def callEntry : Function := {
  id := 1
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.call 2 [])))
  external := none }

private def canonicalCallEntry : Function := {
  id := 1
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.sequence (.returnValue (some (.call 2 []))) .skip)
  external := none }

private def scalarEntry : Function := {
  id := 3
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 0))))
  external := none }

private def nestedExpressionEntry : Function := {
  id := 4
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.binary .add (.value (.signed .i32 1)) (.value (.signed .i32 2)))
    (.value (.signed .i32 3)))))
  external := none }

example : entryStackFootprint callEntry = [8, 16, 32, 40] := by rfl
example : entryStackFootprint canonicalCallEntry = [8, 16, 32, 40] := by rfl
example : startupStackFootprint callEntry = [8, 16, 24, 32, 40, 56, 64] := by rfl
example : entryStackFootprint scalarEntry = [8, 16] := by rfl
example : expressionAllocationCount
    (.binary .add
      (.binary .add (.value (.signed .i32 1)) (.value (.signed .i32 2)))
      (.value (.signed .i32 3))) = 2 := by rfl
example : entryStackFootprint nestedExpressionEntry = [8, 16, 16, 24] := by rfl
example : 56 ∈ startupStackFootprint callEntry := by
  simp [callEntry, startupStackFootprint, entryStackFootprint]

example {before : Machine.State} {slots left right : Nat}
    (window : DynamicFrameWindow before slots)
    (leftBound : left < slots) (rightBound : right < slots)
    (different : left ≠ right) (i j : Fin 4) :
    frameSlotAddress (before.registers rspRegister - 8) left + BitVec.ofNat 64 i.val ≠
      frameSlotAddress (before.registers rspRegister - 8) right + BitVec.ofNat 64 j.val :=
  window.slotsSeparated left right leftBound rightBound different i j

example {before : Machine.State} : DynamicFrameWindow before (2^28) :=
  dynamic_frame_window_of_slots_le (by omega)

example {before : Machine.State} :
    frameSlotAddress (before.registers rspRegister - 8) (2^28 - 1) =
      before.registers rspRegister - BitVec.ofNat 64 (16 + 8 * (2^28 - 1)) := by
  exact (dynamic_frame_window_of_slots_le (before := before) (slots := 2^28) (by omega)).slotAddressExact _
    (by omega)

#check ProcessLayout.startupLayout
#check reaches_function_layout
#check startupStackFootprint_mem
#check StackCodeDisjoint

end Lanius.X86.ProcessLayoutCheckTests
