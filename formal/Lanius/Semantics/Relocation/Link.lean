import Lanius.Semantics.Restriction
import Lanius.Semantics.Relocation.Execution

namespace Lanius.Semantics.Relocation
open Lanius.Core

/-- A checked link from the reachable portion of an old program to a new
program. Changed, unreachable helpers need not match. -/
structure Link (allowed : FunctionId → Bool) (symbols : Core.Relocation.Symbols)
    (original linked : Program) where
  agreement : Restriction.Agreement allowed original (Dependencies.restrict original allowed)
  matching : Core.Relocation.ProgramMatch symbols (Dependencies.restrict original allowed) linked
  internal : Execution.Internal (Dependencies.restrict original allowed)

def checkLink? (allowed : FunctionId → Bool) (symbols : Core.Relocation.Symbols)
    (original linked : Program) : Option (Link allowed symbols original linked) := do
  let ⟨agreement⟩ ← Restriction.check? original allowed
  let matching ← Core.Relocation.checkProgram? symbols (Dependencies.restrict original allowed) linked
  let ⟨internal⟩ ← Execution.checkInternal? (Dependencies.restrict original allowed)
  pure { agreement, matching, internal }

theorem Link.evaluates (link : Link allowed symbols original linked)
    (injective : Function.Injective symbols.typeId)
    (evaluated : Evaluates original before code value after)
    (closed : Dependencies.expression allowed code = true) :
    Evaluates linked (state symbols before) (Core.Relocation.expression symbols code)
      (Core.Relocation.value symbols value) (state symbols after) :=
  Execution.evaluates link.matching injective link.internal
    (Restriction.evaluates link.agreement evaluated closed)

theorem Link.executes (link : Link allowed symbols original linked)
    (injective : Function.Injective symbols.typeId)
    (executed : Executes original before code result after)
    (closed : Dependencies.statement allowed code = true) :
    Executes linked (state symbols before) (Core.Relocation.statement symbols code)
      (completion symbols result) (state symbols after) :=
  Execution.executes link.matching injective link.internal
    (Restriction.executes link.agreement executed closed)

end Lanius.Semantics.Relocation
