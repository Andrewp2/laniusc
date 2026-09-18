import Lanius.Extraction.Entry.File.Advance
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.FileAdvance
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput Lanius.Extraction.Entry.File

def check (argument : VarId) : IO Unit := do
  unless (Advance.check? (Advance.statement argument)).isSome do
    throw (IO.userError "exact file-index increment rejected")
  for amount in [0, 2, 17] do
    if (Advance.check? (.sequence (.expression (.assign .add (.local argument) (number amount))) .skip)).isSome then
      throw (IO.userError "file-index increment accepted a changed step")
  for index in [0, 1, 127, 2147483646] do
    let before := ({ cells := [⟨0, some (.array (signedI32Values [65, 97, 48]))⟩], nextCell := 1 } : State).bindLocal argument (.signed .i32 index)
    let .done .next after := execStmt 20 {} before (Advance.statement argument)
      | throw (IO.userError "file-index increment did not finish normally")
    unless after.local? argument == some (.signed .i32 (index + 1)) && after.locals == before.locals &&
        after.cell? 0 == before.cell? 0 && after.world.calls == before.world.calls && after.nextCell == before.nextCell do
      throw (IO.userError "file-index increment failed to preserve output or advance the existing local")

def checkPipeline (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) (argument : VarId) : IO Unit := do
  unless (Advance.checkRelation? pipeline syntaxStage resultsStage argument).isSome do
    throw (IO.userError "file-index increment does not update the selected argument or is shadowed by the file body")
  for changed in pipeline.boundLocals ++ [syntaxStage.result, resultsStage.nodes, resultsStage.tokens, argument + 1] do
    if (Advance.checkRelation? pipeline syntaxStage resultsStage changed).isSome then
      throw (IO.userError "file-index increment accepted an unrelated or shadowed binding")

#eval check 7

run_elab do
  for name in #[``Advance.finishes, ``FrontendReturn.original_binding, ``Lanius.Extraction.Entry.Scope.Post.inScope,
      ``Lanius.Extraction.Entry.Scope.Post.inScope_iff] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "file-index/state handoff {name} adds unexpected axiom {assumption}"
  Lean.logInfo "File-index increment preserves the original cursor cells and emitted output, using standard axioms only."

end Lanius.Extraction.Tests.FileAdvance
