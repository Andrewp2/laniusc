import Lanius.Extraction.CoreTypingChecker
import Lanius.FunctionalViewCore

namespace Lanius.FunctionalView.Core.Reification

open Lanius
open Lanius.Core
open Lanius.Typing
open Lanius.Extraction.CoreTyping
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

/-!
# Checked Core reification

The functional view is derived from typed structural Core.  Reification is
partial because the view deliberately represents only structured computations
whose local bindings are immutable.  Success carries an exact round-trip
certificate; callers never separately assert that a handwritten view happens
to describe a Core fragment.
-/

/-- All intrinsically scoped slots of one functional environment. -/
def allSlots : (arity : Nat) → List (Fin arity)
  | 0 => []
  | arity + 1 =>
      ⟨0, Nat.zero_lt_succ arity⟩ :: (allSlots arity).map Fin.succ

structure FoundSlot (layout : Layout arity) (id : VarId) where
  slot : Fin arity
  mapsTo : layout slot = id

def findSlotIn? (layout : Layout arity) (id : VarId) :
    List (Fin arity) → Option (FoundSlot layout id)
  | [] => none
  | slot :: tail =>
      if same : layout slot = id then
        some ⟨slot, same⟩
      else
        findSlotIn? layout id tail

def findSlot? (layout : Layout arity) (id : VarId) :
    Option (FoundSlot layout id) :=
  findSlotIn? layout id (allSlots arity)

/-- A typed Core expression and its mechanically recovered functional view. -/
structure ReifiedTerm (program : Program) (context : Context)
    (layout : Layout arity) (expression : Expr) where
  type : Ty
  term : Term signature arity
  coreTyped : ExprHasType program context expression type
  toCoreExactly : toCoreExpr layout term = expression

/-- A source-ordered list of mechanically recovered terms.  Keeping the
    source expressions in the index makes aggregate construction an exact
    round trip rather than an untyped list traversal hidden in a client
    proof. -/
structure ReifiedTerms (program : Program) (context : Context)
    (layout : Layout arity) (expressions : List Expr) where
  types : List Ty
  terms : List (Term signature arity)
  toCoreExactly : toCoreExprs layout terms = expressions

