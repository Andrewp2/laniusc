import verified_compiler.tests.direct_ir_catalog_construction
import verified_compiler.tests.direct_ir_catalog_copy_domain

namespace IRCatalogConstructionTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogAppendProof IRCatalogConstructionProof

/-- Original source bytes and caller state, before any catalog allocation. -/
def original (budget : Nat) : State :=
  let base : State := {
    heap := {
      blocks := [{ base := 16, size := 40, alignment := 8, bytes := List.replicate 40 0 }]
      nextAddress := 64
      remaining := some budget
    }
    world := { standardOutput := [88], standardError := [89] }
  }
  base.bindLocal 100 (.signed .i32 91)

private theorem formed (budget : Nat) : (original budget).CellsWellFormed := by
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]

private theorem below (budget : Nat) : HeapBlocksBelowNext (original budget).heap := by
  intro block member
  simp [original, State.bindLocal, State.bindCell] at member
  subst block
  change 16 + max 40 1 ≤ 64
  decide

private theorem unique (budget : Nat) : HeapBlockBasesUnique (original budget).heap := by
  intro left leftMember right rightMember _
  simp [original, State.bindLocal, State.bindCell] at leftMember rightMember
  exact leftMember.trans rightMember.symm

def catalog : Catalog := { memory := 64, capacity := 1 }

def allocated : State :=
  { original 164 with heap := (original 164).heap.allocatedBytes catalog.bytes 8 (some 60) }

example : (original 164).heap.allocate catalog.bytes 8 = .allocated catalog.memory allocated.heap := rfl
example : (original 103).heap.allocate catalog.bytes 8 = .exhausted (original 103).heap := rfl

theorem validSize : ∃ after,
    RunsExpr extractedProgram (original 164) (.call sizeSource.id [.value (.signed .i32 1)])
      (.signed .i32 104) after ∧ PureFrame (original 164) after := by
  have one : (1 : Int32).toInt = 1 := by decide
  have total : 8 + (1 : Int) * 96 = 104 := by decide
  simpa only [allocationBytes, if_pos (show Supported (1 : Int32) by decide), one, total] using
    actualSize (1 : Int32) (formed 164)

theorem invalidSize : ∃ after,
    RunsExpr extractedProgram (original 164) (.call sizeSource.id [.value (.signed .i32 0)])
      (.signed .i32 (-1)) after ∧ PureFrame (original 164) after := by
  have zero : (0 : Int32).toInt = 0 := by decide
  simpa only [allocationBytes, if_neg (show ¬Supported (0 : Int32) by decide), zero] using
    actualSize (0 : Int32) (formed 164)

/-- Consume the real constructor, deriving count zero and retention of source
    bytes from its actual heap effect, not an assumed initializer execution. -/
theorem constructorInitialized : ∃ after,
    RunsExpr extractedProgram allocated catalog.call catalog.value after ∧
    readRawSliceIndex extractedProgram after (.structure countId) 64 1 0 =
      .ok (.structure countId [.signed .i32 0]) ∧
    after.heap.loadBytes 16 40 = .ok (List.replicate 40 0) := by
  obtain ⟨after, run, effect⟩ := actualConstructor (before := allocated)
    (origin := (original 164).heap) (budget := some 60) catalog (by decide) (by rfl) (by rfl)
    (below 164) (unique 164) (by decide)
    (by change (original 164).CellsWellFormed; exact formed 164) (by rfl)
  refine ⟨after, run, ?_, ?_⟩
  · apply IRCatalogCountReadProof.fromScalarRead (by decide)
    rw [effect.2.2.2]
    rfl
  · rw [effect.2.2.2]
    rfl

/-- The CountCell bridge is inhabited even without readable stride padding. -/
private def fieldOnly : State := {
  heap := { blocks := [{ base := 256, size := 4, alignment := 8, bytes := i32Bytes (-1) }] } }

theorem fieldOnlyCount :
    readRawSliceIndex extractedProgram fieldOnly (.structure countId) 256 1 0 =
      .ok (.structure countId [.signed .i32 (-1)]) :=
  IRCatalogCountReadProof.fromScalarRead (by decide) (by rfl)

example : fieldOnly.heap.loadBytes 256 8 = .error .rawMemoryBounds := rfl

#print axioms validSize
#print axioms invalidSize
#print axioms constructorInitialized
#print axioms fieldOnlyCount

end IRCatalogConstructionTests
