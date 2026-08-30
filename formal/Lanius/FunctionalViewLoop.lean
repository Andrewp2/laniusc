import Lanius.FunctionalViewStateful

namespace Lanius.FunctionalView.Stateful.Loop

open Lanius
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful

universe u v w

/-! # Total functional loops

The command semantics gives the exact finite meaning of `whileLoop`.  This
module packages the recurring proof pattern: verify one local decision,
provide a decreasing algorithmic measure, and obtain the complete functional
execution.  No evaluator fuel or physical Core cell appears here.
-/

abbrev Runtime
    (termMachine : FunctionalView.Machine termSignature) (arity : Nat) :=
  termMachine.World × Env arity

def Runtime.world (runtime : Runtime termMachine arity) : termMachine.World :=
  runtime.1

def Runtime.environment (runtime : Runtime termMachine arity) : Env arity :=
  runtime.2

/-- One continuing functional back edge. -/
inductive Iteration
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity) :
    Runtime termMachine arity → Runtime termMachine arity → Prop where
  | next
      (conditionResult : Term.evaluate termMachine before.world
        before.environment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Command.Evaluates termMachine machine conditionWorld
        before.environment body .next after.world after.environment) :
      Iteration termMachine machine condition body before after
  | continueLoop
      (conditionResult : Term.evaluate termMachine before.world
        before.environment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Command.Evaluates termMachine machine conditionWorld
        before.environment body .continueLoop after.world after.environment) :
      Iteration termMachine machine condition body before after

/-- One functional loop exit.  `break` becomes normal fallthrough; return
    escapes with its value. -/
inductive Exit
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity) :
    Completion → Runtime termMachine arity → Runtime termMachine arity →
      Prop where
  | conditionFalse
      (conditionResult : Term.evaluate termMachine before.world
        before.environment condition = .ok (.boolean false, after.world))
      (environmentEq : after.environment = before.environment := by rfl) :
      Exit termMachine machine condition body .next before after
  | breakLoop
      (conditionResult : Term.evaluate termMachine before.world
        before.environment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Command.Evaluates termMachine machine conditionWorld
        before.environment body .breakLoop after.world after.environment) :
      Exit termMachine machine condition body .next before after
  | returned
      (conditionResult : Term.evaluate termMachine before.world
        before.environment condition = .ok (.boolean true, conditionWorld))
      (bodyResult : Command.Evaluates termMachine machine conditionWorld
        before.environment body (.returned value) after.world
        after.environment) :
      Exit termMachine machine condition body (.returned value) before after

inductive Trace
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity) :
    Runtime termMachine arity → Completion → Runtime termMachine arity →
      Type where
  | exit (edge : Exit termMachine machine condition body completion before after) :
      Trace termMachine machine condition body before completion after
  | step
      (edge : Iteration termMachine machine condition body before middle)
      (rest : Trace termMachine machine condition body middle completion after) :
      Trace termMachine machine condition body before completion after

/-- A loop trace that retains the algorithmic configuration indexing every
    edge.  Separation proofs use this form because logical resources and
    bounds generally cannot be recovered from raw worlds and environments. -/
inductive ConfigTrace
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity)
    (Config : Type u) (runtime : Config → Runtime termMachine arity) :
    Config → Completion → Runtime termMachine arity → Type u where
  | exit
      (edge : Exit termMachine machine condition body completion
        (runtime config) after) :
      ConfigTrace termMachine machine condition body Config runtime config
        completion after
  | step (next : Config)
      (edge : Iteration termMachine machine condition body (runtime config)
        (runtime next))
      (rest : ConfigTrace termMachine machine condition body Config runtime
        next completion after) :
      ConfigTrace termMachine machine condition body Config runtime config
        completion after

def ConfigTrace.erase
    (trace : ConfigTrace termMachine machine condition body Config runtime
      config completion after) :
    Trace termMachine machine condition body (runtime config) completion after :=
  match trace with
  | .exit edge => .exit edge
  | .step _ edge rest => .step edge rest.erase

