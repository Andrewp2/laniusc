import verified_compiler.tests.direct_escaped_identifier

namespace DeclarationNameProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SourceIdentifierProof SymbolSpellingProof

def source := Extracted.«verified::lean_syntax».Functions.«declaration_identifier».core
private theorem sourceFound : extractedProgram.function? source.id = some source := by core_lookup
private def nextId := source.bindingId 3
private def indexId := source.bindingId 4
private def emissionBody : Stmt := match source.body with
  | some (.sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence _ body))))) => body
  | _ => .skip
private def guards : Expr × Expr := match source.body with
  | some (.sequence (.ifThenElse unit _ _) (.letLocal _ _ _ (.letLocal _ _ _
      (.letLocal _ _ _ (.sequence (.ifThenElse path _ _) _))))) => (unit, path)
  | _ => (.value (.boolean true), .value (.boolean true))
private def initializers : Expr × Expr × Expr := match source.body with
  | some (.sequence _ (.letLocal _ _ units (.letLocal _ _ path (.letLocal _ _ segments _)))) => (units, path, segments)
  | _ => (.value .unit, .value .unit, .value .unit)
private def loop : Expr × Stmt := match emissionBody with
  | .letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop guard body) _)) => (guard, body)
  | _ => (.value (.boolean true), .skip)
private def separatorStmt : Stmt := match loop.2 with | .sequence first _ => first | _ => .skip
private def cursorBody : Stmt := match emissionBody with | .letLocal _ _ _ body => body | _ => .skip
private def writer (index : Nat) : Expr := match source.effectExpression index with
  | .assign _ _ expression => expression | _ => .value .unit

def referenceType : Ty := match referenceValue 0 0 with
  | .structure id _ => .structure id | _ => .unit
def separator (index : Nat) : List UInt8 := if index = 0 then [] else World.utf8Bytes "::"

/-- Existing module-path storage and its source names. These are native input
    reads, not successful invocations of the emitter or a second emitted tree. -/
structure Path (reference : Heap) where
  name : Name reference
  segments : List (Name reference)
  address : Nat
  length : Nat
  nonempty : 0 < segments.length
  countBound : segments.length ≤ name.unit.tokenCount
  descriptor : name.unit.modulePath = source_value Extracted.«ir::symbol_catalog».Types.«ModulePath».mk
    [.rawSlice referenceType address length, .signed .i32 segments.length]
  catalogs : ∀ index (inside : index < segments.length), segments[index].catalog = name.catalog
  reads : ∀ index (inside : index < segments.length),
    readRawSliceIndex extractedProgram { heap := reference } referenceType address length index =
      .ok segments[index].referenceValue

def Path.chunks (path : Path reference) : List (List UInt8) :=
  path.segments.mapIdx (fun index name => separator index ++ name.bytes)
def Path.prefix (path : Path reference) (index : Nat) : List UInt8 := (path.chunks.take index).flatten
def Path.bytes (path : Path reference) : List UInt8 := path.chunks.flatten

abbrev Space := Extracted.«verified::lean_syntax».Types.«DeclarationSpace»
def spaceValue : Space → Value
  | .TypeSpace => source_value Extracted.«verified::lean_syntax».Types.«DeclarationSpace».«TypeSpace» []
  | .FunctionSpace => source_value Extracted.«verified::lean_syntax».Types.«DeclarationSpace».«FunctionSpace» []
  | .ConstantSpace => source_value Extracted.«verified::lean_syntax».Types.«DeclarationSpace».«ConstantSpace» []
def namespaceText : Space → String
  | .TypeSpace => ".Types." | .FunctionSpace => ".Functions." | .ConstantSpace => ".Constants."
private def namespaceLength : Space → Nat | .TypeSpace => 7 | _ => 11
def restBytes (path : Path reference) (space : Space) : List UInt8 :=
  path.bytes ++ World.utf8Bytes "»" ++ World.utf8Bytes (namespaceText space) ++ EscapedIdentifierProof.bytes path.name
def bytes (path : Path reference) (space : Space) : List UInt8 := World.utf8Bytes "Extracted.«" ++ restBytes path space

theorem Path.prefixStep (path : Path reference) (inside : index < path.segments.length) :
    path.prefix (index + 1) = path.prefix index ++ separator index ++ path.segments[index].bytes := by
  have bound : index < path.chunks.length := by simpa [Path.chunks] using inside
  change (path.chunks.take (index + 1)).flatten = _
  rw [List.take_succ_eq_append_getElem bound]
  simp only [Path.prefix, List.flatten_append,
    List.flatten_cons, List.flatten_nil, List.append_nil, Path.chunks, List.getElem_mapIdx, List.append_assoc]

