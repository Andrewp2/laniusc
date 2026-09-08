import Lanius.Semantics.CellRenaming.State
import Lanius.Semantics.CellRenaming.CallState
import Lanius.Semantics.CellRenaming.Scalar
import Lanius.Semantics.CellRenaming.Views
import Lanius.Semantics.CellRenaming.Pointers
import Lanius.Semantics.CellRenaming.Pattern
import Lanius.Semantics.CellRenaming.Literal
import Lanius.Semantics.CellRenaming.Execution.Arguments
import Lanius.Semantics.CellRenaming.Execution.Match
import Lanius.Semantics.CellRenaming.Execution.Place
import Lanius.Semantics.CellRenaming.Execution.Iteration
import Lanius.Semantics.CellRenaming.Execution.Statement
import Lanius.Semantics.CellRenaming.Execution.Call
import Lanius.Semantics.CellRenaming.Execution.Scalars
import Lanius.Semantics.CellRenaming.Execution.Aggregates
import Lanius.Semantics.CellRenaming.Execution.References
import Lanius.Semantics.CellRenaming.Execution
import Lanius.Semantics.CellRenaming.Execution.Check
import Lanius.Semantics.CellRenaming.Ownership
import Lanius.Semantics.CellRenaming.Effects

open Lanius Lanius.Core Lanius.Semantics Lanius.Semantics.CellRenaming

-- Cover disjoint, identical, swapped, and partially overlapping placements.
private def placementChecks : Bool :=
  (List.ofFn (fun index : Fin 8 => index)).all fun left =>
    (List.ofFn (fun index : Fin 8 => index)).all fun right =>
      if left.val = right.val then true else
        let rename := Permutation.placePair 0 1 left.val right.val
          (by decide) (by decide) left.isLt right.isLt
        rename.forward 0 == left.val && rename.forward 1 == right.val &&
          rename.forward 8 == 8 && rename.forward 9 == 9

example : placementChecks = true := by decide

private def overlapping : Permutation 8 :=
  Permutation.placePair 0 1 1 7 (by decide) (by decide) (by decide) (by decide)

example : value overlapping.forward
    (.array [.slice (.scalar (.signed .i32)) 0 [] 0 3,
      .reference (.scalar (.signed .i32)) 1 [], .pointer 32]) =
    .array [.slice (.scalar (.signed .i32)) 1 [] 0 3,
      .reference (.scalar (.signed .i32)) 7 [], .pointer 32] := by rfl

example (before : State) :
    state overlapping.backward (state overlapping.forward before) = before :=
  state_leftInverse _ _ overlapping.leftInverse before

example : Source.expression (.value (.array [.reference .unit 0 []])) = false := by decide
example : Source.statement (.forRange 0 (.value (.signed .i32 0))
    (some (.value (.slice .unit 1 [] 0 1))) false .skip) = false := by decide
example : Source.expression (.borrow .unit (.index (.local 0)
    (.value (.reference .unit 1 [])))) = false := by decide
example : Source.expression (.value (.array [.signed .i32 7, .pointer 32])) = true := by decide
example : Lanius.Semantics.CellRenaming.Execution.sourceBody none = false := by decide

#print axioms Lanius.Semantics.CellRenaming.Permutation.placePair_left
#print axioms Lanius.Semantics.CellRenaming.state_leftInverse
#print axioms Lanius.Semantics.CellRenaming.state_wellFormed
#print axioms Lanius.Semantics.CellRenaming.allocateTemporary
#print axioms Lanius.Semantics.CellRenaming.assignLocal
#print axioms Lanius.Semantics.CellRenaming.writeResolvedPlace
#print axioms Lanius.Semantics.CellRenaming.bindLocals
#print axioms Lanius.Semantics.CellRenaming.binary
#print axioms Lanius.Semantics.CellRenaming.syncToHeap
#print axioms Lanius.Semantics.CellRenaming.syncFromHeap
#print axioms Lanius.Semantics.CellRenaming.mapI32ArrayView
#print axioms Lanius.Semantics.CellRenaming.mapI32SliceDataPtr
#print axioms Lanius.Semantics.CellRenaming.mapStringDataPtr
#print axioms Lanius.Semantics.CellRenaming.mapRawI32Slice
#print axioms Lanius.Semantics.CellRenaming.matchPattern
#print axioms Lanius.Semantics.CellRenaming.outcome_leftInverse
#print axioms Lanius.Semantics.CellRenaming.literal_fixed
#print axioms Lanius.Semantics.CellRenaming.Execution.zero
#print axioms Lanius.Semantics.CellRenaming.Execution.expressions
#print axioms Lanius.Semantics.CellRenaming.Execution.arms
#print axioms Lanius.Semantics.CellRenaming.Execution.place
#print axioms Lanius.Semantics.CellRenaming.Execution.forValues
#print axioms Lanius.Semantics.CellRenaming.Execution.forRange
#print axioms Lanius.Semantics.CellRenaming.Execution.statement
#print axioms Lanius.Semantics.CellRenaming.Execution.assignCell_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.writePlace_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.syncToHeap_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.syncFromHeap_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.arrayView_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.slicePointer_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.stringPointer_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.rawSlice_nextCell
#print axioms Lanius.Semantics.CellRenaming.Execution.call
#print axioms Lanius.Semantics.CellRenaming.Execution.constant
#print axioms Lanius.Semantics.CellRenaming.Execution.castExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.unaryExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.binaryExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.arrayExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.structExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.enumExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.matchExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.fieldExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.indexExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.localExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.borrowExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.dereferenceExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.assignExpression
#print axioms Lanius.Semantics.CellRenaming.Execution.atFuel
#print axioms Lanius.Semantics.CellRenaming.Execution.evaluates
#print axioms Lanius.Semantics.CellRenaming.Execution.executes
#print axioms Lanius.Semantics.CellRenaming.Execution.sourceProgram_invariant
#print axioms Lanius.Semantics.CellRenaming.world_owns
#print axioms Lanius.Semantics.CellRenaming.world_pair
#print axioms Lanius.Semantics.CellRenaming.representation
#print axioms Lanius.Semantics.CellRenaming.representation_inverse
#print axioms Lanius.Semantics.CellRenaming.storeEffect
#print axioms Lanius.Semantics.CellRenaming.modifiesOnly
