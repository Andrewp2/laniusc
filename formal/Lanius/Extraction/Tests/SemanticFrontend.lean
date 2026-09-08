import Lanius.Extraction.SemanticTokens.Pipeline
import Lean.Util.CollectAxioms

open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Extraction Lanius.Extraction.SemanticTokens

-- The proof-facing token view must preserve byte offsets and enum codes;
-- it must not retokenize, pack split halves, or renumber the input spans.
private def checkTokenView : IO Unit := do
  let values : List RawToken := [⟨.identifier, 0, 3⟩, ⟨.identifier, 7, 12⟩]
  for tokens in [[], values, values.reverse, values ++ values] do
    let converted := artifactTokens tokens
    unless converted.length == tokens.length &&
        converted.map (fun token => (token.kind, token.span.file, token.span.start, token.span.finish)) ==
          tokens.map (fun token => (token.kind.gpuCode, 0, token.start, token.finish)) do
      throw (IO.userError "collector handoff changed canonical token kinds, order, or byte spans")
#eval checkTokenView

-- Enforce the trust boundary instead of merely printing it. The new
-- collector/adapter proofs are kernel checked with standard Lean axioms.
-- The composed frontend call still carries its explicit legacy native debt.
run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  let newTheorems := #[``Collect.CheckedCollect.call_evaluates, ``Collect.CheckedCollect.short_capacity_call,
    ``frontend_result, ``FrontendResult.collect, ``collect_after_frontend]
  for name in newTheorems do
    unless (← Lean.getEnv).contains name do throwError "missing audited theorem {name}"
    let axioms ← Lean.collectAxioms name
    unless axioms.all standard.contains do
      throwError "new trust assumption in {name}: {axioms.filter (fun ax => !standard.contains ax)}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  let composed ← Lean.collectAxioms ``frontend_then_collect
  unless composed.all (fun ax => standard.contains ax || baseline.contains ax) do
    throwError "collector composition added frontend trust assumptions"
  let inherited := composed.filter (fun ax => !standard.contains ax)
  Lean.logInfo m!"Five collector/handoff theorems use only standard Lean axioms. The two-call composition retains {inherited.size} existing frontend-specific assumptions and adds none."

#print axioms frontend_result
#print axioms FrontendResult.collect
#print axioms collect_after_frontend