theorem Path.prefixBound (path : Path reference) (index : Nat) : (path.prefix index).length ≤ path.bytes.length := by
  have split : path.prefix index ++ (path.chunks.drop index).flatten = path.bytes := by
    simp only [Path.prefix, Path.bytes, ← List.flatten_append, List.take_append_drop]
  have lengths := congrArg List.length split
  simp only [List.length_append] at lengths
  omega

private structure Input (base : State) extends OutputNaturalProof.Buffer base where
  reference : Heap
  path : Path reference
  which : Space
  outputLocal : base.local? (source.argumentId 0) = some (.rawSlice (.scalar (.signed .i32)) address words)
  capacityLocal : base.local? (source.argumentId 1) = some (.signed .i32 capacity)
  namesLocal : base.local? (source.argumentId 3) = some path.name.catalog.value
  referenceLocal : base.local? (source.argumentId 4) = some path.name.referenceValue
  spaceLocal : base.local? (source.argumentId 5) = some (spaceValue which)
  pathLocal : base.local? (source.bindingId 1) = some
    (source_value Extracted.«ir::symbol_catalog».Types.«ModulePath».mk
      [.rawSlice referenceType path.address path.length, .signed .i32 path.segments.length])
  segmentsLocal : base.local? (source.bindingId 2) = some (.rawSlice referenceType path.address path.length)
  memory : ReadOnlyMemory reference base.heap address (words * 4)
  space : position + (restBytes path which).length ≤ capacity
  environment : WriterEnvironment base

private def Input.afterPrefix (context : Input base)
    (frame : WriterFrame base after (context.address + context.position) (World.utf8Bytes "Extracted.«"))
    (locals : after.locals = base.locals)
    (room : context.position + (bytes context.path context.which).length ≤ context.capacity) : Input after := {
  context.toBuffer.afterWriter frame with
  reference := context.reference, path := context.path, which := context.which
  outputLocal := frame.cells.localFound locals _ _ context.outputLocal
  capacityLocal := frame.cells.localFound locals _ _ context.capacityLocal
  namesLocal := frame.cells.localFound locals _ _ context.namesLocal
  referenceLocal := frame.cells.localFound locals _ _ context.referenceLocal
  spaceLocal := frame.cells.localFound locals _ _ context.spaceLocal
  pathLocal := frame.cells.localFound locals _ _ context.pathLocal
  segmentsLocal := frame.cells.localFound locals _ _ context.segmentsLocal
  memory := context.memory.afterOutput frame.output (by omega) (by
    have storage := context.storage
    simp only [bytes, List.length_append] at room ⊢
    omega)
  space := by simpa only [OutputNaturalProof.Buffer.afterWriter, bytes, List.length_append, Nat.add_assoc] using room
  environment := context.environment.afterWrite frame }

private abbrev Current (context : Input base) (current : State) (index : Nat) : Prop :=
  WriterCounter base current nextId indexId (context.address + context.position) context.position
    (context.path.prefix index) index

