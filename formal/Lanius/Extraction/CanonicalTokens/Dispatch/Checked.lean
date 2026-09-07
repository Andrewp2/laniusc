import Lanius.Extraction.CanonicalTokens.Dispatch.Body
import Lanius.Extraction.CanonicalTokens.Dispatch.Reference
import Lanius.Extraction.CanonicalTokens.Dispatch.Validation

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure Checked (program : Program) (matcher : FunctionId) (statement : Stmt) where
  source : CheckedBody matcher statement
  matcherFound : program.function? matcher = some (Ascii.sourceFunction matcher)
  rules : ∀ group ∈ source.groups, ∀ rule ∈ group.rules, ValidRule program group.width rule
  fallback : ConstantValid program source.fallback
  identifier : tag program source.fallback = 1
  reference : (rows program source.groups).Perm referenceRows

/-- Every assumption of the dispatcher correctness theorem is checked against
the actual Core program and body, including the callee, constants, word
padding, and the independently specified keyword/tag table. -/
def check? (program : Program) (matcher : FunctionId) (statement : Stmt) :
    Option (Checked program matcher statement) := do
  let source ← checkBody? matcher statement
  match found : program.function? matcher with
  | none => none
  | some function =>
      let same ← Equality.function? function (Ascii.sourceFunction matcher)
      let rules ← checkGroups? program source.groups
      let fallback ← checkConstant? program source.fallback
      if identifier : tag program source.fallback = 1 then
        let reference ← checkReference? program source.groups
        pure ⟨source, found.trans (congrArg some same.equal), rules.down,
          fallback.down, identifier, reference.down⟩
      else none

theorem Checked.executes (checked : Checked program matcher statement)
    (before : State) (sourceCell : CellId) (source : List Int) (start width : Nat)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (startLocal : before.local? 1 = some (.signed .i32 start))
    (endLocal : before.local? 2 = some (.signed .i32 (start + width)))
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Executes program before statement
      (.returned (some (.signed .i32
        (lookup ((source.drop start).take width) referenceRows 1)))) after ∧ CellEffect CellSet.empty before after := by
  obtain ⟨after, executed, frame⟩ := executes_body program matcher checked.source.fallback before
    sourceCell source start width checked.source.groups checked.matcherFound checked.rules checked.fallback
    wellFormed sourceLocal sourceContents startLocal endLocal capacity bounded
  rw [dispatched_reference program source start width checked.source.fallback checked.source.groups
    checked.rules checked.reference checked.identifier capacity] at executed
  exact ⟨after, checked.source.exactSource ▸ executed, frame⟩

end Lanius.Extraction.CanonicalTokens.Dispatch