mutual

  def reifyTerm? (program : Program) (context : Context)
      (layout : Layout arity) :
      (expression : Expr) → Option (ReifiedTerm program context layout expression)
    | .value value => do
        let inferred ← inferExpr program context (.value value)
        pure {
          type := inferred.type
          term := literal value
          coreTyped := inferred.typed
          toCoreExactly := by rfl
        }
    | .local id => do
        let inferred ← inferExpr program context (.local id)
        let found ← findSlot? layout id
        pure {
          type := inferred.type
          term := reference found.slot
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, reference, refToCoreExpr]
            exact congrArg Expr.local found.mapsTo
        }
    | .cast target operand => do
        let inferred ← inferExpr program context (.cast target operand)
        let operandView ← reifyTerm? program context layout operand
        match operandView.type with
        | .scalar source =>
            pure {
              type := inferred.type
              term := apply (.cast source target) [operandView.term]
              coreTyped := inferred.typed
              toCoreExactly := by
                simp only [toCoreExpr, apply, toCoreExprs, Operation.toCoreExpr]
                rw [operandView.toCoreExactly]
            }
        | _ => none
    | .unary operation operand => do
        let inferred ← inferExpr program context (.unary operation operand)
        let operandView ← reifyTerm? program context layout operand
        pure {
          type := inferred.type
          term := apply (.unary operation operandView.type inferred.type)
            [operandView.term]
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, apply, toCoreExprs, Operation.toCoreExpr]
            rw [operandView.toCoreExactly]
        }
    | .binary .logicalAnd left right => do
        let inferred ← inferExpr program context (.binary .logicalAnd left right)
        let leftView ← reifyTerm? program context layout left
        let rightView ← reifyTerm? program context layout right
        pure {
          type := inferred.type
          term := logicalAnd leftView.term rightView.term
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, logicalAnd]
            rw [leftView.toCoreExactly, rightView.toCoreExactly]
        }
    | .binary .logicalOr left right => do
        let inferred ← inferExpr program context (.binary .logicalOr left right)
        let leftView ← reifyTerm? program context layout left
        let rightView ← reifyTerm? program context layout right
        pure {
          type := inferred.type
          term := logicalOr leftView.term rightView.term
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, logicalOr]
            rw [leftView.toCoreExactly, rightView.toCoreExactly]
        }
    | .binary operation left right => do
        let inferred ← inferExpr program context (.binary operation left right)
        let leftView ← reifyTerm? program context layout left
        let rightView ← reifyTerm? program context layout right
        pure {
          type := inferred.type
          term := apply
            (.binary operation leftView.type rightView.type inferred.type)
            [leftView.term, rightView.term]
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, apply, toCoreExprs, Operation.toCoreExpr]
            rw [leftView.toCoreExactly, rightView.toCoreExactly]
        }
    | .index base index => do
        let inferred ← inferExpr program context (.index base index)
        let baseView ← reifyTerm? program context layout base
        let indexView ← reifyTerm? program context layout index
        pure {
          type := inferred.type
          term := apply (.index baseView.type indexView.type inferred.type)
            [baseView.term, indexView.term]
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, apply, toCoreExprs, Operation.toCoreExpr]
            rw [baseView.toCoreExactly, indexView.toCoreExactly]
        }
    | .structValue typeId fields => do
        let inferred ← inferExpr program context (.structValue typeId fields)
        let fieldViews ← reifyTerms? program context layout fields
        pure {
          type := inferred.type
          term := apply (.structValue typeId fieldViews.types) fieldViews.terms
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, apply, Operation.toCoreExpr]
            exact congrArg (Expr.structValue typeId) fieldViews.toCoreExactly
        }
    | .field base field => do
        let inferred ← inferExpr program context (.field base field)
        let baseView ← reifyTerm? program context layout base
        pure {
          type := inferred.type
          term := apply (.field baseView.type field inferred.type) [baseView.term]
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, apply, toCoreExprs, Operation.toCoreExpr]
            rw [baseView.toCoreExactly]
        }
    | .constant id => do
        let inferred ← inferExpr program context (.constant id)
        pure {
          type := inferred.type
          term := apply (.constant id inferred.type) []
          coreTyped := inferred.typed
          toCoreExactly := by rfl
        }
    | .call function arguments => do
        let inferred ← inferExpr program context (.call function arguments)
        let argumentViews ← reifyTerms? program context layout arguments
        pure {
          type := inferred.type
          term := apply (.call function argumentViews.types inferred.type)
            argumentViews.terms
          coreTyped := inferred.typed
          toCoreExactly := by
            simp only [toCoreExpr, apply, Operation.toCoreExpr]
            exact congrArg (Expr.call function) argumentViews.toCoreExactly
        }
    | _ => none
  termination_by expression => 2 * sizeOf expression

  def reifyTerms? (program : Program) (context : Context)
      (layout : Layout arity) :
      (expressions : List Expr) →
        Option (ReifiedTerms program context layout expressions)
    | [] => some {
        types := []
        terms := []
        toCoreExactly := by rfl
      }
    | expression :: expressions => do
        let head ← reifyTerm? program context layout expression
        let tail ← reifyTerms? program context layout expressions
        pure {
          types := head.type :: tail.types
          terms := head.term :: tail.terms
          toCoreExactly := by
            simp only [toCoreExprs]
            rw [head.toCoreExactly, tail.toCoreExactly]
        }
  termination_by expressions => 2 * sizeOf expressions + 1

end

/-- A typed Core statement and its mechanically recovered functional view. -/
structure ReifiedBlock (program : Program) (returnType : Ty)
    (context : Context) (inLoop : Bool) (layout : Layout arity)
    (nextLocal : VarId) (statement : Stmt) where
  block : Block signature arity
  coreTyped : StmtHasType program returnType context inLoop statement
  toCoreExactly : toCoreStmt layout nextLocal block = statement