private theorem iteration (context : Input base) (current : Current context state index)
    (inside : index < context.path.segments.length) :
    ∃ after, RunsStmt extractedProgram state loop.2 .next after ∧ Current context after (index + 1) := by
  have formed := context.environment.formed
  have room := context.space
  simp only [restBytes, List.length_append] at room
  have prefixSize := context.path.prefixBound (index + 1)
  have step := context.path.prefixStep inside
  have stepLengths := congrArg List.length step
  simp only [List.length_append] at stepLengths
  core_facts [context, current]
  have separated : ∃ middle, RunsStmt extractedProgram state separatorStmt .next middle ∧
      WriterCounter base middle nextId indexId (context.address + context.position) context.position
        (context.path.prefix index ++ separator index) index := by
    by_cases zero : index = 0
    · exact ⟨state, by core_stmt, by simpa only [separator, zero, ↓reduceIte, List.append_nil] using current⟩
    · have nonzero : (index : Int) ≠ 0 := by omega
      obtain ⟨written, text, frame⟩ := OutputWriterProof.textAt context.toBuffer current.frame "::" 2 rfl
        (by simp only [separator, zero, ↓reduceIte] at stepLengths; simp only [List.length_append]; omega)
        context.environment
      have call : RunsExpr extractedProgram state (writer 0)
          (.signed .i32 (context.position + (context.path.prefix index ++ separator index).length : Nat)) written := by
        apply RunsExpr.callArguments
        · core_arguments
        · simpa only [OutputTextProof.textCall, Extracted.«verified::lean_output».Functions.«text»,
            separator, zero, ↓reduceIte, show (Int.ofNat 2 : Int) = 2 by rfl,
            show ((2 : Nat) : Int) = 2 by rfl] using text
      obtain ⟨middle, assigned, next⟩ := current.advance formed call (by simpa only [separator, zero, ↓reduceIte] using frame)
      exact ⟨middle, by core_stmt, next⟩
  obtain ⟨middle, separatorRun, separated⟩ := separated
  let buffer := context.toBuffer.afterWriter separated.frame
  have memory := context.memory.afterOutput separated.frame.output (by omega) (by
    have storage := context.storage
    simp only [List.length_append]
    omega)
  have selected := memory.reads.rawSlice (context.path.reads index inside)
  let segment := context.path.segments[index]
  have sameCatalog := context.path.catalogs index inside
  obtain ⟨written, nameRun, nameFrame⟩ := SourceIdentifierProof.actualCall buffer segment memory
    (by dsimp [buffer, OutputNaturalProof.Buffer.afterWriter, segment]; simp only [List.length_append]; omega)
    (context.environment.afterWrite separated.frame)
  have nameCall : RunsExpr extractedProgram middle (writer 1)
      (.signed .i32 (context.position + ((context.path.prefix index ++ separator index) ++ segment.bytes).length : Nat)) written := by
    core_facts [context, separated]
    apply RunsExpr.callArguments
    · core_arguments
    · simpa only [SourceIdentifierProof.call, SourceIdentifierProof.source,
        Extracted.«verified::lean_syntax».Functions.«source_identifier», buffer, OutputNaturalProof.Buffer.afterWriter,
        segment, sameCatalog, List.length_append, Nat.add_assoc] using nameRun
  obtain ⟨updated, writeCursor, next⟩ := separated.advance formed nameCall (by
    simpa only [buffer, OutputNaturalProof.Buffer.afterWriter, Nat.add_assoc] using nameFrame)
  have countFits : context.path.segments.length < 2 ^ 31 := by
    have bound := context.path.countBound
    have tokens := context.path.name.valid.tokenRange
    have fits := context.path.name.valid.tokensFit
    omega
  obtain ⟨after, increment, advanced⟩ := next.increment (program := extractedProgram) formed (by omega)
  have cursor := next.first
  exact ⟨after, by core_stmt, by simpa only [Current, step, segment, List.append_assoc] using advanced⟩

private theorem actualLoop (context : Input base) :
    ∃ after, RunsStmt extractedProgram
      ((base.bindLocal nextId (.signed .i32 context.position)).bindLocal indexId (.signed .i32 0))
      (.whileLoop loop.1 loop.2) .next after ∧ Current context after context.path.segments.length := by
  have initial : Current context
      ((base.bindLocal nextId (.signed .i32 context.position)).bindLocal indexId (.signed .i32 0)) 0 := by
    simpa only [Current, Path.prefix, List.take_zero, List.flatten_nil] using
      WriterCounter.start context.environment.formed context.environment.unique (by decide : nextId ≠ indexId)
  apply RunsStmt.whilePrefix (remaining := context.path.segments.length)
    (invariant := fun remaining current => ∃ index, index + remaining = context.path.segments.length ∧ Current context current index)
  · intro current ⟨index, total, frame⟩
    have same : index = context.path.segments.length := by omega
    subst index
    core_facts [context, frame]
    have descriptor := context.path.descriptor
    exact ⟨current, .whileFalse (by core_run), frame⟩
  · intro remaining current ⟨index, total, frame⟩
    have inside : index < context.path.segments.length := by omega
    core_facts [context, frame]
    have descriptor := context.path.descriptor
    obtain ⟨after, body, next⟩ := iteration context frame inside
    exact ⟨current, after, by core_run, body, index + 1, by omega, next⟩
  · exact ⟨0, by omega, initial⟩

