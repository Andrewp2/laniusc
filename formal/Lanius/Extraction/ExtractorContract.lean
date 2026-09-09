import Lanius.Extraction.EntrypointAnalysis
import Lanius.Properties
import Lanius.Memory.Store
import Lanius.Extraction.OutputPacking.Execution
import Lanius.CallContracts.Host
import Lanius.Semantics.I32Views

namespace Lanius.Extraction.ExtractorContract

open Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program
open Lanius.Extraction.EntrypointAnalysis
open Lanius.Core
open Lanius.Memory
open Lanius.Semantics

/-! The semantic target for the Lanius extractor's eventual execution proof.

This module does not assert that the current source meets the contract. It
defines the exact success boundary so the proofs of `byte_io`, syntax
extraction, compact serialization, and `main` can compose against one stable
statement instead of independently chosen postconditions.
-/

def modulePrefix : String :=
  "import Lanius.Extraction.CoreSynthesis.Program\n\n" ++
  "open Lanius.Extraction\n" ++
  "open Lanius.Extraction.CoreSynthesis.Program\n\n" ++
  "def encodedPack : String := \""

def moduleSuffix : String :=
  "\"\n\n" ++
  "def readExpectedSources (paths : List String) : IO (List SourceFile) :=\n" ++
  "  paths.mapM fun (path : String) =>\n" ++
  "    IO.FS.readBinFile path >>= fun contents =>\n" ++
  "      pure { path, bytes := contents.toList.map UInt8.toNat }\n\n" ++
  "def main (paths : List String) : IO UInt32 :=\n" ++
  "  readExpectedSources paths >>= fun sources =>\n" ++
  "    match checkCompactCoreSourcePack encodedPack sources with\n" ++
  "    | .success _ => do\n" ++
  "      IO.println \"source, syntax, Surface, and synthesized x86 Core certificates accepted for the exact input files\"\n" ++
  "      pure 0\n" ++
  "    | .failure stage => do\n" ++
  "      IO.eprintln (\"compact source, Surface, or synthesized Core certificate checking failed at \" ++ stage)\n" ++
  "      pure 1\n"

def renderedModule (encoded : String) : String :=
  modulePrefix ++ encoded ++ moduleSuffix

/-- Exact behavior of the modeled stdout service: append the loaded bytes,
preserve the heap and all other world fields, and record one host call.
This describes `World.call`, not a guarantee that an OS write cannot be short. -/
theorem writeStdout_exact
    (heap : Heap) (world : Lanius.World.State)
    (pointer length : Nat) (bytes : List UInt8)
    (loaded : heap.loadBytes pointer length = .ok bytes) :
    Lanius.World.call heap world .writeStdout
        [.pointer pointer, .unsigned .usize length] =
      .returned (Lanius.World.i32Result bytes.length) heap {
        world with
        standardOutput := world.standardOutput ++ bytes
        calls := world.calls ++ [.writeStdout]
      } := by
  simp [Lanius.World.call, Lanius.World.callSimple, loaded,
    Lanius.World.record]

/-- An invalid output range traps without modifying output or memory. -/
theorem writeStdout_invalidRange
    (heap : Heap) (world : Lanius.World.State)
    (pointer length : Nat) (reason : Lanius.Trap)
    (invalid : heap.loadBytes pointer length = .error reason) :
    Lanius.World.call heap world .writeStdout
        [.pointer pointer, .unsigned .usize length] =
      .trapped reason heap (Lanius.World.record world .writeStdout) := by
  simp [Lanius.World.call, Lanius.World.callSimple, invalid]

