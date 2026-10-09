import verified_compiler.tests.direct_match_arm
import Lanius.Semantics.LoopRun

namespace MatchArmsProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceExpressionTreeProof IRBuilderNavigationProof
open SourceIdentifierProof MatchArmProof

private def source := MatchBindingsProof.source
private def guard : Expr := (source.whileLoop 0).1
def armLoop : Stmt := .whileLoop guard armBody
attribute [local simp] source MatchBindingsProof.sourceBindings Function.bindingId

/-- The arm's observable specification. Its native representation below is
    independent of execution; no second tree is emitted or validated. -/
structure Arm (reference : Heap) where
  pattern : MatchArmProof.Pattern reference
  names : List (Name reference)
  body : List UInt8
def Arm.output (arm : Arm reference) : List UInt8 := bytes arm.pattern arm.names arm.body
def output (arms : List (Arm reference)) : List UInt8 := arms.flatMap Arm.output
def Arm.Represents (tree : Ready region { heap := reference }) (metadata : Metadata) (typeId : Nat)
    (arm : Arm reference) (index : Nat) : Prop :=
  arm.pattern.Matches metadata typeId ∧ index < region.count ∧
    region.events index = IRShapeProof.armEvent arm.pattern.ordinal arm.names.length ∧
    arm.names.length < 2 ^ 31 ∧
    MatchBindingsProof.Represents tree metadata.names metadata.unit arm.names (index + 1)
def Represents (tree : Ready region { heap := reference }) (metadata : Metadata) (typeId : Nat) :
    List (Arm reference) → Int → Prop
  | [], _ => True
  | arm :: rest, index => 0 ≤ index ∧ arm.Represents tree metadata typeId index.toNat ∧
      Represents tree metadata typeId rest (tree.ends index.toNat)

/-- Open body contracts for an internal traversal step. These are deliberately
    separate from the native representation predicate and closed by induction. -/
def BodyWriters (tree : Ready region { heap := reference }) (metadata : Metadata) :
    List (Arm reference) → Int → Prop
  | [], _ => True
  | arm :: rest, index => Writer Context.expressionCall reference tree.value
      (MatchBindingsProof.bodyIndex tree arm.names (index.toNat + 1)) arm.body (.fixed metadata) ∧
      BodyWriters tree metadata rest (tree.ends index.toNat)

/-- Traverse the actual outer arm loop. The final expression induction supplies
    all body contracts; setup and progress are proved from native data. -/
theorem actualArmsStep (input : Input base region) (arms : List (Arm input.reference))
    (initial : LoopState input current front child ordinal)
    (represented : Represents input.tree input.context.metadata input.typeId arms child)
    (writers : BodyWriters input.tree input.context.metadata arms child)
    (children : arms = [] ∨ input.tree.Children input.matchIndex (ordinal + 1) arms.length child.toNat)
    (ordered : arms ≠ [] → input.matchIndex < child.toNat)
    (count : ordinal + arms.length = input.armCount) (fits : input.armCount < 2 ^ 31)
    (room : input.context.position + (front ++ output arms).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current armLoop .next after ∧
      LoopState input after (front ++ output arms) (if arms = [] then child else -1) input.armCount := by
  induction arms generalizing current front child ordinal with
  | nil =>
      have ordinalIs : ordinal = input.armCount := by simpa using count
      core_facts 1 [input, initial]
      have stopped : RunsExpr extractedProgram current guard (.boolean false) current := by
        subst ordinal
        core_run
      exact ⟨current, .whileFalse stopped, by simpa [output, ordinalIs] using initial⟩
  | cons arm rest ih =>
      obtain ⟨nonnegative, ⟨naming, inside, event, countFits, bindings⟩, representedRest⟩ := represented
      obtain ⟨body, writersRest⟩ := writers
      have live : LoopState input current front child.toNat ordinal := by
        simpa only [Int.toNat_of_nonneg nonnegative] using initial
      have chain := children.resolve_left (by simp)
      have forward := ordered (by simp)
      core_facts 1 [input, initial]
      have condition : RunsExpr extractedProgram current guard (.boolean true) current := by
        have smaller : ordinal < input.armCount := by simp only [List.length_cons] at count; omega
        core_run
      obtain ⟨middle, iteration, next⟩ := actualArmStep input live arm.pattern naming arm.names arm.body
        inside event bindings body rfl chain forward countFits
        (by simp only [List.length_cons] at count; omega)
        (by simp only [output, List.flatMap_cons, Arm.output, List.length_append] at room ⊢; omega)
      let nextChild : Int := if rest.length = 0 then -1 else input.tree.ends child.toNat
      have restRep : Represents input.tree input.context.metadata input.typeId rest nextChild := by
        by_cases empty : rest = []
        · simp [empty, Represents]
        · have positive : rest.length ≠ 0 := by simpa using empty
          simpa only [nextChild, if_neg positive] using representedRest
      have restWriters : BodyWriters input.tree input.context.metadata rest nextChild := by
        by_cases empty : rest = []
        · simp [empty, BodyWriters]
        · have positive : rest.length ≠ 0 := by simpa using empty
          simpa only [nextChild, if_neg positive] using writersRest
      have restChain : rest = [] ∨ input.tree.Children input.matchIndex
          (ordinal + 1 + 1) rest.length nextChild.toNat := by
        by_cases empty : rest = []
        · exact Or.inl empty
        · have positive : rest.length ≠ 0 := by simpa using empty
          cases chain with
          | cons _ _ _ _ tail => exact Or.inr (by simpa only [Ready.Children, nextChild, if_neg positive] using tail)
      have restOrder : rest ≠ [] → input.matchIndex < nextChild.toNat := by
        intro empty
        have positive : rest.length ≠ 0 := by simpa using empty
        cases chain with
        | cons _ _ advance _ _ => simp only [nextChild, if_neg positive]; omega
      obtain ⟨after, remaining, final⟩ := ih next restRep restWriters restChain restOrder
        (by simp only [List.length_cons] at count; omega)
        (by simpa only [output, List.flatMap_cons, Arm.output, List.append_assoc] using room)
      refine ⟨after, .whileStep condition iteration (Or.inl rfl) remaining, ?_⟩
      by_cases empty : rest = []
      · simpa [output, List.flatMap_cons, Arm.output, List.append_assoc, empty, nextChild] using final
      · simpa [output, List.flatMap_cons, Arm.output, List.append_assoc, empty] using final

#print axioms actualArmsStep

end MatchArmsProof
