import Lanius.Extraction.Entry.Source
import Lanius.Extraction.Entry.Domain.Output
import Lanius.Extraction.Tests.Path
import Lanius.Extraction.Tests.File
import Lanius.Extraction.Tests.Oversize
import Lanius.Extraction.Tests.Stderr
import Lanius.Extraction.Tests.Diagnostics
import Lanius.Extraction.Tests.Load
import Lanius.Extraction.Tests.FileSyntax
import Lanius.Extraction.Tests.FileResults
import Lanius.Extraction.Tests.FileCollect
import Lanius.Extraction.Tests.FileEmit
import Lanius.Extraction.Tests.FileAdvance
import Lanius.Extraction.Tests.Next
import Lanius.Extraction.Tests.Files
import Lanius.Extraction.Tests.Startup
import Lanius.Extraction.Tests.Suffix
import Lanius.Extraction.Tests.Output
import Lanius.Extraction.Tests.FrontendLink
import Lanius.Extraction.Tests.SemanticTokens
import Lanius.Extraction.Tests.Capacity
import Lanius.Extraction.Tests.Ascii
import Lanius.Extraction.Tests.Compaction
import Lanius.Extraction.Tests.Domain
import Lanius.Extraction.Tests.Storage.Tokens
import Lanius.Extraction.Tests.Storage.Parser
import Lanius.Extraction.Tests.Storage.Tree
import Lanius.Extraction.Tests.Storage.Output
import Lanius.Extraction.Tests.Storage.Success
import Lanius.Extraction.Tests.Parser.Completeness
import Lanius.Extraction.Tests.Parser.Language
import Lanius.Extraction.Tests.Parser.Bounds
import Lanius.Extraction.Tests.Parser.Envelope
import Lanius.Extraction.Tests.Parser.TreeBounds
import Lanius.Extraction.Tests.Parser.Metadata
import Lanius.Extraction.Tests.Reduction
import Lanius.Extraction.Tests.Typing
import Lanius.Extraction.Tests.Lowering
import Lanius.Extraction.Tests.Quotation
import Lanius.Extraction.Tests.Compact.RoundTrip
import Lanius.Extraction.Tests.Compact.Bounded
import Lanius.Extraction.Tests.Surface.Views
import Lanius.Extraction.Tests.Equality
import Lanius.Extraction.Tests.Accesses
import Lanius.Extraction.Tests.Renaming
import Lanius.Extraction.Tests.Arguments
import Lanius.Extraction.Tests.Allocation
import Lanius.Extraction.Tests.Later
import Lanius.Extraction.Tests.Process
import Lanius.Extraction.Tests.Provenance
import Lean.Util.CollectAxioms

open Lanius.Extraction Lanius.Extraction.ExtractorContract Lanius.Extraction.EntrypointAnalysis

