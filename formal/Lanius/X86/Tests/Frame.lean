import Lanius.X86.Frame.Source
import Lanius.X86.Frame.Return
import Lanius.X86.Frame.Slot
import Lanius.X86.Frame.Allocate
import Lanius.X86.Lower.Expression.Indexed.Prepare
import Lanius.X86.Lower.Expression.Indexed.Reject
import Lanius.X86.Lower.Expression.Indexed.Body
import Lanius.X86.Lower.Expression.Indexed.Failure
import Lanius.X86.Lower.Expression.Indexed.Preservation
import Lanius.X86.Control.Require
import Lanius.X86.Source.Check
import Lanius.X86.Source.Index
import Lanius.X86.Lower.Index.Preservation
import Lanius.X86.Lower.Index.Reject
import Lanius.X86.Transport.Core
import Lanius.X86.Storage.Value
import Lanius.X86.Machine.Index
import Lanius.X86.Encode.Indexed
import Lanius.X86.Encode.Memory
import Lanius.X86.Encode.Immediate
import Lanius.X86.Encode.Immediate.Wide.Preservation
import Lanius.X86.Lower.Value.Get
import Lanius.X86.Frame.Take
import Lanius.X86.Frame.Take.Reject
import Lanius.X86.Frame.Lookup
import Lanius.X86.Lower.Expression.Literal.Layout
import Lanius.X86.Lower.Expression.Literal
import Lanius.X86.Lower.Expression.Literal.Preservation
import Lanius.X86.Lower.Expression.Literal.Capacity
import Lanius.X86.Lower.Expression.Literal.Boolean
import Lanius.X86.Lower.Expression.Indexed.Literal.Preservation
import Lanius.X86.Lower.Expression.Local
import Lanius.X86.Lower.Expression.Local.Reject
import Lanius.X86.Lower.Expression.Local.Native
import Lanius.X86.Lower.Expression.Local.Preservation
import Lanius.Extraction.ExtractorContract

open Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.X86.Source Lanius.X86.Frame

