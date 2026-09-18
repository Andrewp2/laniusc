import Lanius.Extraction.Entry.Certificate
import Lanius.Extraction.Frontend.Link
import Lanius.Extraction.Entry.Startup.Reject
import Lanius.Extraction.Entry.Startup.Oversize

namespace Lanius.Extraction.Entry
open Lanius.Extraction Lanius.Extraction.ExtractorContract Lanius.Extraction.EntrypointAnalysis

/-- Authenticate the complete source and retain its whole-executable theorem.
The accepted singular embedding is consumed directly: this performs no second
extraction, source parse, or Core synthesis. All stage executions and runtime
resources are derived; failure identifies the rejected source boundary. -/
def checkExecution (checked : CheckedExtractorCoreSourcePack encoded sources) :
    Except String (CheckedExecution checked) := do
  let some frontendSource := CoreSynthesis.Program.checkSourceFunction? checked.checked.program ["verified", "extraction"] "extract_syntax"
    | throw "checked extract_syntax source function was not found"
  let reachable := Lanius.Core.Dependencies.closure checked.checked.program.core [frontendSource.source.id]
  let allowed := fun id => reachable.contains id
  let capacityProof : PLift (Lanius.Semantics.Capacity.Fragment.Checked checked.checked.program.core allowed) ←
    if accepted : Lanius.Semantics.Capacity.Fragment.check checked.checked.program.core allowed = true then do
      pure ⟨Lanius.Semantics.Capacity.Fragment.checked accepted⟩
    else
      throw "extract_syntax closure contains an operation not covered by capacity-extension execution transport"
  let some outputByte := CompactOutput.checkByte? checked.checked.program
    | throw "output byte helper differs from its execution proof"
  let some fileInput := Input.File.check? checked.checked.program
    | throw "read_file differs from its full checked body, signature, or scratch-size constant"
  let some outputText := CompactOutput.Text.check? checked.checked.program outputByte
    | throw "output text helper differs from its checked source shape"
  let some outputDigit := CompactOutput.checkDigit? checked.checked.program
    | throw "hex digit helper differs from its execution proof"
  let some outputWord := CompactOutput.Word.check? checked.checked.program outputByte outputDigit
    | throw "hex word helper differs from its execution proof"
  let some packHeader := CompactOutput.PackHeader.check? checked.checked.program outputByte outputDigit outputWord
    | throw "compact header helper differs from its execution proof"
  let some hex := Entry.Hex.check? checked.checked.program
    | throw "hex_nibble source differs from the proved lowercase-hex decoder"
  let some entry := Entry.checkArguments? checked.checked.program.core checked.analysis.body
    | throw "checked main does not start with the proved argc/argument-guard sequence"
  let some allocator := checked.checked.program.core.functions.find? fun function =>
      function.body.isNone && function.external == some (.host .alloc)
    | throw "checked allocator declaration was not found"
  let some allocatorProof := Allocation.checkAllocator? checked.checked.program.core allocator.id
    | throw "host allocator declaration does not satisfy the sequence theorem"
  let some allocations := Allocation.checkSequence? allocatorProof.function.id Allocation.extractorCounts entry.entry.continuation
    | throw "checked main does not contain the exact 13-buffer host allocation sequence"
  let some pointers := Entry.Pointers.checkPreparation? 3 allocations.locals.continuation
    | throw "post-allocation continuation lacks the three required pointer aliases"
  let initialPointers := allocations.locals.buffers.map (fun buffer => Entry.Pointers.Pointer.slice buffer.binding)
  let some pointerSupport := pointers.locals.checkSupported? initialPointers
    | throw "pointer aliases read an unavailable or shadowed buffer"
  let some names := allocations.locals.distinctNames?
    | throw "allocation sequence shadows a buffer binding"
  let some literal := Entry.Grammar.checkLiteral? hex.source.function.id pointers.locals.continuation
    | throw "post-alias grammar literal/setup is not the exact checked prefix"
  let some literalData := Entry.Grammar.checkLiteralData? Entry.Grammar.indexedLanius literal.locals.text
    | throw "embedded grammar literal does not encode the parser's formal Lanius grammar"
  let some literalSupport := literal.locals.checkSupported? literalData.values.length
    | throw "grammar initialization count or local shadowing violates the execution proof"
  let some framing := Entry.Framing.check? outputText.source.function.id literal.locals.setup.cursor.continuation
    | throw "grammar continuation differs from the proved framing literals, text call, and guard"
  let some framingSupport := framing.locals.checkSupported?
    | throw "actual framing literals, capacity, or shadowing violate the execution proof"
  let some grammarBuffer := Entry.checkBuffer? allocations.locals.buffers pointers.locals.aliases
      literal.locals.setup.cursor.locals.destination literalData.values.length
    | throw "grammar destination does not match a sufficiently sized, unshadowed entry allocation"
  let some outputBuffer := Entry.checkBuffer? allocations.locals.buffers pointers.locals.aliases
      framing.locals.output framing.locals.capacity
    | throw "framing output is not a sufficiently sized, unshadowed entry allocation"
  let some outputPreserved := Entry.framingPreserved? outputBuffer.buffer grammarBuffer.buffer literal.locals
    | throw "grammar initialization overwrites or shadows the framing output buffer"
  let some header := Entry.Header.check? packHeader.source.function.id framing.locals.continuation
    | throw "framing continuation differs from the compact-header call, cursor assignment, or guard"
  unless header.locals.output == framing.locals.output && header.locals.position == framing.locals.position &&
      header.locals.capacity == framing.locals.capacity && header.locals.count == entry.entry.count do
    throw "compact header uses different output, cursor, capacity, or argc bindings"
  let some headerRelation := Entry.Framing.checkHeaderRelation? framing.locals header.locals
    | throw "framing shadows the compact header's count or output binding"
  let some countPreserved := Entry.countPreserved? entry.entry.count allocations.locals pointers.locals literal.locals
    | throw "startup shadows the original argc binding"
  let some startupSupport := (if valid : header.locals.count = entry.entry.count ∧
      Entry.Framing.bytes.length + 16 ≤ framing.locals.capacity then some (PLift.up valid) else none)
    | throw "compact-header startup count or capacity is unsupported"
  have completeStartup := Entry.Startup.reaches entry allocatorProof allocations.locals allocations.exactSource
    pointers.locals pointers.exactSource names.proof pointerSupport hex literal.locals literal.exactSource
    literalData literalSupport grammarBuffer framing.locals outputText framing.exactSource framingSupport
    outputBuffer outputPreserved.down header.locals packHeader header.exactSource headerRelation
    startupSupport.down.1 countPreserved.down startupSupport.down.2
  let .letLocal argumentId _ (.value (.signed .i32 1))
      (.sequence (.whileLoop (.binary .notEqual (.local readArgument) (.local readCount)) fileBody) _) :=
      header.locals.continuation
    | throw "ordered-file phase lacks its initial argument cursor or loop condition"
  let .letLocal _ _ (.call lengthId _) _ := fileBody
    | throw "ordered-file body does not begin with argument length"
  let some lengthHost := Host.checkLength? checked.checked.program.core lengthId
    | throw "ordered-file length call is not the modeled arg_len service"
  let some pathLength := Entry.Path.Length.check? lengthHost.function.id fileBody
    | throw "actual path-length call or guard differs from its execution proof"
  unless argumentId == readArgument && readCount == entry.entry.count &&
      pathLength.locals.argument == argumentId do
    throw "path length reads a different index from the ordered-file cursor"
  let .sequence (.ifThenElse (.binary .notEqual (.call argumentReadId _) _) _ _) _ :=
      pathLength.locals.continuation
    | throw "path-length continuation does not begin with its argument-read count guard"
  let some argumentReader := Host.checkExternal? checked.checked.program.core .argRead 3 argumentReadId
    | throw "path copy is not the modeled arg_read service"
  let some pathRead := Entry.Path.Read.check? argumentReader.function.id pathLength.locals.continuation
    | throw "actual argument read, usize cast, or count guard differs from its execution proof"
  let some pathRelation := Entry.Path.checkRelation? pathLength.locals pathRead.locals
    | throw "path copy reads a different argument/length or a shadowed pointer"
  let findHost := fun service => checked.checked.program.core.functions.find? fun function =>
    function.body.isNone && function.external == some (.host service)
  let some opener := findHost .openRead
    | throw "checked file opener was not found"
  let some closer := findHost .close
    | throw "checked file closer was not found"
  let some pathUnpack := Input.Unpack.check? pathRead.locals.continuation
    | throw "actual path unpack initialization or loop differs from its execution proof"
  let some unpackSupport := pathUnpack.locals.checkSupported?
    | throw "path unpack loop has an offset or shadows a live input binding"
  let some unpackRelation := Entry.Path.checkUnpackRelation? pathLength.locals pathRead.locals pathUnpack.locals
    | throw "path unpack does not use the copied length or shadows a slice binding"
  let some openHost := Host.checkExternal? checked.checked.program.core .openRead 2 opener.id
    | throw "checked file opener has the wrong service or arity"
  let some fileOpen := Entry.File.Open.check? openHost.function.id pathUnpack.locals.continuation
    | throw "path continuation differs from the exact open call and negative-handle guard"
  let some closeHost := Host.checkExternal? checked.checked.program.core .close 1 closer.id
    | throw "checked closer has the wrong service or arity"
  let some readClose := Entry.File.Read.check? fileInput.source.source.function.id closeHost.function.id fileOpen.locals.continuation
    | throw "file caller differs from the proved read/close/success-guard sequence"
  let some readCloseSupport := readClose.locals.checkSupported?
    | throw "file caller shadows the handle or read count"
  let some readFailure := Diagnostics.Read.check? checked.checked.program pathLength.locals.argument readClose.locals.count readClose.locals.failure
    | throw "read/close diagnostics or classified code 6 differ from the execution proof"
  let some openRelation := Entry.File.checkPathRelation? pathRead.locals pathUnpack.locals fileOpen.locals
    | throw "file open uses a different path pointer/length or the unpack cursor shadows its pointer"
  let some loadRelation := Entry.File.Load.checkRelation? pathLength.locals pathUnpack.locals fileOpen.locals readClose.locals
    | throw "path/open prefix shadows a reader input or read_file uses a different handle"
  let loadPipeline : Entry.File.Load.Pipeline checked.checked.program := {
    length := lengthHost
    path := pathLength.locals
    argumentReader
    argument := pathRead.locals
    argumentSource := pathRead.exactSource
    argumentRelation := pathRelation
    unpack := pathUnpack.locals
    unpackSource := pathUnpack.exactSource
    unpackSupported := unpackSupport.down
    unpackRelation := unpackRelation.down
    opener := openHost
    opened := fileOpen.locals
    openSource := fileOpen.exactSource
    openRelation := openRelation.down
    reader := fileInput
    closer := closeHost
    read := readClose.locals
    readSource := readClose.exactSource
    readSupported := readCloseSupport.down
    readRelation := loadRelation.down }
  let some derivationReader := ParserDerivation.checkReader? checked.checked.program
    | throw "file/frontend handoff lacks the checked derivation reader"
  let some tree := ParserTreeSource.checkVisit? checked.checked.program derivationReader
    | throw "file/frontend handoff lacks the checked tree traversal"
  let some materializer := ParserTreeSource.checkMaterialize? tree
    | throw "file/frontend handoff lacks the checked materializer"
  let some publicSyntax := Frontend.checkSyntax? materializer
    | throw "file/frontend handoff lacks the checked whole frontend body"
  let some linked := Frontend.checkLinkedSyntax? publicSyntax
    | throw "current frontend could not be connected to the lexer, canonicalizer, and parser execution proofs"
  let some syntaxStage := Entry.File.Syntax.check? publicSyntax.source.function.id readClose.locals.continuation
    | throw "loaded source does not feed the exact 17-argument frontend call"
  let some syntaxRelation := Entry.File.Syntax.checkRelation? loadPipeline syntaxStage.locals
    | throw "loaded source count or surviving frontend buffer bindings are disconnected"
  let some accessors := Entry.File.Results.checkAccessors? checked.checked.program publicSyntax.tail.finish.constructor.typeId
    | throw "frontend-result status/node/token projections differ from their proved bodies"
  let some resultsStage := Entry.File.Results.check? accessors.status.source.function.id accessors.nodes.source.function.id
      accessors.tokens.source.function.id syntaxStage.locals.continuation
    | throw "frontend continuation differs from the actual success guard and node/token bindings"
  let some resultsSupport := resultsStage.locals.checkSupported?
    | throw "frontend-result continuation shadows a live binding or lets diagnostics fall through"
  let some resultsBinding := (if same : resultsStage.locals.result = syntaxStage.locals.result then some (PLift.up same) else none)
    | throw "frontend-result accessors do not consume the actual extracted result binding"
  let some collector := SemanticTokens.Collect.checkCollect? checked.checked.program
    | throw "collector body differs from its checked traversal proof"
  let some collectStage := Entry.File.Collect.check? collector.source.function.id resultsStage.locals.continuation
    | throw "count bindings do not feed the exact collector call and error guard"
  let some collectMemory := Lanius.Semantics.CellOnly.checkRegion? checked.checked.program.core
      (.expression (.call collector.source.function.id collectStage.locals.arguments))
    | throw "collector call or a transitive helper changes native heap/view metadata"
  let some collectRelation := Entry.File.Collect.checkRelation? loadPipeline syntaxStage.locals resultsStage.locals collectStage.locals
    | throw "collector buffers/counts are disconnected or shadowed by the preceding prefix"
  let some rawCount := Source.checkProjection? checked.checked.program ["verified", "extraction"] "raw_count"
      publicSyntax.tail.finish.constructor.typeId 2
    | throw "emitter raw-count accessor differs from its exact result projection"
  let some outputHex := CompactOutput.checkHexByte? checked.checked.program outputByte outputDigit
    | throw "emitter hex-byte helper differs from its checked body"
  let some outputBytes := CompactOutput.Bytes.check? checked.checked.program outputByte outputDigit outputHex
    | throw "emitter byte-sequence helper differs from its checked body"
  let some outputAssignments := CompactOutput.Assignments.check? checked.checked.program outputByte outputDigit outputWord
    | throw "emitter semantic-assignment helper differs from its checked body"
  let some outputTokens := CompactOutput.Tokens.check? checked.checked.program outputByte outputDigit outputWord
    | throw "emitter token helper differs from its checked body"
  let some outputNodes := CompactOutput.Nodes.check? checked.checked.program outputByte outputDigit outputWord
      collector.symbols.childToken collector.symbols.childState
    | throw "emitter node helper differs from its checked body and tag constants"
  let some unitWriter := CompactOutput.Unit.check? checked.checked.program
      ⟨outputWord.source.function.id, outputBytes.source.function.id, outputTokens.source.function.id,
        outputAssignments.source.function.id, outputNodes.source.function.id⟩
    | throw "unit emitter differs from its checked body and helper identities"
  let some emitStage := Entry.File.Emit.check? unitWriter.source.function.id rawCount.source.function.id collectStage.locals.continuation
    | throw "collector continuation differs from the exact emitter arguments, cursor assignment, and error guard"
  let some emitMemory := Lanius.Semantics.CellOnly.checkRegion? checked.checked.program.core
      (emitStage.locals.assignment unitWriter.source.function.id rawCount.source.function.id)
    | throw "emitter assignment or a transitive helper changes native heap/view metadata"
  let some emitRelation := Entry.File.Emit.checkRelation? loadPipeline syntaxStage.locals resultsStage.locals collectStage.locals emitStage.locals
    | throw "emitter arguments are disconnected from the actual file/frontend/collector bindings"
  let some advance := Entry.File.Advance.check? emitStage.locals.continuation
    | throw "emitter continuation differs from the final file-index increment"
  let some advanceRelation := Entry.File.Advance.checkRelation? loadPipeline syntaxStage.locals resultsStage.locals advance.locals
    | throw "final file-index increment is disconnected from the selected argument or shadowed by the file body"
  let some diagnostics := Diagnostics.checkFrontend? checked.checked.program publicSyntax.tail.finish.constructor.typeId
      advance.locals syntaxStage.locals.result resultsStage.locals.failure
    | throw "frontend diagnostic branch differs from its complete six-call execution proof"
  if included : allowed publicSyntax.source.function.id = true then
    let some nextRelation := Entry.File.Next.checkRelation? loadPipeline syntaxStage.locals resultsStage.locals
      | throw "next-file inputs are shadowed inside the completed file body"
    let fileChecked : Entry.File.Checked checked.checked.program := {
      pipeline := loadPipeline, syntaxStage := syntaxStage.locals, visit := tree, materializer
      syntaxProof := publicSyntax, linked, source := syntaxStage.exactSource, relation := syntaxRelation.down
      allowed, fragment := capacityProof.down, included, accessors, resultsStage := resultsStage.locals
      resultsSupported := resultsSupport.down, resultsSource := resultsStage.exactSource, resultsBinding := resultsBinding.down
      collector, collectStage := collectStage.locals, collectMemory, collectSource := collectStage.exactSource
      collectRelation := collectRelation.down, rawCount, byte := outputByte, digit := outputDigit, hex := outputHex
      tokenTag := collector.symbols.childToken, stateTag := collector.symbols.childState
      word := outputWord, bytes := outputBytes, tokens := outputTokens, assignmentWriter := outputAssignments
      nodes := outputNodes, unitWriter, tokenConstant := collector.tokenTag, stateConstant := collector.stateTag
      emitStage := emitStage.locals, emitMemory, emitSource := emitStage.exactSource, emitRelation := emitRelation.down
      argument := advance.locals, advanceSource := advance.exactSource, advanceRelation := advanceRelation.down
      diagnostics, nextRelation := nextRelation.down }
    let some countCarried := Entry.File.checkCarried? loadPipeline syntaxStage.locals resultsStage.locals entry.entry.count
      | throw "file iteration shadows the loop's original argc binding"
    let some loopSource := Entry.Files.check? advance.locals entry.entry.count
        (loadPipeline.path.statement loadPipeline.length.function.id) header.locals.continuation
      | throw "actual ordered loop differs from the proved initializer, condition, or complete file body"
    let some suffix := Entry.Suffix.check? outputText.source.function.id loopSource.continuation
      | throw "ordered loop does not continue into the exact suffix append and cursor guard"
    let some suffixSupport := Entry.Suffix.checkSupported? suffix.locals framing.locals
      | throw "suffix is disconnected from startup framing storage or shadows a live binding"
    let some finalSource := Entry.Output.check? checked.checked.program.core suffix.locals
      | throw "post-suffix tail differs from complete packing/stdout source or clobbers a live binding"
    let some loadingSource := Entry.Files.checkLoadingSource? loadPipeline allocations.locals.buffers
        pointers.locals.aliases literal.locals framing.locals
      | throw "first file-loading resources are disconnected from startup allocations or pointer aliases"
    let some frontendSource := Entry.Files.checkFrontendSource? loadPipeline syntaxStage.locals
        allocations.locals.buffers pointers.locals.aliases literal.locals framing.locals
      | throw "first frontend resources are disconnected from startup or the initialized grammar"
    let some outputSource := Entry.Files.checkOutputSource? loadPipeline syntaxStage.locals collectStage.locals
        emitStage.locals header.locals allocations.locals.buffers pointers.locals.aliases literal.locals framing.locals
      | throw "first semantic/output resources are disconnected from startup header or cursor"
    let some suffixCarried := Entry.File.checkCarried? loadPipeline syntaxStage.locals resultsStage.locals framing.locals.closing
      | throw "file loop shadows the suffix literal needed by final output"
    let some suffixArgument := (if valid : loadPipeline.path.argument ≠ framing.locals.closing
        then some (PLift.up valid) else none)
      | throw "argument cursor shadows the final suffix literal"
    let some workspaceSource := Entry.Files.checkBufferSource? allocations.locals.buffers pointers.locals.aliases
        literal.locals framing.locals loadPipeline.path.argument finalSource.preparation.packing.workspace 4194304
      | throw "packing workspace is not the actual retained 4194304-word allocation"
    let some workspacePointer := Entry.Files.checkPointerSource? pointers.locals.aliases literal.locals framing.locals
        loadPipeline.path.argument finalSource.stdout.pointer finalSource.preparation.packing.workspace
      | throw "stdout pointer is not the original packing-workspace slice pointer"
    let some workspaceCarried := Entry.File.checkCarried? loadPipeline syntaxStage.locals resultsStage.locals
        finalSource.preparation.packing.workspace
      | throw "file loop shadows the workspace needed for final packing"
    let some pointerCarried := Entry.File.checkCarried? loadPipeline syntaxStage.locals resultsStage.locals finalSource.stdout.pointer
      | throw "file loop shadows the pointer needed for final stdout"
    let separate : PLift (finalSource.preparation.packing.workspace ≠ emitStage.locals.output) ←
      if distinct : finalSource.preparation.packing.workspace ≠ emitStage.locals.output then pure ⟨distinct⟩
      else throw "packing workspace overlaps its input allocation"
    have completeMain := fun (before : Lanius.Semantics.State)
        {context : Lanius.Typing.Context} {store : Lanius.Properties.StoreTyping}
        {returnType : Lanius.Core.Ty} {inLoop : Bool}
        {request : Entry.Files.Request} {rest : List Entry.Files.Request}
        (wellFormed : Lanius.Properties.StateWellFormed before) (empty : before.i32ArrayViews = [])
        (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
        (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount allocations.locals.buffers ≤ available) =>
      Entry.Startup.executes (completeStartup before wellFormed empty enough bounded room)
        fileChecked loopSource startupSupport.down.1
        loadingSource frontendSource outputSource countCarried.down names.proof
        finalSource suffixSupport.down framingSupport outputText suffix.exactSource headerRelation
        workspaceSource workspacePointer separate.down suffixArgument.down suffixCarried.down
        workspaceCarried.down pointerCarried.down
        (context := context) (store := store) (returnType := returnType) (inLoop := inLoop)
        (request := request) (rest := rest)
    have completeExecutable (world : Lanius.World.State)
        {request : Entry.Files.Request} {rest : List Entry.Files.Request}
        (enough : 1 < world.arguments.length) (bounded : world.arguments.length < 2 ^ 31)
        (pending : Entry.Files.Pending world 1 (request :: rest))
        (endpoint : 1 + (request :: rest).length = world.arguments.length)
        (handles : world.nextFileHandle + rest.length ≤ 2147483647)
        (olderHandles : ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)) :
        ExecutionCorrect checked.entrypoint.executable world := by
      let before : Lanius.Semantics.State := { world }
      have typed := Lanius.Properties.initial_world_state_has_runtime_type checked.checked.program.core world
      have main := completeMain before typed.typed.wellFormed rfl enough bounded
        (by intro available impossible; cases impossible)
        (Entry.Run.body_typed checked.analysis) typed pending endpoint handles olderHandles
        (by rw [checked.checked.program.target]; decide)
      simpa only [ExecutionCorrect, checked.entrypoint.executableDefinition] using
        Entry.Run.observations checked.entrypoint (Entry.Run.evaluates checked.analysis rfl main)
    pure {
      arguments := entry
      allocator := allocatorProof
      allocations := allocations
      file := fileChecked
      firstFile := by
        intro world enough bounded
        have typed := Lanius.Properties.initial_world_state_has_runtime_type checked.checked.program.core world
        obtain ⟨started⟩ := completeStartup ({ world } : Lanius.Semantics.State)
          typed.typed.wellFormed rfl enough bounded (by intro available impossible; cases impossible)
        have buffers := loadingSource.pathBuffers started.history started.frame started.originalRegistry
          started.registry names.proof started.retained
        refine ⟨loopSource.first started startupSupport.down.1, ?_⟩
        simpa only [Entry.Files.CheckedSource.first, advanceRelation.down.selected] using buffers
      aliases := pointers.locals.aliases
      literal := literal.locals
      framing := framing.locals
      header := header.locals
      text := outputText
      suffix := suffix.locals
      output := finalSource
      correct := by
        intro world supported
        obtain ⟨request, rest, pending, endpoint, handles⟩ := supported.requests
        exact completeExecutable world supported.enough supported.bounded pending endpoint handles supported.olderHandles
      rejectsLater := by
        intro world supported
        obtain ⟨request, rest, rejectedCode, pending, issue, handles⟩ := supported.requests
        have typed := Lanius.Properties.initial_world_state_has_runtime_type checked.checked.program.core world
        have enough : 1 < world.arguments.length := by have bound := issue.index_lt; omega
        have started := completeStartup ({ world } : Lanius.Semantics.State) typed.typed.wellFormed rfl
          enough supported.bounded (by intro available impossible; cases impossible)
        obtain ⟨code, after, run, ⟨failure⟩, stdout⟩ := Entry.Startup.rejectsAfter started
          fileChecked readFailure loopSource startupSupport.down.1 loadingSource frontendSource outputSource countCarried.down names.proof
          (Entry.Run.body_typed checked.analysis) typed pending issue handles supported.olderHandles
          (by rw [checked.checked.program.target]; decide)
        refine ⟨code, Lanius.Semantics.restoreLocals ({ world } : Lanius.Semantics.State) after, ?_,
          ⟨{ failure with memorySafe := failure.memorySafe }⟩, stdout⟩
        simpa only [checked.entrypoint.executableDefinition] using Entry.Run.call checked.analysis rfl run
      rejectsOversized := by
        intro world supported
        obtain ⟨path, file, selected, fileFound, nonempty, pathFits, oversize⟩ := supported.request
        have typed := Lanius.Properties.initial_world_state_has_runtime_type checked.checked.program.core world
        have enough : 1 < world.arguments.length := (List.getElem?_eq_some_iff.mp selected).1
        have started := completeStartup ({ world } : Lanius.Semantics.State) typed.typed.wellFormed rfl
          enough supported.bounded (by intro available impossible; cases impossible)
        obtain ⟨after, run, ⟨failure⟩, stdout⟩ := Entry.Startup.rejectsOversized started
          fileChecked loopSource startupSupport.down.1 loadingSource names.proof
          (Entry.Run.body_typed checked.analysis) typed ⟨path, file⟩ selected fileFound nonempty pathFits oversize
          supported.handleFit supported.olderHandles readFailure (by rw [checked.checked.program.target]; decide)
        refine ⟨Lanius.Semantics.restoreLocals ({ world } : Lanius.Semantics.State) after, ?_,
          ⟨{ failure with memorySafe := failure.memorySafe }⟩, stdout⟩
        simpa only [checked.entrypoint.executableDefinition] using Entry.Run.call checked.analysis rfl run }
  else throw "file-loop frontend call is not in the checked capacity-extension closure"

end Lanius.Extraction.Entry