/-- Bridge from the packed workspace to exact stdout. The final write excludes
the padding bytes in the last word. The remaining source proof must establish
that this is the workspace actually produced by the packing loop and sync. -/
theorem writeStdout_packed
    (heap : Heap) (world : Lanius.World.State) (pointer : Nat)
    (bytes storage : List UInt8)
    (encoded : encodeI32Array (OutputPacking.pack bytes) = .ok storage)
    (loaded : heap.loadBytes pointer storage.length = .ok storage) :
    Lanius.World.call heap world .writeStdout
        [.pointer pointer, .unsigned .usize bytes.length] =
      .returned (Lanius.World.i32Result bytes.length) heap {
        world with
        standardOutput := world.standardOutput ++ bytes
        calls := world.calls ++ [.writeStdout]
      } := by
  have storageEq : storage =
      bytes ++ List.replicate (OutputPacking.padding bytes.length) 0 := by
    rw [OutputPacking.encode_pack] at encoded
    exact Except.ok.inj encoded.symm
  subst storage
  apply writeStdout_exact
  simpa using Heap.loadBytes_prefix (requested := bytes.length) loaded (by simp)

/-- Storing the packed workspace is sufficient to establish the exact bytes
read by stdout. No separate assumption about the resulting heap contents is
needed: it follows from heap read-after-write correctness. -/
theorem writeStdout_storedPacked
    {heap afterHeap : Heap} (wellFormed : HeapWellFormed heap)
    (world : Lanius.World.State) (pointer : Nat) (bytes storage : List UInt8)
    (encoded : encodeI32Array (OutputPacking.pack bytes) = .ok storage)
    (stored : heap.storeBytes pointer storage = .ok afterHeap) :
    Lanius.World.call afterHeap world .writeStdout
        [.pointer pointer, .unsigned .usize bytes.length] =
      .returned (Lanius.World.i32Result bytes.length) afterHeap {
        world with
        standardOutput := world.standardOutput ++ bytes
        calls := world.calls ++ [.writeStdout]
      } :=
  writeStdout_packed afterHeap world pointer bytes storage encoded
    (Heap.loadBytes_after_store wellFormed stored)

/-- Source-level stdout call for a packed buffer, with both synchronization
obligations explicit. The result is an authoritative Core evaluation, not
just a property of the host-service model in isolation. -/
theorem evaluates_packed_stdout
    {program : Core.Program} {function : Core.Function}
    {before afterArguments ready after : Lanius.Semantics.State}
    {arguments : List Core.Expr} {bindings : List (Lanius.VarId × Core.Value)}
    (pointer : Nat) (bytes storage : List UInt8)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program before
      arguments [.pointer pointer, .unsigned .usize bytes.length] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer pointer, .unsigned .usize bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout))
    (synchronized : syncI32ViewsToHeap afterArguments = .ok ready)
    (encoded : encodeI32Array (OutputPacking.pack bytes) = .ok storage)
    (loaded : ready.heap.loadBytes pointer storage.length = .ok storage)
    (refreshed : syncI32ViewsFromHeap { ready with world := {
        ready.world with
        standardOutput := ready.world.standardOutput ++ bytes
        calls := ready.world.calls ++ [.writeStdout]
      } } = .ok after) :
    Evaluates program before (.call function.id arguments)
      (Lanius.World.i32Result bytes.length) after := by
  exact Lanius.CallContracts.evaluatesHostCallReturned argumentsResult
    functionFound parametersBound noBody host synchronized
    (writeStdout_packed ready.heap ready.world pointer bytes storage encoded loaded)
    refreshed

/-- Exact stdout bytes after synchronizing the real, oversized workspace.
Only its packed prefix matters; the unused parser-workspace tail is framed
out. This discharges the heap-content premise from the packed cell invariant. -/
theorem synchronized_workspace_stdout
    {before ready : Lanius.Semantics.State} {view : I32ArrayView}
    (bytes : List UInt8) (tail : List Core.Value) (storage : List UInt8)
    (wellFormed : HeapWellFormed before.heap)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ before.i32ArrayViews)
    (packed : readCellProjection before view.root view.projections =
      .ok (.array (OutputPacking.pack bytes ++ tail)))
    (encoded : encodeI32Array (OutputPacking.pack bytes ++ tail) = .ok storage)
    (synchronized : syncI32ViewsToHeap before = .ok ready) :
    Lanius.World.call ready.heap ready.world .writeStdout
        [.pointer view.address, .unsigned .usize bytes.length] =
      .returned (Lanius.World.i32Result bytes.length) ready.heap {
        ready.world with
        standardOutput := ready.world.standardOutput ++ bytes
        calls := ready.world.calls ++ [.writeStdout]
      } := by
  have loaded := syncI32ViewsToHeapFrom_reads_view wellFormed disjoint member
    packed encoded synchronized
  obtain ⟨within, exactPrefix⟩ :=
    OutputPacking.encode_pack_workspace_prefix bytes tail storage encoded
  apply writeStdout_exact
  simpa only [exactPrefix] using Heap.loadBytes_prefix loaded within

