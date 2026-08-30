import Lanius.FunctionalViewCoreStateful
import Lanius.FunctionalViewRenaming

namespace Lanius.FunctionalView.Core.Stateful

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful

/-! # Scoped renaming for Core slice actions -/

/-- The standard Core action language is functorial in its scoped local
    environment.  Slice bases and both value terms use the same embedding. -/
def actionRenamer : ActionRenamer actions where
  rename := fun embedding action =>
    match action with
    | .setI32Index base index value =>
        .setI32Index (embedding.slot base) (index.rename embedding)
          (value.rename embedding)

/-- Core slice-action evaluation depends only on the embedded projection of
    the environment. -/
theorem actionRenamer_sound (program : Program)
    (evaluateOperation : OperationEvaluator) :
    actionRenamer.Sound (termMachine evaluateOperation)
      (machineWith program evaluateOperation) := by
  intro source target embedding world small large related action
  cases action with
  | setI32Index base index value =>
      simp only [actionRenamer, machineWith, evaluateActionWith]
      rw [Term.evaluate_rename related index]
      cases indexResult : Term.evaluate (termMachine evaluateOperation) world
          small index with
      | error => rfl
      | ok result =>
          rcases result with ⟨indexValue, afterIndex⟩
          simp only [bind, Except.bind]
          rw [Term.evaluate_rename related value]
          cases valueResult : Term.evaluate (termMachine evaluateOperation)
              afterIndex small value with
          | error => rfl
          | ok result =>
              rcases result with ⟨replacement, afterValue⟩
              simp only [bind, Except.bind]
              rw [related base]

/-! ## Exact structural-Core preservation -/

/-- A larger Core-local layout realizes a smaller layout through an
    environment embedding. -/
def Layout.Extends (embedding : Embedding source target)
    (small : Layout source) (large : Layout target) : Prop :=
  ∀ index, large (embedding.slot index) = small index

/-- A closed equality of the finite projected layouts establishes the
    pointwise layout relation.  Concrete reified scopes can discharge the
    equality by computation without duplicating one case per local slot. -/
theorem Layout.Extends.ofFn
    {source target : Nat} {embedding : Embedding source target}
    {small : Layout source} {large : Layout target}
    (same : List.ofFn (fun index => large (embedding.slot index)) =
      List.ofFn small) :
    Layout.Extends embedding small large := by
  intro index
  have selected := congrArg (fun values => values[index.val]?) same
  have projectedBound : index.val <
      (List.ofFn (fun index => large (embedding.slot index))).length := by
    simpa using index.isLt
  have smallBound : index.val < (List.ofFn small).length := by
    simpa using index.isLt
  rw [List.getElem?_eq_getElem projectedBound,
    List.getElem?_eq_getElem smallBound] at selected
  simp only [Option.some.injEq] at selected
  rw [List.getElem_ofFn, List.getElem_ofFn] at selected
  simpa using selected

theorem Layout.Extends.push (related : Layout.Extends embedding small large)
    (id : VarId) :
    Layout.Extends embedding.push (small.push id) (large.push id) := by
  intro index
  refine Fin.lastCases ?_ (fun old => ?_) index
  · rw [Embedding.push_last]
    simp [Layout.push]
  · rw [Embedding.push_old]
    simpa [Layout.push] using related old

/-- Renaming a term and then converting it to Core is exactly the same as
    converting it under the projected compact layout. -/
theorem toCoreExpr_rename
    {source target : Nat} {embedding : Embedding source target}
    {small : Layout source} {large : Layout target}
    (related : Layout.Extends embedding small large)
    (term : Term Core.signature source) :
    Core.toCoreExpr large (term.rename embedding) =
      Core.toCoreExpr small term := by
  apply @Term.rec _ _
    (fun term => Core.toCoreExpr large (term.rename embedding) =
      Core.toCoreExpr small term)
    (fun terms => Core.toCoreExprs large
        (terms.map (Term.rename embedding)) = Core.toCoreExprs small terms)
  · intro reference
    cases reference with
    | slot index => simp [Term.rename, Core.toCoreExpr, Core.refToCoreExpr,
        Ref.rename, related index]
    | literal =>
        simp [Term.rename, Core.toCoreExpr, Core.refToCoreExpr, Ref.rename]
  · intro operation arguments argumentsIH
    simp only [Term.rename, Core.toCoreExpr]
    rw [argumentsIH]
  · intro left right leftIH rightIH
    simp only [Term.rename, Core.toCoreExpr, leftIH, rightIH]
  · intro left right leftIH rightIH
    simp only [Term.rename, Core.toCoreExpr, leftIH, rightIH]
  · rfl
  · intro head tail headIH tailIH
    simp only [List.map_cons, Core.toCoreExprs, headIH, tailIH]

