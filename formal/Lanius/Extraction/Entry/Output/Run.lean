import Lanius.Extraction.Entry.Output.Source
import Lanius.Extraction.Entry.Suffix.Resources
import Lanius.Extraction.Entry.Files.Rendering
import Lanius.Extraction.OutputPacking.Complete

namespace Lanius.Extraction.Entry.Output
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput Lanius.Extraction.OutputPacking

/-- Both modeled final-output outcomes. Exhaustion exposes no partial module;
success appends exactly one complete module in one logical stdout call. -/
def Result (bytes : List UInt8) (before : Lanius.World.State)
    (completion : Completion) (after : Lanius.World.State) : Prop :=
  (completion = .returned (some (.signed .i32 25)) ∧ after = before) ∨
  (completion = .returned (some (.signed .i32 0)) ∧ after = {
    before with
    standardOutput := before.standardOutput ++ bytes
    calls := before.calls ++ [.writeStdout] })

/-- Compose the actual suffix, clearing, packing, and stdout tail. All output
bytes and the accepted certificate follow from ordered file history. The
remaining inputs are live workspace/pointer resources, not executions or
assumptions about successful serialization. -/
theorem Source.executes (source : Source program.core stage)
    (supported : Suffix.Supported stage framing) (framingSupport : Framing.Supported framing)
    (text : Text.Checked program byte) (resources : Suffix.Resources stage framing outputCell before)
    {count : Nat} {units : List CompactDecode.UnitData} {sources : List SourceFile}
    (history : Files.History count units sources resources.earlier.length (resources.earlier ++ resources.untouched))
    (complete : units.length = count) (positive : 0 < count) (countFit : count < 4294967296)
    (workspace : I32ArrayView) (original : List Int)
    (member : workspace ∈ before.i32ArrayViews) (capacity : original.length = 4194304)
    (workspaceRead : before.local? source.preparation.packing.workspace = some
      (.slice i32 workspace.root [] 0 original.length))
    (workspaceContents : before.cellEntry? workspace.root = some {
      id := workspace.root, value := some (.array (signedI32Values original)) })
    (pointerRead : before.local? source.stdout.pointer = some (.pointer workspace.address))
    (separate : workspace.root ≠ outputCell)
    (usizeFit : 16777216 < unsignedModulus program.core.target .usize) :
    Nonempty (CheckedCompactSyntaxSourcePack (CompactDecode.renderedPack count units) sources) ∧
    ∃ completion after, Executes program.core before (stage.statement text.source.function.id) completion after ∧
      Result (Lanius.World.utf8Bytes (ExtractorContract.renderedModule (CompactDecode.renderedPack count units)))
        before.world completion after.world ∧
      (resources.earlier.length + Suffix.bytes.length ≤ 16777216 →
        completion = .returned (some (.signed .i32 0))) := by
  obtain ⟨certificate, rendered⟩ := history.rendered complete positive countFit
  let bytes := Lanius.World.utf8Bytes (ExtractorContract.renderedModule (CompactDecode.renderedPack count units))
  have bytesLength : bytes.length = resources.earlier.length + Suffix.bytes.length := by
    have length := congrArg List.length rendered
    simp only [Input.copiedBuffer, List.length_append, List.length_map] at length
    change resources.earlier.length + Suffix.bytes.length + _ = bytes.length + _ at length
    omega
  refine ⟨certificate, ?_⟩
  apply stage.executes supported framingSupport text before resources.earlier resources.untouched
    resources.registry resources.outputRead resources.positionRead resources.suffixRead resources.backing
    resources.positionBound resources.capacity (Scope.Post.world (fun completion world =>
      Result bytes before.world completion world ∧
        (resources.earlier.length + Suffix.bytes.length ≤ 16777216 →
          completion = .returned (some (.signed .i32 0)))))
  · intro middle positionCell overflow _owned _output effect _registry _views
    refine ⟨Or.inl ⟨rfl, effect.world⟩, ?_⟩
    intro room
    rw [source.capacity] at overflow
    omega
  · intro middle positionCell room owned output effect bindings registry views _reached
    obtain ⟨oldPosition, oldOwned⟩ := Assertion.exists_localPointsTo_of_local _ _ _ resources.positionRead
    have binding : before.cellId? stage.position = some positionCell :=
      (bindings stage.position (Ne.symm supported.previousPosition)).symm.trans owned.1
    have positionIdentity := Option.some.inj (oldOwned.1.symm.trans binding)
    have positionBefore : (Assertion.localPointsTo stage.position positionCell
        (some (.signed .i32 resources.earlier.length))).holds before := positionIdentity ▸ oldOwned
    have workspacePosition : workspace.root ≠ positionCell := by
      intro same
      rw [same, positionBefore.2] at workspaceContents
      cases workspaceContents
    have stored : middle.cellEntry? workspace.root = some {
        id := workspace.root, value := some (.array (signedI32Values original)) } :=
      effect.preserves_entry resources.registry.wellFormed workspaceContents
        (by intro changed; exact changed.elim separate workspacePosition)
    have kept {id : VarId} {value : Value} (notPrevious : id ≠ stage.previous)
        (read : before.local? id = some value)
        (notArray : ∀ values, value ≠ .array values)
        (notScalar : ∀ scalar, value ≠ .signed .i32 scalar) : middle.local? id = some value := by
      have preserved := effect.preserves_local resources.registry.wellFormed read (by
        intro cell found changed
        rcases changed with output | cursor
        · exact local_cell_ne_of_distinct_value read resources.backing (notArray _) found output
        · exact local_cell_ne_of_distinct_value read positionBefore.2 (notScalar _) found cursor)
      have same : middle.local? id = (restoreLocals before middle).local? id := by
        simp only [State.local?, bindings id notPrevious]
        rfl
      exact same.trans preserved
    have workspaceMiddle := kept (Ne.symm source.previousWorkspace) workspaceRead
      (by intro values same; cases same) (by intro scalar same; cases same)
    have pointerMiddle := kept (Ne.symm source.previousPointer) pointerRead
      (by intro values same; cases same) (by intro scalar same; cases same)
    have outputMiddle := kept (Ne.symm supported.previousOutput) resources.outputRead
      (by intro values same; cases same) (by intro scalar same; cases same)
    have memberMiddle : workspace ∈ middle.i32ArrayViews := by
      obtain ⟨fresh, extended⟩ := views
      rw [extended]
      exact List.mem_append_left _ member
    have bounded : bytes.length ≤ 16777216 := by rw [bytesLength, ← source.capacity]; exact room
    have tailRoom : Suffix.bytes.length ≤ resources.untouched.length := by
      have := resources.capacity
      omega
    have inputLength : (bytes.map (fun byte => Int.ofNat byte.toNat) ++
        resources.untouched.drop Suffix.bytes.length).length =
        resources.earlier.length + resources.untouched.length := by
      simp only [List.length_append, List.length_map, List.length_drop, bytesLength]
      omega
    let memory : LoopMemory := {
      workspaceCell := workspace.root, inputCell := outputCell, cursorCell := middle.nextCell,
      bytes, inputTail := resources.untouched.drop Suffix.bytes.length,
      tail := original.drop ((bytes.length + 3) / 4)
      bounded := by omega
      workspace_cursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry registry.wellFormed stored)
      input_workspace := Ne.symm separate
      input_cursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry registry.wellFormed output) }
    have outputStored : middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values memory.inputValues)) } := by
      rw [rendered] at output
      simpa only [memory, LoopMemory.inputValues, bytes, Int.ofNat_eq_natCast] using output
    have inputSize : memory.inputValues.length = resources.earlier.length + resources.untouched.length := by
      simpa only [memory, LoopMemory.inputValues, Int.ofNat_eq_natCast] using inputLength
    have lengthRead : middle.local? source.preparation.packing.length = some (.signed .i32 bytes.length) := by
      rw [source.length, bytesLength]
      exact Assertion.localPointsTo_local _ _ _ _ owned
    let args : List Value := [.pointer workspace.address, .unsigned .usize bytes.length]
    let boundParameters := (source.function.parameters.zip args).map (fun pair => (pair.1.1, pair.2))
    have bound : bindParameters source.function.parameters args = some boundParameters := by
      simp only [bindParameters, source.parameters, args, List.length_cons, List.length_nil, beq_self_eq_true, if_true,
        boundParameters]
    obtain ⟨after, run, world⟩ := prepare_and_write program.core memory source.preparation.packing
      source.preparation.wordCount source.preparation.clearCursor original registry bounded
      (by change (bytes.length + 3) / 4 ≤ original.length; rw [capacity]; exact (output_word_bounds _ bounded).2)
      rfl workspaceMiddle stored
      (by simpa only [inputSize, source.input] using outputMiddle)
      outputStored lengthRead source.wordDistinct source.clearDistinct source.packDistinct
      source.stdout source.function boundParameters workspace source.stdoutLength
      (by change bytes.length < unsignedModulus program.core.target .usize; omega)
      pointerMiddle source.pointerDistinct source.sizeLength source.sizePointer source.functionId source.functionFound
      bound source.noBody source.host memberMiddle rfl
    have statement : stage.continuation =
        Preparation.statement ⟨source.preparation.packing, source.preparation.wordCount,
          source.preparation.clearCursor, source.stdout.statement⟩ := by
      rw [source.preparationSource]
      exact source.preparation.checked_stdout_statement ⟨source.stdout, source.stdoutSource⟩
    refine ⟨_, after, statement.symm ▸ run, Or.inr ⟨rfl, ?_⟩, fun _ => rfl⟩
    exact world.trans (congrArg (fun initial : Lanius.World.State => {
      initial with
      standardOutput := initial.standardOutput ++ bytes
      calls := initial.calls ++ [HostService.writeStdout] }) effect.world)

end Lanius.Extraction.Entry.Output