/-- Construct the actual stdout evaluation for the oversized packed workspace.
Heap byte contents and host-call success follow from the cell encoding; only
the two view-synchronization operations remain explicit. -/
theorem evaluates_workspace_stdout
    {program : Core.Program} {function : Core.Function}
    {before afterArguments ready after : Lanius.Semantics.State}
    {arguments : List Core.Expr} {bindings : List (Lanius.VarId × Core.Value)}
    {view : I32ArrayView}
    (bytes : List UInt8) (tail : List Int)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program before arguments
      [.pointer view.address, .unsigned .usize bytes.length] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout))
    (wellFormed : HeapWellFormed afterArguments.heap)
    (disjoint : afterArguments.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ afterArguments.i32ArrayViews)
    (packed : readCellProjection afterArguments view.root view.projections =
      .ok (.array (OutputPacking.pack bytes ++ signedI32Values tail)))
    (synchronized : syncI32ViewsToHeap afterArguments = .ok ready)
    (refreshed : syncI32ViewsFromHeap { ready with world := {
      ready.world with
        standardOutput := ready.world.standardOutput ++ bytes
        calls := ready.world.calls ++ [.writeStdout] } } = .ok after) :
    Evaluates program before (.call function.id arguments) (Lanius.World.i32Result bytes.length) after := by
  have encoded : encodeI32Array (OutputPacking.pack bytes ++ signedI32Values tail) =
      .ok ((bytes ++ List.replicate (OutputPacking.padding bytes.length) 0) ++ tail.flatMap i32Bytes) := by
    rw [OutputPacking.encodeI32Array_append, OutputPacking.encode_pack, encodeSignedI32Values]
  exact Lanius.CallContracts.evaluatesHostCallReturned argumentsResult functionFound parametersBound noBody host
    synchronized (synchronized_workspace_stdout bytes (signedI32Values tail) _ wellFormed disjoint member
      packed encoded synchronized) refreshed

