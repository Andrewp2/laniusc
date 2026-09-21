import Lanius.Compiler.Lexer.QuotedInvariant
import Lanius.Semantics.Scalar

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

/-! Stable contracts for the byte temporary introduced by the quoted loop. -/

theorem quotedByte_initializer (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 2 program current (.index (.local 0) (.local 4))
      (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)) current := by
  have sourceInBounds : cursor < (sourceI32Values source).length := by
    simpa [sourceI32Values] using inBounds
  have indexed := evalExpr_source_slice_index_of_locals program current 0 4 cell
    (sourceI32Values source) cursor invariant.sourceSlice invariant.cursorLocal
    sourceInBounds
  refine ⟨?_, PureFrame.refl invariant.frame.currentFormed⟩
  intro fuel enough
  have run := indexed fuel enough
  have valueEq : (sourceI32Values source).get ⟨cursor, sourceInBounds⟩ =
      Int.ofNat (source.get ⟨cursor, inBounds⟩).val := by
    simp [sourceI32Values]
  rw [valueEq] at run
  exact run

theorem quotedByte_newline (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 2 program (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)))
      (.binary .equal (.local 6) (.value (.signed .i32 10)))
      (.boolean (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == Int.ofNat 10))
      (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) := by
  simpa using ThresholdPure.i32LocalEqualLiteral program
    (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) 6
    (Int.ofNat (source.get ⟨cursor, inBounds⟩).val) 10
    (State.bindLocal_local? current invariant.frame.currentFormed 6 _)
    (invariant.frame.currentFormed.bindLocal 6 _)

theorem quotedByte_delimiter (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 2 program (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)))
      (.binary .equal (.local 6) (.local 3))
      (.boolean (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == delimiter))
      (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) := by
  simpa using ThresholdPure.i32LocalsEqual program
    (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) 6 3
    (Int.ofNat (source.get ⟨cursor, inBounds⟩).val) delimiter
    (State.bindLocal_local? current invariant.frame.currentFormed 6 _)
    (State.bindLocal_local?_of_ne current invariant.frame.currentFormed 3 6
      (.signed .i32 delimiter) _ (by decide) invariant.delimiterLocal)
    (invariant.frame.currentFormed.bindLocal 6 _)

theorem quotedByte_backslash (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 2 program (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)))
      (.binary .equal (.local 6) (.value (.signed .i32 92)))
      (.boolean (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == Int.ofNat 92))
      (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) := by
  simpa using ThresholdPure.i32LocalEqualLiteral program
    (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) 6
    (Int.ofNat (source.get ⟨cursor, inBounds⟩).val) 92
    (State.bindLocal_local? current invariant.frame.currentFormed 6 _)
    (invariant.frame.currentFormed.bindLocal 6 _)

theorem quotedByte_escaping (program : Program)
    (invariant : QuotedInvariant caller current cell source delimiter cursor escaping cursorCellId escapingCellId)
    (inBounds : cursor < source.length) :
    ThresholdPure 1 program (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val)))
      (.local 5) (.boolean escaping)
      (current.bindLocal 6 (.signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val))) := by
  let value : Value := .signed .i32 (Int.ofNat (source.get ⟨cursor, inBounds⟩).val); let after := current.bindLocal 6 value; have formed := invariant.frame.currentFormed.bindLocal 6 value
  have found := State.bindLocal_local?_of_ne current invariant.frame.currentFormed 5 6
    (.boolean escaping) value (by decide) invariant.escapingLocal
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough; cases fuel with
  | zero => omega
  | succ fuel => simpa [after, value, Nat.succ_eq_add_one] using
      (evalExpr_local_of_local? fuel program after 5 (.boolean escaping) found)

end Lanius.Compiler.Lexer
