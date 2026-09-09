import Lanius.Extraction.ExtractorContract
import Lanius.Extraction.Allocation.Source
import Lanius.Extraction.Allocation.Sequence
import Lanius.Extraction.Entry.Arguments
import Lanius.Extraction.Entry.Pointers
import Lanius.Extraction.OutputPacking.Source
import Lanius.Extraction.OutputPacking.Stdout
import Lanius.Extraction.OutputPacking.Complete
import Lanius.Extraction.Input.Source
import Lanius.Extraction.Input.Request
import Lanius.Extraction.CanonicalTokens.Ascii.Source
import Lanius.Extraction.Tests.Ascii
import Lanius.Extraction.Tests.Compaction
import Lanius.Extraction.CanonicalTokens.Compaction.Range.Loop

open Lanius.Extraction
open Lanius.Extraction.ExtractorContract
open Lanius.Extraction.EntrypointAnalysis
open Lanius.Extraction.OutputPacking

/-- Check one self-embedding once, retaining its checked Core body when
checking the packing proof's source linkage. No second extraction or parse. -/
def main (arguments : List String) : IO UInt32 := do
  let modulePath :: paths := arguments
    | throw (IO.userError "expected emitted-module followed by its ordered source paths")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith modulePrefix && emitted.endsWith moduleSuffix do
    throw (IO.userError "emitted module framing differs from the extraction contract")
  let encoded := ((emitted.drop modulePrefix.length).dropEnd moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : SourceFile)
  match checkExtractorCoreSourcePack encoded sources with
  | .failure stage => throw (IO.userError ("self-embedding rejected: " ++ stage))
  | .success checked =>
      let some entry := Entry.checkArguments? checked.checked.program.core checked.analysis.body
        | throw (IO.userError "checked main does not start with the proved argc/argument-guard sequence")
      have _argumentExecution := entry.executes
      let some allocator := checked.checked.program.core.functions.find? fun function =>
          function.body.isNone && function.external == some (.host .alloc)
        | throw (IO.userError "checked allocator declaration was not found")
      let some allocatorProof := Allocation.checkAllocator? checked.checked.program.core allocator.id
        | throw (IO.userError "host allocator declaration does not satisfy the sequence theorem")
      let some allocations := Allocation.checkSequence? allocatorProof.function.id Allocation.extractorCounts entry.entry.continuation
        | throw (IO.userError "checked main does not contain the exact 13-buffer host allocation sequence")
      have _allocationExecution := allocatorProof.executes allocations.locals
      have _entryAllocationExecution := entry.allocate allocatorProof allocations.locals allocations.exactSource
      let some pointers := Entry.Pointers.findGuard? allocations.locals.continuation
        | throw (IO.userError "post-allocation continuation lacks the exact pointer null-check guard")
      have _pointerGuardExecution := pointers.locals.executes checked.checked.program.core
      let some names := allocations.locals.distinctNames?
        | throw (IO.userError "allocation sequence shadows a buffer binding")
      have _bufferReads := fun (before ready : Lanius.Semantics.State)
          (history : Allocation.HostReady allocations.locals.buffers before ready)
          (buffer : Allocation.Buffer) (member : buffer ∈ allocations.locals.buffers) =>
        history.buffer names.proof member
      match findPreparation? checked.analysis.body with
      | none => throw (IO.userError "checked main does not contain the exact count/clear/pack source sequence")
      | some found =>
          let preparation := found.locals
          let some stdout := checkStdoutTail? preparation.continuation
            | throw (IO.userError "checked packing continuation differs from the stdout tail proof")
          unless stdout.locals.length == preparation.packing.length do
            throw (IO.userError "stdout tail uses a different output length from packing")
          let some stdoutFunction := checked.checked.program.core.function? stdout.locals.function
            | throw (IO.userError "stdout tail calls a missing function")
          unless stdoutFunction.body.isNone && stdoutFunction.external == some (.host .writeStdout) do
            throw (IO.userError "stdout tail does not call the external stdout service")
          have _stdoutExecution := stdout.locals.executes checked.checked.program.core
          have _outputStatement := preparation.checked_stdout_statement stdout
          have _outputExecution := fun before : Lanius.Semantics.State =>
            prepare_and_write (before := before) checked.checked.program.core
          let some reader := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
              ["verified", "byte_io"] "read_file"
            | throw (IO.userError "checked source read_file function was not found")
          let some readerBody := reader.function.body
            | throw (IO.userError "checked source read_file has no body")
          let some unpacking := Input.findUnpackLoop? readerBody
            | throw (IO.userError "checked read_file lacks the exact unpacking-loop shape")
          let some request := Input.findRequestAdjustment? readerBody
            | throw (IO.userError "checked read_file lacks the exact capacity-probe adjustment")
          let some matcher := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
              ["verified", "canonical_tokens"] "matches_ascii"
            | throw (IO.userError "checked ASCII matcher was not found")
          let some matcherBody := matcher.function.body
            | throw (IO.userError "checked ASCII matcher has no body")
          let some matchingLoop := CanonicalTokens.Ascii.findLoop? matcherBody
            | throw (IO.userError s!"checked ASCII matcher loop differs: {reprStr matcherBody}")
          let some _ := CanonicalTokens.Ascii.checkFunction? matcher.function
            | throw (IO.userError "checked ASCII matcher signature/body differs")
          Tests.Ascii.check checked.checked.program.core matcher.function.id
          let some keywords := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
              ["verified", "canonical_tokens"] "keyword_kind"
            | throw (IO.userError "checked keyword dispatch was not found")
          let some table := CanonicalTokens.Dispatch.checkFunction? checked.checked.program.core
              keywords.function.id matcher.function.id
            | throw (IO.userError "keyword dispatcher failed its source, representation, or reference-table proof checks")
          let some canonicalKind := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
              ["verified", "canonical_tokens"] "canonical_kind"
            | throw (IO.userError "checked canonical_kind was not found")
          let some kindProof := CanonicalTokens.Kind.check? checked.checked.program.core canonicalKind.function.id table
            | throw (IO.userError "canonical_kind differs from the proved source function")
          have _kindSound := kindProof.executes_body
          let some trivia := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
              ["verified", "canonical_tokens"] "is_trivia"
            | throw (IO.userError "checked is_trivia was not found")
          let some triviaProof := CanonicalTokens.Trivia.check? checked.checked.program.core trivia.function.id
            | throw (IO.userError "is_trivia differs from the proved source function")
          let some compaction := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
              ["verified", "canonical_tokens"] "canonicalize_in_place"
            | throw (IO.userError "checked canonicalize_in_place was not found")
          let some compactionProof := CanonicalTokens.Compaction.checkSource? checked.checked.program.core
              compaction.function.id triviaProof kindProof
            | throw (IO.userError "canonicalize_in_place differs from the compaction source template")
          have _firstPassSound := CanonicalTokens.Compaction.executes_input_loop compactionProof.trivia compactionProof.kind
          let rangeTable : CanonicalTokens.Compaction.Range.Table checked.checked.program.core compactionProof.tokens :=
            ⟨compactionProof.rangeFound, compactionProof.assignFound, compactionProof.inclusiveFound⟩
          have _secondPassSound := CanonicalTokens.Compaction.Range.executes_loop rangeTable
          have _canonicalizerSound := compactionProof.evaluates_call
          Tests.Compaction.check checked.checked.program.core compaction.function.id
          Tests.Ascii.checkKeywords checked.checked.program.core keywords.function.id
          IO.println s!"exact self-embedding accepted ({sources.length} files); count/clear/pack sequence linked to checked main: workspace={preparation.packing.workspace}, input={preparation.packing.input}, clearCursor={preparation.clearCursor}, packCursor={preparation.packing.cursor}, length={preparation.packing.length}"
          IO.println s!"allocation sequence linked to checked main: {allocations.locals.buffers.length} buffers, {Allocation.byteCount allocations.locals.buffers} bytes"
          IO.println s!"read_file unpacking loop linked to checked source: packed={unpacking.locals.packed}, output={unpacking.locals.output}, total={unpacking.locals.total}, cursor={unpacking.locals.cursor}"
          IO.println s!"read_file capacity probe linked to checked source: remaining={request.locals.remaining}, request={request.locals.request}"
          IO.println s!"ASCII comparison loop linked to checked source: packed={matchingLoop.locals.packed}, cursor={matchingLoop.locals.cursor}, expected={matchingLoop.locals.expected}"
          IO.println "ASCII matcher execution passed empty, all keywords, and every mismatching-byte position"
          IO.println "source keyword dispatch agrees with the independent lexer table and rejects keyword prefixes/suffixes"
          IO.println s!"keyword correctness linked with proof evidence: {table.correct.source.groups.length} length groups"
          IO.println "canonical_kind correctness linked to its checked source and keyword call"
          IO.println "is_trivia correctness and canonicalize_in_place source template linked to the self-embedding"
          IO.println "first compaction pass linked to its total-correctness proof and independent lexer specification"
          IO.println "second compaction pass linked to its total-correctness proof and inclusive-range specification"
          IO.println "complete canonicalize_in_place call proof linked; execution regressions passed with zero and spare capacity"
          return 0