/-- Constructive stdout execution from structural buffer conditions, without
assuming that either synchronization operation succeeds. -/
theorem workspace_stdout_exists
    {program : Core.Program} {function : Core.Function}
    {before afterArguments : Lanius.Semantics.State}
    {arguments : List Core.Expr} {bindings : List (Lanius.VarId × Core.Value)}
    {view : I32ArrayView}
    (bytes : List UInt8) (tail : List Int)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program before arguments
      [.pointer view.address, .unsigned .usize bytes.length] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout))
    (wellFormed : HeapWellFormed afterArguments.heap)
    (disjoint : afterArguments.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ afterArguments.i32ArrayViews)
    (packed : readCellProjection afterArguments view.root view.projections =
      .ok (.array (OutputPacking.pack bytes ++ signedI32Values tail)))
    (blocks : ∀ view ∈ afterArguments.i32ArrayViews,
      I32ArrayViewBlockWellFormed afterArguments.heap view)
    (roots : ∀ view ∈ afterArguments.i32ArrayViews, view.projections = [])
    (arrays : ∀ view ∈ afterArguments.i32ArrayViews, ∃ elements,
      readCellProjection afterArguments view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value) :
    ∃ after, Evaluates program before (.call function.id arguments)
      (Lanius.World.i32Result bytes.length) after ∧
      after.world = { afterArguments.world with
        standardOutput := afterArguments.world.standardOutput ++ bytes
        calls := afterArguments.world.calls ++ [.writeStdout] } ∧
      (∀ cell, (∀ other ∈ afterArguments.i32ArrayViews, cell ≠ other.root) →
        after.cellEntry? cell = afterArguments.cellEntry? cell) ∧
      after.locals = afterArguments.locals := by
  obtain ⟨ready, synchronized⟩ := syncI32ViewsToHeap_exists wellFormed blocks arrays
  obtain ⟨readyValid, preserved, cells, registry, locals⟩ :=
    syncI32ViewsToHeapFrom_preserves_storage (views := afterArguments.i32ArrayViews)
      wellFormed synchronized
  let written : Lanius.Semantics.State := { ready with world := { ready.world with
    standardOutput := ready.world.standardOutput ++ bytes
    calls := ready.world.calls ++ [.writeStdout] } }
  have readyCells : ∀ other ∈ written.i32ArrayViews,
      ∃ cell, written.cellEntry? other.root = some cell := by
    intro other mem
    have original : other ∈ afterArguments.i32ArrayViews := by simpa only [written, registry] using mem
    obtain ⟨elements, read, _, _⟩ := arrays other original
    cases found : afterArguments.cellEntry? other.root with
    | none => simp [readCellProjection, found] at read
    | some cell =>
        exact ⟨cell, by change ready.cells.find? _ = some cell; rw [cells]; exact found⟩
  obtain ⟨after, refreshed⟩ := syncI32RootViewsFromHeapFrom_exists
    (before := written) (pending := written.i32ArrayViews) readyValid
    (fun other mem => preserved other (by simpa only [written, registry] using mem)
      (blocks other (by simpa only [written, registry] using mem)))
    (fun other mem => roots other (by simpa only [written, registry] using mem)) readyCells
  refine ⟨after, evaluates_workspace_stdout bytes tail argumentsResult functionFound
    parametersBound noBody host wellFormed disjoint member packed synchronized refreshed, ?_, ?_, ?_⟩
  · have unchanged := Lanius.Properties.syncI32ViewsToHeap_preserves_world synchronized
    have finalWorld := syncI32ViewsFromHeapFrom_preserves_world refreshed
    simpa only [written, unchanged] using finalWorld
  · intro cell separate
    have kept := syncI32RootViewsFromHeapFrom_preserves_other_cell
      (fun other mem => roots other (by simpa only [written, registry] using mem))
      (fun other mem => separate other (by simpa only [written, registry] using mem)) refreshed
    simpa only [State.cellEntry?, written, cells] using kept
  · have kept := syncI32RootViewsFromHeapFrom_preserves_locals
      (fun other mem => roots other (by simpa only [written, registry] using mem)) refreshed
    exact kept.trans locals

/-- Partial correctness of the real stdout call: an observed successful Core
evaluation with a packed, disjoint workspace returns its byte count and appends
exactly those bytes. Neither synchronization success nor its resulting heap is
assumed; both are recovered from the observed evaluation. -/
theorem packed_stdout_call_sound
    {program : Core.Program} {function : Core.Function}
    {before afterArguments after : Lanius.Semantics.State}
    {arguments : List Core.Expr} {bindings : List (Lanius.VarId × Core.Value)}
    {view : I32ArrayView} {result : Core.Value}
    (bytes : List UInt8) (tail : List Core.Value) (storage : List UInt8)
    (argumentsResult : Lanius.CallContracts.ArgumentsEvaluateTo program before
      arguments [.pointer view.address, .unsigned .usize bytes.length] afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize bytes.length] = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host .writeStdout))
    (wellFormed : HeapWellFormed afterArguments.heap)
    (disjoint : afterArguments.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ afterArguments.i32ArrayViews)
    (packed : readCellProjection afterArguments view.root view.projections =
      .ok (.array (OutputPacking.pack bytes ++ tail)))
    (encoded : encodeI32Array (OutputPacking.pack bytes ++ tail) = .ok storage)
    (actual : Evaluates program before (.call function.id arguments) result after) :
    result = Lanius.World.i32Result bytes.length ∧
      after.world = {
        afterArguments.world with
        standardOutput := afterArguments.world.standardOutput ++ bytes
        calls := afterArguments.world.calls ++ [.writeStdout]
      } := by
  obtain ⟨ready, heap, world, synced, called, refreshed⟩ :=
    Lanius.CallContracts.evaluatesHostCallReturned_invert argumentsResult functionFound
      parametersBound noBody host actual
  have expected := synchronized_workspace_stdout bytes tail storage
    wellFormed disjoint member packed encoded synced
  rw [expected] at called
  cases called
  refine ⟨rfl, ?_⟩
  have finalWorld := syncI32ViewsFromHeap_preserves_world refreshed
  have initialWorld := Lanius.Properties.syncI32ViewsToHeap_preserves_world synced
  simpa only [initialWorld] using finalWorld