theorem Trace.evaluates
    (trace : Trace termMachine machine condition body before completion after) :
    Command.Evaluates termMachine machine before.world before.environment
      (.whileLoop condition body) completion after.world after.environment := by
  induction trace with
  | exit edge =>
      cases edge with
      | conditionFalse conditionResult environmentEq =>
          rw [environmentEq]
          exact .whileFalse conditionResult
      | breakLoop conditionResult bodyResult =>
          exact .whileBreak conditionResult bodyResult
      | returned conditionResult bodyResult =>
          exact .whileReturn conditionResult bodyResult
  | step edge rest induction =>
      cases edge with
      | next conditionResult bodyResult =>
          exact .whileNext conditionResult bodyResult induction
      | continueLoop conditionResult bodyResult =>
          exact .whileContinue conditionResult bodyResult induction

theorem ConfigTrace.evaluates
    (trace : ConfigTrace termMachine machine condition body Config runtime
      config completion after) :
    Command.Evaluates termMachine machine (runtime config).world
      (runtime config).environment (.whileLoop condition body) completion
      after.world after.environment :=
  trace.erase.evaluates

/-- Algorithm-specific result attached to a verified exit. -/
structure LoopExit
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity)
    (Config : Type u) (runtime : Config → Runtime termMachine arity)
    (Result : Config → Completion → Runtime termMachine arity → Sort v)
    (config : Config) where
  completion : Completion
  after : Runtime termMachine arity
  edge : Exit termMachine machine condition body completion (runtime config)
    after
  result : Result config completion after

inductive Decision
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity)
    (Config : Type u) (runtime : Config → Runtime termMachine arity)
    {Measure : Type w} [WellFoundedRelation Measure]
    (measure : Config → Measure)
    (Result : Config → Completion → Runtime termMachine arity → Sort v)
    (config : Config) : Type (max u v w) where
  | exit (loopExit : LoopExit termMachine machine condition body Config runtime
      Result config) :
      Decision termMachine machine condition body Config runtime measure Result
        config
  | next (next : Config)
      (edge : Iteration termMachine machine condition body (runtime config)
        (runtime next))
      (decreases : WellFoundedRelation.rel (measure next) (measure config))
      (lift : ∀ {completion after}, Result next completion after →
        Result config completion after) :
      Decision termMachine machine condition body Config runtime measure Result
        config

structure Run
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity)
    (Config : Type u) (runtime : Config → Runtime termMachine arity)
    (Result : Config → Completion → Runtime termMachine arity → Sort v)
    (config : Config) where
  completion : Completion
  after : Runtime termMachine arity
  trace : ConfigTrace termMachine machine condition body Config runtime config
    completion after
  result : Result config completion after

/-- Assemble a total functional loop from a local, decreasing decision. -/
noncomputable def run
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity)
    (Config : Type u) (runtime : Config → Runtime termMachine arity)
    {Measure : Type w} [WellFoundedRelation Measure]
    (measure : Config → Measure)
    (Result : Config → Completion → Runtime termMachine arity → Sort v)
    (decide : ∀ config, Decision termMachine machine condition body Config
      runtime measure Result config)
    (config : Config) :
    Run termMachine machine condition body Config runtime Result config := by
  cases choice : decide config with
  | exit loopExit =>
      exact {
        completion := loopExit.completion
        after := loopExit.after
        trace := .exit loopExit.edge
        result := loopExit.result
      }
  | next next edge decreases lift =>
      let rest := run termMachine machine condition body Config runtime measure
        Result decide next
      exact {
        completion := rest.completion
        after := rest.after
        trace := .step next edge rest.trace
        result := lift rest.result
      }
termination_by measure config
decreasing_by exact decreases

/-! ## Bounded cursor scans

Many lexer and parser loops advance a cursor while it is in bounds and a
predicate accepts the current element.  `CursorScan` packages that recurrence
once.  A client supplies only the functional condition/body equations and the
three elementary equations defining its desired result cursor. -/

namespace CursorScan

/-- Equations characterizing the result of a bounded, unit-step scan. -/
structure Recurrence (limit : Nat) (accept : Nat → Bool)
    (finish : Nat → Nat) : Prop where
  outOfBounds : ∀ cursor, ¬ cursor < limit → finish cursor = cursor
  rejected : ∀ cursor, cursor < limit → accept cursor = false →
    finish cursor = cursor
  accepted : ∀ cursor, cursor < limit → accept cursor = true →
    finish cursor = finish (cursor + 1)

