import Lanius.X86.Relative
import Lanius.ExecutionRules

namespace Lanius.X86

open Lanius.Core Lanius.Semantics

theorem wrap_relative (target : Target) (next destination : Nat)
    (nextBound : next ≤ 2147483647) (destinationBound : destination ≤ 2147483647) :
    wrapSigned target .i32 (relativeDisplacement next destination) =
      relativeDisplacement next destination := by
  have bounds := relativeDisplacement_fits next destination nextBound destinationBound
  change (if relativeDisplacement next destination % 4294967296 ≥ 2147483648 then
      relativeDisplacement next destination % 4294967296 - 4294967296
    else relativeDisplacement next destination % 4294967296) = relativeDisplacement next destination
  split <;> omega

/-- The source patcher's subtraction has exactly the signed displacement
used by near x86 transfers; no overflowing Int-to-i32 conversion is assumed. -/
theorem relative_evaluates (next destination : Nat)
    (nextBound : next ≤ 2147483647) (destinationBound : destination ≤ 2147483647)
    (destinationResult : Evaluates program before destinationExpr (.signed .i32 destination) middle)
    (nextResult : Evaluates program middle nextExpr (.signed .i32 next) after) :
    Evaluates program before (.binary .subtract destinationExpr nextExpr)
      (.signed .i32 (relativeDisplacement next destination)) after := by
  apply evaluatesEagerBinary (by decide) (by decide) destinationResult nextResult
  simpa only [evalBinaryValue, evalSignedBinary, BEq.rfl, ↓reduceIte, relativeDisplacement] using
    congrArg (fun value => (Except.ok (.signed .i32 value) : Except Lanius.Trap Value))
      (wrap_relative program.target next destination nextBound destinationBound)

end Lanius.X86