def sourceFileInWorld? (world : Lanius.World.State) (path : String) :
    Option SourceFile := do
  let file ← world.file? (Lanius.World.utf8Bytes path)
  pure { path, bytes := file.bytes.map UInt8.toNat }

/-- `World.arguments` models native `argv`, including the executable in slot
zero. The extractor consumes every later argument in order. -/
def requestedSources? (world : Lanius.World.State) : Option (List SourceFile) :=
  (world.arguments.drop 1).mapM (sourceFileInWorld? world)

def externalInputWithinBounds (world : Lanius.World.State) : Prop :=
  1 < world.arguments.length ∧
  ∀ path ∈ world.arguments.drop 1,
    0 < path.toUTF8.size ∧ path.toUTF8.size ≤ 1024 ∧
      ∃ file, world.file? (Lanius.World.utf8Bytes path) = some file ∧
        file.bytes.length ≤ 65536

/-- The memory portion of the extractor contract. Besides the ordinary heap
invariants, every registered native `i32` view must still name a live block.
This makes the success/failure contract rule out dangling host-I/O views rather
than merely ruling out an observed trap. -/
def MemorySafe (state : Lanius.Semantics.State) : Prop :=
  HeapWellFormed state.heap ∧
    ∀ view, view ∈ state.i32ArrayViews →
      I32ArrayViewBlockWellFormed state.heap view

/-- Memory safety is not an extractor-specific axiom. It is the direct
projection of the language runtime-state invariant preserved by typed Core
execution, including the native raw-view registry. -/
theorem memorySafe_of_runtimeStateHasType
    {program : Core.Program} {context : Typing.Context}
    {state : Lanius.Semantics.State} {store : Properties.StoreTyping}
    (typed : Properties.RuntimeStateHasType program context state store) :
    MemorySafe state := by
  constructor
  · exact typed.typed.wellFormed.heapWellFormed
  · intro view member
    exact (typed.views view member).2

/-- Terminal-state projection used to compose the general Core preservation
theorem with the extractor's success and failure postconditions. Fuel
exhaustion has no terminal state to constrain. -/
def OutcomeMemorySafe : Lanius.Semantics.Outcome α → Prop
  | .done _ state | .trapped _ state | .exited _ state => MemorySafe state
  | .outOfFuel => True

theorem outcomeMemorySafe_of_runtimePreservation
    {program : Core.Program} {context : Typing.Context}
    {before : Lanius.Semantics.State} {beforeStore : Properties.StoreTyping}
    {outcome : Lanius.Semantics.Outcome Core.Value} {type : Core.Ty}
    (preserved : Properties.RuntimeValueOutcomeHasExtendedType
      program context before beforeStore outcome type) :
    OutcomeMemorySafe outcome := by
  cases outcome with
  | done value after =>
      obtain ⟨afterStore, _, _, typed, _, _⟩ := preserved
      exact memorySafe_of_runtimeStateHasType typed
  | trapped reason after | exited code after =>
      obtain ⟨afterStore, _, _, typed⟩ := preserved
      exact memorySafe_of_runtimeStateHasType typed
  | outOfFuel => trivial

theorem checkedProgram_constantsClosed
    {artifacts : List Artifact}
    (checked : CheckedProgram artifacts) :
    Properties.ProgramConstantsClosed checked.core := by
  intro constant member
  exact Properties.Value.isLiteral_is_closed constant.value
    (checked.constantsLiteral constant member)