/-- Functional obligations for a cursor scan.  No Core state, physical cell,
    or separation proof is exposed here. -/
structure Spec
    (termMachine : FunctionalView.Machine termSignature)
    (machine : Stateful.Machine termMachine actions)
    (condition : Term termSignature arity)
    (body : Command termSignature actions arity)
    (runtime : Nat → Runtime termMachine arity)
    (limit : Nat) (accept : Nat → Bool) : Prop where
  conditionInBounds : ∀ cursor, (inBounds : cursor < limit) →
    Term.evaluate termMachine (runtime cursor).world
      (runtime cursor).environment condition =
      .ok (.boolean (accept cursor), (runtime cursor).world)
  conditionOutOfBounds : ∀ cursor, ¬ cursor < limit →
    Term.evaluate termMachine (runtime cursor).world
      (runtime cursor).environment condition =
      .ok (.boolean false, (runtime cursor).world)
  body : ∀ cursor, cursor < limit → accept cursor = true →
    Command.Evaluates termMachine machine (runtime cursor).world
      (runtime cursor).environment body .next
      (runtime (cursor + 1)).world (runtime (cursor + 1)).environment

/-- Exact result retained by a total cursor scan. -/
structure Result
    (runtime : Nat → Runtime termMachine arity) (finish : Nat → Nat)
    (initial : Nat) (completion : Completion)
    (after : Runtime termMachine arity) where
  completionEq : completion = .next
  finalCursor : Nat
  finalEq : finalCursor = finish initial
  afterEq : after = runtime finalCursor

private def measure (limit cursor : Nat) : Nat := limit - cursor

private noncomputable def decide
    (spec : Spec termMachine machine condition body runtime limit accept)
    (recurrence : Recurrence limit accept finish) (cursor : Nat) :
    Decision termMachine machine condition body Nat runtime (measure limit)
      (Result runtime finish) cursor := by
  by_cases inBounds : cursor < limit
  · by_cases accepted : accept cursor = true
    · apply Decision.next (cursor + 1)
      · exact .next (by simpa [accepted] using
          spec.conditionInBounds cursor inBounds)
          (spec.body cursor inBounds accepted)
      · simp only [measure]
        exact Nat.sub_lt_sub_left inBounds (Nat.lt_succ_self cursor)
      · intro completion after result
        exact {
          completionEq := result.completionEq
          finalCursor := result.finalCursor
          finalEq := result.finalEq.trans
            (recurrence.accepted cursor inBounds accepted).symm
          afterEq := result.afterEq
        }
    · have rejected : accept cursor = false := Bool.eq_false_iff.mpr accepted
      apply Decision.exit
      exact {
        completion := .next
        after := runtime cursor
        edge := .conditionFalse (by
          have conditionResult := spec.conditionInBounds cursor inBounds
          rw [rejected] at conditionResult
          exact conditionResult)
        result := {
          completionEq := rfl
          finalCursor := cursor
          finalEq := (recurrence.rejected cursor inBounds rejected).symm
          afterEq := rfl
        }
      }
  · apply Decision.exit
    exact {
      completion := .next
      after := runtime cursor
      edge := .conditionFalse (spec.conditionOutOfBounds cursor inBounds)
      result := {
        completionEq := rfl
        finalCursor := cursor
        finalEq := (recurrence.outOfBounds cursor inBounds).symm
        afterEq := rfl
      }
    }

/-- Construct the complete functional execution of a bounded cursor scan. -/
noncomputable def run
    (spec : Spec termMachine machine condition body runtime limit accept)
    (recurrence : Recurrence limit accept finish) (initial : Nat) :
    Run termMachine machine condition body Nat runtime
      (Result runtime finish) initial :=
  Loop.run termMachine machine condition body Nat runtime (measure limit)
    (Result runtime finish) (decide spec recurrence) initial

end CursorScan

end Lanius.FunctionalView.Stateful.Loop
