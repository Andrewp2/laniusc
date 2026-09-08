import Lanius.Extraction.Frontend.Body
import Lanius.Extraction.Frontend.Input

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CoreSynthesis.Program Lanius.Extraction.ParserTreeSource

variable {program : CheckedProgram artifacts} {visit : CheckedVisit program}

def syntaxParameters : List (VarId × Ty) :=
  let int := Ty.scalar (.signed .i32)
  [(0, .slice int), (1, int), (2, .slice int), (3, int), (4, .slice int), (5, int),
    (6, .slice int), (7, int), (8, .slice int), (9, int), (10, .slice int), (11, int),
    (12, .slice int), (13, int), (14, .slice int), (15, int), (16, int)]

def syntaxFunctionBody {materializer : CheckedMaterialize visit}
    (tail : CheckedAfterParse materializer) (early : CheckedEarly program symbols)
    (inputs : CheckedInput tail.finish.constructor) (parserId : FunctionId) (parserType : TypeId) : Stmt :=
  inputs.body (tokenizationBody symbols early.lexicalBody early.canonicalBody
    (recognitionBody parserId parserType early.kindsBody tail.body))

/-- Whole-function evidence, not a matching statement found somewhere inside
the source. The eight guards and every later branch share one return type. -/
structure CheckedSyntax (materializer : CheckedMaterialize visit) where
  source : CheckedSourceFunction program ["verified", "extraction"] "extract_syntax"
  tail : CheckedAfterParse materializer
  symbols : TokenizationSymbols
  parserId : FunctionId
  parserType : TypeId
  early : CheckedEarly program symbols
  sameConstructor : early.constructor = tail.finish.constructor
  inputs : CheckedInput tail.finish.constructor
  signature : source.function.parameters = syntaxParameters ∧
    source.function.returnType = .structure tail.finish.constructor.typeId ∧ source.function.external = none
  body : source.function.body = some (syntaxFunctionBody tail early inputs parserId parserType)

/-- Check the signature and entire current public function in one pass through
the existing component matchers. Extra statements before/between/after regions,
changed guard order, or a different result constructor cannot be hidden. -/
def checkSyntax? (materializer : CheckedMaterialize visit) : Option (CheckedSyntax materializer) := do
  let source ← checkSourceFunction? program ["verified", "extraction"] "extract_syntax"
  match present : source.function.body with
  | some body => do
    let tokenization ← findTokenization? body
    let recognition ← checkRecognitionStage? tokenization.locals.rest
    let ⟨tail, _⟩ ← checkAfterParse? materializer recognition.locals.rest
    let early ← checkEarly? tail.finish.constructor tokenization.locals recognition.locals
    let rest := tokenizationBody tokenization.locals.symbols early.checked.lexicalBody early.checked.canonicalBody
      (recognitionBody recognition.locals.functionId recognition.locals.resultType early.checked.kindsBody tail.body)
    let ⟨inputs, full⟩ ← checkInput? tail.finish.constructor body rest
    if signature : source.function.parameters = syntaxParameters ∧
        source.function.returnType = .structure tail.finish.constructor.typeId ∧ source.function.external = none then
      pure ⟨source, tail, tokenization.locals.symbols, recognition.locals.functionId, recognition.locals.resultType,
        early.checked, early.result, inputs, signature, present.trans (congrArg some full.equal)⟩
    else none
  | none => none

end Lanius.Extraction.Frontend