theorem checkedProgram_opaqueResponsesWellTyped
    {artifacts : List Artifact}
    (checked : CheckedProgram artifacts) (world : Lanius.World.State) :
    Properties.OpaqueResponsesWellTyped checked.core world := by
  intro response responseMember function functionMember externalFound
  exact (checked.noOpaqueExternals function functionMember response.external
    externalFound).elim

/-- Every evaluation of an expression already typed in an accepted synthesized
program has a memory-safe terminal state. The theorem discharges constant
closure and the opaque foreign boundary from the certificate itself. -/
theorem checkedProgram_evaluation_memorySafe
    {artifacts : List Artifact} (checked : CheckedProgram artifacts)
    {context : Typing.Context} {expression : Core.Expr} {type : Core.Ty}
    (expressionTyped : Typing.ExprHasType checked.core context expression type)
    (fuel : Nat) (before : Lanius.Semantics.State)
    (beforeStore : Properties.StoreTyping)
    (beforeTyped : Properties.RuntimeStateHasType checked.core context before
      beforeStore) :
    OutcomeMemorySafe
      (Lanius.Semantics.evalExpr fuel checked.core before expression) := by
  apply outcomeMemorySafe_of_runtimePreservation
  exact Properties.evalExpr_has_runtime_type checked.typed
    (checkedProgram_constantsClosed checked)
    (checkedProgram_opaqueResponsesWellTyped checked) fuel beforeTyped
    expressionTyped

/-- Memory-safety projection for a whole executable observation. -/
def ExecutionResultMemorySafe : Lanius.Execution.Result → Prop
  | .returned _ state | .trapped _ state | .exited _ state => MemorySafe state
  | .outOfFuel => True

/-- Running a source-linked entrypoint from an ordinary process world is
memory-safe for every fuel bound. The entrypoint lookup, zero-argument ABI,
return ABI, Core typing, constant closure, and foreign-call boundary are all
discharged by the accepted certificate. -/
theorem checkedEntrypoint_run_memorySafe
    {artifacts : List Artifact} (checked : CheckedProgram artifacts)
    {modulePath : Names.ModulePath} {name : Surface.Name}
    (entrypoint : CheckedEntrypoint checked modulePath name)
    (fuel : Nat) (world : Lanius.World.State) :
    ExecutionResultMemorySafe
      (Lanius.Execution.run fuel entrypoint.executable
        ({ world := world } : Lanius.Semantics.State)) := by
  have programTyped :
      Typing.ProgramWellTyped entrypoint.executable.program := by
    simpa [entrypoint.executableDefinition] using checked.typed
  have constantsClosed :
      Properties.ProgramConstantsClosed entrypoint.executable.program := by
    simpa [entrypoint.executableDefinition] using
      checkedProgram_constantsClosed checked
  have opaqueWorldsTyped : ∀ currentWorld,
      Properties.OpaqueResponsesWellTyped entrypoint.executable.program
        currentWorld := by
    intro currentWorld
    simpa [entrypoint.executableDefinition] using
      checkedProgram_opaqueResponsesWellTyped checked currentWorld
  have initialTyped := Properties.initial_world_state_has_runtime_type
    entrypoint.executable.program world
  obtain ⟨returnType, returnAllowed, preserved⟩ :=
    Properties.executable_run_has_runtime_type programTyped constantsClosed
      opaqueWorldsTyped entrypoint.wellFormed fuel
      ({ world := world } : Lanius.Semantics.State)
      Properties.emptyStoreTyping initialTyped
  cases result : Lanius.Execution.run fuel entrypoint.executable
      ({ world := world } : Lanius.Semantics.State) with
  | returned value after =>
      rw [result] at preserved
      obtain ⟨afterStore, _, _, afterTyped, _, _⟩ := preserved
      exact memorySafe_of_runtimeStateHasType afterTyped
  | exited code after | trapped reason after =>
      rw [result] at preserved
      obtain ⟨afterStore, _, _, afterTyped⟩ := preserved
      exact memorySafe_of_runtimeStateHasType afterTyped
  | outOfFuel => trivial

