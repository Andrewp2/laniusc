import Lanius.Extraction.CanonicalTokens.Functions
import Lanius.FunctionalViewStatefulPattern

namespace Lanius.Extraction.CanonicalTokens.Pattern

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Pattern

abbrev C (arity : Nat) := Command Core.signature actions arity
abbrev T (arity : Nat) := Term Core.signature arity

/-! This is a total Core-specific structural pattern builder.  Its fallback
maps unsupported literal constructors to `Exact.unit`, so it is not a general
round-trip theorem.  Callers must authenticate both the recovered command and
the intended command with `exact_of_matches`; fixed clients use only supported
literals. -/

def exactOp (value : Operation) : Exact Operation :=
  Exact.ofDecidableEq value

def termPattern : T arity → TermPattern Core.signature arity
  | .reference (.slot index) => .slot index
  | .reference (.literal (.signed type value)) =>
      .literal (Exact.signed type value)
  | .reference (.literal .unit) => .literal Exact.unit
  | .reference (.literal (.boolean value)) => .literal (Exact.boolean value)
  | .reference (.literal (.unsigned type value)) =>
      .literal (Exact.unsigned type value)
  | .reference (.literal (.f32Bits value)) =>
      .literal (Exact.f32Bits value)
  | .reference (.literal (.f64Bits value)) =>
      .literal (Exact.f64Bits value)
  | .reference (.literal (.character value)) =>
      .literal (Exact.character value)
  | .reference (.literal (.string value)) => .literal (Exact.string value)
  | .reference (.literal (.pointer value)) => .literal (Exact.pointer value)
  | .reference (.literal _) => .literal Exact.unit
  | .apply op arguments => .apply (exactOp op) (arguments.map termPattern)
  | .logicalAnd left right => .logicalAnd (termPattern left) (termPattern right)
  | .logicalOr left right => .logicalOr (termPattern left) (termPattern right)

def exactSetI32Index (base : Fin arity)
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

def commandPattern : C arity → CommandPattern Core.signature actions arity
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

end Lanius.Extraction.CanonicalTokens.Pattern
