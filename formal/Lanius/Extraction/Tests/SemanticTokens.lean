import Lanius.Extraction.SemanticTokens.Records
import Lanius.Semantics

namespace Lanius.Extraction.Tests.SemanticTokens

open Lanius.Core Lanius.Semantics Lanius.Compiler.Parser
open Lanius.Extraction.SemanticTokens

private def grammar : IndexedGrammar := {
  grammar := ⟨4, 2, 0, 12, 11, [10, 11, 12, 11], [⟨0, [0, 2, 1, 5]⟩, ⟨1, [3]⟩]⟩
  productionsByLhs := [[0], [1]]
}

private def tokens : List Token := [⟨10, ⟨0, 0, 1⟩⟩, ⟨12, ⟨0, 1, 3⟩⟩, ⟨12, ⟨0, 3, 5⟩⟩]

-- The root consumes the inner half of the final split token; its nonterminal
-- child consumes the outer half. Postorder visits the outer assignment first.
private def tree : Lanius.Compiler.Parser.ParseTree := .nonterminal 0 0 0 6
  [.terminal 0 0, .terminal 1 2, .terminal 2 1, .nonterminal 1 1 5 6 [.terminal 2 3]]

private def selected : MaterializedParse grammar (tokens.map Token.kind) := {
  tree
  recognizes := by
    refine ParseTreeRecognizesSymbol.nonterminal (nonterminal := 0) (productionId := 0)
      (by decide) (by decide) rfl ?_
    refine .cons (middle := 2) (.terminal rfl (by decide) (by decide)) ?_
    refine .cons (middle := 4) (.terminal rfl (by decide) (by decide)) ?_
    refine .cons (middle := 5) (.terminal rfl (by decide) (by decide)) ?_
    refine .cons ?_ .empty
    exact .nonterminal (nonterminal := 1) (productionId := 1) (by decide) (by decide) rfl
      (.cons (middle := 6) (.terminal rfl (by decide) (by decide)) .empty)
}

private def uses : List Use := [⟨0, 2, 0, 0⟩, ⟨2, 4, 1, 2⟩, ⟨4, 5, 2, 1⟩, ⟨5, 6, 2, 3⟩]
private def expected : List Assignment := [⟨0, none⟩, ⟨2, none⟩, ⟨1, some 3⟩]

private def checkModel : IO Unit := do
  for order in [uses, uses.reverse, uses.drop 3 ++ uses.take 3, uses.drop 2 ++ uses.take 2] do
    unless assignmentsFrom? order 0 tokens.length == some expected do
      throw (IO.userError "semantic assignments changed with terminal visitation order")
  unless expected.flatMap Assignment.words == [0, -1, 2, -1, 1, 3] &&
      expected.map Assignment.code == [0, 2, 2147483648 + 1 + 3 * 32768] &&
      semanticKindsValid grammar.grammar tokens (expected.map Assignment.code) do
    throw (IO.userError "ordinary/whole-split/virtual-split assignment encoding differs from the checker")
  unless assignmentsFrom? [] 0 0 == some [] && (assignmentsFrom? [] 0 1).isNone do
    throw (IO.userError "empty or missing-first-slot assignment boundary failed")
  for first in [0, 1, 32767] do
    for second in [0, 1, 32767] do
      let code := (Assignment.mk first (some second)).code
      unless isPackedSemanticKind code && packedInnerKind code == first && packedOuterKind code == second do
        throw (IO.userError s!"packed-kind boundary failed for {first}/{second}")
  for nodeBase in [0, 7] do
    for wordBase in [0, 19] do
      let layout := ParserTreeLayout.treeFrom nodeBase wordBase tree
      let records := (treeVisits grammar (tokens.map Token.kind) nodeBase wordBase 0 tree).1
      let visited := records.flatMap RecordVisit.uses
      unless visited == uses.drop 3 ++ uses.take 3 &&
          assignmentsFrom? visited 0 tokens.length == some expected &&
          records.map RecordVisit.offset == layout.offsets do
        throw (IO.userError "postorder record visits lost token positions, assignments, or offset identity")
      for index in List.range records.length do
        let some record := records[index]? | throw (IO.userError "record fixture index is missing")
        unless (layout.words.drop (record.offset - wordBase)).take record.words.length == record.words do
          throw (IO.userError "semantic record differs from the materializer's exact word buffer")
        for child in record.children do
          match child with
          | .token _ => pure ()
          | .node id start finish =>
            let some nested := records[id - nodeBase]?
              | throw (IO.userError "state child does not point to an allocated record")
            unless nodeBase <= id && id < nodeBase + index && nested.start == start && nested.finish == finish do
              throw (IO.userError "state child changed span or violated postorder linkage")