theorem acceptedExtractor_run_memorySafe
    {encoded : String} {sources : List SourceFile}
    (accepted : CheckedExtractorCoreSourcePack encoded sources)
    (fuel : Nat) (world : Lanius.World.State) :
    ExecutionResultMemorySafe
      (Lanius.Execution.run fuel accepted.entrypoint.executable
        ({ world := world } : Lanius.Semantics.State)) :=
  checkedEntrypoint_run_memorySafe accepted.checked.program accepted.entrypoint fuel world

/-- Faithful extraction, independently of whether the input type-checks.
A source such as `fn main() -> i32 { return true; }` can have a valid syntax
embedding but no typed Core program. The generated module runs that stronger
check separately; process exit zero must not be confused with its acceptance.
The program may make host
calls and allocate its process-lifetime workspaces, but it must not mutate its
arguments or source files, write diagnostics, or leak a file handle. -/
structure Success
    (before after : Lanius.Semantics.State) where
  encoded : String
  sources : List SourceFile
  sourcesFound : requestedSources? before.world = some sources
  certificate : Nonempty (CheckedCompactSyntaxSourcePack encoded sources)
  stdout :
    after.world.standardOutput = before.world.standardOutput ++
      Lanius.World.utf8Bytes (renderedModule encoded)
  stderr : after.world.standardError = before.world.standardError
  arguments : after.world.arguments = before.world.arguments
  files : after.world.files = before.world.files
  handles : after.world.fileHandles = before.world.fileHandles
  memorySafe : MemorySafe after

/-- The stronger result available only after the emitted module's typed-Core
checker accepts the exact same encoding and sources. This does not add a
type-checker obligation to the extraction process. -/
structure AcceptedSuccess (before after : Lanius.Semantics.State)
    extends Success before after where
  coreCertificate : Nonempty (CheckedCompactCoreSourcePack encoded sources)

theorem Success.accepted
    {before after : Lanius.Semantics.State}
    (extracted : Success before after)
    (accepted : (checkCompactCoreSourcePack?
      extracted.encoded extracted.sources).isSome = true) :
    Nonempty (AcceptedSuccess before after) := by
  cases found : checkCompactCoreSourcePack?
      extracted.encoded extracted.sources with
  | none => simp [found] at accepted
  | some checked => exact ⟨{ extracted with coreCertificate := ⟨checked⟩ }⟩

/-- Every deliberate source-level failure belongs to a stable public class.
Extractor stage/detail diagnostics remain in stderr; the process result uses
one stable code so the formal result and native eight-bit exit status agree. -/
inductive FailureCode : Int → Prop where
  | noInputs : FailureCode 1
  | badPath : FailureCode 2
  | allocation : FailureCode 3
  | badArgumentRead : FailureCode 4
  | open : FailureCode 5
  | readOrClose : FailureCode 6
  | semanticTokens : FailureCode 20
  | encodeUnit : FailureCode 21
  | writeUnit : FailureCode 22
  | writePrefix : FailureCode 23
  | writeSuffix : FailureCode 25
  | encodeHeader : FailureCode 26
  | writeHeader : FailureCode 27
  | extraction : FailureCode 28