theorem actionAdapter_rename
    {source target : Nat} {embedding : Embedding source target}
    {small : Layout source} {large : Layout target}
    (related : Layout.Extends embedding small large)
    (action : Action source) :
    actionAdapter.toCoreStmt large (actionRenamer.rename embedding action) =
      actionAdapter.toCoreStmt small action := by
  cases action with
  | setI32Index base index value =>
      simp only [actionRenamer, actionAdapter]
      rw [related base, toCoreExpr_rename related index,
        toCoreExpr_rename related value]

@[simp] theorem localCapacity_rename
    {source target : Nat} {embedding : Embedding source target}
    (command : Command Core.signature actions source) :
    localCapacity actionAdapter (command.rename actionRenamer embedding) =
      localCapacity actionAdapter command := by
  induction command generalizing target with
  | skip | setLocal | updateLocal | action | returnValue | breakLoop |
      continueLoop => rfl
  | sequence first second firstIH secondIH =>
      simp only [Command.rename, localCapacity, firstIH, secondIH]
  | letValue type initializer body bodyIH =>
      simp only [Command.rename, localCapacity]
      rw [bodyIH (embedding := embedding.push)]
  | ifThenElse condition thenBranch elseBranch thenIH elseIH =>
      simp only [Command.rename, localCapacity, thenIH, elseIH]
  | whileLoop condition body bodyIH =>
      simp only [Command.rename, localCapacity, bodyIH]

/-- Scoped command renaming commutes exactly with structural-Core emission. -/
theorem toCoreStmt_rename
    {source target : Nat} {embedding : Embedding source target}
    {small : Layout source} {large : Layout target}
    (related : Layout.Extends embedding small large)
    (nextLocal : VarId)
    (command : Command Core.signature actions source) :
    toCoreStmt actionAdapter large nextLocal
        (command.rename actionRenamer embedding) =
      toCoreStmt actionAdapter small nextLocal command := by
  induction command generalizing target nextLocal with
  | skip => rfl
  | sequence first second firstIH secondIH =>
      simp only [Command.rename, toCoreStmt]
      rw [firstIH related nextLocal, localCapacity_rename,
        secondIH related]
  | letValue type initializer body bodyIH =>
      simp only [Command.rename, toCoreStmt]
      rw [toCoreExpr_rename related initializer]
      exact congrArg
        (fun bodyStatement => Stmt.letLocal nextLocal type
          (Core.toCoreExpr small initializer) bodyStatement)
        (bodyIH (related.push nextLocal) (nextLocal + 1))
  | setLocal index value =>
      simp only [Command.rename, toCoreStmt]
      rw [related index, toCoreExpr_rename related value]
  | updateLocal operation index value =>
      simp only [Command.rename, toCoreStmt]
      rw [related index, toCoreExpr_rename related value]
  | action operation =>
      simp only [Command.rename, toCoreStmt]
      exact actionAdapter_rename related operation
  | ifThenElse condition thenBranch elseBranch thenIH elseIH =>
      simp only [Command.rename, toCoreStmt]
      rw [toCoreExpr_rename related condition, thenIH related nextLocal,
        elseIH related nextLocal]
  | whileLoop condition body bodyIH =>
      simp only [Command.rename, toCoreStmt]
      rw [toCoreExpr_rename related condition, bodyIH related nextLocal]
  | returnValue value =>
      cases value with
      | none => rfl
      | some value =>
          simp only [Command.rename, Option.map, toCoreStmt]
          rw [toCoreExpr_rename related value]
  | breakLoop | continueLoop => rfl

end Lanius.FunctionalView.Core.Stateful
