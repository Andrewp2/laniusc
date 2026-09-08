import Lanius.Compiler.ParserDerivation

namespace Lanius.Extraction.ParserTreeDerivation

open Lanius.Compiler.Parser

/-- A retained reader reference denotes this exact materialized child. State
    children keep their actual recursive computation, not only grammar validity. -/
inductive ChildExpansion (grammar : IndexedGrammar) (workspace : LogicalWorkspace) :
    Child → Lanius.Compiler.Parser.ParseTree → Prop where
  | token : ChildExpansion grammar workspace (.token token kind) (.terminal token kind)
  | state
      (found : workspace.state? childId = some state)
      (productionBound : state.production < grammar.productionCount)
      (complete : state.dot = (grammar.productionAt ⟨state.production, productionBound⟩).rhs.length)
      (enough : childId < fuel)
      (computed : materializeStatePrefix? grammar workspace fuel childId = some trees) :
      ChildExpansion grammar workspace (.state childId)
        (.nonterminal state.production (grammar.productionAt ⟨state.production, productionBound⟩).lhs
          state.origin state.position trees)

/-- Source-order correspondence, including repeated occurrences of one state. -/
inductive ChildrenExpansion (grammar : IndexedGrammar) (workspace : LogicalWorkspace) :
    List Child → List Lanius.Compiler.Parser.ParseTree → Prop where
  | nil : ChildrenExpansion grammar workspace [] []
  | cons : ChildExpansion grammar workspace child tree → ChildrenExpansion grammar workspace children trees →
      ChildrenExpansion grammar workspace (child :: children) (tree :: trees)

theorem ChildrenExpansion.append_one (matched : ChildrenExpansion grammar workspace children trees)
    (last : ChildExpansion grammar workspace child tree) :
    ChildrenExpansion grammar workspace (children ++ [child]) (trees ++ [tree]) := by
  induction matched with
  | nil => exact .cons last .nil
  | cons head tail ih => exact .cons head ih

theorem ChildrenExpansion.length (matched : ChildrenExpansion grammar workspace children trees) :
    children.length = trees.length := by
  induction matched with
  | nil => rfl
  | cons head tail ih => exact congrArg Nat.succ ih

theorem ChildrenExpansion.lookup {index : Nat}
    (matched : ChildrenExpansion grammar workspace children trees)
    (found : children[index]? = some child) :
    ∃ tree, trees[index]? = some tree ∧ ChildExpansion grammar workspace child tree := by
  induction matched generalizing index with
  | nil => simp at found
  | @cons current tree children trees head tail ih =>
    cases index with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst current
      exact ⟨tree, rfl, head⟩
    | succ index => exact ih found

/-- The two existing workspace readers agree on every child occurrence, even
    when their sufficient fuel budgets differ. This is the recursive execution
    proof's bridge from copied state IDs to the selected semantic tree. -/
theorem children_match
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (readerEnough : stateId < readerFuel)
    (treeEnough : stateId < treeFuel)
    (read : derivationChildren? workspace readerFuel stateId = some children)
    (materialized : materializeStatePrefix? grammar workspace treeFuel stateId = some trees) :
    ChildrenExpansion grammar workspace children trees := by
  induction stateId using Nat.strongRecOn generalizing state readerFuel treeFuel children trees with
  | ind stateId ih =>
    cases readerFuel with
    | zero => omega
    | succ readerFuel =>
      cases treeFuel with
      | zero => omega
      | succ treeFuel =>
        cases sound stateId state found with
        | fresh productionBound =>
          simp [derivationChildren?, found, freshSeed, StateSeed.atPosition] at read
          simp [materializeStatePrefix?, found, freshSeed, StateSeed.atPosition] at materialized
          subst children trees
          exact .nil
        | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
          rename_i previousId previous kind finish
          obtain ⟨previousChildren, previousRead, _⟩ :=
            sound.derivationChildren_complete previousFound (show previousId < readerFuel by omega)
          obtain ⟨previousTrees, previousMaterialized, _⟩ :=
            sound.materializeStatePrefix?_complete previousFound productionBound (show previousId < treeFuel by omega)
          have previousMatched := ih previousId previousBefore previousFound (by omega) (by omega)
            previousRead previousMaterialized
          simp [derivationChildren?, found, EarleyState.advanceSeed, StateSeed.atPosition, previousRead] at read
          simp [materializeStatePrefix?, found, EarleyState.advanceSeed, StateSeed.atPosition,
            previousMaterialized] at materialized
          subst children trees
          exact previousMatched.append_one .token
        | nonterminal previousFound previousBefore childFound childBefore productionBound
            childProductionBound symbolFound childLhsBound childOrigin childComplete =>
          rename_i previousId previous childId child
          obtain ⟨previousChildren, previousRead, _⟩ :=
            sound.derivationChildren_complete previousFound (show previousId < readerFuel by omega)
          obtain ⟨previousTrees, previousMaterialized, _⟩ :=
            sound.materializeStatePrefix?_complete previousFound productionBound (show previousId < treeFuel by omega)
          obtain ⟨childTrees, childMaterialized, _⟩ :=
            sound.materializeStatePrefix?_complete childFound childProductionBound (show childId < treeFuel by omega)
          have previousMatched := ih previousId previousBefore previousFound (by omega) (by omega)
            previousRead previousMaterialized
          simp [derivationChildren?, found, EarleyState.advanceSeed, StateSeed.atPosition, previousRead] at read
          simp [materializeStatePrefix?, found, EarleyState.advanceSeed, StateSeed.atPosition,
            previousMaterialized, childFound, childProductionBound, childMaterialized] at materialized
          subst children trees
          exact previousMatched.append_one (.state childFound childProductionBound childComplete (by omega) childMaterialized)

/-- Lookup for a recursive occurrence exposes both the exact subtree and the
    strict state-ID decrease needed by the recursive call induction. -/
theorem state_child {index : Nat}
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (readerEnough : stateId < readerFuel)
    (treeEnough : stateId < treeFuel)
    (read : derivationChildren? workspace readerFuel stateId = some children)
    (materialized : materializeStatePrefix? grammar workspace treeFuel stateId = some trees)
    (childAt : children[index]? = some (.state childId)) :
    childId < stateId ∧ ∃ child childTrees fuel,
      workspace.state? childId = some child ∧
      ∃ productionBound : child.production < grammar.productionCount,
        child.dot = (grammar.productionAt ⟨child.production, productionBound⟩).rhs.length ∧
        childId < fuel ∧ materializeStatePrefix? grammar workspace fuel childId = some childTrees ∧
        trees[index]? = some (.nonterminal child.production
          (grammar.productionAt ⟨child.production, productionBound⟩).lhs child.origin child.position childTrees) := by
  have earlier := (sound.derivationChildren_state_before found readerEnough read (List.mem_of_getElem? childAt)).1
  obtain ⟨tree, treeAt, expanded⟩ := (children_match sound found readerEnough treeEnough read materialized).lookup childAt
  cases expanded with
  | state childFound productionBound complete enough computed =>
    exact ⟨earlier, _, _, _, childFound, productionBound, complete, enough, computed, treeAt⟩

end Lanius.Extraction.ParserTreeDerivation
