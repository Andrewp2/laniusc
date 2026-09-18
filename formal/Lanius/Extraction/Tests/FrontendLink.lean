import Lanius.Extraction.Frontend.Link
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.FrontendLink
open Lanius Lanius.Core Lanius.Extraction.Frontend

/-- Exercise authentication with the actual source-linked proof programs.
The production checker owns link construction; tests do not reconstruct a
second link from external JSON. Preserve the former guard/tail regressions. -/
def check {program : CoreSynthesis.Program.CheckedProgram artifacts}
    {visit : ParserTreeSource.CheckedVisit program}
    {materializer : ParserTreeSource.CheckedMaterialize visit}
    (source : CheckedSyntax materializer) (linked : LinkedSyntax source) : IO Unit := do
  for changed in [
      { linked.lexerSymbols with functionId := fun id => linked.lexerSymbols.functionId id + 1 },
      { linked.lexerSymbols with constantId := fun id => linked.lexerSymbols.constantId id + 1 },
      { linked.lexerSymbols with typeId := fun id => linked.lexerSymbols.typeId id + 1000000 }] do
    if (Semantics.Relocation.checkLink? linked.lexerAllowed changed verifiedFrontendCore program.core).isSome then
      throw (IO.userError "frontend link accepted a different lexer function, constant, or result-type mapping")
  let lexerId := source.symbols.lexer
  let missing : Program := { program.core with
    functions := program.core.functions.filter (fun function => function.id != lexerId) }
  let changed : Program := { program.core with
    functions := program.core.functions.map (fun function =>
      if function.id == lexerId then { function with body := some .skip } else function) }
  for current in [missing, changed] do
    if (Semantics.Relocation.checkLink? linked.lexerAllowed linked.lexerSymbols verifiedFrontendCore current).isSome then
      throw (IO.userError "frontend link accepted a missing or changed lexer body")
  for functions in [true, false] do
    let changed := { linked.parserSymbols with
      functionId := fun id => linked.parserSymbols.functionId id + (if functions then 1 else 0)
      constantId := fun id => linked.parserSymbols.constantId id + (if functions then 0 else 1) }
    if (ParserDerivation.checkLinkedReader? visit.reader linked.parserAllowed changed linked.reader.injective).isSome then
      throw (IO.userError "frontend link accepted a different parser function or constant mapping")
  let rest := tokenizationBody source.symbols source.early.lexicalBody source.early.canonicalBody
    (recognitionBody source.parserId source.parserType source.early.kindsBody source.tail.body)
  let reordered := inputGuards source.tail.finish.constructor.source.function.id source.inputs.badInput
    inputLengths.reverse rest
  let inserted := Stmt.sequence .skip (source.inputs.body rest)
  unless (checkInput? source.tail.finish.constructor reordered rest).isNone &&
      (checkInput? source.tail.finish.constructor inserted rest).isNone do
    throw (IO.userError "whole frontend accepted reordered input guards or an extra leading statement")
  let some tokenization := findTokenization? (source.inputs.body rest)
    | throw (IO.userError "checked frontend lost its complete tokenization prefix")
  let some recognition := checkRecognitionStage? tokenization.locals.rest
    | throw (IO.userError "checked frontend lost its adjacent recognizer call")
  let swappedTokenization := { tokenization.locals with storageFailure := source.early.kindsBody }
  let swappedRecognition := { recognition.locals with storageFailure := source.early.canonicalBody }
  unless (checkEarly? source.tail.finish.constructor swappedTokenization recognition.locals).isNone &&
      (checkEarly? source.tail.finish.constructor tokenization.locals swappedRecognition).isNone do
    throw (IO.userError "early-return checker accepted interchanged canonical/kind failure fields")
  let wrongArguments := materializeArguments.set 3 (.local 18)
  let wrongCount : Stmt := .sequence (.ifThenElse source.tail.condition source.tail.rejected .skip)
    (.letLocal 23 (.structure visit.symbols.resultType) (.call materializer.source.function.id wrongArguments)
      (finishBody source.tail.finish.symbols))
  let wrongStage := finishBody { source.tail.finish.symbols with failure := source.tail.finish.successId }
  unless (checkAfterParse? materializer wrongCount).isNone && (checkFinish? visit wrongStage).isNone do
    throw (IO.userError "frontend accepted a raw-count materializer argument or success-tagged tree failure")
  IO.println "constructed frontend link rejected seven mapping/body mutations and six guard/continuation mutations"

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  -- Audit the actual execution constructors and source/link checkers. An
  -- inherited baseline could conceal a regression in their shared dependencies.
  for name in #[``Frontend.lex_to_recognize,
      ``Frontend.CheckedSyntax.call_evaluates,
      ``Frontend.CheckedSyntax.call_native,
      ``Frontend.CheckedSyntax.reject_call,
      ``Frontend.checkSyntax?, ``Frontend.checkLinkedSyntax?] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Frontend execution or authentication {name} adds unexpected axiom {assumption}"
  Lean.logInfo "The connected frontend call, negative-length rejection, and source/link checkers use only standard Lean axioms."

end Lanius.Extraction.Tests.FrontendLink