private theorem prepared (context : Input base) :
    ∃ after, RunsStmt extractedProgram (base.bindLocal nextId (.signed .i32 context.position)) cursorBody
      (.returned (some (.signed .i32 (context.position + (restBytes context.path context.which).length : Nat)))) after ∧
      WriterFrame base after (context.address + context.position) (restBytes context.path context.which) := by
  obtain ⟨finished, loopRun, final⟩ := actualLoop context
  have prefixAll : context.path.prefix context.path.segments.length = context.path.bytes := by
    have length : context.path.chunks.length = context.path.segments.length := by simp only [Path.chunks, List.length_mapIdx]
    simp only [Path.prefix, Path.bytes, ← length, List.take_length]
  have cursor := final.toCursor
  rw [prefixAll] at cursor
  have formed := context.environment.formed
  have room := context.space
  simp only [restBytes, List.length_append] at room
  have closing := OutputWriterProof.textAt context.toBuffer cursor.frame "»" 2 rfl
    (by simp only [List.length_append]; omega) context.environment
  obtain ⟨closed, closingRun, closedCursor⟩ := cursor.advanceArguments formed closing
    (expressions := [.local (source.argumentId 0), .local (source.argumentId 1), .local nextId,
      .value (.string "»"), .value (.signed .i32 2)]) (by core_facts [context]; core_arguments) rfl
  have namespaceWriter := OutputWriterProof.textAt context.toBuffer closedCursor.frame (namespaceText context.which)
    (namespaceLength context.which) (by cases context.which <;> rfl)
    (by simp only [List.length_append]; omega) context.environment
  obtain ⟨named, namespaceRun, namedCursor⟩ := closedCursor.advanceArguments formed namespaceWriter
    (expressions := [.local (source.argumentId 0), .local (source.argumentId 1), .local nextId,
      .value (.string (namespaceText context.which)), .value (.signed .i32 (namespaceLength context.which))])
    (by core_facts [context]; core_arguments) rfl
  let buffer := context.toBuffer.afterWriter namedCursor.frame
  have retained := context.memory.afterOutput namedCursor.frame.output (by omega) (by
    have storage := context.storage
    simp only [List.length_append]
    omega)
  have name := EscapedIdentifierProof.actualCall buffer context.path.name retained
    (by dsimp [buffer, OutputNaturalProof.Buffer.afterWriter]; simp only [List.length_append]; omega)
    (context.environment.afterWrite namedCursor.frame)
  simp only [EscapedIdentifierProof.call, buffer, OutputNaturalProof.Buffer.afterWriter,
    List.length_append, Nat.add_assoc] at name
  have nextFound := namedCursor.value
  simp only [List.length_append, Nat.add_assoc] at nextFound
  obtain ⟨last, returned, written⟩ := namedCursor.finishArguments (program := extractedProgram)
    (suffix := EscapedIdentifierProof.bytes context.path.name)
    (next := (context.position + (restBytes context.path context.which).length : Nat))
    (by simpa only [restBytes, List.length_append, Nat.add_assoc] using name)
    (expressions := [.local (source.argumentId 0), .local (source.argumentId 1), .local nextId,
      .local (source.argumentId 3), .local (source.argumentId 4)])
    (by core_facts [context]; core_arguments) (by
      simp only [List.length_append, restBytes])
  have tail : RunsStmt extractedProgram
      ((base.bindLocal nextId (.signed .i32 context.position)).bindLocal indexId (.signed .i32 0))
      (match cursorBody with | .letLocal _ _ _ tail => tail | _ => .skip)
      (.returned (some (.signed .i32 (context.position + (restBytes context.path context.which).length : Nat)))) last := by
    core_facts [context]
    have spaceFound := context.spaceLocal
    cases which : context.which <;>
      simp only [which, spaceValue, namespaceText, namespaceLength,
        show ((7 : Nat) : Int) = 7 by rfl, show ((11 : Nat) : Int) = 11 by rfl]
        at namespaceRun spaceFound returned <;> core_stmt
  let bound := base.bindLocal nextId (.signed .i32 context.position)
  exact ⟨restoreLocals bound last, .letLocal (by core_run) tail, written.restoreLocals bound⟩

