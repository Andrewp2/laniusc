import Lanius.Extraction.Parser.Derivation.Entry
import Lanius.Extraction.Parser.Derivation.Linked
import Lanius.Extraction.Parser.Derivation.Call

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics
open Lanius.CallContracts Lanius.Separation
open Lanius.Extraction.ParserRecognize

/-- The checked source's local coordinates, with the standalone accessor
    and field selector used by the execution proof. -/
def CheckedReader.standaloneStores (reader : CheckedReader program) : ChildStores :=
  { reader.stores.locals with accessor := extractedParserStateValueFunction.id, selector := 36 }

def CheckedReader.standaloneTail (reader : CheckedReader program) : CheckedCursorTail reader.standaloneStores :=
  { previous := reader.cursorTail.previous
    remaining := reader.cursorTail.remaining
    exactTail := reader.cursorTail.exactTail }

def CheckedReader.standaloneBody (reader : CheckedReader program) : Stmt :=
  readerEntry reader.standaloneStores reader.standaloneTail 10 11 7 2 9 4 3 6 1 28

/-- Instantiate the execution theorem's runtime in the checked source's
    local coordinates. Cursor cells are assigned only when their scopes
    are entered, so these initial placeholders carry no ownership claim. -/
def CheckedReader.runtime (reader : CheckedReader program)
    (layout : Lanius.Compiler.Parser.WorkspaceLayout)
    (workspace : Lanius.Compiler.Parser.LogicalWorkspace)
    (workspaceValues outputValues : List Int) (workspaceCell outputCell : CellId) (offset : Nat) : ReaderRuntime :=
  { stores := reader.standaloneStores, tail := reader.standaloneTail
    offsetId := 7, tokenCountId := 2, layout, workspace, workspaceValues, outputValues
    workspaceCell, outputCell, currentCell := 0, remainingCell := 0, offset, tokenCount := layout.tokenCount }

theorem CheckedReader.runtime_body (reader : CheckedReader program) :
    (reader.runtime layout workspace workspaceValues outputValues workspaceCell outputCell offset).entryBody
      1 4 3 6 9 10 11 = reader.standaloneBody := by
  exact (reader.runtime layout workspace workspaceValues outputValues workspaceCell outputCell offset).entryBody_source rfl

/-- Evidence connecting the complete standalone reader execution to the
    actual current source body. Both program lookup and statement equality
    are checked; neither is an execution assumption. -/
structure LinkedReader (reader : CheckedReader program)
    (allowed : Lanius.FunctionId → Bool) (symbols : Core.Relocation.Symbols) where
  link : Semantics.Relocation.Link allowed symbols verifiedParserCore program.core
  injective : Function.Injective symbols.typeId
  accessorAllowed : allowed extractedParserStateValueFunction.id = true
  bodyMatch : reader.body = Core.Relocation.statement symbols reader.standaloneBody

def checkLinkedReader? (reader : CheckedReader program)
    (allowed : Lanius.FunctionId → Bool) (symbols : Core.Relocation.Symbols)
    (injective : Function.Injective symbols.typeId) : Option (LinkedReader reader allowed symbols) := do
  let link ← Semantics.Relocation.checkLink? allowed symbols verifiedParserCore program.core
  let matching ← Core.Equality.statement? reader.body (Core.Relocation.statement symbols reader.standaloneBody)
  if accessorAllowed : allowed extractedParserStateValueFunction.id = true then
    pure ⟨link, injective, accessorAllowed, matching.equal⟩
  else none

/-- Transport the reader's execution, including its returned value, into
    the current checked source program. -/
theorem LinkedReader.executes {reader : CheckedReader program} (checked : LinkedReader reader allowed symbols)
    (execution : Executes verifiedParserCore before reader.standaloneBody result after) :
    Executes program.core (Semantics.Relocation.state symbols before) reader.body
      (Semantics.Relocation.completion symbols result) (Semantics.Relocation.state symbols after) := by
  have closed := reader.standaloneTail.entry_closed checked.accessorAllowed 10 11 7 2 9 4 3 6 1 28
  have transported := checked.link.executes checked.injective execution closed
  rw [← checked.bodyMatch] at transported
  exact transported

/-- Compose argument evaluation, checked execution transport, and the
    current reader's call boundary. The entered-state equality identifies
    the original proof's runtime with the actual caller's bound parameters. -/
theorem LinkedReader.call_returns {reader : CheckedReader program}
    (checked : LinkedReader reader allowed symbols)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program.core caller arguments
      [workspace, workspaceLength, tokenCount, stateCount, stateId, output,
        outputLength, outputOffset] afterArguments)
    (entered : Semantics.Relocation.state symbols before =
      enterCall afterArguments [(0, workspace), (1, workspaceLength), (2, tokenCount),
        (3, stateCount), (4, stateId), (5, output), (6, outputLength), (7, outputOffset)])
    (execution : Executes verifiedParserCore before reader.standaloneBody (.returned (some result)) after) :
    Evaluates program.core caller (.call reader.source.function.id arguments)
      (Core.Relocation.value symbols result)
      (restoreLocals afterArguments (Semantics.Relocation.state symbols after)) := by
  apply reader.call_returns argumentsResult
  rw [← entered]
  exact checked.executes execution

end Lanius.Extraction.ParserDerivation
