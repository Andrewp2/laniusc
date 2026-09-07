import Lanius.Extraction.CanonicalTokens.Dispatch.Source
import Lanius.Extraction.CanonicalTokens.Ascii.Call
import Lanius.Separation.CellEffect

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

def Rule.spelling (rule : Rule) (width : Nat) : List UInt8 :=
  (Lanius.World.utf8Bytes rule.text).take width

def tag (program : Program) (kind : ConstantId) : Int :=
  match program.constant? kind with
  | some { value := .signed .i32 value, .. } => value
  | _ => 0

structure ValidRule (program : Program) (width : Nat) (rule : Rule) : Prop where
  padded : (Lanius.World.utf8Bytes rule.text).length = ((width + 3) / 4) * 4
  countBound : width + 3 ≤ 2147483647
  constant : program.constant? rule.kind = some {
    id := rule.kind, type := .scalar (.signed .i32), value := .signed .i32 (tag program rule.kind) }

theorem ValidRule.spelling_length (valid : ValidRule program width rule) :
    (rule.spelling width).length = width := by
  simp only [Rule.spelling, List.length_take, valid.padded]
  omega

theorem evaluates_condition (program : Program) (matcher : FunctionId)
    (before : State) (sourceCell : CellId) (source : List Int) (start width : Nat) (rule : Rule)
    (found : program.function? matcher = some (Ascii.sourceFunction matcher))
    (valid : ValidRule program width rule)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (startLocal : before.local? 1 = some (.signed .i32 start))
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Evaluates program before (condition matcher width rule)
      (.boolean (Ascii.matchesBytes source start (rule.spelling width))) after ∧ CellEffect CellSet.empty before after := by
  have sourceResult : Evaluates program before (.local 0)
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ sourceLocal⟩
  have startResult : Evaluates program before (.local 1) (.signed .i32 start) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ startLocal⟩
  have arguments : ArgumentsEvaluateTo program before
      [.local 0, .local 1, .value (.string rule.text), .value (.signed .i32 width)]
      [.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length,
        .signed .i32 start, .string rule.text, .signed .i32 (rule.spelling width).length] before := by
    rw [valid.spelling_length]
    exact ArgumentsEvaluateTo.cons sourceResult (ArgumentsEvaluateTo.cons startResult
      (ArgumentsEvaluateTo.cons
        (show Evaluates program before (.value (.string rule.text)) (.string rule.text) before from ⟨1, rfl⟩)
        (ArgumentsEvaluateTo.cons
          (show Evaluates program before (.value (.signed .i32 width)) (.signed .i32 width) before from ⟨1, rfl⟩)
          (ArgumentsEvaluateTo.nil program before))))
  obtain ⟨after, evaluated, afterWF, locals, world, cells, domain, frontier⟩ :=
    Ascii.evaluates_call program matcher before sourceCell source start rule.text (rule.spelling width)
      _ found wellFormed sourceContents arguments
      (by simpa only [valid.spelling_length] using capacity) bounded
      (by simpa only [valid.spelling_length] using valid.countBound)
      (by simpa only [valid.spelling_length] using valid.padded)
      (by rw [valid.spelling_length]; rfl)
  exact ⟨after, evaluated, ⟨afterWF, locals, world, fun cell old _ => cells cell old, frontier, domain⟩⟩

theorem executes_returned (program : Program) (before : State) (rule : Rule)
    (valid : ValidRule program width rule) :
    Executes program before (returned rule.kind)
      (.returned (some (.signed .i32 (tag program rule.kind)))) before := by
  apply executesSequenceReturned
  apply executesReturnValue
  refine ⟨1, ?_⟩
  rw [evalExpr.eq_def]
  simp only [valid.constant]

end Lanius.Extraction.CanonicalTokens.Dispatch
