import Lanius.Extraction.Parser.Derivation.Source
import Lanius.CallContracts
import Lanius.Semantics.Sequence

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.CallContracts
open Lanius.Properties
open Lanius.Separation

/-- Use a proved store fragment at its exact grouping in the source body. -/
theorem ChildStores.continue (stores : ChildStores)
    (execution : Executes program before stores.fragment .next middle)
    (continuation : Executes program middle stores.rest completion after) :
    Executes program before stores.body completion after := by
  obtain ⟨between, first, remaining⟩ := executesSequenceNext_inv execution
  exact executesSequence first (executesSequence_continue remaining continuation)

/-- Lift an execution of the exact checked reader body to its source call.
    This does not assert the still-required body correctness theorem. -/
theorem CheckedReader.call_returns (reader : CheckedReader program)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [workspace, workspaceLength, tokenCount, stateCount, stateId, output,
       outputLength, outputOffset] afterArguments)
    (bodyResult : Executes program.core
      (enterCall afterArguments [(0, workspace), (1, workspaceLength), (2, tokenCount),
        (3, stateCount), (4, stateId), (5, output), (6, outputLength), (7, outputOffset)])
      reader.body (.returned (some result)) completed) :
    Evaluates program.core before (.call reader.source.function.id arguments) result
      (restoreLocals afterArguments completed) := by
  have identity : reader.source.function.id = reader.source.source.id := by
    simpa [Program.function?] using List.find?_some reader.source.found
  have found : program.core.function? reader.source.function.id = some reader.source.function := by
    rw [identity]
    exact reader.source.found
  exact evaluatesCallReturned argumentsResult found
    (reader.bind_parameters workspace workspaceLength tokenCount stateCount stateId
      output outputLength outputOffset) reader.bodyPresent bodyResult

end Lanius.Extraction.ParserDerivation
