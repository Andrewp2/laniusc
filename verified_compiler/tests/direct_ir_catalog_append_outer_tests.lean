import verified_compiler.tests.direct_ir_catalog_append_contract

namespace IRCatalogAppendOuterTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRCatalogAppendProof

-- An already represented count-slice fragment, not raw-parts construction or
-- a complete catalog. Only its selected i32 is readable; padding is absent.
def countOnly : State :=
  let base : State := {
    heap := {
      blocks := [{ base := 256, size := 4, alignment := 8, bytes := i32Bytes 0 }]
      nextAddress := 260
      remaining := some 100 }
    world := { standardOutput := [88], standardError := [89] } }
  base.bindLocal 100 (.signed .i32 91)

def negativeId : Arguments := {
  rowsAddress := 4096, rowsLength := 1
  countAddress := 256, countLength := 1
  capacity := 1, id := -1, parameters := 0, result := .I32
  eventsAddress := 8192, eventsLength := 1
  resultAddress := 12288, resultLength := 1
  hasResultTypes := true, sourceCapacity := 1, eventCount := 1, next := 0 }

-- A nonnegative ID reaches valid_result, code, and nominal_code. Its nominal
-- ID is invalid, so no duplicate scan, allocation or source read is needed.
def invalidResult : Arguments := { negativeId with id := 7, result := .Nominal (-1) }

private theorem countOnlyFormed : countOnly.CellsWellFormed := by
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]

example : countOnly.heap.loadByte 256 4 = .error .rawMemoryBounds := rfl
example : countOnly.heap.containingBlock? negativeId.rowsAddress = none := rfl
example : countOnly.heap.containingBlock? negativeId.eventsAddress = none := rfl
example : countOnly.heap.containingBlock? negativeId.resultAddress = none := rfl

theorem negativeIdRejected : ∃ after,
    RunsExpr extractedProgram countOnly negativeId.call (.signed .i32 (-1)) after ∧
      PureFrame countOnly after :=
  actualGuardReject negativeId countOnlyFormed (by rfl) (by
    intro guarded
    have nonnegative := guarded.1
    change (0 : Int) ≤ -1 at nonnegative
    omega)

theorem invalidResultRejected : ∃ after,
    RunsExpr extractedProgram countOnly invalidResult.call (.signed .i32 (-1)) after ∧
      PureFrame countOnly after :=
  actualGuardReject invalidResult countOnlyFormed (by rfl) (by
    intro guarded
    have valid := guarded.2.1
    change false = true at valid
    contradiction)

def absentCount : State := { countOnly with heap := { countOnly.heap with blocks := [] } }
def truncatedCount : State := {
  countOnly with heap := {
    countOnly.heap with
    blocks := [{ base := 256, size := 4, alignment := 8, bytes := [0, 0] }] } }

private theorem absentDecode :
    readRawSliceIndex extractedProgram absentCount (.structure countId) 256 1 0 =
      .error .invalidPointer := rfl
private theorem truncatedDecode :
    readRawSliceIndex extractedProgram truncatedCount (.structure countId) 256 1 0 =
      .error .rawMemoryBounds := rfl

-- Negative ID alone cannot inhabit the rejection theorem's domain: its
-- mandatory count-read premise is false for either failed native decode.
theorem absentCountNotAdmitted : ¬negativeId.CountRead absentCount := by
  unfold Arguments.CountRead
  change ¬(readRawSliceIndex extractedProgram absentCount (.structure countId) 256 1 0 =
    .ok (.structure countId [.signed .i32 0]))
  rw [absentDecode]
  simp

theorem truncatedCountNotAdmitted : ¬negativeId.CountRead truncatedCount := by
  unfold Arguments.CountRead
  change ¬(readRawSliceIndex extractedProgram truncatedCount (.structure countId) 256 1 0 =
    .ok (.structure countId [.signed .i32 0]))
  rw [truncatedDecode]
  simp

private def blocks (heap : Heap) := heap.blocks.map fun block =>
  (block.base, block.size, block.alignment, block.live, block.owned, block.bytes)
private def sameHeap (before after : Heap) : Bool :=
  before.nextAddress == after.nextAddress && before.remaining == after.remaining &&
    blocks before == blocks after
private def cells (state : State) := state.cells.map fun cell => (cell.id, cell.value)
private def callerFrame (before after : State) : Bool :=
  before.locals == after.locals &&
    cells before == (cells after).take before.cells.length &&
    decide (before.nextCell ≤ after.nextCell) &&
    before.local? 100 == after.local? 100 && after.i32ArrayViews.length == 0 &&
    before.world.standardOutput == after.world.standardOutput &&
    before.world.standardError == after.world.standardError && before.world.calls == after.world.calls

private def rejectedAndFramed (input : Arguments) : Bool :=
  match evalExpr 128 extractedProgram countOnly input.call with
  | .done (.signed .i32 result) after =>
      result == -1 && sameHeap countOnly.heap after.heap && callerFrame countOnly after
  | _ => false

private def trappedAndFramed (before : State) (reason : Trap) : Bool :=
  match evalExpr 128 extractedProgram before negativeId.call with
  | .trapped actual after =>
      actual == reason && sameHeap before.heap after.heap && callerFrame before after
  | _ => false

#eval (do
  unless rejectedAndFramed negativeId do
    throw (IO.userError "negative-ID append did not reject with four-byte count/caller frame")
  unless rejectedAndFramed invalidResult do
    throw (IO.userError "valid_result append rejection lost its count/caller frame")
  unless trappedAndFramed absentCount .invalidPointer do
    throw (IO.userError "negative ID bypassed the absent mandatory count read")
  unless trappedAndFramed truncatedCount .rawMemoryBounds do
    throw (IO.userError "negative ID bypassed the truncated mandatory count decode")
  IO.println "actual catalog append outer fixtures: 4 passed" : IO Unit)

#print axioms negativeIdRejected
#print axioms invalidResultRejected
#print axioms absentCountNotAdmitted
#print axioms truncatedCountNotAdmitted

end IRCatalogAppendOuterTests
