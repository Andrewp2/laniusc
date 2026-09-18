import Lanius.Extraction.Parser.Tree.Layout

namespace Lanius.Extraction.ParserTreeBounds
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout

/-- Words include the three-word reference from a node's parent. Keeping
that charge on each child makes forest costs compositional; the root's actual
record storage is three words less. Terminals allocate no node or call frame. -/
structure Cost where
  nodes : Nat := 0
  words : Nat := 0
  depth : Nat := 0
deriving DecidableEq, Repr, Inhabited

def Cost.Le (left right : Cost) : Prop :=
  left.nodes ≤ right.nodes ∧ left.words ≤ right.words ∧ left.depth ≤ right.depth

instance : LE Cost := ⟨Cost.Le⟩
instance (left right : Cost) : Decidable (left ≤ right) :=
  inferInstanceAs (Decidable (left.nodes ≤ right.nodes ∧ left.words ≤ right.words ∧ left.depth ≤ right.depth))

def Cost.zero : Cost := ⟨0, 0, 0⟩
def Cost.terminal : Cost := ⟨0, 3, 0⟩
def Cost.join (left right : Cost) : Cost :=
  ⟨left.nodes + right.nodes, left.words + right.words, max left.depth right.depth⟩
def Cost.node (children : Cost) : Cost :=
  ⟨children.nodes + 1, children.words + 7, children.depth + 1⟩

variable {left middle right first second largerFirst largerSecond : Cost}

theorem Cost.refl (cost : Cost) : cost ≤ cost := ⟨Nat.le_refl _, Nat.le_refl _, Nat.le_refl _⟩
theorem Cost.trans (first : left ≤ middle) (second : middle ≤ right) : left ≤ right :=
  ⟨Nat.le_trans first.1 second.1, Nat.le_trans first.2.1 second.2.1, Nat.le_trans first.2.2 second.2.2⟩
theorem Cost.zero_le (cost : Cost) : zero ≤ cost := ⟨Nat.zero_le _, Nat.zero_le _, Nat.zero_le _⟩

theorem Cost.join_mono (left : first ≤ largerFirst) (right : second ≤ largerSecond) :
    first.join second ≤ largerFirst.join largerSecond := by
  exact ⟨Nat.add_le_add left.1 right.1, Nat.add_le_add left.2.1 right.2.1,
    by have h := left.2.2; have h' := right.2.2; dsimp only [join]; omega⟩

theorem Cost.node_mono (bound : first ≤ second) : first.node ≤ second.node :=
  ⟨Nat.add_le_add_right bound.1 _, Nat.add_le_add_right bound.2.1 _, Nat.add_le_add_right bound.2.2 _⟩

@[simp] theorem Cost.join_zero (cost : Cost) : cost.join zero = cost := by cases cost; simp [join, zero]
@[simp] theorem Cost.zero_join (cost : Cost) : zero.join cost = cost := by cases cost; simp [join, zero]
theorem Cost.join_assoc (first second third : Cost) :
    (first.join second).join third = first.join (second.join third) := by
  simp [join, Nat.add_assoc, Nat.max_assoc]

theorem Cost.right_le_join (left right : Cost) : right ≤ left.join right := by
  exact ⟨Nat.le_add_left _ _, Nat.le_add_left _ _, Nat.le_max_right _ _⟩

mutual
  def treeCost : Lanius.Compiler.Parser.ParseTree → Cost
    | .terminal _ _ => Cost.terminal
    | .nonterminal _ _ _ _ children => (forestCost children).node
  def forestCost : List Lanius.Compiler.Parser.ParseTree → Cost
    | [] => Cost.zero
    | tree :: trees => (treeCost tree).join (forestCost trees)
end

mutual
  theorem treeCost_layout (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      (treeCost tree).nodes = (treeFrom nodeBase wordBase tree).offsets.length ∧
      (treeCost tree).words = treeWords tree + 3 ∧ (treeCost tree).depth = treeDepth tree := by
    cases tree with
    | terminal token kind => exact ⟨rfl, rfl, rfl⟩
    | nonterminal production nonterminal start finish children =>
      obtain ⟨nodes, words, depth⟩ := forestCost_layout children nodeBase (wordBase + 4 + children.length * 3)
      simp only [treeCost, treeFrom, Cost.node, List.length_append, List.length_singleton,
        treeWords, treeDepth]
      exact ⟨by omega, by omega, by omega⟩
  termination_by sizeOf tree

  theorem forestCost_layout (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      (forestCost trees).nodes = (forestFrom nodeBase wordBase trees).offsets.length ∧
      (forestCost trees).words = forestWords trees + trees.length * 3 ∧
      (forestCost trees).depth = forestDepth trees := by
    cases trees with
    | nil => exact ⟨rfl, rfl, rfl⟩
    | cons tree trees =>
      obtain ⟨headNodes, headWords, headDepth⟩ := treeCost_layout tree nodeBase wordBase
      obtain ⟨tailNodes, tailWords, tailDepth⟩ := forestCost_layout trees
        (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
        (wordBase + (treeFrom nodeBase wordBase tree).words.length)
      simp only [forestCost, forestFrom, Cost.join, List.length_append, forestWords,
        List.length_cons, forestDepth]
      exact ⟨by omega, by omega, by rw [headDepth, tailDepth]⟩
  termination_by sizeOf trees
end

/-- Exactly the three sufficient-resource premises of the existing public
materializer success theorem, independent of runtime state or execution. -/
def Fits (tree : Lanius.Compiler.Parser.ParseTree) (recordWords nodeSlots depth : Nat) : Prop :=
  treeDepth tree ≤ depth ∧ (treeFrom 0 0 tree).words.length ≤ recordWords ∧
    (treeFrom 0 0 tree).offsets.length ≤ nodeSlots

theorem Fits.of_cost (bounded : treeCost tree ≤ budget)
    (nodes : budget.nodes ≤ nodeSlots) (words : budget.words ≤ recordWords + 3)
    (depth : budget.depth ≤ limit) : Fits tree recordWords nodeSlots limit := by
  obtain ⟨nodeCount, wordCount, depthCount⟩ := treeCost_layout tree 0 0
  rw [Fits, tree_words_length]
  change (treeCost tree).nodes ≤ budget.nodes ∧ (treeCost tree).words ≤ budget.words ∧
    (treeCost tree).depth ≤ budget.depth at bounded
  exact ⟨by omega, by omega, by omega⟩

end Lanius.Extraction.ParserTreeBounds
