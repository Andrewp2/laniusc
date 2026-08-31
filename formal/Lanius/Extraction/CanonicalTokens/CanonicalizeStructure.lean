import Lanius.Extraction.CanonicalTokens.Functions
import Lanius.FunctionalViewStatefulPattern

namespace Lanius.Extraction.CanonicalTokens.CanonicalizeStructure

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Pattern
open Lanius.Extraction.CanonicalTokens.Functions

set_option maxRecDepth 100000

abbrev C (arity : Nat) := Command Core.signature actions arity
abbrev T (arity : Nat) := Term Core.signature arity

def i32 : Ty := .scalar (.signed .i32)
def bool : Ty := .scalar .bool
def sliceI32 : Ty := .slice i32

def slot (index : Fin arity) : T arity := .reference (.slot index)
def signed (value : Int) : T arity := .reference (.literal (.signed .i32 value))
def operation (op : BinaryOp) (left right : T arity) : T arity :=
  .apply (.binary op i32 i32 (if op = .less ∨ op = .equal then bool else i32))
    [left, right]
def add (left right : T arity) : T arity :=
  .apply (.binary .add i32 i32 i32) [left, right]
def multiply (left right : T arity) : T arity :=
  .apply (.binary .multiply i32 i32 i32) [left, right]
def less (left right : T arity) : T arity :=
  .apply (.binary .less i32 i32 bool) [left, right]
def equal (left right : T arity) : T arity :=
  .apply (.binary .equal i32 i32 bool) [left, right]
def index (base offset : T arity) : T arity :=
  .apply (.index sliceI32 i32 i32) [base, offset]
def constant (id : ConstantId) : T arity := .apply (.constant id i32) []
def logicalNot (term : T arity) : T arity :=
  .apply (.unary .logicalNot bool bool) [term]

def firstCondition : T 5 :=
  less (slot ⟨3, by omega⟩) (slot ⟨2, by omega⟩)

def firstWrites : C 10 :=
  .sequence
    (.action (.setI32Index ⟨1, by omega⟩
      (slot ⟨9, by omega⟩)
      (.apply (.call canonicalKindFunction.id [sliceI32, i32, i32, i32] i32)
        [slot ⟨0, by omega⟩, slot ⟨6, by omega⟩,
          slot ⟨7, by omega⟩, slot ⟨8, by omega⟩])))
    (.sequence
      (.action (.setI32Index ⟨1, by omega⟩
        (add (slot ⟨9, by omega⟩) (signed 1)) (slot ⟨7, by omega⟩)))
      (.sequence
        (.action (.setI32Index ⟨1, by omega⟩
          (add (slot ⟨9, by omega⟩) (signed 2)) (slot ⟨8, by omega⟩)))
        (.sequence (.updateLocal .add ⟨4, by omega⟩ (signed 1)) .skip)))

def firstOutputRow : T 9 :=
  multiply (slot ⟨4, by omega⟩) (signed 3)

def firstAfterEnd : C 9 :=
  .letValue i32 firstOutputRow firstWrites

def firstEnd : T 8 :=
  index (slot ⟨1, by omega⟩)
    (add (slot ⟨5, by omega⟩) (signed 2))

def firstAfterStart : C 8 :=
  .letValue i32 firstEnd firstAfterEnd

def firstStart : T 7 :=
  index (slot ⟨1, by omega⟩)
    (add (slot ⟨5, by omega⟩) (signed 1))

def firstKept : C 7 :=
  .letValue i32 firstStart firstAfterStart

def firstKind : T 6 :=
  index (slot ⟨1, by omega⟩) (slot ⟨5, by omega⟩)

def firstIsKept : T 7 :=
  logicalNot (.apply (.call isTriviaFunction.id [i32] bool)
    [slot ⟨6, by omega⟩])

def firstAfterRow : C 6 :=
  .letValue i32
    firstKind
    (.sequence
      (.ifThenElse
        firstIsKept firstKept .skip)
      (.sequence (.updateLocal .add ⟨3, by omega⟩ (signed 1)) .skip))

def firstBody : C 5 :=
  .letValue i32 (multiply (slot ⟨3, by omega⟩) (signed 3)) firstAfterRow

def firstLoop : C 5 := .whileLoop firstCondition firstBody

def secondCondition : T 6 :=
  less (add (slot ⟨5, by omega⟩) (signed 1)) (slot ⟨4, by omega⟩)

def secondPredicate : T 8 :=
  .logicalAnd
    (.logicalAnd
      (equal (index (slot ⟨1, by omega⟩) (slot ⟨6, by omega⟩))
        (constant 87))
      (equal (index (slot ⟨1, by omega⟩) (slot ⟨7, by omega⟩))
        (constant 14)))
    (equal
      (index (slot ⟨1, by omega⟩)
        (add (slot ⟨7, by omega⟩) (signed 1)))
      (index (slot ⟨1, by omega⟩)
        (add (slot ⟨6, by omega⟩) (signed 2))))