/-- Reuse the library checker's actual stage evidence for focused execution
and mutation tests. This driver does not assemble another correctness proof. -/
private def checkStages (execution : Entry.CheckedExecution accepted) : IO Unit := do
  Tests.Arguments.checkExecutable execution
  Tests.Allocation.checkExecutable execution
  Tests.Path.checkExecutable execution
  Tests.Later.checkExecutable execution
  Tests.Oversize.checkExecutable execution
  Tests.Process.checkExecutable execution
  let program := accepted.checked.program.core
  let file := execution.file
  let pipeline := file.pipeline
  let frontend := file.syntaxProof
  Tests.File.check program pipeline.reader.source.source.function.id
  Tests.CompactOutput.Text.checkExecution program execution.text.source.function.id
  Tests.Path.checkExecution program pipeline.length.function.id
  Tests.Path.checkPrefix program pipeline.length.function.id pipeline.argumentReader.function.id
  Tests.Path.checkOpenedPath program pipeline.length.function.id pipeline.argumentReader.function.id pipeline.opener.function.id
  Tests.Path.checkMissing program pipeline.length.function.id pipeline.argumentReader.function.id pipeline.opener.function.id
  Tests.Host.checkArguments program pipeline.argumentReader.function.id
  Tests.Host.checkFile program pipeline.reader.reader.function.id
  Tests.Host.checkSession program pipeline.argumentReader.function.id pipeline.opener.function.id
    pipeline.reader.reader.function.id pipeline.closer.function.id
  Tests.Stderr.check program file.diagnostics.writer.writer.function.id
  Tests.File.checkStage program pipeline.reader.source.source.function.id pipeline.closer.function.id pipeline.read
  Tests.Oversize.checkClose program pipeline.reader.source.source.function.id pipeline.closer.function.id pipeline.read pipeline.path.argument
  Tests.Load.check program pipeline.length.function.id pipeline.argumentReader.function.id pipeline.opener.function.id
    pipeline.reader.source.source.function.id pipeline.closer.function.id
    pipeline.path pipeline.argument pipeline.unpack pipeline.opened pipeline.read
  Tests.FrontendLink.check frontend file.linked
  Tests.FileSyntax.checkStage frontend.source.function.id file.syntaxStage
  Tests.FileSyntax.checkPipeline pipeline file.syntaxStage
  Tests.FileResults.check program frontend.tail.finish.constructor.typeId file.accessors.status.source.function.id
    file.accessors.nodes.source.function.id file.accessors.tokens.source.function.id file.resultsStage
  Tests.FileCollect.checkStage file.collector.source.function.id file.collectStage
  Tests.FileCollect.checkPipeline pipeline file.syntaxStage file.resultsStage file.collectStage
  Tests.SemanticTokens.checkCollectExecution program file.collector.source.function.id
  Tests.FileEmit.checkStage program frontend.tail.finish.constructor.typeId file.unitWriter.source.function.id
    file.rawCount.source.function.id file.emitStage
  Tests.FileEmit.checkPipeline pipeline file.syntaxStage file.resultsStage file.collectStage file.emitStage
  Tests.FileAdvance.check file.argument
  Tests.FileAdvance.checkPipeline pipeline file.syntaxStage file.resultsStage file.argument
  Tests.Diagnostics.checkNatural program file.diagnostics.writer.source.source.function.id
  Tests.Diagnostics.checkFrontend file.diagnostics
  let _ ← Tests.Next.checkPipeline pipeline file.syntaxStage file.resultsStage
  Tests.Next.checkReuse program pipeline.length.function.id pipeline.argumentReader.function.id pipeline.opener.function.id
    pipeline.reader.source.source.function.id pipeline.closer.function.id
    pipeline.path pipeline.argument pipeline.unpack pipeline.opened pipeline.read
  Tests.Next.checkRejectReuse program pipeline.length.function.id pipeline.argumentReader.function.id pipeline.opener.function.id
    pipeline.reader.source.source.function.id pipeline.closer.function.id
    pipeline.path pipeline.argument pipeline.unpack pipeline.opened pipeline.read
  Tests.Files.checkSource file.argument execution.arguments.entry.count file.body execution.header.continuation
  Tests.Suffix.checkSource execution.text.source.function.id execution.framing
    (execution.suffix.statement execution.text.source.function.id)
  Tests.Suffix.checkExecution program execution.text.source.function.id execution.framing.suffixText
  Tests.Output.checkSource execution.output
  Tests.Startup.checkAllocations execution.buffers execution.aliases execution.literal execution.framing file.argument
  Tests.Startup.checkFirstFile pipeline file.syntaxStage file.collectStage file.emitStage execution.header
    execution.buffers execution.aliases execution.literal execution.framing
  -- Borrow the real checked literals, including partial final packed words.
  for (storage, expected) in [(execution.framing.prefixText, modulePrefix), (execution.framing.suffixText, moduleSuffix)] do
    let length := expected.toUTF8.size
    let paddedLength := ((length + 3) / 4) * 4
    unless storage.toUTF8.size == paddedLength &&
        storage.toUTF8.data.toList.take length == expected.toUTF8.data.toList do
      throw (IO.userError "framing literal bytes or whole-word padding differ from the contract")
    let .done (.pointer address) stored := Lanius.Semantics.mapStringDataPtr {} storage
      | throw (IO.userError "framing string allocation failed")
    let .done (.slice _ _ _ _ _) _ := Lanius.Semantics.mapRawI32Slice stored address ((length + 3) / 4)
      | throw (IO.userError "framing string word view exceeds its actual storage")
  Tests.Ascii.check program file.linked.matcher
  Tests.Ascii.checkKeywords program file.linked.keywordId
  Tests.Compaction.check program frontend.symbols.canonicalize
  IO.println "actual checked stages passed host/file, dirty-buffer reuse, frontend, output, and framing regressions"

