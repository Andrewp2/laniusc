import verified_compiler.tests.direct_ir_children
import Lanius.Extraction.OutputPacking.Byte

namespace IRChildrenTests

open Lanius Lanius.Core Lanius.Semantics IRShapeProof IRChildrenProof

private def leaf : Value := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionPointerNull» []
private def leafTag : Nat := match leaf with
  | .enumeration _ variant _ => variant
  | _ => 0
private def leafType : Ty := match leaf with
  | .enumeration id _ _ => .enumeration id
  | _ => .unit
private theorem leafWidth : NativeLayout.valueWords? extractedProgram leafType = some 5 := by decide +kernel
private def sample : State := { heap := { blocks := [
  { base := 16, size := 40, alignment := 8, bytes := encodeNatLE 4 leafTag ++ List.replicate 36 0 },
  { base := 64, size := 4, alignment := 4, bytes := i32Bytes 1 }], nextAddress := 68 } }

-- Physical bytes and a represented event witness the input domain. No
-- successful evaluation or validator acceptance is assumed by the fixture.
private def input : Input sample := {
  count := 1, index := 0, arity := 0, eventsAddress := 48, eventsLength := 1, endsAddress := 64
  fits := by decide, inside := by decide, room := by decide
  parentKind := .ExpressionNode, rule := .NoChildren
  events := fun _ => leaf, kinds := fun _ => .ExpressionNode
  eventArities := fun _ => 0, eventRules := fun _ => .NoChildren, ends := fun _ => 1
  eventReads := by
    intro position inside
    have : position = 0 := by omega
    subst position
    change readRawSliceIndex extractedProgram sample leafType 48 1 0 = .ok leaf
    have width := leafWidth
    dsimp only [leafType, leaf] at width ⊢
    simp only [readRawSliceIndex, rawSliceElementAddress?, width]
    rfl
  endReads := by
    intro position inside
    have : position = 0 := by omega
    subst position
    rfl
  classified := by
    intro position inside
    exact .fixed (List.mem_append_left _ (List.mem_cons_self)) }

example : ∃ _valid : Input sample, True := ⟨input, trivial⟩

example : ∃ after, RunsExpr extractedProgram sample input.call (.signed .i32 1) after ∧ PureFrame sample after :=
  actualChildren input (by simp [State.CellsWellFormed, sample])

example : EndpointCorrect input 1 :=
  Or.inl ⟨1, rfl, ChildChain.nil⟩

example : ¬ EndpointCorrect input (-1) := by
  intro wrong
  rcases wrong with ⟨endpoint, impossible, _⟩ | ⟨_, missing⟩
  · omega
  · exact missing ⟨1, ChildChain.nil⟩

private def parent : Value := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryPositive» []
private def parentTag : Nat := match parent with
  | .enumeration _ variant _ => variant
  | _ => 0
private def childSample (word : BitVec 32) : State := { heap := { blocks := [
  { base := 16, size := 80, alignment := 8,
    bytes := encodeNatLE 4 leafTag ++ List.replicate 36 0 ++ encodeNatLE 4 parentTag ++ List.replicate 36 0 },
  { base := 112, size := 8, alignment := 4, bytes := i32Bytes word.toInt ++ i32Bytes word.toInt }], nextAddress := 120 } }

-- Nominal-slice pointers name the high word; elements advance downward.
-- The unary parent is at byte 56 and its leaf child at byte 16.
private def childInput (word : BitVec 32) : Input (childSample word) := {
  count := 2, index := 0, arity := 1, eventsAddress := 88, eventsLength := 2, endsAddress := 112
  fits := by decide, inside := by decide, room := by decide
  parentKind := .ExpressionNode, rule := .Expressions
  events := fun position => if position = 0 then parent else leaf
  kinds := fun _ => .ExpressionNode, eventArities := fun position => if position = 0 then 1 else 0
  eventRules := fun position => if position = 0 then .Expressions else .NoChildren
  ends := fun _ => word.toInt
  eventReads := by
    intro position inside
    change readRawSliceIndex extractedProgram (childSample word) leafType 88 2 position =
      .ok (if position = 0 then parent else leaf)
    have width := leafWidth
    dsimp only [leafType, leaf] at width ⊢
    have cases : position = 0 ∨ position = 1 := by omega
    rcases cases with rfl | rfl <;>
      simp only [readRawSliceIndex, rawSliceElementAddress?, width] <;> rfl
  endReads := by
    intro position inside
    apply Lanius.Semantics.readRawSliceIndex_i32Bytes extractedProgram _ inside
    have cases : position = 0 ∨ position = 1 := by omega
    rcases cases with rfl | rfl <;> rfl
  classified := by
    intro position inside
    have cases : position = 0 ∨ position = 1 := by omega
    rcases cases with rfl | rfl
    · exact .fixed (List.mem_cons_of_mem _ List.mem_cons_self)
    · exact .fixed List.mem_cons_self }

example : ∃ after, RunsExpr extractedProgram (childSample 2) (childInput 2).call (.signed .i32 2) after ∧
    PureFrame (childSample 2) after := actualChildren (childInput 2) (by simp [State.CellsWellFormed, childSample])

example : ∃ after, RunsExpr extractedProgram (childSample 1) (childInput 1).call (.signed .i32 (-1)) after ∧
    PureFrame (childSample 1) after := actualChildren (childInput 1) (by simp [State.CellsWellFormed, childSample])

example : ∃ after, RunsExpr extractedProgram (childSample 3) (childInput 3).call (.signed .i32 (-1)) after ∧
    PureFrame (childSample 3) after := actualChildren (childInput 3) (by simp [State.CellsWellFormed, childSample])

#print axioms leafWidth
#print axioms childInput

end IRChildrenTests