theorem extractorReturnCode_classified
    {code : Int} (member : code ∈ extractorReturnCodes)
    (nonzero : code ≠ 0) : FailureCode code := by
  simp only [extractorReturnCodes, List.mem_cons, List.not_mem_nil,
    or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
      rfl | rfl | rfl | rfl | rfl | rfl
  · exact (nonzero rfl).elim
  · exact .noInputs
  · exact .badPath
  · exact .allocation
  · exact .badArgumentRead
  · exact .open
  · exact .readOrClose
  · exact .semanticTokens
  · exact .encodeUnit
  · exact .writeUnit
  · exact .writePrefix
  · exact .writeSuffix
  · exact .encodeHeader
  · exact .writeHeader
  · exact .extraction

/-- For the analyzed extractor entrypoint body, every ordinary nonzero i32
return is one of the public deliberate-failure classes. This conclusion is
independent of the path through the loops and conditionals. -/
theorem analyzedEntrypoint_failureCode
    {artifacts : List Artifact} {checked : CheckedProgram artifacts}
    {modulePath : Names.ModulePath} {name : Surface.Name}
    {entrypoint : CheckedEntrypoint checked modulePath name}
    (analysis : AnalyzedEntrypoint checked entrypoint)
    {before after : Lanius.Semantics.State} {code : Int}
    (executed : Lanius.Semantics.Executes checked.core before analysis.body
      (.returned (some (.signed .i32 code))) after)
    (nonzero : code ≠ 0) : FailureCode code := by
  apply extractorReturnCode_classified _ nonzero
  exact returnCode_mem_of_executes analysis.classifiedReturns
    analysis.relationallySupported executed

theorem acceptedExtractor_failureCode
    {encoded : String} {sources : List SourceFile}
    (accepted : CheckedExtractorCoreSourcePack encoded sources)
    {fuel : Nat} {before after : Lanius.Semantics.State} {code : Int}
    (returned : Lanius.Execution.run fuel
      accepted.entrypoint.executable before =
        .returned (.signed .i32 code) after)
    (nonzero : code ≠ 0) : FailureCode code :=
  extractorReturnCode_classified
    (analyzedRun_returnCode_mem accepted.analysis returned) nonzero

/-- A deliberate failure never authenticates its partial stdout. It still
preserves external inputs, closes any opened source handle, and leaves a
well-formed heap. Stderr is intentionally unconstrained because diagnostics
are part of the failure path. -/
structure Failure
    (before after : Lanius.Semantics.State) (code : Int) where
  nonzero : code ≠ 0
  classified : FailureCode code
  arguments : after.world.arguments = before.world.arguments
  files : after.world.files = before.world.files
  handles : after.world.fileHandles = before.world.fileHandles
  memorySafe : MemorySafe after

/-- Soundness is intentionally one-way. A nonzero return makes no claim about
partial stdout, which callers are required to discard. -/
def RunSound
    (before : Lanius.Semantics.State)
    (outcome : Lanius.Semantics.Outcome Lanius.Core.Value) : Prop :=
  ∀ result after,
    outcome = .done (.signed .i32 result) after →
    result = 0 → Nonempty (Success before after)

/-- Nonzero normal returns are deliberate, classified failures. Traps and
fuel exhaustion are therefore not silently treated as ordinary rejection. -/
def RunFailureSafe
    (before : Lanius.Semantics.State)
    (outcome : Lanius.Semantics.Outcome Lanius.Core.Value) : Prop :=
  ∀ result after,
    outcome = .done (.signed .i32 result) after →
    result ≠ 0 → Nonempty (Failure before after result)

/-- Completeness is stated separately because it additionally needs internal
token, parser-workspace, tree, and output-capacity preconditions. -/
def RunComplete
    (supported : Lanius.Semantics.State → Prop)
    (before : Lanius.Semantics.State)
    (outcome : Lanius.Semantics.Outcome Lanius.Core.Value) : Prop :=
  supported before →
    ∃ after,
      outcome = .done (.signed .i32 0) after ∧
      Nonempty (Success before after)

theorem acceptedCertificate_sound
    {encoded : String} {sources : List SourceFile}
    (accepted :
      (checkCompactCoreSourcePack? encoded sources).isSome = true) :
    Nonempty (CheckedCompactCoreSourcePack encoded sources) := by
  cases found : checkCompactCoreSourcePack? encoded sources with
  | none => simp [found] at accepted
  | some checked => exact ⟨checked⟩

theorem acceptedExtractorCertificate_sound
    {encoded : String} {sources : List SourceFile}
    (accepted :
      (checkExtractorCoreSourcePack? encoded sources).isSome = true) :
    Nonempty (CheckedExtractorCoreSourcePack encoded sources) := by
  cases found : checkExtractorCoreSourcePack? encoded sources with
  | none => simp [found] at accepted
  | some checked => exact ⟨checked⟩

end Lanius.Extraction.ExtractorContract