def secondBody : C 6 :=
  .letValue i32
    (multiply (slot ⟨5, by omega⟩) (signed 3))
    (.letValue i32 (add (slot ⟨6, by omega⟩) (signed 3))
      (.sequence
        (.ifThenElse
          secondPredicate
          (.sequence
            (.action (.setI32Index ⟨1, by omega⟩
              (slot ⟨6, by omega⟩) (constant 88)))
            .skip)
          .skip)
        (.sequence (.updateLocal .add ⟨5, by omega⟩ (signed 1)) .skip)))

def secondLoop : C 6 := .whileLoop secondCondition secondBody

def command : C 3 :=
  .letValue i32 (signed 0)
    (.letValue i32 (signed 0)
      (.sequence firstLoop
        (.letValue i32 (signed 0)
          (.sequence secondLoop
            (.sequence
              (.returnValue (some (slot ⟨4, by omega⟩)))
              .skip)))))

/-! The readable command above is accepted only if it is structurally equal
to the mechanically recovered checked artifact.  The pattern is intentionally
separate from evaluation; it is a certificate, not an alternative program. -/

private def exactOp (value : Operation) : Exact Operation :=
  Exact.ofDecidableEq value

private def termPattern : T arity → TermPattern Core.signature arity
  | .reference (.slot index) => .slot index
  | .reference (.literal (.signed type value)) =>
      .literal (Exact.signed type value)
  | .reference (.literal .unit) => .literal Exact.unit
  | .reference (.literal (.boolean value)) => .literal (Exact.boolean value)
  | .reference (.literal (.unsigned type value)) =>
      .literal (Exact.unsigned type value)
  | .reference (.literal (.f32Bits value)) => .literal (Exact.f32Bits value)
  | .reference (.literal (.f64Bits value)) => .literal (Exact.f64Bits value)
  | .reference (.literal (.character value)) =>
      .literal (Exact.character value)
  | .reference (.literal (.string value)) => .literal (Exact.string value)
  | .reference (.literal (.pointer value)) => .literal (Exact.pointer value)
  | .reference (.literal _) => .literal Exact.unit
  | .apply op arguments => .apply (exactOp op) (arguments.map termPattern)
  | .logicalAnd left right => .logicalAnd (termPattern left) (termPattern right)
  | .logicalOr left right => .logicalOr (termPattern left) (termPattern right)

private def exactSetI32Index (base : Fin arity)
    (indexPattern valuePattern : TermPattern Core.signature arity) :
    Exact (Action arity) := {
  value := .setI32Index base indexPattern.denote valuePattern.denote
  accepts := fun candidate =>
    match candidate with
    | .setI32Index candidateBase candidateIndex candidateValue =>
        decide (candidateBase = base) &&
          indexPattern.matches candidateIndex &&
          valuePattern.matches candidateValue
  sound := by
    intro candidate accepted
    cases candidate with
    | setI32Index candidateBase candidateIndex candidateValue =>
        simp only [Bool.and_eq_true, decide_eq_true_eq] at accepted
        obtain ⟨⟨rfl, indexAccepted⟩, valueAccepted⟩ := accepted
        rw [indexPattern.matches_sound indexAccepted,
          valuePattern.matches_sound valueAccepted]
}

private def commandPattern : C arity → CommandPattern Core.signature actions arity
  | .skip => .skip
  | .sequence first second =>
      .sequence (commandPattern first) (commandPattern second)
  | .letValue type initializer body =>
      .letValue type (termPattern initializer) (commandPattern body)
  | .setLocal target value => .setLocal target (termPattern value)
  | .updateLocal operation target value =>
      .updateLocal operation target (termPattern value)
  | .action (.setI32Index base index value) =>
      .action (exactSetI32Index base (termPattern index) (termPattern value))
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse (termPattern condition) (commandPattern thenBranch)
        (commandPattern elseBranch)
  | .whileLoop condition body =>
      .whileLoop (termPattern condition) (commandPattern body)
  | .returnValue value => .returnValue (value.map termPattern)
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

private def pattern := commandPattern command

theorem recovered_command_exact : canonicalizeInPlaceView.command = command := by
  calc
    canonicalizeInPlaceView.command = pattern.denote :=
      exact_of_matches (by native_decide)
    _ = command := (exact_of_matches
      (candidate := command) (by native_decide)).symm

end Lanius.Extraction.CanonicalTokens.CanonicalizeStructure
