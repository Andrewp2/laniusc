import Lanius.Extraction.CompactOutput.Word.Assign
import Lanius.Extraction.CanonicalTokens.Compaction.Invariant
import Lanius.Separation.I32Prefix

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer Lanius.Extraction.CanonicalTokens
open CanonicalizeModel Compaction

def rowIndex : Expr := binary .multiply (read 8) (number 3)
def kindRead : Expr := .index (read 0) (read 9)
def startRead : Expr := .index (read 0) (binary .add (read 9) (number 1))
def finishRead : Expr := .index (read 0) (binary .add (read 9) (number 2))

theorem row_index (program : Program) (index count : Nat)
    (bound : index < count) (sizeFit : 3 * count ≤ 2147483647)
    (indexRead : before.local? 8 = some (.signed .i32 index)) :
    Evaluates program before rowIndex (.signed .i32 (3 * index : Nat)) before := by
  have run := evaluatesNatI32Multiply (leftValue := index) (rightValue := 3)
    (local_evaluates program indexRead)
    (show Evaluates program before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩) (by omega)
  simpa only [rowIndex, binary, Nat.mul_comm index 3, Int.ofNat_eq_natCast] using run

/-- Read the frontend's existing canonical token encoding through the actual
serializer expressions. Arbitrary spare words cannot affect any field. -/
theorem read_row (program : Program) (tokens : List RawToken) (index : Nat)
    (input : I32PrefixLocal before 0 inputCell (encodeTokens tokens))
    (rowRead : before.local? 9 = some (.signed .i32 (3 * index : Nat)))
    (bound : index < tokens.length) (sizeFit : 3 * tokens.length ≤ 2147483647) :
    Evaluates program before kindRead (.signed .i32 tokens[index].kind.gpuCode) before ∧
    Evaluates program before startRead (.signed .i32 tokens[index].start) before ∧
    Evaluates program before finishRead (.signed .i32 tokens[index].finish) before := by
  have firstBound : 3 * index < (encodeTokens tokens).length := by rw [encoded_length]; omega
  have secondBound : 3 * index + 1 < (encodeTokens tokens).length := by rw [encoded_length]; omega
  have thirdBound : 3 * index + 2 < (encodeTokens tokens).length := by rw [encoded_length]; omega
  have row := local_evaluates program rowRead
  have startIndex := evaluatesNatI32Add (leftValue := 3 * index) (rightValue := 1) row
    (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (by omega)
  have finishIndex := evaluatesNatI32Add (leftValue := 3 * index) (rightValue := 2) row
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩) (by omega)
  have kindRun := input.read program (read 9) (3 * index) firstBound row
  have startRun := input.read program (binary .add (read 9) (number 1)) (3 * index + 1) secondBound startIndex
  have finishRun := input.read program (binary .add (read 9) (number 2)) (3 * index + 2) thirdBound finishIndex
  have selected := encoded_row tokens [] index tokens[index] (List.getElem?_eq_getElem bound)
  simp only [List.append_nil, List.getElem?_eq_getElem firstBound, List.getElem?_eq_getElem secondBound,
    List.getElem?_eq_getElem thirdBound, Option.some.injEq] at selected
  exact ⟨by simpa only [kindRead, read, List.get_eq_getElem, selected.1, Int.ofNat_eq_natCast] using kindRun,
    by simpa only [startRead, read, List.get_eq_getElem, selected.2.1, Int.ofNat_eq_natCast] using startRun,
    by simpa only [finishRead, read, List.get_eq_getElem, selected.2.2, Int.ofNat_eq_natCast] using finishRun⟩

end Lanius.Extraction.CompactOutput.Tokens
