import verified_compiler.tests.direct_ir_decimal_loop
import Lanius.Semantics.NativeStore

namespace IRDecimalTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRDecimalProof IRDecimalLoopProof

def sample (word : BitVec 32) : State := { heap := { blocks := [{
  base := 16, size := 4, alignment := 4, bytes := i32Bytes word.toInt, owned := false }], nextAddress := 20 } }

def input (word : BitVec 32) : Input (sample word) := {
  address := 16, count := 1, start := 0, length := 1, bytes := fun _ => word.toInt
  fits := by decide, inside := by decide, nonempty := by decide
  reads := by
    intro index inside
    have equal : index = 0 := by omega
    subst index
    have snapshot : NativeSnapshot 64 extractedProgram (sample word).heap
        (.scalar (.signed .i32)) 16 (.signed .i32 word.toInt) 4 :=
      NativeSnapshot.i32 word (by rfl)
    exact snapshot.read }

/-- A closed, inhabited instance with arbitrary signed source words; invalid
    characters are rejected and readable input storage remains unchanged. -/
theorem singleWord (word : BitVec 32) :
    ∃ after, RunsExpr extractedProgram (sample word) (input word).call
      (resultValue (step .empty word.toInt)) after ∧ after.heap = (sample word).heap := by
  obtain ⟨after, run, pure⟩ := actualDecimal (input word) (by simp [State.CellsWellFormed, sample]) rfl
  exact ⟨after, run, pure.heap⟩

example : ∃ after, RunsExpr extractedProgram {} (.call Extracted.«lowering::constant_expression».Functions.«decimal».core.id
    [.value .unit, .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0)])
    (resultValue .rejected) after ∧ PureFrame {} after :=
  actualReject 0 0 0 .unit (Or.inr (Or.inl (by decide))) (by simp [State.CellsWellFormed])

#print axioms singleWord

-- Independent examples supplement the all-input traversal proof: separators,
-- leading zeros, signed boundaries, malformed bytes and bad ranges.
#eval (do
  let cases : List (List Int × Value) := [([55], resultValue (.number 7)),
    ([48, 48, 55], resultValue (.number 7)), ([95], resultValue .rejected),
    ([95, 55, 95, 95], resultValue (.number 7)), ([-1], resultValue .rejected),
    ([58], resultValue .rejected), ([2147483647], resultValue .rejected),
    ([50,49,52,55,52,56,51,54,52,55], resultValue (.number 2147483647)),
    ([50,49,52,55,52,56,51,54,52,56,95], resultValue .minimum),
    ([50,49,52,55,52,56,51,54,52,57], resultValue .rejected),
    ([50,49,52,55,52,56,51,54,52,56,48], resultValue .rejected)]
  for (words, expected) in cases do
    let block : Block := {
      base := 16
      size := words.length * 4
      alignment := 4
      bytes := words.flatMap i32Bytes
      owned := false }
    let heap : Heap := { blocks := [block], nextAddress := 16 + words.length * 4 }
    let before : State := { heap }
    let call := Expr.call Extracted.«lowering::constant_expression».Functions.«decimal».core.id
      [.value (.rawSlice (.scalar (.signed .i32)) 16 words.length), .value (.signed .i32 words.length),
        .value (.signed .i32 0), .value (.signed .i32 words.length)]
    let .done actual after := evalExpr 200 extractedProgram before call
      | throw (IO.userError "decimal traversal trapped or did not terminate")
    unless actual == expected do throw (IO.userError s!"wrong decimal value for {words}")
    unless (after.heap.loadBytes 16 (words.length * 4)).toOption == some (words.flatMap i32Bytes) do
      throw (IO.userError "decimal decoder changed input storage")
    unless after.heap.nextAddress == before.heap.nextAddress do throw (IO.userError "decimal decoder allocated raw storage")
  IO.println s!"{cases.length} decimal traversal cases passed" : IO Unit)

end IRDecimalTests