/-- Validate one singular embedding, then retain the public execution
certificate without a second extraction, source parse, or Core synthesis. -/
def main (arguments : List String) : IO UInt32 := do
  let modulePath :: envelopePath :: paths := arguments
    | throw (IO.userError "expected emitted-module, parser-envelopes, then ordered source paths")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith modulePrefix && emitted.endsWith moduleSuffix do
    throw (IO.userError "emitted module framing differs from the extraction contract")
  let encoded := ((emitted.drop modulePrefix.length).dropEnd moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : SourceFile)
  let certified ← IO.ofExcept (Entry.checkSource encoded sources)
  let accepted := certified.accepted
  let execution := certified.execution
  Tests.Provenance.checkCertified certified
  let world : Lanius.World.State := {
    arguments := "extractor" :: sources.map (·.path)
    files := sources.map fun source =>
      ⟨Lanius.World.utf8Bytes source.path, source.bytes.map UInt8.ofNat⟩ }
  let some domain := Entry.checkLoadingDomain? world
    | throw (IO.userError "actual self-source closure is outside the proved loading domain")
  have _selfTerminates := execution.terminates domain.down
  have _selfSound := execution.run_sound domain.down
  have _selfFailureSafe := execution.run_failureSafe domain.down
  let some hostDomain := Entry.checkHostDomain? world
    | throw (IO.userError "self-source process violates the explicit host bounds")
  have _selfHostSafe := execution.hostSafe hostDomain.down
  let tokenStarted ← IO.monoNanosNow
  let some tokenDomain := execution.checkTokenDomain?
    | throw (IO.userError "actual self-source closure exceeds the source-checked token capacities")
  let tokenFinished ← IO.monoNanosNow
  have _selfTokenStorage : Entry.TokenDomain sources := tokenDomain.down
  have _selfSyntax : Entry.SyntaxDomain sources := execution.syntaxDomain
  let envelopeBytes ← IO.FS.readBinFile envelopePath
  let some candidates := Lanius.Compiler.Parser.Envelope.decode? envelopeBytes
    | throw (IO.userError "malformed parser-envelope transport")
  let parserStarted ← IO.monoNanosNow
  let some parserTreeDomain := execution.checkParserTreeDomain? candidates
    | throw (IO.userError "self-source parser/tree resources are missing, not closed, cyclic, or exceed capacity")
  let parserFinished ← IO.monoNanosNow
  have _selfParserStorage : Entry.ParserDomain sources := parserTreeDomain.parser
  have _selfTreeStorage : Entry.TreeDomain sources := parserTreeDomain.tree
  let outputStarted ← IO.monoNanosNow
  let some outputDomain := parserTreeDomain.checkOutputDomain? 16777216
    | throw (IO.userError "self-source output bound exceeds the actual module allocation")
  let outputFinished ← IO.monoNanosNow
  have _selfOutputStorage : Entry.OutputDomain sources 16777216 := outputDomain.domain
  let successStarted ← IO.monoNanosNow
  let some successDomain := outputDomain.checkSuccessDomain? tokenDomain.down execution.syntaxDomain
      parserTreeDomain.parser parserTreeDomain.tree world
    | throw (IO.userError "self-source process inputs do not match the proved successful-input domain")
  let successFinished ← IO.monoNanosNow
  have _selfComplete := execution.run_complete domain.down
  have _selfSuccessful := execution.succeeds domain.down successDomain.down
  Tests.Storage.Success.checkInputs outputDomain tokenDomain.down execution.syntaxDomain
    parserTreeDomain.parser parserTreeDomain.tree world
  Tests.Storage.Output.checkRawEvidence accepted.checked.program.surfaceData parserTreeDomain.units
  Tests.Storage.Output.checkCapacity outputDomain.units
  Tests.Storage.Tree.check accepted.checked.program.surfaceData candidates
  checkStages execution
  IO.println s!"exact self-embedding accepted ({sources.length} files); public whole-executable certificate retained"
  IO.println "the library checker constructs frontend links and all main phases; soundness, failure safety, and finite termination are available to consumers"
  IO.println "the actual self-source process world satisfies the loading domain; termination and public contracts instantiated without assumed input-domain evidence"
  IO.println "all self-source files satisfy the lexical/token-storage domain at the authenticated call capacities; file-loop lexer and token-buffer failures are excluded"
  IO.println s!"numeric token-storage check: {(tokenFinished - tokenStarted) / 1000} microseconds (existing syntax evidence reused)"
  IO.println s!"all {candidates.length} self-source parser/tree resource certificates checked in {(parserFinished - parserStarted) / 1000000} ms"
  IO.println s!"source-only full-module output bound: {Entry.moduleFramingBytes + outputDomain.units.bounds.sum} / 16777216 bytes; output-domain checking took {(outputFinished - outputStarted) / 1000} microseconds"
  IO.println "source-bound lexical, syntax, parser, and tree domains establish actual frontend success; the checked output bound covers the actual emitter and every recognized tree"
  IO.println s!"the public RunComplete theorem is instantiated on the actual self-source world: enough fuel gives return zero and exact certified output; input binding took {(successFinished - successStarted) / 1000} microseconds"
  IO.println "host-bounded invocations have exhaustive safety/termination coverage; persisted kernel self-acceptance, final milestone audit, native x86 correctness, and the trusted fast path remain open"
  return 0

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Entry.CheckedExecution.run_sound, ``Entry.CheckedExecution.run_failureSafe,
      ``Entry.CheckedExecution.terminates, ``Entry.CheckedExecution.run_complete,
      ``Entry.CheckedExecution.succeeds] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Public execution-certificate projection {name} adds unexpected axiom {assumption}"
  for name in #[``Entry.File.step, ``Entry.File.Checked.executes, ``Entry.Files.executes,
      ``Entry.Startup.executes, ``Entry.checkExecution, ``Entry.checkSource] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Whole-extractor execution theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "The actual whole-extractor execution constructors and combined source checker use only standard Lean axioms. This generic audit does not certify a concrete self-instance."
