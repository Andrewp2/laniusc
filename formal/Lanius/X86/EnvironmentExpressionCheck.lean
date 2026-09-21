import Lanius.X86.DynamicComparison

namespace Lanius.X86.EnvironmentExpressionCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck
open Lanius.X86.ExpressionEnvironment
open Lanius.X86.DynamicComparison

/- The certificate carries only source shape and authenticated bytes.  Runtime
   `Environment.Relates` evidence is supplied separately to `sound`. -/
structure LocalCertificate (id : VarId) (emitted : List UInt8) where
  location : ExpressionEnvironment.Location
  bytesExact : emitted = location.bodyBytes

structure NotEqualCertificate (leftId rightId : VarId) (emitted : List UInt8) where
  leftLocation : ExpressionEnvironment.Location
  rightLocation : ExpressionEnvironment.Location
  slot : Nat
  bytesExact : emitted = DynamicComparison.localNotEqualBytes
    leftLocation rightLocation slot

inductive Certificate : Core.Expr → List UInt8 → Type
  | local {id : VarId} (certificate : LocalCertificate id emitted) :
      Certificate (.local id) emitted
  | notEqual {leftId rightId : VarId}
      (certificate : NotEqualCertificate leftId rightId emitted) :
      Certificate (.binary .notEqual (.local leftId) (.local rightId)) emitted

def check (source : Core.Expr) (emitted : List UInt8)
    (left right : ExpressionEnvironment.Location) (slot : Nat) :
    Option (Certificate source emitted) :=
  match source with
  | .local id =>
      if exact : emitted = left.bodyBytes then
        some (.local ⟨left, exact⟩)
      else none
  | .binary .notEqual (.local leftId) (.local rightId) =>
      if exact : emitted = localNotEqualBytes left right slot then
        some (.notEqual ⟨left, right, slot, exact⟩)
      else none
  | _ => none

theorem local_sound
    (id : VarId) {emitted : List UInt8}
    (certificate : LocalCertificate id emitted)
    (environment : Environment coreBefore machineBefore) (program : Program) (value : Int)
    (related : environment.Relates id certificate.location value)
    (loaded : CodeAt machineBefore.memory machineBefore.rip emitted) :
    evalExpr 1 program coreBefore (.local id) =
        .done (.signed .i32 value) coreBefore ∧
      ∃ after, Step machineBefore after ∧
        after.registers 0 = (BitVec.ofInt 32 value).setWidth 64 ∧
        after.rip = machineBefore.rip + BitVec.ofNat 64 certificate.location.bodyBytes.length := by
  rw [certificate.bytesExact] at loaded
  obtain ⟨core, after, step, result, rip, rsp, preserved, memory, flags⟩ :=
    loadLocal environment program id certificate.location value related loaded
  exact ⟨core, ⟨after, step, result, rip⟩⟩

theorem sound
    (leftId rightId : VarId) {emitted : List UInt8}
    (certificate : NotEqualCertificate leftId rightId emitted)
    (program : Program) (environment : Environment coreBefore machineBefore)
    (leftValue rightValue : Int) (lower upper : Nat)
    (leftRelated : environment.Relates leftId certificate.leftLocation leftValue)
    (rightRelated : environment.Relates rightId certificate.rightLocation rightValue)
    (leftWindow : ∀ old, certificate.leftLocation = .frame old → lower ≤ old ∧ old < upper)
    (rightWindow : ∀ old, certificate.rightLocation = .frame old → lower ≤ old ∧ old < upper)
    (slotWindow : lower ≤ certificate.slot ∧ certificate.slot < upper)
    (rightNotSlot : ∀ old, certificate.rightLocation = .frame old → old ≠ certificate.slot)
    (invariant : FrameCodeInvariant machineBefore lower upper emitted) :
    ∃ after, evalExpr 2 program coreBefore
        (.binary .notEqual (.local leftId) (.local rightId)) =
        .done (.boolean (leftValue != rightValue)) coreBefore ∧
      Steps 8 machineBefore after ∧
      after.registers 0 = (if leftValue != rightValue then (1 : BitVec 64) else 0) := by
  rw [certificate.bytesExact] at invariant
  obtain ⟨after, core, steps, result, rbp, memory, rip⟩ :=
    local_notEqual program environment leftId rightId certificate.leftLocation
    certificate.rightLocation
    leftValue rightValue certificate.slot lower upper leftRelated rightRelated leftWindow
    rightWindow slotWindow rightNotSlot invariant
  exact ⟨after, core, steps, result⟩

end Lanius.X86.EnvironmentExpressionCheck