private theorem emit (input : Input base)
    (room : input.position + (bytes input.path input.which).length ≤ input.capacity)
    (positionFound : base.local? (source.argumentId 2) = some (.signed .i32 input.position)) :
    ∃ after, RunsStmt extractedProgram base emissionBody
      (.returned (some (.signed .i32 (input.position + (bytes input.path input.which).length : Nat)))) after ∧
      WriterFrame base after (input.address + input.position) (bytes input.path input.which) := by
  obtain ⟨first, firstRun, firstFrame⟩ := OutputWriterProof.text input.toBuffer "Extracted.«"
    (by simp only [bytes, List.length_append] at room ⊢; omega) input.environment
  let context := input.afterPrefix firstFrame firstRun.choose_spec.2 room
  obtain ⟨last, tailRun, tailFrame⟩ := prepared context
  refine ⟨restoreLocals first last, ?_, ?_⟩
  · apply RunsStmt.letLocal
    · apply RunsExpr.callArguments
      · core_facts [input]
        core_arguments
      · exact firstRun
    · change RunsStmt extractedProgram
        (first.bindLocal nextId (.signed .i32 (input.position + (World.utf8Bytes "Extracted.«").length : Nat)))
        cursorBody (.returned (some (.signed .i32 (input.position + (bytes input.path input.which).length : Nat)))) last
      simpa only [context, Input.afterPrefix, OutputNaturalProof.Buffer.afterWriter, bytes,
        List.length_append, Nat.add_assoc] using tailRun
  · exact (firstFrame.append (by
      simpa only [context, Input.afterPrefix, OutputNaturalProof.Buffer.afterWriter, Nat.add_assoc] using tailFrame)).restoreLocals first

def call (buffer : OutputNaturalProof.Buffer state) (path : Path reference) (space : Space) : Expr :=
  .call source.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position, path.name.catalog.value,
    path.name.referenceValue, spaceValue space].map Expr.value)

/-- Actual qualified declaration emission: native module-path and segment
    reads, termination, exact spelling, cursor, and caller/input framing. -/
theorem actualCall (buffer : OutputNaturalProof.Buffer state) (path : Path reference) (space : Space)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + (bytes path space).length ≤ buffer.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (call buffer path space)
      (.signed .i32 (buffer.position + (bytes path space).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (bytes path space) := by
  have formed := environment.formed
  have found := sourceFound
  obtain ⟨address, length, descriptor, unitRead⟩ := path.name.valid.unitRead
  have selected := memory.reads.rawSlice unitRead
  have unitInside := path.name.valid.unitInside
  have countPositive := path.nonempty
  have countBound := path.countBound
  have modulePath := path.descriptor
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  clear found
  have unitGuard : RunsExpr extractedProgram callee guards.1 (.boolean false) callee := by core_run
  let units := callee.bindLocal (source.bindingId 0) (.rawSlice unitType address length)
  let named := units.bindLocal (source.bindingId 1)
    (source_value Extracted.«ir::symbol_catalog».Types.«ModulePath».mk
      [.rawSlice referenceType path.address path.length, .signed .i32 path.segments.length])
  let ready := named.bindLocal (source.bindingId 2) (.rawSlice referenceType path.address path.length)
  have unitsInitial : RunsExpr extractedProgram callee initializers.1 (.rawSlice unitType address length) callee := by
    rw [← descriptor]
    core_run
  have pathInitial : RunsExpr extractedProgram units initializers.2.1
      (source_value Extracted.«ir::symbol_catalog».Types.«ModulePath».mk
        [.rawSlice referenceType path.address path.length, .signed .i32 path.segments.length]) units := by
    rw [← modulePath]
    core_run
  have segmentsInitial : RunsExpr extractedProgram named initializers.2.2
      (.rawSlice referenceType path.address path.length) named := by core_run
  have pathGuard : RunsExpr extractedProgram ready guards.2 (.boolean false) ready := by core_run
  let input : Input ready := { buffer with
    reference, path, which := space,
    outputLocal := by core_local, capacityLocal := by core_local, namesLocal := by core_local,
    referenceLocal := by core_local, spaceLocal := by core_local, pathLocal := by core_local,
    segmentsLocal := by core_local, memory,
    space := by simp only [bytes, List.length_append] at room; omega
    environment := environment.reheap rfl rfl (by core_formed) }
  have write := emit input room (by core_local)
  core_writer

/-- Invalid source-unit IDs reject before any backing or output access. -/
theorem rejectsUnit (output : Value) (capacity position unit token : Int) (catalog : Catalog) (space : Space)
    (bad : unit < 0 ∨ catalog.unitCount ≤ unit) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call source.id ([output, .signed .i32 capacity, .signed .i32 position, catalog.value,
      referenceValue unit token, spaceValue space].map Expr.value)) (.signed .i32 (-1)) after ∧ PureFrame state after := by
  have found := sourceFound
  core_call_pure source as callee
  clear found
  core_pure

#print axioms iteration
#print axioms actualLoop
#print axioms prepared
#print axioms emit
#print axioms actualCall
#print axioms rejectsUnit

end DeclarationNameProof
