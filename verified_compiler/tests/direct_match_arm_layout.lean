import verified_compiler.tests.direct_match_bindings
import Lanius.Semantics.NaturalArithmetic

namespace MatchArmLayoutProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory
open IRShapeProof IRChildrenProof IRBuilderNavigationProof MatchBindingsProof

private theorem classifiedArm (variant count : Int)
    (classified : Classifies (armEvent variant count)
      (shapeValue (kindValue kind) arity (ruleValue rule))) :
    shapeValue (kindValue kind) arity (ruleValue rule) = armShape variant count := by
  generalize shape : shapeValue (kindValue kind) arity (ruleValue rule) = result at classified
  cases classified with
  | arm => rfl
  | fixed listed => simp [fixedShapes, armEvent, armValue, shapeValue] at listed
  | payload listed => simp [payloadShapes, armEvent, armValue, shapeValue] at listed
  | counted listed => simp [countedShapes, armEvent, armValue, shapeValue] at listed

/-- An existing builder tree supplies the real arm's child rule and count,
    including rejection of wildcard bindings and signed count overflow. -/
theorem armLayout {variant : Int} {count : Nat} (tree : Ready region state) (inside : parent < region.count)
    (event : region.events parent = armEvent variant count) (bounded : count < 2 ^ 31) :
    -1 ≤ variant ∧ (variant = -1 → count = 0) ∧ count + 1 < 2 ^ 31 ∧
      region.arities parent = (count + 1 : Nat) ∧ region.rules parent = .BindingsThenExpression ∧
      tree.Children parent 0 (count + 1) (parent + 1) := by
  have classified := region.classified parent inside
  rw [event] at classified
  have layout := classifiedArm variant count classified
  have nonnegative := (tree.suffix parent (Nat.zero_le _) inside).1
  unfold armShape at layout
  split at layout
  · simp [shapeValue] at layout
    omega
  · rename_i valid
    simp [shapeValue, kindValue, ruleValue] at layout
    have wrapped : 0 ≤ wrapSigned extractedProgram.target .i32 ((count : Int) + 1) := by omega
    have fits := i32_succ_bound extractedProgram.target count bounded wrapped
    have normal := wrapSigned_i32_nat_lt extractedProgram.target (count + 1) fits
    simp only [Int.natCast_add, Int.natCast_one] at normal
    have arity : region.arities parent = (count + 1 : Nat) := by omega
    have rule : region.rules parent = .BindingsThenExpression := by
      cases kind : region.rules parent <;> simp_all [ruleValue]
    refine ⟨by omega, by omega, fits, arity, rule, ?_⟩
    simpa only [arity, Int.toNat_natCast] using tree.childrenStart inside

/-- The actual child reader returns the first binding/body node of this arm.
    The positive arity is derived from its event and the builder, not supplied. -/
theorem actualFirstArmChild {variant : Int} {count : Nat} (tree : Ready region state)
    (inside : parent < region.count) (event : region.events parent = armEvent variant count)
    (bounded : count < 2 ^ 31) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (tree.firstChildCall parent)
      (.signed .i32 (parent + 1 : Nat)) after ∧ PureFrame state after := by
  obtain ⟨_, _, _, arity, _, _⟩ := armLayout tree inside event bounded
  have positive : ¬ region.arities parent ≤ 0 := by rw [arity]; omega
  simpa only [Ready.firstIndex, if_neg positive, Int.natCast_add, Int.natCast_one] using
    tree.firstChild inside formed

private theorem finalChild (tree : Ready region { heap := reference }) (names : List (SourceIdentifierProof.Name reference))
    (children : tree.Children parent ordinal (names.length + 1) child) (count : ordinal + names.length = total)
    (arity : region.arities parent = (total + 1 : Nat)) (rule : region.rules parent = .BindingsThenExpression) :
    let body := bodyIndex tree names child
    body < region.count ∧ region.kinds body = .ExpressionNode := by
  induction names generalizing child ordinal with
  | nil =>
      cases children with
      | cons inside kind _ _ _ =>
        simp only [arity, rule, Int.toNat_natCast, expectedKind] at kind
        have final : (ordinal : Int) = (total + 1 : Nat) - (1 : Int) := by simp only [List.length_nil] at count; omega
        simpa only [bodyIndex, if_pos final] using And.intro inside kind
  | cons name rest ih =>
      cases children with
      | cons _ _ _ _ remaining =>
        exact ih remaining (by simp only [List.length_cons] at count; omega)

/-- The real arm event discharges the traversal's initial child-chain
    obligation. The returned body node is now known to be an expression. -/
theorem actualArmBindings (input : Input base region) (names : List (SourceIdentifierProof.Name input.reference))
    (initial : LoopState input current front (input.parent + 1) 0)
    (inside : input.parent < region.count)
    (event : region.events input.parent = armEvent input.variant input.count)
    (count : names.length = input.count)
    (represented : Represents input.tree input.context.names input.context.unit names (input.parent + 1))
    (room : input.context.position + (front ++ bytes names).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current bindingLoop .next after ∧
      LoopState input after (front ++ bytes names) (bodyIndex input.tree names (input.parent + 1)) input.count ∧
      bodyIndex input.tree names (input.parent + 1) < region.count ∧
      region.kinds (bodyIndex input.tree names (input.parent + 1)) = .ExpressionNode := by
  obtain ⟨_, _, _, arity, rule, children⟩ := armLayout input.tree inside event input.fits
  rw [← count] at children
  have length : 0 + names.length = input.count := by simpa using count
  obtain ⟨after, run, final⟩ := actualBindings input names initial represented children (by omega) length room
  exact ⟨after, run, final, finalChild input.tree names children length arity rule⟩

#print axioms armLayout
#print axioms actualFirstArmChild
#print axioms actualArmBindings

/-- Invalid metadata, including the signed-overflow edge of count + body. -/
def BadArm (variant count : Int) : Prop :=
  count < 0 ∨ variant < -1 ∨ (variant = -1 ∧ count ≠ 0) ∨ count = 2147483647

private theorem noMalformedTree (tree : Ready region state) (inside : parent < region.count)
    (event : region.events parent = armEvent variant count) (bad : BadArm variant count) : False := by
  rcases bad with negative | ordinal | wildcard | overflow
  all_goals try {
    have classified := region.classified parent inside
    rw [event] at classified
    have layout := classifiedArm variant count classified
    have invalid : count ≤ -1 ∨ variant < -1 ∨ (variant = -1 ∧ count ≠ 0) := by omega
    simp only [armShape, if_pos invalid] at layout
    simp [shapeValue] at layout
    have nonnegative := (tree.suffix parent (Nat.zero_le _) inside).1
    omega }
  subst count
  have layout := armLayout (count := 2147483647) tree inside event (by decide)
  omega

/-- A malformed arm forces the actual builder's rejection result. Allocation
    failures also remain rejection; an accepted tree is never a premise. -/
theorem actualMalformedArmRejects (region : IRBuilderCallProof.Region original)
    (inside : parent < region.count) (event : region.events parent = armEvent variant count)
    (bad : BadArm variant count) (formed : original.CellsWellFormed)
    (unique : HeapBlockBasesUnique original.heap) (views : original.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram original region.call IRBuilderProof.emptyTree after ∧
      FreshCellFrame original after := by
  obtain ⟨value, after, run, cells, rejected | ⟨tree, accepted⟩⟩ := actualReadyCall region formed unique views
  · exact ⟨after, rejected ▸ run, cells⟩
  · exact False.elim (noMalformedTree tree inside event bad)

#print axioms actualMalformedArmRejects

end MatchArmLayoutProof