def reifyBlock? (program : Program) (returnType : Ty) :
    (context : Context) → (inLoop : Bool) → (layout : Layout arity) →
      (nextLocal : VarId) → (statement : Stmt) →
      Option (ReifiedBlock program returnType context inLoop layout nextLocal statement)
  | context, inLoop, layout, nextLocal, .skip => do
      let typed ← checkStmt program returnType context inLoop .skip
      pure {
        block := .skip
        coreTyped := typed.proof
        toCoreExactly := by rfl
      }
  | context, inLoop, layout, nextLocal,
      .sequence first second => do
      let firstView ← reifyBlock? program returnType context inLoop layout
        nextLocal first
      let secondView ← reifyBlock? program returnType context inLoop layout
        (nextLocal + localCapacity firstView.block) second
      let typed ← checkStmt program returnType context inLoop
        (.sequence first second)
      pure {
        block := .sequence firstView.block secondView.block
        coreTyped := typed.proof
        toCoreExactly := by
          simp only [toCoreStmt]
          rw [firstView.toCoreExactly, secondView.toCoreExactly]
      }
  | context, inLoop, layout, nextLocal,
      .letLocal id type initializer body => do
      if localMatches : id = nextLocal then
        let initializerView ← reifyTerm? program context layout initializer
        if typeMatches : initializerView.type = type then
          let bodyView ← reifyBlock? program returnType
            (context.bind id type) inLoop (Layout.push layout id)
            (nextLocal + 1) body
          let typed ← checkStmt program returnType context inLoop
            (.letLocal id type initializer body)
          pure {
            block := .letValue type initializerView.term bodyView.block
            coreTyped := typed.proof
            toCoreExactly := by
              subst id
              simp only [toCoreStmt]
              rw [initializerView.toCoreExactly, bodyView.toCoreExactly]
          }
        else none
      else none
  | context, inLoop, layout, nextLocal,
      .ifThenElse condition thenBranch elseBranch => do
      let conditionView ← reifyTerm? program context layout condition
      if conditionType : conditionView.type = .scalar .bool then
        let thenView ← reifyBlock? program returnType context inLoop layout
          nextLocal thenBranch
        let elseView ← reifyBlock? program returnType context inLoop layout
          nextLocal elseBranch
        let typed ← checkStmt program returnType context inLoop
          (.ifThenElse condition thenBranch elseBranch)
        pure {
          block := .ifThenElse conditionView.term thenView.block elseView.block
          coreTyped := typed.proof
          toCoreExactly := by
            simp only [toCoreStmt]
            rw [conditionView.toCoreExactly, thenView.toCoreExactly,
              elseView.toCoreExactly]
        }
      else none
  | context, inLoop, layout, nextLocal, .returnValue none => do
      let typed ← checkStmt program returnType context inLoop
        (.returnValue none)
      pure {
        block := .returnValue none
        coreTyped := typed.proof
        toCoreExactly := by rfl
      }
  | context, inLoop, layout, nextLocal,
      .returnValue (some value) => do
      let valueView ← reifyTerm? program context layout value
      if returnTypeMatches : valueView.type = returnType then
        let typed ← checkStmt program returnType context inLoop
          (.returnValue (some value))
        pure {
          block := .returnValue (some valueView.term)
          coreTyped := typed.proof
          toCoreExactly := by
            simp only [toCoreStmt]
            rw [valueView.toCoreExactly]
        }
      else none
  | _, _, _, _, _ => none
  termination_by _ _ _ _ statement => sizeOf statement

/-- Reification success is, by construction, an exact right inverse of
    `toCoreExpr`. -/
theorem reifyTerm?_roundTrip
    (_reified : reifyTerm? program context layout expression = some view) :
    toCoreExpr layout view.term = expression :=
  view.toCoreExactly

/-- Reification success is, by construction, an exact right inverse of
    `toCoreStmt`. -/
theorem reifyBlock?_roundTrip
    (_reified : reifyBlock? program returnType context inLoop layout nextLocal
      statement = some view) :
    toCoreStmt layout nextLocal view.block = statement :=
  view.toCoreExactly

end Lanius.FunctionalView.Core.Reification
