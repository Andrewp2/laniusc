import Lanius.Relational.SemanticWP
import Lanius.Relational.Diagnostics

namespace Lanius.Automation.VCGen

set_option linter.defProp false

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.Relational
open Lanius.Relational.Semantics

/-! # Stable verification-condition facade

The semantic definitions remain in `Lanius.Relational.SemanticWP`.  This
module is the sole home for tactic-facing annotations, diagnostic resolution,
and named automation sets, so changes to Lean's `vcgen` implementation cannot
change the compiler proof logic.
-/

abbrev Assertion (World : Type) (arity : Nat) := World → Env arity → Prop

namespace Term

abbrev WP (machine : Semantics.Machine signature actions)
    {arity : Nat} (term : FunctionalView.Term signature arity)
    (post : Value → machine.World → Prop)
    (world : machine.World) (environment : Env arity) : Prop :=
  Relational.SemanticWP.Term.WP machine term post world environment

def intro := @Relational.SemanticWP.Term.intro
def apply := @Relational.SemanticWP.Term.apply

end Term

namespace Command

abbrev Postcondition (World : Type) (arity : Nat) :=
  Stateful.Completion → World → Env arity → Prop

abbrev WP (machine : Semantics.Machine signature actions)
    {arity : Nat}
    (command : Stateful.Command signature actions arity)
    (post : Postcondition machine.World arity)
    (world : machine.World) (environment : Env arity) : Prop :=
  Relational.SemanticWP.Command.WP machine command post world environment

def intro := @Relational.SemanticWP.Command.intro
def apply := @Relational.SemanticWP.Command.apply
def skip := @Relational.SemanticWP.Command.skip
def sequence := @Relational.SemanticWP.Command.sequence
def letValue := @Relational.SemanticWP.Command.letValue
def setLocal := @Relational.SemanticWP.Command.setLocal
def updateLocal := @Relational.SemanticWP.Command.updateLocal
def action := @Relational.SemanticWP.Command.action
def ifThenElse := @Relational.SemanticWP.Command.ifThenElse
def whileLoop := @Relational.SemanticWP.Command.whileLoop
def returnSome := @Relational.SemanticWP.Command.returnSome
def returnNone := @Relational.SemanticWP.Command.returnNone
def breakLoop := @Relational.SemanticWP.Command.breakLoop
def continueLoop := @Relational.SemanticWP.Command.continueLoop

end Command

/-- Source-indexed loop annotations.  The arity is quantified because a
checked command can introduce scoped locals before reaching a nested loop. -/
structure AnnotationRegistry (World : Type) where
  loopInvariant : (arity : Nat) → SourceIdentity →
    Option (Assertion World arity)

def AnnotationRegistry.single
    (source : SourceIdentity) (invariant : Assertion World arity) :
    AnnotationRegistry World where
  loopInvariant := fun candidateArity candidateSource =>
    if _sourceEq : candidateSource = source then
      if arityEq : candidateArity = arity then
        some (arityEq ▸ invariant)
      else
        none
    else
      none

@[simp] theorem AnnotationRegistry.single_finds
    (source : SourceIdentity) (invariant : Assertion World arity) :
    (AnnotationRegistry.single source invariant).loopInvariant arity source =
      some invariant := by
  simp [AnnotationRegistry.single]

def AnnotationRegistry.resolveLoopInvariant
    (annotations : AnnotationRegistry World) (arity : Nat)
    (source : SourceIdentity) :
    Except Relational.Diagnostics.Diagnostic (Assertion World arity) :=
  Relational.Diagnostics.requireLoopInvariant source
    (annotations.loopInvariant arity source)

def requireSpecification := @Relational.Diagnostics.requireSpecification
def requireRepresentation := @Relational.Diagnostics.requireRepresentation

/-- Named, intentionally empty-by-default automation sets.  Proof modules add
only stable equations to the relevant set and invoke them explicitly. -/
register_simp_attr lanius_pure
register_simp_attr lanius_bounds
register_simp_attr lanius_rep
register_simp_attr lanius_frames

end Lanius.Automation.VCGen
