import Lanius.FunctionalViewCoreReification
import Lanius.FunctionalViewCoreStateful

namespace Lanius.FunctionalView.Core.Stateful.Reification

open Lanius
open Lanius.Core
open Lanius.Typing
open Lanius.Extraction.CoreTyping
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Reification
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Core.Stateful

/-! # Checked stateful Core reification

This is the mutation/loop counterpart of read-only block reification.  A
successful result contains an exact round trip to the checked Core artifact,
so lexer/parser proofs consume compiler-derived commands rather than a second
handwritten program.
-/

structure ReifiedCommand (program : Program) (returnType : Ty)
    (context : Context) (inLoop : Bool) (layout : Layout arity)
    (nextLocal : VarId) (statement : Stmt) where
  command : Command Core.signature actions arity
  coreTyped : StmtHasType program returnType context inLoop statement
  toCoreExactly : Stateful.toCoreStmt actionAdapter layout nextLocal command =
    statement

def reifyCommand? (program : Program) (returnType : Ty) :
    (context : Context) → (inLoop : Bool) → (layout : Layout arity) →
      (nextLocal : VarId) → (statement : Stmt) →
      Option (ReifiedCommand program returnType context inLoop layout nextLocal
        statement)
  | context, inLoop, layout, nextLocal, .skip => do
      let typed ← checkStmt program returnType context inLoop .skip
      pure {
        command := .skip
        coreTyped := typed.proof
        toCoreExactly := by rfl
      }
  | context, inLoop, layout, nextLocal, .sequence first second => do
      let firstView ← reifyCommand? program returnType context inLoop layout
        nextLocal first
      let secondView ← reifyCommand? program returnType context inLoop layout
        (nextLocal + localCapacity actionAdapter firstView.command) second
      let typed ← checkStmt program returnType context inLoop
        (.sequence first second)
      pure {
        command := .sequence firstView.command secondView.command
        coreTyped := typed.proof
        toCoreExactly := by
          simp only [Stateful.toCoreStmt]
          rw [firstView.toCoreExactly, secondView.toCoreExactly]
      }
  | context, inLoop, layout, nextLocal,
      .letLocal id type initializer body => do
      if localMatches : id = nextLocal then
        let initializerView ← reifyTerm? program context layout initializer
        if typeMatches : initializerView.type = type then
          let bodyView ← reifyCommand? program returnType
            (context.bind id type) inLoop (Layout.push layout id)
            (nextLocal + 1) body
          let typed ← checkStmt program returnType context inLoop
            (.letLocal id type initializer body)
          pure {
            command := .letValue type initializerView.term bodyView.command
            coreTyped := typed.proof
            toCoreExactly := by
              subst id
              simp only [Stateful.toCoreStmt]
              rw [initializerView.toCoreExactly, bodyView.toCoreExactly]
          }
        else none
      else none
  | context, inLoop, layout, nextLocal,
      .expression (.assign .set (.local id) value) => do
      let target ← findSlot? layout id
      let valueView ← reifyTerm? program context layout value
      let statement := .expression (.assign .set (.local id) value)
      let typed ← checkStmt program returnType context inLoop statement
      pure {
        command := .setLocal target.slot valueView.term
        coreTyped := typed.proof
        toCoreExactly := by
          simp only [Stateful.toCoreStmt]
          rw [target.mapsTo, valueView.toCoreExactly]
      }
  | context, inLoop, layout, nextLocal,
      .expression (.assign operation (.local id) value) => do
      let target ← findSlot? layout id
      let valueView ← reifyTerm? program context layout value
      let statement := .expression (.assign operation (.local id) value)
      let typed ← checkStmt program returnType context inLoop statement
      pure {
        command := .updateLocal operation target.slot valueView.term
        coreTyped := typed.proof
        toCoreExactly := by
          simp only [Stateful.toCoreStmt]
          rw [target.mapsTo, valueView.toCoreExactly]
      }
  | context, inLoop, layout, nextLocal,
      .expression (.assign .set (.index (.local id) index) value) => do
      let base ← findSlot? layout id
      let indexView ← reifyTerm? program context layout index
      let valueView ← reifyTerm? program context layout value
      let statement :=
        .expression (.assign .set (.index (.local id) index) value)
      let typed ← checkStmt program returnType context inLoop statement
      pure {
        command := .action
          (.setI32Index base.slot indexView.term valueView.term)
        coreTyped := typed.proof
        toCoreExactly := by
          simp only [Stateful.toCoreStmt, actionAdapter]
          rw [base.mapsTo, indexView.toCoreExactly, valueView.toCoreExactly]
      }
  | context, inLoop, layout, nextLocal,
      .ifThenElse condition thenBranch elseBranch => do
      let conditionView ← reifyTerm? program context layout condition
      if conditionType : conditionView.type = .scalar .bool then
        let thenView ← reifyCommand? program returnType context inLoop layout
          nextLocal thenBranch
        let elseView ← reifyCommand? program returnType context inLoop layout
          nextLocal elseBranch
        let typed ← checkStmt program returnType context inLoop
          (.ifThenElse condition thenBranch elseBranch)
        pure {
          command := .ifThenElse conditionView.term thenView.command
            elseView.command
          coreTyped := typed.proof
          toCoreExactly := by
            simp only [Stateful.toCoreStmt]
            rw [conditionView.toCoreExactly, thenView.toCoreExactly,
              elseView.toCoreExactly]
        }
      else none
  | context, inLoop, layout, nextLocal, .whileLoop condition body => do
      let conditionView ← reifyTerm? program context layout condition
      if conditionType : conditionView.type = .scalar .bool then
        let bodyView ← reifyCommand? program returnType context true layout
          nextLocal body
        let typed ← checkStmt program returnType context inLoop
          (.whileLoop condition body)
        pure {
          command := .whileLoop conditionView.term bodyView.command
          coreTyped := typed.proof
          toCoreExactly := by
            simp only [Stateful.toCoreStmt]
            rw [conditionView.toCoreExactly, bodyView.toCoreExactly]
        }
      else none
  | context, inLoop, layout, _nextLocal, .returnValue none => do
      let typed ← checkStmt program returnType context inLoop
        (.returnValue none)
      pure {
        command := .returnValue none
        coreTyped := typed.proof
        toCoreExactly := by rfl
      }
  | context, inLoop, layout, _nextLocal, .returnValue (some value) => do
      let valueView ← reifyTerm? program context layout value
      if returnTypeMatches : valueView.type = returnType then
        let typed ← checkStmt program returnType context inLoop
          (.returnValue (some value))
        pure {
          command := .returnValue (some valueView.term)
          coreTyped := typed.proof
          toCoreExactly := by
            simp only [Stateful.toCoreStmt]
            rw [valueView.toCoreExactly]
        }
      else none
  | context, true, _layout, _nextLocal, .breakLoop => do
      let typed ← checkStmt program returnType context true .breakLoop
      pure {
        command := .breakLoop
        coreTyped := typed.proof
        toCoreExactly := by rfl
      }
  | context, true, _layout, _nextLocal, .continueLoop => do
      let typed ← checkStmt program returnType context true .continueLoop
      pure {
        command := .continueLoop
        coreTyped := typed.proof
        toCoreExactly := by rfl
      }
  | _, _, _, _, _ => none
  termination_by _ _ _ _ statement => sizeOf statement

theorem reifyCommand?_roundTrip
    (_reified : reifyCommand? program returnType context inLoop layout nextLocal
      statement = some view) :
    Stateful.toCoreStmt actionAdapter layout nextLocal view.command = statement :=
  view.toCoreExactly

end Lanius.FunctionalView.Core.Stateful.Reification