#eval checkModel

-- Instantiate the general result with an actual derivation, not merely a
-- hand-written sequence of plausible-looking terminal records.
example : ∃ assignments : List Assignment,
    semanticKindsValid grammar.grammar tokens (assignments.map Assignment.code) = true := by
  obtain ⟨_, assignments, _, _, _, _, _, _, valid⟩ := selected_tree_assignments tokens selected (by decide)
  exact ⟨assignments, valid⟩

example : Nonempty (CollectionRecords grammar tokens selected.tree 7 19) :=
  selected_collection_records tokens selected (by decide) 7 19

/-- Run the actual current Lanius collect body after the source pack has been
loaded. The fixture supplies exactly the grammar header/table that collect
reads; parser production encoding is outside this focused collector test. -/
def checkCollectExecution (program : Program) (functionId : Lanius.FunctionId) : IO Unit := do
  let layout := ParserTreeLayout.treeFrom 0 0 tree
  let grammarWords : List Int := [1, 4, 2, 2, 0, 12, 11, 17] ++ List.replicate 9 0 ++ [10, 11, 12, 11]
  let kindWords : List Int := [10, 12, 12]
  let recordWords := layout.words ++ [444]
  let offsetWords := layout.offsets.map Int.ofNat ++ [-1]
  for capacity in [0, 1, 5, 6, 7, 8, 9] do
    for malformed in [false, true] do
      -- A kind equal to kind_count is out of range. This changes a real token
      -- triple in the root record, while preserving all offsets and lengths.
      let records := if malformed then recordWords.set 6 4 else recordWords
      let before : State := {
        cells := [⟨0, some (.array (signedI32Values grammarWords))⟩,
          ⟨1, some (.array (signedI32Values kindWords))⟩,
          ⟨2, some (.array (signedI32Values records))⟩,
          ⟨3, some (.array (signedI32Values offsetWords))⟩,
          ⟨4, some (.array (signedI32Values (List.replicate 9 777)))⟩]
        nextCell := 5
      }
      let before := before.bindLocal 99 (.signed .i32 999)
      let slice := fun cell length => Expr.value (Value.slice (.scalar (.signed .i32)) cell [] 0 length)
      let number := fun value : Nat => Expr.value (Value.signed .i32 value)
      let arguments := [slice 0 grammarWords.length, number grammarWords.length, slice 1 3, number 3,
        slice 2 records.length, number records.length, slice 3 offsetWords.length, number layout.offsets.length,
        slice 4 capacity, number capacity]
      let wanted : Int := if capacity < 6 then -2 else if malformed then -1 else 0
      match evalExpr 2000 program before (.call functionId arguments) with
      | .done (.signed .i32 result) after =>
        unless result == wanted && before.locals == after.locals do
          throw (IO.userError s!"current collect returned {result}, expected {wanted}, or changed scope at capacity {capacity}")
        for entry in before.cells do
          if entry.id != 4 then
            let some current := after.cellEntry? entry.id
              | throw (IO.userError "current collect removed an input/caller cell")
            unless current.id == entry.id && current.value == entry.value do
              throw (IO.userError "current collect changed an input/caller cell")
        if wanted == 0 then
          unless after.cell? 4 == some (.array (signedI32Values (expected.flatMap Assignment.words ++ [777, 777, 777]))) do
            throw (IO.userError "current collect swapped split halves, changed token meaning, or overwrote the unused suffix")
        else if wanted == -2 then
          unless after.cell? 4 == before.cell? 4 do
            throw (IO.userError "current collect wrote assignments before rejecting insufficient capacity")
        else
          let some (.array values) := after.cell? 4 | throw (IO.userError "current collect lost the assignment buffer")
          unless values.drop 6 == signedI32Values [777, 777, 777] do
            throw (IO.userError "current collect wrote outside the assignment prefix on malformed input")
      | _ => throw (IO.userError "current collect trapped, exhausted, or returned the wrong value type")

#print axioms selected_tree_assignments
#print axioms ScanPath.slots_unique
#print axioms ScanPath.assignment
#print axioms assignmentsFrom_permutation
#print axioms tree_visit_lookup
#print axioms tree_visit_child_lookup
#print axioms selected_tree_visits
#print axioms selected_collection_records
#print axioms CollectionRecords.token_child

end Lanius.Extraction.Tests.SemanticTokens