/-- Bind the frame laws to the expanded, exact backend source closure, not a
handwritten replacement for either Lanius helper. -/
def main (arguments : List String) : IO UInt32 := do
  let backend :: directory :: modulePath :: paths := arguments
    | throw (IO.userError "expected backend executable, fixture directory, extracted backend module and exact ordered sources")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid source pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : SourceFile)
  let emitters ← IO.ofExcept (checkBuffer encoded sources)
  let some immediate := Lanius.X86.Source.Immediate.check? emitters.pack.program
      emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
    | throw (IO.userError "actual immediate emitter source does not match its proof")
  have _immediateTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} {low high : Int} =>
    Lanius.X86.Encode.Immediate.succeeds32 (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) (low := low) (high := high) immediate
  have _immediateReject := fun {before caller : State} {arguments : List Expr} =>
    Lanius.X86.Encode.Immediate.rejects_capacity32 (before := before) (caller := caller)
      (arguments := arguments) immediate
  have _wideTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Encode.Immediate.Wide.Preservation.emits (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) immediate
  have _wideTransport := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} {value : Nat} =>
    Lanius.X86.Encode.Immediate.Wide.Preservation.from_transport (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) (value := value) immediate
  have _wideReject := fun {before caller : State} {arguments : List Expr} =>
    Lanius.X86.Encode.Immediate.Wide.rejects_capacity64 (before := before) (caller := caller)
      (arguments := arguments) immediate
  let some taking := Lanius.X86.Source.Take.check? emitters.pack.program
    | throw (IO.userError "actual transport reader source does not match its proof")
  have _takeTheorem := fun {before caller : State} {arguments : List Expr}
      {input work : Lanius.CellId} {values workspace : List Int} {value : Int} =>
    Lanius.X86.Frame.Take.succeeds (before := before) (caller := caller) (arguments := arguments)
      (input := input) (work := work) (values := values) (workspace := workspace) (value := value) taking
  have _takeReject := fun {before caller : State} {arguments : List Expr}
      {work : Lanius.CellId} {workspace : List Int} =>
    Lanius.X86.Frame.Take.Reject.rejects (before := before) (caller := caller) (expressions := arguments)
      (work := work) (workspace := workspace) taking
  let some lookup := Lanius.X86.Source.Lookup.check? emitters.pack.program
    | throw (IO.userError "actual lexical lookup source does not match its proof")
  have _lookupTheorem := fun {before caller : State} {arguments : List Expr}
      {work : Lanius.CellId} {workspace : List Int} =>
    Lanius.X86.Frame.Lookup.runs (before := before) (caller := caller) (expressions := arguments)
      (work := work) (workspace := workspace) lookup
  have _lookupEmpty := fun {before caller : State} {arguments : List Expr} =>
    Lanius.X86.Frame.Lookup.nonpositive (before := before) (caller := caller) (expressions := arguments) lookup
  let some literal := Lanius.X86.Source.Expression.Literal.check? emitters
    | throw (IO.userError "actual literal dispatch, expression wrapper, layout or callees differ from the source contract")
  let some localExpression := Lanius.X86.Source.Expression.Local.check? literal
    | throw (IO.userError "actual local-expression dispatch, lookup, binding tables or getter differ from the source contract")
  have _localExpression := fun {key : Int} {slot : Nat} =>
    Lanius.X86.Lower.Expression.Local.compiles (width := .w32) (key := key) (slot := slot) localExpression
  have _missingLocal := fun {before caller : State} {arguments : List Expr}
      {input output work : Lanius.CellId} {transport values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Local.Reject.wrapper_rejects (before := before) (caller := caller) (arguments := arguments)
      (input := input) (output := output) (work := work) (transport := transport) (values := values) (workspace := workspace) localExpression
  have _nativeLocal := fun {coreLocal slot : Nat} {value : Int} =>
    Lanius.X86.Lower.Expression.Local.Preservation.compiles
      (coreLocal := coreLocal) (slot := slot) (value := value) localExpression
  have _localTransport := fun {sourceProgram : Program} {words suffix : List Int} {coreLocal slot : Nat} {value : Int} =>
    Lanius.X86.Lower.Expression.Local.Preservation.from_transport
      (sourceProgram := sourceProgram) (words := words) (suffix := suffix)
      (coreLocal := coreLocal) (slot := slot) (value := value) localExpression
  have _literalWidth := fun {before caller : State} {arguments : List Expr} =>
    Lanius.X86.Lower.Expression.Literal.Layout.width32 (before := before) (caller := caller)
      (arguments := arguments) literal.layout (.inl rfl)
  have _literalAggregate := fun {before caller : State} {arguments : List Expr} =>
    Lanius.X86.Lower.Expression.Literal.Layout.aggregate (before := before) (caller := caller)
      (arguments := arguments) literal.layout 1
  have _literalCompiler := fun {kind low : Int} =>
    Lanius.X86.Lower.Expression.Literal.compiles (kind := kind) (low := low) literal
  have _booleanCompiler := fun {program : Program} {value : Bool} {words suffix : List Int} =>
    Lanius.X86.Lower.Expression.Literal.Boolean.from_transport
      (program := program) (value := value) (words := words) (suffix := suffix) literal
  have _booleanCapacity := Lanius.X86.Lower.Expression.Literal.Boolean.rejects_capacity literal
  have _literalNative := fun {before caller : State} {arguments : List Expr}
      {input output work : Lanius.CellId} {transport values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Literal.Preservation.compiles (before := before) (caller := caller) (arguments := arguments)
      (input := input) (output := output) (work := work) (transport := transport) (values := values) (workspace := workspace) literal
  have _literalTransport := fun {before caller : State} {arguments : List Expr} {sourceProgram : Program}
      {input output work : Lanius.CellId} {words suffix transport values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Literal.Preservation.from_transport (before := before) (caller := caller)
      (arguments := arguments) (sourceProgram := sourceProgram) (words := words) (suffix := suffix)
      (input := input) (output := output) (work := work) (transport := transport) (values := values) (workspace := workspace) literal
  have _literalCapacity := fun {before caller : State} {arguments : List Expr}
      {input output work : Lanius.CellId} {transport values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Literal.Capacity.records_failure (before := before) (caller := caller) (arguments := arguments)
      (input := input) (output := output) (work := work) (transport := transport) (values := values) (workspace := workspace) literal
  let some allocation := Lanius.X86.Source.Allocate.check? emitters.pack.program
    | throw (IO.userError "actual frame allocator source does not match its proof")
  have _allocateTheorem := fun {before caller : State} {arguments : List Expr}
      {work : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Frame.Allocate.succeeds (before := before) (caller := caller) (arguments := arguments)
      (work := work) (values := values) allocation
  have _allocateReject := fun {before caller : State} {arguments : List Expr}
      {work : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Frame.Allocate.rejects (before := before) (caller := caller) (arguments := arguments)
      (work := work) (values := values) allocation
  let some recursiveIndex := Lanius.X86.Source.Expression.Indexed.check? emitters
    | throw (IO.userError "actual indexed-expression caller or its callees differ from the source contract")
  if sameExpression : recursiveIndex.expression.function.id = literal.wrapper.source.function.id then
    have _closedIndexedLiteral := fun {before caller : State} {arguments : List Expr}
        {input output work : Lanius.CellId} {transport values workspace : List Int} =>
      Lanius.X86.Lower.Expression.Indexed.Literal.Preservation.compiles
        (before := before) (caller := caller) (arguments := arguments) (input := input) (output := output) (work := work)
        (transport := transport) (values := values) (workspace := workspace) recursiveIndex literal sameExpression
    have _closedIndexedTransport := fun {before caller : State} {arguments : List Expr} {sourceProgram : Program}
        {input output work : Lanius.CellId} {words suffix transport values workspace : List Int} =>
      Lanius.X86.Lower.Expression.Indexed.Literal.Preservation.from_transport
        (before := before) (caller := caller) (arguments := arguments) (sourceProgram := sourceProgram)
        (input := input) (output := output) (work := work) (words := words) (suffix := suffix)
        (transport := transport) (values := values) (workspace := workspace) recursiveIndex literal sameExpression
    pure ()
  else
    throw (IO.userError "indexed caller and literal base case refer to different expression functions")
  have _prepareIndexTheorem := fun {before : State} {inputs : List Value}
      {frontier output work : Nat} {values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Indexed.prepare (before := before) (inputs := inputs)
      (frontier := frontier) (output := output) (work := work) (values := values) (workspace := workspace) recursiveIndex
  have _rejectIndexTheorem := fun {before caller : State} {arguments : List Expr}
      {work : Lanius.CellId} {workspace : List Int} {input length output capacity active depth context contextLength : Value} =>
    Lanius.X86.Lower.Expression.Indexed.Reject.rejects (before := before) (caller := caller)
      (arguments := arguments) (work := work) (workspace := workspace) (input := input) (length := length)
      (output := output) (capacity := capacity) (active := active) (depth := depth) (context := context)
      (contextLength := contextLength) recursiveIndex
  have _compileIndexTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Indexed.compiles (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) recursiveIndex
  have _invalidOperandTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Indexed.Failure.rejects (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) recursiveIndex
  have _nativeIndexTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Lower.Expression.Indexed.Preservation.compiles (before := before) (caller := caller)
      (arguments := arguments) (output := output) (work := work) (values := values) (workspace := workspace) recursiveIndex
  let some require := Lanius.X86.Source.Require.check? emitters.pack.program emitters.branch emitters.trap
    | throw (IO.userError "actual bounds guard source does not match its proof")
  have _requireTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Control.Require.emits (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) require
  let some memory := Lanius.X86.Source.Memory.check? emitters.pack.program
      emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
    | throw (IO.userError "actual shared memory emitter source does not match its proof")
  let some memoryLoad := Lanius.X86.Source.Memory.checkMove? emitters.pack.program memory true
    | throw (IO.userError "actual public load emitter source does not match its proof")
  let some memoryStore := Lanius.X86.Source.Memory.checkMove? emitters.pack.program memory false
    | throw (IO.userError "actual public store emitter source does not match its proof")
  have _memoryTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Encode.Memory.succeeds (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) memory
  have _loadTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Encode.Memory.move_emits (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) memoryLoad
  have _storeTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Encode.Memory.move_emits (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) memoryStore
  have _memoryReject := fun {before caller : State} {arguments : List Expr} =>
    Lanius.X86.Encode.Memory.rejects_capacity (before := before) (caller := caller) (arguments := arguments) memory
  let some indexed := Lanius.X86.Source.Indexed.check? emitters.pack.program
      emitters.registerValid emitters.rex emitters.fits emitters.word
    | throw (IO.userError "actual scaled-address emitter source does not match its proof")
  have _indexedTheorem := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Encode.Indexed.slice_address_emits (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) indexed
  have _indexedGeneral := fun {before caller : State} {arguments : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Lanius.X86.Encode.Indexed.succeeds (before := before) (caller := caller)
      (arguments := arguments) (cell := cell) (values := values) indexed
  let some offset := checkDisplacement? emitters.pack.program
    | throw (IO.userError "actual frame displacement source does not match its proof")
  let some scalarGet := Lanius.X86.Source.Value.Get.check? emitters.pack.program literal.layout memoryLoad offset
    | throw (IO.userError "actual scalar value getter source does not match its proof")
  have _scalarGet := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Lower.Value.Get.emits (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) scalarGet .w32
  let some slotLoad := Lanius.X86.Source.Slot.check? emitters.pack.program .load32 memoryLoad offset
    | throw (IO.userError "actual frame load source does not match its proof")
  let some wordLoad := Lanius.X86.Source.Slot.check? emitters.pack.program .load64 memoryLoad offset
    | throw (IO.userError "actual word load source does not match its proof")
  let some wordStore := Lanius.X86.Source.Slot.check? emitters.pack.program .save64 memoryStore offset
    | throw (IO.userError "actual word store source does not match its proof")
  have _slotTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Frame.Slot.emits (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) slotLoad
  have _wordLoadTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Frame.Slot.emits (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) wordLoad
  have _wordStoreTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Frame.Slot.emits (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) wordStore
  let some size := checkBytes? emitters.pack.program
    | throw (IO.userError "actual frame size source does not match its proof")
  let some returning := checkReturn? emitters.pack.program emitters.fits
    | throw (IO.userError "actual frame return source does not match its proof")
  let some compiler := CoreSynthesis.Program.checkSourceFunction? emitters.pack.program ["backend", "program"] "compile"
    | throw (IO.userError "missing actual program compiler body")
  let some copying := CoreSynthesis.Program.checkSourceFunction? emitters.pack.program ["backend", "value"] "copy"
    | throw (IO.userError "missing actual aggregate copy emitter")
  let some indexSource := Lanius.X86.Source.Index.check? emitters
    | throw (IO.userError "actual checked-address body, constants, or callees differ from the composed source contract")
  let indexing := indexSource.internal.source
  have _indexTheorem := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Lanius.X86.Lower.Index.Emission.compiles (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) indexSource
  have _invalidIndexTheorem := fun {before caller : State} {arguments : List Expr}
      {output capacity work slot : Value} =>
    Lanius.X86.Lower.Index.Reject.rejects (before := before) (caller := caller) (arguments := arguments)
      (output := output) (capacity := capacity) (work := work) (slot := slot) indexSource
  have _offsetTheorem := fun {before caller : State} {arguments : List Expr} =>
    displacement_call (before := before) (caller := caller) (arguments := arguments) offset
  have _sizeTheorem := fun {before caller : State} {arguments : List Expr} =>
    bytes_call (before := before) (caller := caller) (arguments := arguments) size
  have _returnTheorem := fun {before caller : State} {arguments : List Expr} {cell : Lanius.CellId} {values : List Int} =>
    return_emits (before := before) (caller := caller) (arguments := arguments) (cell := cell) (values := values) returning
  let immediateGuard := Lanius.X86.Source.Immediate.guard emitters.registerValid.source.function.id emitters.widthValid.source.function.id
  let wrongImmediateSize : Stmt := .sequence (.ifThenElse immediateGuard (returned negativeOne) .skip)
    (.letLocal 7 i32 (.call emitters.rex.source.function.id [read 3, number 0, read 4, .value (.boolean false)])
      (.letLocal 8 i32 (number 4) (.sequence Lanius.X86.Source.Immediate.wideSize
        (.sequence (Lanius.X86.Source.countPrefix 8 Lanius.X86.Source.Immediate.hasRex)
          (Lanius.X86.Source.Immediate.afterSize emitters.fits.source.function.id emitters.word.source.function.id)))))
  for wrong in [wrongImmediateSize, Lanius.X86.Source.Immediate.body emitters.registerValid.source.function.id
      emitters.widthValid.source.function.id emitters.rex.source.function.id emitters.word.source.function.id emitters.fits.source.function.id] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["x86", "encode"] "immediate"
        Lanius.X86.Source.Immediate.parameters i32 wrong).isNone do
      throw (IO.userError "immediate source checker accepted an undersized reservation or swapped reservation/word callees")
  let takeTail : Stmt := .sequence
    (Lanius.X86.Source.Take.assign taking.input.id (.binary .add (read 3) (number 1)))
    (returned (.index (read 0) (read 3)))
  let wrongTakeBoundary : Stmt := .letLocal 3 i32 (Lanius.X86.Source.Take.field taking.input.id)
    (.sequence (.ifThenElse (.binary .logicalOr (.binary .less (read 3) (number 0))
      (.binary .greater (read 3) (read 1)))
      (.sequence (Lanius.X86.Source.Take.assign taking.failed.id (number 1)) (returned (number 0))) .skip) takeTail)
  let wrongTakeIncrement : Stmt := .letLocal 3 i32 (Lanius.X86.Source.Take.field taking.input.id)
    (.sequence (.ifThenElse Lanius.X86.Source.Take.guard
      (.sequence (Lanius.X86.Source.Take.assign taking.failed.id (number 1)) (returned (number 0))) .skip)
      (.sequence (Lanius.X86.Source.Take.assign taking.input.id (.binary .add (read 3) (number 2)))
        (returned (.index (read 0) (read 3)))))
  for wrong in [wrongTakeBoundary, wrongTakeIncrement] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "frame"] "take"
        Lanius.X86.Source.Take.parameters i32 wrong).isNone do
      throw (IO.userError "transport source checker accepted an inclusive end cursor or skipped input word")
  let lookupEnd := returned (.unary .negate (number 1))
  let wrongLookupGuard : Stmt := .letLocal 3 i32 (read 1)
    (.sequence (.whileLoop (.binary .greaterEqual (read 3) (number 0))
      (Lanius.X86.Source.Lookup.step lookup.header.id)) lookupEnd)
  let wrongLookupStep : Stmt := .sequence (.expression (.assign .subtract (.local 3) (number 2)))
    (.sequence (.ifThenElse (Lanius.X86.Source.Lookup.sameKey lookup.header.id) (returned (read 3)) .skip) .skip)
  for wrong in [Lanius.X86.Source.Lookup.body allocation.top.id, wrongLookupGuard,
      .letLocal 3 i32 (read 1) (.sequence (.whileLoop Lanius.X86.Source.Lookup.positive wrongLookupStep) lookupEnd)] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "frame"] "lookup"
        Lanius.X86.Source.Lookup.parameters i32 wrong).isNone do
      throw (IO.userError "lookup source checker accepted a changed table header, empty-range guard, or skipped binding")
  unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "layout"] "width"
      [(0, i32)] i32 (Lanius.X86.Source.Expression.Literal.widthBody literal.constants.pointer.id literal.layout.boolean.id)).isNone do
    throw (IO.userError "layout source checker accepted pointer width in place of signed-i32 width")
  unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "compile"] "emit_expression"
      Lanius.X86.Source.Expression.Indexed.parameters i32
      (Lanius.X86.Source.Expression.Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
        emitters.fits.source.function.id literal.stringBranch literal.otherBranches)).isNone do
    throw (IO.userError "literal source checker accepted a changed immediate callee")
  unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "compile"] "expression"
      Lanius.X86.Source.Expression.Indexed.parameters i32
      (Lanius.X86.Source.Expression.Literal.body literal.layout literal.constants literal.immediate.source.function.id)).isNone do
    throw (IO.userError "expression wrapper source checker accepted a changed emitter callee")
  for (emit, code, rax, base) in [
      (memoryLoad.source.function.id, scalarGet.base.id, scalarGet.rax.id, scalarGet.base.id),
      (memoryLoad.source.function.id, scalarGet.code.id, scalarGet.base.id, scalarGet.rax.id),
      (memoryStore.source.function.id, scalarGet.code.id, scalarGet.rax.id, scalarGet.base.id)] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "value"] "get"
        Lanius.X86.Source.Value.Get.parameters i32
        (Lanius.X86.Source.Value.Get.body literal.layout.aggregate.source.function.id emit
          literal.layout.width.source.function.id offset.source.function.id code rax base scalarGet.aggregateBranch)).isNone do
      throw (IO.userError "scalar getter source checker accepted a changed CODE field, register mapping, or load callee")
  let localTail := Lanius.X86.Source.Expression.Local.tail literal.layout.aggregate.source.function.id
    localExpression.get.internal.source.function.id localExpression.negativeBranch localExpression.aggregateBranch
  let localKindAddress := Lanius.X86.Source.Expression.Local.kindAddress localExpression.lookup.header.id localExpression.stride.id
  let localSlotAddress := Lanius.X86.Source.Expression.Local.slotAddress localExpression.lookup.header.id localExpression.stride.id
  let localBranch := fun (lookupArguments : List Expr) (kindAddress slotAddress : Expr) (tail : Stmt) =>
    Stmt.letLocal 14 i32 (.call literal.take.internal.source.function.id Lanius.X86.Source.Expression.Literal.takeArguments)
      (.letLocal 15 i32 (.call localExpression.lookup.internal.source.function.id lookupArguments)
        (.sequence (.ifThenElse Lanius.X86.Source.Expression.Local.rejected (returned negativeOne) .skip)
          (.letLocal 16 i32 (.index (read 2) kindAddress) (.letLocal 17 i32 (.index (read 2) slotAddress) tail))))
  let localRest := fun (tag : Lanius.ConstantId) (branch : Stmt) =>
    Stmt.sequence (.ifThenElse (Lanius.X86.Source.Expression.Local.selected tag) branch .skip) localExpression.otherBranches
  let normalLocalBranch := localBranch [read 2, read 5, read 14] localKindAddress localSlotAddress localTail
  let localTailWith := fun (getArguments : List Expr) (result : Expr) =>
    Stmt.sequence (.ifThenElse Lanius.X86.Source.Expression.Local.negativeKind localExpression.negativeBranch .skip)
      (.sequence (.expression (.call localExpression.get.internal.source.function.id getArguments))
        (.sequence (.ifThenElse (.call literal.layout.aggregate.source.function.id [read 16])
          localExpression.aggregateBranch .skip) (returned result)))
  for wrongRest in [
      localRest literal.constants.value.id normalLocalBranch,
      localRest localExpression.tag.id (localBranch [read 2, read 5, read 9] localKindAddress localSlotAddress localTail),
      localRest localExpression.tag.id (localBranch [read 2, read 5, read 14] localSlotAddress localSlotAddress localTail),
      localRest localExpression.tag.id (localBranch [read 2, read 5, read 14] localKindAddress localKindAddress localTail),
      localRest localExpression.tag.id (localBranch [read 2, read 5, read 14] localKindAddress localSlotAddress
        (localTailWith [read 3, read 4, read 2, read 16, read 17] (read 16))),
      localRest localExpression.tag.id (localBranch [read 2, read 5, read 14] localKindAddress localSlotAddress
        (localTailWith Lanius.X86.Source.Expression.Local.getArguments (read 17)))] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "compile"] "emit_expression"
        Lanius.X86.Source.Expression.Indexed.parameters i32
        (Lanius.X86.Source.Expression.Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
          literal.immediate.source.function.id literal.stringBranch wrongRest)).isNone do
      throw (IO.userError "local-expression source checker accepted changed tag, lookup key, kind/slot table, getter arguments or return kind")
  let allocationTail : Stmt := .sequence
    (Lanius.X86.Source.Allocate.watermark allocation.top.id allocation.slots.id)
    (returned (.binary .subtract (Lanius.X86.Source.Allocate.field allocation.top.id) (number 1)))
  let wrongIncrement : Stmt := .sequence
    (.ifThenElse (Lanius.X86.Source.Allocate.guard allocation.top.id)
      (Lanius.X86.Source.Allocate.reject allocation.failed.id) .skip)
    (.sequence (Lanius.X86.Source.Allocate.assign allocation.top.id .add (number 1)) allocationTail)
  let wrongGuard : Expr := .binary .logicalOr (.binary .lessEqual (read 1) (number 1))
    (.binary .greater (read 1) (.binary .subtract (number 1048576)
      (Lanius.X86.Source.Allocate.field allocation.top.id)))
  let wrongAllocationGuard : Stmt := .sequence
    (.ifThenElse wrongGuard (Lanius.X86.Source.Allocate.reject allocation.failed.id) .skip)
    (.sequence (Lanius.X86.Source.Allocate.assign allocation.top.id .add (read 1)) allocationTail)
  for wrong in [wrongIncrement, wrongAllocationGuard] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "frame"] "allocate"
        Lanius.X86.Source.Allocate.parameters i32 wrong).isNone do
      throw (IO.userError "allocator source checker accepted a changed slot increment or one-slot boundary")
  let recursiveTail := Lanius.X86.Source.Expression.Indexed.continuation
    recursiveIndex.expression.function.id recursiveIndex.index.internal.source.function.id
  for wrong in [
      Lanius.X86.Source.Expression.Indexed.preparation allocation.internal.source.function.id
        recursiveIndex.save.internal.source.function.id recursiveIndex.index.constants.r11.id recursiveTail,
      Lanius.X86.Source.Expression.Indexed.preparation allocation.internal.source.function.id
        recursiveIndex.index.internal.source.function.id recursiveIndex.index.constants.rax.id recursiveTail,
      Lanius.X86.Source.Expression.Indexed.preparation allocation.internal.source.function.id
        recursiveIndex.save.internal.source.function.id recursiveIndex.index.constants.rax.id
        (Lanius.X86.Source.Expression.Indexed.continuation recursiveIndex.index.internal.source.function.id
          recursiveIndex.expression.function.id)] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "compile"] "indexed"
        Lanius.X86.Source.Expression.Indexed.parameters (.scalar .bool) wrong).isNone do
      throw (IO.userError "indexed-expression source checker accepted a changed descriptor register, save callee, or recursive call")
  for (name, wrong) in [("displacement", bytesExpr), ("bytes", displacementExpr)] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "frame"] name
        [(0, i32)] i32 (returned wrong)).isNone do
      throw (IO.userError "frame source checker accepted a different computation")
  for wrong in [[72, 137, 229, 93, 195], [72, 137, 236, 195]] do
    unless (checkFixed? emitters.pack.program emitters.fits ["backend", "frame"] "return_value" wrong).isNone do
      throw (IO.userError "frame return checker accepted a wrong register or omitted pop")
  for (code, base) in [(slotLoad.base.id, slotLoad.base.id), (slotLoad.code.id, slotLoad.code.id)] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "frame"] "load"
        Lanius.X86.Source.Slot.parameters i32
        (Lanius.X86.Source.Slot.body .load32 memoryLoad.source.function.id offset.source.function.id code base)).isNone do
      throw (IO.userError "slot source checker accepted a changed workspace field or base register")
  let wrongTarget : Stmt := .letLocal 4 i32 (.call emitters.branch.source.function.id
    [read 0, read 1, read 2, read 3, .binary .add (read 2) (number 7)])
    (returned (.call emitters.trap.source.function.id [read 0, read 1, read 4]))
  for wrong in [wrongTarget, Lanius.X86.Source.Require.body emitters.trap.source.function.id emitters.branch.source.function.id] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "index"] "require"
        Lanius.X86.Source.Require.parameters i32 wrong).isNone do
      throw (IO.userError "bounds guard source checker accepted a changed jump target or swapped emitters")
  let calls := indexSource.helpers.calls
  for wrong in [Lanius.X86.Source.Index.body indexSource.constants { calls with slot := calls.load },
      Lanius.X86.Source.Index.body indexSource.constants { calls with compare := calls.require },
      Lanius.X86.Source.Index.scope indexSource.constants calls] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "index"] "address"
        Lanius.X86.Source.Index.parameters i32 wrong).isNone do
      throw (IO.userError "whole-index source checker accepted changed callees or omitted entry checks")
  let before : State := {
    cells := [⟨0, some (.signed .i32 123)⟩]
    nextCell := 1
    world := { standardOutput := [65], standardError := [66], arguments := ["keep"] } }
  let before := before.bindLocal 0 (.signed .i32 909)
  let lookupCases : List (List Int × Nat × Int × Int) := [
    ([7, 8, 7], 3, 7, 2), ([7, 8, 7], 2, 7, 0), ([7, 8, 7], 1, 7, 0),
    ([7, 8, 7], 3, 8, 1), ([7, 8, 7], 3, 9, -1), ([7, 8, 7], 0, 7, -1),
    ([], 0, -2147483648, -1), ([-1, -2147483648, -1], 3, -1, 2),
    ([-1, -2147483648, -1], 2, -1, 0), ([-1, -2147483648, -1], 3, -2147483648, 1)]
  for (keys, active, key, expected) in lookupCases do
    let workspace := (List.range 16).map (fun index => ((1000 + index : Nat) : Int)) ++ keys
    let state : State := {
      cells := [⟨0, some (.array (signedI32Values workspace))⟩, ⟨1, some (.signed .i32 777)⟩]
      nextCell := 2, world := before.world }
    let state := (state.bindLocal 0 (.signed .i32 909)).bindLocal 3 (.signed .i32 939)
    let args := Lanius.X86.Frame.Lookup.arguments (.slice i32 0 [] 0 workspace.length) active key
    let .done (.signed .i32 result) after := evalExpr 500 emitters.pack.program.core state
        (.call lookup.internal.source.function.id (args.map Expr.value))
      | throw (IO.userError "actual lexical lookup did not return")
    unless result == expected && state.cells.all (fun cell => after.cell? cell.id == cell.value) &&
        after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
        reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
      throw (IO.userError s!"lexical lookup violated nearest active binding or caller frame: keys={keys}, active={active}, key={key}")
  for active in ([0, -1, -2147483648] : List Int) do
    let args : List Value := [.unit, .signed .i32 active, .unit]
    let .done (.signed .i32 (-1)) after := evalExpr 100 emitters.pack.program.core before
        (.call lookup.internal.source.function.id (args.map Expr.value))
      | throw (IO.userError "nonpositive lookup accessed the invalid table or key")
    unless before.cells.all (fun cell => after.cell? cell.id == cell.value) && after.locals == before.locals &&
        reprStr after.heap == reprStr before.heap && reprStr after.world == reprStr before.world &&
        reprStr after.i32ArrayViews == reprStr before.i32ArrayViews do
      throw (IO.userError "nonpositive lookup changed caller state")
  let transport := ([-2147483648, -1, 0, 2147483647] : List Int)
  let takeCases : List (List Int × Int × Int) := [
    (transport, 4, 0), (transport, 4, 1), (transport, 4, 2), (transport, 4, 3),
    ([-2147483648], 1, 0), (transport, 2, 1),
    (transport, 4, -1), (transport, 4, -2147483648), (transport, 4, 4), (transport, 4, 5),
    (transport, 3, 3), (transport, 0, 0), (transport, -1, 0), (transport, 2147483647, 2147483647)]
  for (words, length, position) in takeCases do
    for failed in ([0, 1] : List Int) do
      let workspace : List Int := [position, 19, 23, -33, failed, 51, 61, -71]
      let state : State := {
        cells := [⟨0, some (.array (signedI32Values words))⟩,
          ⟨1, some (.array (signedI32Values workspace))⟩, ⟨2, some (.signed .i32 777)⟩]
        nextCell := 3, world := before.world }
      let state := (state.bindLocal 0 (.signed .i32 909)).bindLocal 3 (.signed .i32 939)
      let readable := 0 ≤ position && position < length
      -- A rejected transport read must not inspect even an invalid input
      -- argument; the source-linked rejection theorem covers the same path.
      let input : Value := if readable then .slice i32 0 [] 0 words.length else .unit
      let args : List Value := [input, .signed .i32 length, .slice i32 1 [] 0 workspace.length]
      let .done (.signed .i32 result) after := evalExpr 200 emitters.pack.program.core state
          (.call taking.internal.source.function.id (args.map Expr.value))
        | throw (IO.userError s!"transport reader failed to return at length={length}, position={position}")
      let expected := if readable then words[position.toNat]! else 0
      let expectedWork := if readable then workspace.set 0 (position + 1) else workspace.set 4 1
      unless result == expected && after.cell? 1 == some (.array (signedI32Values expectedWork)) &&
          state.cells.all (fun cell => cell.id == 1 || after.cell? cell.id == cell.value) &&
          after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
          reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
        throw (IO.userError s!"transport reader violated value, INPUT/FAILED update, or caller frame at length={length}, position={position}")
  let allocationCases : List (Nat × Nat × Int) := [
    (0, 0, 1), (7, 11, 1), (7, 8, 1), (7, 8, 2), (7, 100, 9),
    (0, 0, 1048576), (1048575, 1048576, 1), (1048575, 1048575, 1),
    (1048576, 1048576, 1), (1048575, 1048576, 2), (0, 0, 1048577),
    (0, 0, 2147483647), (0, 7, 0), (7, 11, 0), (0, 0, -1), (7, 11, -2147483648)]
  for (top, peak, count) in allocationCases do
    for failed in ([0, 1] : List Int) do
      let workspace : List Int := [-10, 13, peak, -33, failed, -55, top, -77, 88, -99, 101, -111, 121, -131, 141, -151, 161]
      let state : State := {
        cells := [⟨0, some (.array (signedI32Values workspace))⟩, ⟨1, some (.signed .i32 777)⟩,
          ⟨2, some (.array (signedI32Values [17, -19]))⟩]
        nextCell := 3
        heap := {
          blocks := [{ base := 8, size := 3, alignment := 4, bytes := [11, 22, 33] },
            { base := 16, size := 8, alignment := 4, bytes := [17, 0, 0, 0, 237, 255, 255, 255], owned := false }],
          nextAddress := 24, remaining := some 91 }
        i32ArrayViews := [{ address := 16, root := 2, projections := [], length := 2 }]
        world := { before.world with
          environment := [("frame", "keep")], standardInput := [21, 22],
          currentDirectory := "/frame", files := [{ path := [97], bytes := [7, 9] }], nextFileHandle := 11,
          secureU32Stream := [29], monotonicSeconds := 42 } }
      let state := (state.bindLocal 0 (.signed .i32 909)).bindLocal 9 (.signed .i32 919)
      let args := Lanius.X86.Frame.Allocate.inputValues 0 workspace.length count
      let .done (.signed .i32 result) after := evalExpr 200 emitters.pack.program.core state
          (.call allocation.internal.source.function.id (args.map Expr.value))
        | throw (IO.userError s!"actual allocator did not return at top={top}, peak={peak}, count={count}")
      let rejected := count < 1 || (1048576 - (top : Int)) < count
      let expectedResult : Int := if rejected then -1 else (top : Int) + count - 1
      let expected := if rejected then workspace.set 4 1
        else (workspace.set 6 ((top : Int) + count)).set 2 (max (peak : Int) ((top : Int) + count))
      -- Compare the entire owned array and every old caller cell. Repr equality
      -- covers all fields of host/heap records that do not expose a BEq instance.
      unless result == expectedResult && after.cell? 0 == some (.array (signedI32Values expected)) &&
          state.cells.all (fun cell => cell.id == 0 || after.cell? cell.id == cell.value) &&
          after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
          reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
        throw (IO.userError s!"allocator violated result, full workspace, or caller frame at top={top}, peak={peak}, count={count}, failed={failed}")
      if top == 1048576 then
        -- Invalid non-workspace parameters detect accidental output access or
        -- recursion before the exhausted allocator has returned false.
        let args := Lanius.X86.Lower.Expression.Indexed.Reject.inputValues .unit .unit 0 workspace.length
          .unit .unit .unit .unit .unit .unit
        let .done (.boolean false) after := evalExpr 300 emitters.pack.program.core state
            (.call recursiveIndex.internal.source.function.id (args.map Expr.value))
          | throw (IO.userError "exhausted indexed-expression allocation accessed another argument or did not return false")
        unless after.cell? 0 == some (.array (signedI32Values (workspace.set 4 1))) &&
            state.cells.all (fun cell => cell.id == 0 || after.cell? cell.id == cell.value) &&
            after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
            reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
          throw (IO.userError "indexed-expression allocation rejection changed more than FAILED or leaked caller bindings")
  let cases := [0, 1, 2, 3, 4, 5, 6, 511, 512, 513, 65535, 65536, 1048575, 1048576]
  for count in cases do
    for (id, expected) in [(offset.source.function.id, displacement count),
        (size.source.function.id, (bytes count : Int))] do
      match evalExpr 100 emitters.pack.program.core before (.call id [.value (.signed .i32 count)]) with
      | .done (.signed .i32 value) after =>
        unless value == expected && after.locals == before.locals &&
            after.cell? 0 == some (.signed .i32 123) && after.world.standardOutput == [65] &&
            after.world.standardError == [66] && after.world.arguments == ["keep"] &&
            after.world.calls.isEmpty && after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError s!"frame helper result or caller frame differs at {count}")
      | _ => throw (IO.userError s!"frame helper did not return at {count}")
  let output := (List.range 32).map fun i => ((1000 + i : Nat) : Int)
  let initial : State := {
    cells := [⟨0, some (.array (signedI32Values output))⟩, ⟨1, some (.signed .i32 777)⟩]
    nextCell := 2
    world := before.world }
  let initial := initial.bindLocal 0 (.signed .i32 909)
  let slotCases : List (Lanius.X86.Source.Slot.Kind × Lanius.FunctionId) := [
    (.load32, slotLoad.internal.source.function.id), (.load64, wordLoad.internal.source.function.id),
    (.save64, wordStore.internal.source.function.id)]
  for slot in ([0, 511, 1048576] : List Nat) do
    for cursor in ([0, 3] : List Nat) do
      for capacity in [cursor + 6, output.length] do
        let workspace : List Int := [-19, cursor, 97, -55, 0, -77, 123]
        let state := initial.bindLocal 9 (.signed .i32 111)
        let work := state.nextCell
        let state := { state with
          cells := state.cells ++ [⟨work, some (.array (signedI32Values workspace))⟩]
          nextCell := work + 1 }
        let args := Lanius.X86.Lower.Value.Get.inputValues .w32 (.slice i32 0 [] 0 output.length) capacity
          (.slice i32 work [] 0 workspace.length) slot
        let .done (.signed .i32 result) after := evalExpr 700 emitters.pack.program.core state
            (.call scalarGet.internal.source.function.id (args.map Expr.value))
          | throw (IO.userError "actual scalar getter rejected valid input")
        let code := Lanius.X86.Lower.Value.Get.bytes .w32 slot
        let expected := output.take cursor ++ code.map (fun byte => (byte.toNat : Int)) ++ output.drop (cursor + 6)
        unless result == (cursor + 6 : Nat) && after.cell? 0 == some (.array (signedI32Values expected)) &&
            after.cell? work == some (.array (signedI32Values (workspace.set 1 result))) &&
            state.cells.all (fun cell => cell.id == 0 || cell.id == work || after.cell? cell.id == cell.value) &&
            after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
            reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
          throw (IO.userError s!"scalar getter violated MOV bytes or caller/output/workspace frame at slot={slot}, cursor={cursor}")
  for (kind, id) in slotCases do
    for slot in ([0, 511, 1048576] : List Nat) do
      for register in ([0, 15] : List (Fin 16)) do
        for cursor in ([0, 3] : List Nat) do
          let bytes := Lanius.X86.Frame.Slot.bytes kind slot register
          for capacity in [cursor + bytes.length, output.length] do
            let workspace : List Int := [-19, cursor, 97, -55]
            let state := initial.bindLocal 9 (.signed .i32 111)
            let state := { state with
              cells := state.cells ++ [⟨state.nextCell, some (.array (signedI32Values workspace))⟩]
              nextCell := state.nextCell + 1 }
            let work := state.nextCell - 1
            let args := Lanius.X86.Frame.Slot.inputValues (.slice i32 0 [] 0 output.length) capacity
              (.slice i32 work [] 0 workspace.length) slot register
            let .done (.signed .i32 result) after := evalExpr 500 emitters.pack.program.core state (.call id (args.map Expr.value))
              | throw (IO.userError "actual slot emitter rejected valid input")
            let expected := output.take cursor ++ bytes.map (fun byte => (byte.toNat : Int)) ++ output.drop (cursor + bytes.length)
            unless result == (cursor + bytes.length : Nat) &&
                after.cell? 0 == some (.array (signedI32Values expected)) &&
                after.cell? work == some (.array (signedI32Values (workspace.set 1 result))) &&
                state.cells.all (fun cell => cell.id == 0 || cell.id == work || after.cell? cell.id == cell.value) &&
                after.locals == state.locals && after.world.standardOutput == state.world.standardOutput &&
                after.world.standardError == state.world.standardError && after.world.arguments == state.world.arguments &&
                after.world.calls.isEmpty && after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
              throw (IO.userError "slot emission changed bytes, workspace fields, or the caller frame outside its contract")
  let memoryFrame := fun (after : State) =>
    initial.cells.all (fun cell => cell.id == 0 || after.cell? cell.id == cell.value) && after.locals == initial.locals &&
    after.world.standardOutput == initial.world.standardOutput && after.world.standardError == initial.world.standardError &&
    after.world.arguments == initial.world.arguments && after.world.calls.isEmpty &&
    after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty
  let checkMemory := fun (id : Lanius.FunctionId) (arguments : List Value) (cursor : Nat) (bytes : List UInt8) => do
    let .done (.signed .i32 result) after := evalExpr 300 emitters.pack.program.core initial
        (.call id (arguments.map Expr.value))
      | throw (IO.userError "memory emitter rejected valid operands/capacity")
    let expected := output.take cursor ++ bytes.map (fun byte => (byte.toNat : Int)) ++ output.drop (cursor + bytes.length)
    unless result == (cursor + bytes.length : Nat) && after.cell? 0 == some (.array (signedI32Values expected)) && memoryFrame after do
      throw (IO.userError "source memory emitter differs from proved bytes or caller/output frame")
  let rejectMemory := fun (id : Lanius.FunctionId) (arguments : List Value) => do
    let .done (.signed .i32 (-1)) after := evalExpr 300 emitters.pack.program.core initial
        (.call id (arguments.map Expr.value))
      | throw (IO.userError "memory reservation failure accessed invalid output")
    unless after.cell? 0 == initial.cell? 0 && memoryFrame after do
      throw (IO.userError "memory reservation failure changed caller state")
  let literalValues : List Int := [-2147483648, -1, 0, 1, 305419896, 2147483647]
  for low in literalValues do
    for high in ([-2147483648, 0, 2147483647] : List Int) do
      for cursor in ([0, 3] : List Nat) do
        for capacity in [cursor + 5, output.length] do
          checkMemory immediate.source.function.id
            (Lanius.X86.Encode.Immediate.inputs (.slice i32 0 [] 0 output.length) capacity cursor low high)
            cursor (Lanius.X86.Encode.Immediate.bytes low)
  for (capacity, cursor) in ([(4, 0), (7, 3), (-1, 0), (32, -1), (32, 33),
      (2147483647, 2147483643)] : List (Int × Int)) do
    rejectMemory immediate.source.function.id (Lanius.X86.Encode.Immediate.inputs .unit capacity cursor (-2147483648) 2147483647)
  for (low, high) in ([(0, 0), (-1, -1), (-2147483648, 0), (0, -2147483648),
      (305419896, -1867788817), (-1, 2147483647)] : List (Int × Int)) do
    for cursor in ([0, 3] : List Nat) do
      for capacity in [cursor + 10, output.length] do
        checkMemory immediate.source.function.id
          (Lanius.X86.Encode.Immediate.Wide.inputs (.slice i32 0 [] 0 output.length) capacity cursor low high)
          cursor (Lanius.X86.Encode.Immediate.Wide.bytes low high)
  for remaining in List.range 10 do
    rejectMemory immediate.source.function.id
      (Lanius.X86.Encode.Immediate.Wide.inputs .unit (3 + remaining : Nat) 3 (-1) (-2147483648))
  for (capacity, cursor) in ([(-1, 0), (32, -1), (32, 33), (2147483647, 2147483638)] : List (Int × Int)) do
    rejectMemory immediate.source.function.id (Lanius.X86.Encode.Immediate.Wide.inputs .unit capacity cursor 0 (-1))
  let memoryCases : List Lanius.X86.Encode.Memory.Config := [
    ⟨.w32, .escaped 182, 0, 1, -2147483648, false⟩,
    ⟨.w32, .escaped 182, 15, 12, 2147483647, false⟩,
    ⟨.w32, .primary 136, 4, 13, -1, true⟩,
    ⟨.w64, .primary 141, 15, 4, 0, false⟩]
  for condition in List.finRange 16 do
    for cursor in ([0, 3] : List Nat) do
      for capacity in [cursor + 8, output.length] do
        let expected := ([15, 128 + condition.val, 2, 0, 0, 0, 15, 11] : List Nat).map UInt8.ofNat
        checkMemory require.source.function.id
          (Lanius.X86.Control.Require.inputValues (.slice i32 0 [] 0 output.length) capacity cursor condition) cursor expected
  for condition in ([-1, 16] : List Int) do
    rejectMemory require.source.function.id [.unit, .signed .i32 32, .signed .i32 0, .signed .i32 condition]
  for cursor in ([-1, 2147483640] : List Int) do
    rejectMemory require.source.function.id [.unit, .signed .i32 2147483647, .signed .i32 cursor, .signed .i32 2]
  for config in memoryCases do
    for cursor in ([0, 3] : List Nat) do
      for capacity in [cursor + config.size, 32] do
        checkMemory memory.source.function.id
          (config.arguments (.slice i32 0 [] 0 output.length) capacity cursor) cursor config.bytes
    for (capacity, cursor) in ([(config.size - 1, 0), (32, -1), (2147483647, 2147483646)] : List (Int × Int)) do
      rejectMemory memory.source.function.id (config.arguments .unit capacity cursor)
  let operands : List (Fin 16 × Fin 16 × Int) := [(0, 0, 0), (15, 4, -8), (8, 12, -2147483648), (1, 13, 2147483647)]
  for width in [Lanius.X86.Register.Width.w32, .w64] do
    for load in [false, true] do
      let id := if load then memoryLoad.source.function.id else memoryStore.source.function.id
      for (reg, base, displacement) in operands do
        let bytes := Lanius.X86.Machine.memoryBytes width load reg base displacement
        for cursor in ([0, 3] : List Nat) do
          checkMemory id (Lanius.X86.Encode.Memory.moveValues (.slice i32 0 [] 0 output.length)
            (cursor + bytes.length) cursor width reg base displacement) cursor bytes
        for (capacity, cursor) in ([(bytes.length - 1, 0), (32, -1), (2147483647, 2147483646)] : List (Int × Int)) do
          rejectMemory id (Lanius.X86.Encode.Memory.moveValues .unit capacity cursor width reg base displacement)
  let indexedCases : List Lanius.X86.Encode.Indexed.Config := [
    ⟨0, 11, 0, 2, 0, by decide⟩,
    ⟨15, 12, 12, 3, -2147483648, by decide⟩,
    ⟨8, 13, 15, 0, 2147483647, by decide⟩,
    ⟨4, 4, 3, 1, -1, by decide⟩]
  for config in indexedCases do
    for cursor in ([0, 3, 11] : List Nat) do
      for capacity in [cursor + 8, 32] do
        let args := config.arguments (.slice i32 0 [] 0 output.length) capacity cursor
        let .done (.signed .i32 result) after := evalExpr 200 emitters.pack.program.core initial
            (.call indexed.internal.source.function.id (args.map Expr.value))
          | throw (IO.userError "source indexed emitter rejected valid operands and capacity")
        let expected := output.take cursor ++ config.bytes.map (fun byte => (byte.toNat : Int)) ++ output.drop (cursor + 8)
        unless result == (cursor + 8 : Nat) && after.cell? 0 == some (.array (signedI32Values expected)) &&
            after.cell? 1 == initial.cell? 1 && after.locals == initial.locals &&
            after.world.standardOutput == initial.world.standardOutput && after.world.standardError == initial.world.standardError &&
            after.world.arguments == initial.world.arguments && after.world.calls.isEmpty &&
            after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError "source indexed emitter differs from its general byte or caller-frame contract")
    for (capacity, cursor) in ([(7, 0), (32, -1), (2147483647, 2147483646)] : List (Int × Int)) do
      let args := config.arguments .unit capacity cursor
      let .done (.signed .i32 (-1)) after := evalExpr 200 emitters.pack.program.core initial
          (.call indexed.internal.source.function.id (args.map Expr.value))
        | throw (IO.userError "indexed capacity rejection accessed invalid output")
      unless after.cell? 0 == initial.cell? 0 && after.cell? 1 == initial.cell? 1 && after.locals == initial.locals &&
          after.world.standardOutput == initial.world.standardOutput && after.world.standardError == initial.world.standardError &&
          after.world.arguments == initial.world.arguments && after.world.calls.isEmpty &&
          after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
        throw (IO.userError "indexed capacity rejection changed caller state")
  for cursor in ([0, 3, 11, 27] : List Nat) do
    for capacity in [cursor + 5, 32] do
      let args := Lanius.X86.Buffer.fixedValues (.slice i32 0 [] 0 output.length) capacity cursor
      match evalExpr 100 emitters.pack.program.core initial (.call returning.source.function.id (args.map Expr.value)) with
      | .done (.signed .i32 result) after =>
        let expected := output.take cursor ++ [72, 137, 236, 93, 195] ++ output.drop (cursor + 5)
        unless result == (cursor + 5 : Nat) && after.cell? 0 == some (.array (signedI32Values expected)) &&
            after.cell? 1 == initial.cell? 1 && after.locals == initial.locals &&
            after.world.standardOutput == [65] && after.world.standardError == [66] &&
            after.world.arguments == ["keep"] && after.world.calls.isEmpty &&
            after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError "return emitter changed bytes outside its window or caller state")
      | _ => throw (IO.userError "source return emitter failed despite sufficient capacity")
  -- Rejection must not even inspect output. Invalid slice arguments make an
  -- accidental load/store fail instead of being masked by valid test storage.
  for (capacity, cursor) in ([(0, 0), (4, 0), (31, 27), (32, -1), (-1, 0),
      (2147483647, 2147483646), (32, 33)] : List (Int × Int)) do
    let args := Lanius.X86.Buffer.fixedValues .unit capacity cursor
    match evalExpr 100 emitters.pack.program.core initial (.call returning.source.function.id (args.map Expr.value)) with
    | .done (.signed .i32 (-1)) after =>
      unless after.cell? 0 == initial.cell? 0 && after.cell? 1 == initial.cell? 1 && after.locals == initial.locals &&
          after.world.standardOutput == [65] && after.world.standardError == [66] &&
          after.world.arguments == ["keep"] && after.world.calls.isEmpty &&
          after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
        throw (IO.userError "rejected return emitter changed caller state")
    | _ => throw (IO.userError "return capacity rejection accessed output or failed to return -1")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  for count in [0, 1, 2, 7, 31] do
    let code := Lanius.X86.Machine.Copy.bytes 0 count
    let output : List Int := List.replicate (code.length + 11) 171
    let work : List Int := [-333, 3, -444, -555]
    let initial : State := {
      cells := [⟨0, some (.array (signedI32Values output))⟩,
        ⟨1, some (.array (signedI32Values work))⟩, ⟨2, some (.signed .i32 777)⟩]
      nextCell := 3
      world := before.world }
    let initial := initial.bindLocal 0 (.signed .i32 909)
    let args : List Value := [.slice i32 0 [] 0 output.length, .signed .i32 (code.length + 3),
      .slice i32 1 [] 0 work.length, .signed .i32 count]
    let .done (.signed .i32 result) after := evalExpr 1000 emitters.pack.program.core initial
        (.call copying.function.id (args.map Expr.value))
      | throw (IO.userError s!"actual value-copy emitter failed at {count} words")
    let expected := output.take 3 ++ code.map (fun byte => (byte.toNat : Int)) ++ output.drop (3 + code.length)
    unless result == (3 + code.length : Nat) && after.cell? 0 == some (.array (signedI32Values expected)) &&
        after.cell? 1 == some (.array (signedI32Values (work.set 1 (3 + code.length : Nat)))) &&
        after.cell? 2 == initial.cell? 2 && after.locals == initial.locals &&
        after.world.standardOutput == initial.world.standardOutput && after.world.standardError == initial.world.standardError &&
        after.world.arguments == initial.world.arguments && after.world.calls.isEmpty &&
        after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
      throw (IO.userError s!"copy emitter differs from the proved MOV64 sequence or changes caller storage at {count} words")
  for (slot, start) in ([0, 1, 511, 1048575] : List Nat).flatMap (fun slot => [0, 1, 3].map (slot, ·)) do
    for signed in [false, true] do
      let code := Lanius.X86.Machine.Index.bytes signed slot
      let output : List Int := (List.range (code.length + start + 8)).map (fun index => (1000 + index : Nat))
      let work : List Int := [-333, start, -444, -555]
      let initial : State := {
        cells := [⟨0, some (.array (signedI32Values output))⟩,
          ⟨1, some (.array (signedI32Values work))⟩, ⟨2, some (.signed .i32 777)⟩]
        nextCell := 3, world := before.world }
      let initial := initial.bindLocal 0 (.signed .i32 909)
      for enough in [true, false] do
        let capacity := code.length + start - (if enough then 0 else 1)
        let args : List Value := [.slice i32 0 [] 0 output.length, .signed .i32 capacity,
          .slice i32 1 [] 0 work.length, .signed .i32 slot, .signed .i32 (if signed then 1 else 3)]
        let .done (.signed .i32 result) after := evalExpr 1500 emitters.pack.program.core initial
            (.call indexing.function.id (args.map Expr.value))
          | throw (IO.userError "actual checked-address emitter failed to return")
        let expectedResult : Int := if enough then code.length + start else -1
        let some (.array actual) := after.cell? 0 | throw (IO.userError "checked-address output is not an array")
        let expected := output.take start ++ code.map (fun byte => (byte.toNat : Int)) ++ output.drop (start + code.length)
        unless result == expectedResult && after.cell? 1 == some (.array (signedI32Values (work.set 1 expectedResult))) &&
            (if enough then actual == signedI32Values expected
             else actual.take start == (signedI32Values output).take start &&
               actual.drop capacity == (signedI32Values output).drop capacity) &&
            initial.cells.all (fun cell => cell.id == 0 || cell.id == 1 || after.cell? cell.id == cell.value) && after.locals == initial.locals &&
            after.world.standardOutput == initial.world.standardOutput && after.world.standardError == initial.world.standardError &&
            after.world.arguments == initial.world.arguments && after.world.calls.isEmpty &&
            after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError s!"checked-address emission differs from the proved sequence or crosses its output/caller window at slot {slot}, start={start}, signed={signed}, enough={enough}")
  for kind in ([-1, 0, 2, 4] : List Int) do
    let args := Lanius.X86.Lower.Index.Reject.inputValues .unit .unit .unit .unit kind
    let .done (.signed .i32 (-1)) after := evalExpr 200 emitters.pack.program.core before
        (.call indexing.function.id (args.map Expr.value))
      | throw (IO.userError "invalid index kind accessed output/workspace")
    unless after.locals == before.locals && before.cells.all (fun cell => after.cell? cell.id == cell.value) &&
        reprStr after.heap == reprStr before.heap && reprStr after.world == reprStr before.world &&
        reprStr after.i32ArrayViews == reprStr before.i32ArrayViews do
      throw (IO.userError "invalid index kind changed caller storage")
  -- Exercise the real recursive caller, not a replacement implementation of
  -- its operand compiler. These cases do not discharge the general recursive
  -- simulation: they check the joined source contract at concrete leaves.
  let recursiveCases : List (List Int × List UInt8 × Bool × Bool) := [
    ([0, 1, -1], [184, 255, 255, 255, 255], true, true),
    ([0, 3, 7, 1], [72, 184, 7, 0, 0, 0, 1, 0, 0, 0], true, false),
    ([0, 2, 1], [184, 1, 0, 0, 0], false, false),
    ([-1], [], false, false)]
  for (words, childBytes, accepted, signed) in recursiveCases do
    for (top, peak, start) in ([(0, 0, 0), (7, 11, 3), (1048575, 1048575, 1)] : List (Nat × Nat × Nat)) do
      let code := Lanius.X86.Lower.Expression.Indexed.saveBytes top ++ childBytes ++
        (if accepted then Lanius.X86.Machine.Index.bytes signed top else [])
      let output : List Int := (List.range (start + code.length + 8)).map (fun index => (1000 + index : Nat))
      let workspace : List Int := [0, start, peak, -33, 0, -55, top, -77, 88, -99, 101, -111, 121, -131, 141, -151, 161]
      for capacity in [start + code.length, output.length] do
        let state : State := {
          cells := [⟨0, some (.array (signedI32Values words))⟩,
            ⟨1, some (.array (signedI32Values workspace))⟩,
            ⟨2, some (.array (signedI32Values output))⟩, ⟨3, some (.signed .i32 777)⟩]
          nextCell := 4, world := before.world }
        let state := (state.bindLocal 0 (.signed .i32 909)).bindLocal 9 (.signed .i32 919)
        let args : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 words.length,
          .slice i32 1 [] 0 workspace.length, .slice i32 2 [] 0 output.length, .signed .i32 capacity,
          .signed .i32 0, .signed .i32 0, .unit, .signed .i32 0]
        let .done (.boolean result) after := evalExpr 2500 emitters.pack.program.core state
            (.call recursiveIndex.internal.source.function.id (args.map Expr.value))
          | throw (IO.userError "actual indexed-expression caller did not return for a concrete recursive operand")
        let expected := output.take start ++ code.map (fun byte => (byte.toNat : Int)) ++ output.drop (start + code.length)
        let expectedWork := ((workspace.set 0 words.length).set 1 (start + code.length : Nat)).set 2 (max peak (top + 1) : Nat)
        let expectedWork := expectedWork.set 6 (top + 1 : Nat)
        unless result == accepted && after.cell? 2 == some (.array (signedI32Values expected)) &&
            after.cell? 1 == some (.array (signedI32Values expectedWork)) &&
            state.cells.all (fun cell => cell.id == 1 || cell.id == 2 || after.cell? cell.id == cell.value) &&
            after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
            reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
          throw (IO.userError s!"actual indexed-expression capture/recursion/address sequence violated bytes, workspace or caller frame at top={top}, words={words}")
  -- The actual wrapper must use the nearest active name and its distinct
  -- kind/slot columns. Context is invalid because initialized scalar locals
  -- must never enter the negative-kind or aggregate helper paths.
  for (active, key, slot) in ([(3, 7, 1048576), (2, 7, 0), (3, 8, 511), (1, 7, 0)] : List (Nat × Int × Nat)) do
    for (stride, top, position, start) in ([(3, 0, 0, 0), (5, 17, 1, 3),
        (4, 1048576, 2, 1)] : List (Nat × Nat × Nat × Nat)) do
      let words : List Int := List.replicate position (-99) ++ [1, key, 777]
      let code := Lanius.X86.Lower.Value.Get.bytes .w32 slot
      let output : List Int := (List.range (start + 13)).map (fun index => (1000 + index : Nat))
      let header : List Int := [position, start, top, -33, 0, -55, top, -77, 88, -99, 101, -111, stride, -131, 141, -151]
      let workspace := header ++ [7, 8, 7] ++ List.replicate (stride - 3) (-313) ++
        [1, 1, 1] ++ List.replicate (stride - 3) (-414) ++ [0, 511, 1048576] ++ List.replicate (stride - 3) (-515)
      for capacity in [start + 6, output.length] do
        let state : State := {
          cells := [⟨0, some (.array (signedI32Values words))⟩, ⟨1, some (.array (signedI32Values workspace))⟩,
            ⟨2, some (.array (signedI32Values output))⟩, ⟨3, some (.signed .i32 777)⟩]
          nextCell := 4, world := before.world }
        let state := ((state.bindLocal 0 (.signed .i32 909)).bindLocal 14 (.signed .i32 949)).bindLocal 17 (.signed .i32 979)
        let args : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 (position + 2 : Nat),
          .slice i32 1 [] 0 workspace.length, .slice i32 2 [] 0 output.length, .signed .i32 capacity,
          .signed .i32 active, .signed .i32 0, .unit, .unit]
        let .done (.signed .i32 1) after := evalExpr 1600 emitters.pack.program.core state
            (.call literal.wrapper.source.function.id (args.map Expr.value))
          | throw (IO.userError s!"actual local wrapper failed at active={active}, key={key}, stride={stride}")
        let expected := output.take start ++ code.map (fun byte => (byte.toNat : Int)) ++ output.drop (start + 6)
        let expectedWork := (workspace.set 0 (position + 2 : Nat)).set 1 (start + 6 : Nat)
        unless after.cell? 2 == some (.array (signedI32Values expected)) &&
            after.cell? 1 == some (.array (signedI32Values expectedWork)) &&
            state.cells.all (fun cell => cell.id == 1 || cell.id == 2 || after.cell? cell.id == cell.value) &&
            after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
            reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
          throw (IO.userError s!"local wrapper violated shadowing, slot bytes or INPUT/CODE/TOP/caller frame at active={active}, key={key}, slot={slot}")
  -- No kind/slot columns exist in these workspaces. A missing lookup must
  -- return before touching either column, even with an enormous stride.
  for (active, key) in ([(3, 99), (0, 7), (1, 8), (2, -2147483648)] : List (Nat × Int)) do
    for (position, start) in ([(0, 0), (2, 3)] : List (Nat × Nat)) do
      let words : List Int := List.replicate position (-99) ++ [1, key, 777]
      let output := ([1001, 1002, 1003, 1004, 1005, 1006] : List Int)
      let workspace : List Int := [position, start, 19, -33, 0, -55, 17, -77, 88, -99, 101, -111,
        2147483647, -131, 141, -151, 7, 8, 7]
      let state : State := {
        cells := [⟨0, some (.array (signedI32Values words))⟩, ⟨1, some (.array (signedI32Values workspace))⟩,
          ⟨2, some (.array (signedI32Values output))⟩, ⟨3, some (.signed .i32 777)⟩]
        nextCell := 4, world := before.world }
      let state := ((state.bindLocal 0 (.signed .i32 909)).bindLocal 14 (.signed .i32 949)).bindLocal 17 (.signed .i32 979)
      let args : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 (position + 2 : Nat),
        .slice i32 1 [] 0 workspace.length, .slice i32 2 [] 0 output.length, .signed .i32 0,
        .signed .i32 active, .signed .i32 0, .unit, .unit]
      let .done (.signed .i32 (-1)) after := evalExpr 1000 emitters.pack.program.core state
          (.call literal.wrapper.source.function.id (args.map Expr.value))
        | throw (IO.userError "missing-local wrapper accessed absent kind/slot columns or returned the wrong kind")
      unless after.cell? 1 == some (.array (signedI32Values (workspace.set 0 (position + 2 : Nat)))) &&
          state.cells.all (fun cell => cell.id == 1 || after.cell? cell.id == cell.value) &&
          after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
          reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
        throw (IO.userError "missing-local wrapper changed output, CODE, TOP, binding tables or caller state")
  for (kind, low) in literalValues.map (1, ·) ++ [(2, 0), (2, 1)] do
    for (top, peak, position, start) in ([(0, 0, 0, 0), (7, 11, 1, 3),
        (1048576, 1048576, 1, 0)] : List (Nat × Nat × Nat × Nat)) do
      let words : List Int := List.replicate position (-99) ++ [0, kind, low, 777]
      let code := Lanius.X86.Encode.Immediate.bytes low
      let output : List Int := (List.range (start + 13)).map (fun index => (1000 + index : Nat))
      let workspace : List Int := [position, start, peak, -33, 0, -55, top, -77]
      for capacity in [start + 5, output.length] ++ (List.range 5).map (start + ·) do
        let state : State := {
          cells := [⟨0, some (.array (signedI32Values words))⟩,
            ⟨1, some (.array (signedI32Values workspace))⟩,
            ⟨2, some (.array (signedI32Values output))⟩, ⟨3, some (.signed .i32 777)⟩]
          nextCell := 4, world := before.world }
        let state := ((state.bindLocal 0 (.signed .i32 909)).bindLocal 9 (.signed .i32 919)).bindLocal 10 (.signed .i32 929)
        let args : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 (position + 3 : Nat),
          .slice i32 1 [] 0 workspace.length, .slice i32 2 [] 0 output.length, .signed .i32 capacity,
          .signed .i32 0, .signed .i32 0, .unit, .signed .i32 0]
        let .done (.signed .i32 resultKind) after := evalExpr 1000 emitters.pack.program.core state
            (.call literal.wrapper.source.function.id (args.map Expr.value))
          | throw (IO.userError s!"actual literal compiler failed at kind={kind}, low={low}, position={position}, start={start}")
        let enough := start + 5 ≤ capacity
        let expected := if enough then output.take start ++ code.map (fun byte => (byte.toNat : Int)) ++ output.drop (start + 5)
          else output
        let finalCursor : Int := if enough then (start + 5 : Nat) else -1
        let expectedWork := (workspace.set 0 (position + 3 : Nat)).set 1 finalCursor
        unless resultKind == kind && after.cell? 2 == some (.array (signedI32Values expected)) &&
            after.cell? 1 == some (.array (signedI32Values expectedWork)) &&
            state.cells.all (fun cell => cell.id == 1 || cell.id == 2 || after.cell? cell.id == cell.value) &&
            after.locals == state.locals && reprStr after.heap == reprStr state.heap &&
            reprStr after.world == reprStr state.world && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
          throw (IO.userError "literal compiler changed bytes outside its MOV window, consumed an extra transport word, or failed to restore TOP/caller bindings")
  for (depth, failed, cursor) in ([(512, 0, 0), (0, 1, 0), (0, 0, -1)] : List (Int × Int × Int)) do
    let workspace : List Int := [17, cursor, 29, -33, failed, -55, 23, -77]
    let state : State := {
      cells := [⟨0, some (.array (signedI32Values workspace))⟩, ⟨1, some (.signed .i32 777)⟩]
      nextCell := 2, world := before.world }
    let state := (state.bindLocal 0 (.signed .i32 909)).bindLocal 9 (.signed .i32 919)
    let args : List Value := [.unit, .unit, .slice i32 0 [] 0 workspace.length, .unit, .unit,
      .signed .i32 0, .signed .i32 depth, .unit, .unit]
    let .done (.signed .i32 (-1)) after := evalExpr 500 emitters.pack.program.core state
        (.call literal.wrapper.source.function.id (args.map Expr.value))
      | throw (IO.userError "literal entry guard accessed an invalid input/output or failed to return -1")
    unless state.cells.all (fun cell => after.cell? cell.id == cell.value) && after.locals == state.locals &&
        reprStr after.heap == reprStr state.heap && reprStr after.world == reprStr state.world &&
        reprStr after.i32ArrayViews == reprStr state.i32ArrayViews do
      throw (IO.userError "literal entry rejection changed workspace or caller storage")
  for target in [offset.source.function, size.source.function] do
    let some words := Lanius.X86.Transport.program? emitters.pack.program.core target.id
      | throw (IO.userError "frame helper is not supported scalar Core")
    let path := directory / "frame.core"
    IO.FS.writeBinFile path ⟨(words.flatMap i32Bytes).toArray⟩
    let child ← IO.Process.spawn { cmd := "timeout", args := #["--kill-after=1s", "2s", backend, "--raw", path.toString], stdout := .piped }
    let mut native := ByteArray.empty
    repeat
      let next ← child.stdout.read 4096
      if next.isEmpty then break
      native := native ++ next
    unless (← child.wait) == 0 && !native.isEmpty do throw (IO.userError "native backend rejected its own frame helper")
    let work := List.replicate (16 + words.length * 8) (-333 : Int)
    let output := List.replicate (native.size + 11) (171 : Int)
    let state : State := {
      cells := [⟨0, some (.array (signedI32Values words))⟩,
        ⟨1, some (.array (signedI32Values work))⟩,
        ⟨2, some (.array (signedI32Values output))⟩,
        ⟨3, some (.signed .i32 777)⟩,
        ⟨4, some (.array (signedI32Values (List.replicate words.length (-222))))⟩]
      nextCell := 5 }
    let state := state.bindLocal 0 (.signed .i32 909)
    let args : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 words.length,
      .slice i32 4 [] 0 words.length, .signed .i32 words.length,
      .slice i32 1 [] 0 work.length, .signed .i32 work.length,
      .slice i32 2 [] 0 output.length, .signed .i32 output.length, .signed .i32 3]
    match evalExpr 12000 emitters.pack.program.core state (.call compiler.function.id (args.map Expr.value)) with
    | .done (.signed .i32 result) after =>
      let expected := output.take 3 ++ native.toList.map (fun byte => (byte.toNat : Int)) ++ output.drop (3 + native.size)
      unless result == (3 + native.size : Nat) &&
          after.cell? 2 == some (.array (signedI32Values expected)) &&
          after.cell? 0 == state.cell? 0 && after.cell? 3 == state.cell? 3 && after.locals == state.locals &&
          after.world.calls.isEmpty && after.heap.blocks.isEmpty && after.i32ArrayViews.isEmpty do
        throw (IO.userError "actual Core compiler disagrees with native compiler bytes or changed framed storage")
    | _ => throw (IO.userError "actual Core scalar compiler did not return")
  IO.println "Authenticated-source Core checks: 13 lexical lookup cases; 12 successful and 16 rejected transport reads; 72 immediate32 emissions and 6 capacity rejections; 24 immediate64 emissions and 14 capacity rejections; 48 successful integer/Boolean literal wrappers, 120 short-capacity wrappers (0–4 bytes remaining), and 3 entry rejections; 24 successful local wrappers and 8 lookup misses with absent kind/slot columns; 12 scalar getters; 32 allocator calls; 2 exhausted-allocation indexed calls and 24 complete indexed callers; 28 frame arithmetic calls; 35 source mutations rejected; 72 slot emissions; 64 bounds guard emissions and 4 rejections; 48 memory emissions and 60 rejections; 24 indexed-address emissions and 12 rejections; 8 return emissions and 7 rejections; 5 aggregate emissions; 24 whole-index emissions and 28 rejections. These check exact bytes and caller/output/workspace frames. Separate native evidence: the actual Core compiler and existing native backend emit identical bytes for both frame helpers. Helper boundary examples above are Core execution, not physical native executions."
  pure 0
