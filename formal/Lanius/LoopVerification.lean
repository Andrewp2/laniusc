import Lanius.Separation

namespace Lanius.LoopVerification

open Lanius.Core
open Lanius.Semantics
open Lanius.Separation

universe u v w

/-! ## Reusable total-correctness driver for extracted loops

Compiler proofs usually carry more state than the evaluator does: a logical
workspace, cursor decomposition, ownership evidence, and an invariant indexed
by all three. `WhileIteration` already describes one semantic back edge, but
assembling those edges recursively was previously repeated by every verified
compiler loop. The types below separate that generic assembly from each
loop's algorithm-specific decision procedure.
-/

/-- One verified back edge, including its declared write footprint. -/
structure BackEdge
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State)
    (before after : Config) where
  semantic : WhileIteration program condition body (runtime before)
    (runtime after)
  effect : ModifiesOnly writes (runtime before) (runtime after)

/-- One semantic loop exit, including its declared write footprint. -/
structure ExitEdge
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State)
    (config : Config) (completion : Completion) (after : State) where
  semantic : WhileExit program condition body completion (runtime config) after
  effect : ModifiesOnly writes (runtime config) after

/-- One verified loop exit and the algorithm-specific result it establishes. -/
structure LoopExit
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State)
    (Result : Config → Completion → State → Sort v)
    (config : Config) where
  completion : Completion
  after : State
  edge : ExitEdge program condition body writes Config runtime config completion
    after
  result : Result config completion after

/-- A finite, algorithm-indexed execution trace of one Core `while` loop. -/
inductive Trace
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State) :
    Config → Completion → State → Type u where
  | exit (edge : ExitEdge program condition body writes Config runtime config
      completion after) :
      Trace program condition body writes Config runtime config
        completion after
  | step (edge : BackEdge program condition body writes Config runtime
      config next)
      (rest : Trace program condition body writes Config runtime next
        completion after) :
      Trace program condition body writes Config runtime config completion after

theorem Trace.executes
    (trace : Trace program condition body writes Config runtime config
      completion after) :
    Executes program (runtime config) (.whileLoop condition body) completion
      after := by
  induction trace with
  | exit edge => exact edge.semantic.executes
  | step edge _ inductionHypothesis =>
      exact edge.semantic.executeThen inductionHypothesis

theorem Trace.modifiesOnly
    (trace : Trace program condition body writes Config runtime config
      completion after) :
    ModifiesOnly writes (runtime config) after := by
  induction trace with
  | exit edge => exact edge.effect
  | step edge _ inductionHypothesis =>
      exact edge.effect.trans_same inductionHypothesis

/-- The local decision supplied by a compiler-loop proof. A continuing edge
    must decrease the chosen measure. `lift` transports a final result across
    that edge; this is where append-closure transitivity or similar logical
    bookkeeping belongs. -/
inductive Decision
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State)
    {Measure : Type w} [WellFoundedRelation Measure]
    (measure : Config → Measure)
    (Result : Config → Completion → State → Sort v)
    (config : Config) : Type (max u v w) where
  | exit (loopExit : LoopExit program condition body writes Config runtime
      Result config) : Decision program condition body writes Config runtime
        (Measure := Measure) measure Result config
  | next (next : Config)
      (edge : BackEdge program condition body writes Config runtime config next)
      (decreases : WellFoundedRelation.rel (measure next) (measure config))
      (lift : ∀ {completion after}, Result next completion after →
        Result config completion after) :
      Decision program condition body writes Config runtime
        (Measure := Measure) measure Result config

/-- The assembled loop execution and its algorithm-specific postcondition. -/
structure Run
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State)
    (Result : Config → Completion → State → Sort v)
    (config : Config) where
  completion : Completion
  after : State
  trace : Trace program condition body writes Config runtime config completion
    after
  result : Result config completion after

/-- Assemble a total loop proof from a decreasing local decision procedure.
    The recursion is over the algorithmic measure, never evaluator fuel. -/
noncomputable def run
    (program : Program) (condition : Expr) (body : Stmt) (writes : CellSet)
    (Config : Type u) (runtime : Config → State)
    {Measure : Type w} [WellFoundedRelation Measure]
    (measure : Config → Measure)
    (Result : Config → Completion → State → Sort v)
    (decide : ∀ config, Decision program condition body writes Config runtime
      (Measure := Measure) measure Result config)
    (config : Config) :
    Run program condition body writes Config runtime Result config := by
  cases choice : decide config with
  | exit loopExit =>
      exact {
        completion := loopExit.completion
        after := loopExit.after
        trace := .exit loopExit.edge
        result := loopExit.result
      }
  | next next edge decreases lift =>
      let rest := run program condition body writes Config runtime measure Result
        decide next
      exact {
        completion := rest.completion
        after := rest.after
        trace := .step edge rest.trace
        result := lift rest.result
      }
termination_by measure config
decreasing_by exact decreases

end Lanius.LoopVerification
