import verified_compiler.tests.direct_ir_event_store
import verified_compiler.tests.direct_ir_result_type
import Lanius.Semantics.NativeStoreProof

namespace IREventCodecProof

open Lanius Lanius.Core Lanius.Semantics IREventStoreProof IRTypeRefProof

def callHeader (functionId arguments : Int32) : Value :=
  source_value Extracted.«ir::body_events».Types.«CallHeader».mk
    [.signed .i32 functionId.toInt, .signed .i32 arguments.toInt]
def matchingHeader (kind : Reference) (scrutinee arms : Int32) : Value :=
  source_value Extracted.«ir::body_events».Types.«MatchHeader».mk
    [referenceValue kind, .signed .i32 scrutinee.toInt, .signed .i32 arms.toInt]
def callEvent (functionId arguments : Int32) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionCall» [callHeader functionId arguments]
def matchingEvent (kind : Reference) (scrutinee arms : Int32) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionMatch» [matchingHeader kind scrutinee arms]

theorem callCodec (functionId arguments : Int32) :
    NativeStoreSpec 64 extractedProgram eventType (callEvent functionId arguments) 40 := by native_store
theorem matchingCodec (kind : Reference) (scrutinee arms : Int32) :
    NativeStoreSpec 64 extractedProgram eventType (matchingEvent kind scrutinee arms) 40 := by native_store

abbrev SliceKind := Extracted.«ir::body_events».Types.«SliceElementKind»
def sliceKindValue : SliceKind → Value
  | .I32Slice => source_value Extracted.«ir::body_events».Types.«SliceElementKind».«I32Slice» []
  | .StructureSlice => source_value Extracted.«ir::body_events».Types.«SliceElementKind».«StructureSlice» []
  | .EnumerationSlice => source_value Extracted.«ir::body_events».Types.«SliceElementKind».«EnumerationSlice» []
private def sliceKindType : Ty := match sliceKindValue .I32Slice with
  | .enumeration id _ _ => .enumeration id
  | _ => .unit

@[native_store_rule] theorem sliceKindCodec (kind : SliceKind) :
    NativeStoreSpec (fuel + 1) extractedProgram sliceKindType (sliceKindValue kind) 8 := by
  cases kind <;> dsimp only [sliceKindValue] <;> native_store

/-- Every aggregate event schema, with independently arbitrary represented
    fields. Raw string slices have a real pointer/length model rather than
    the empty surface-syntax Slice type. Copying does not validate referents. -/
def aggregateEvents (first second third : Int32) (kind : Reference)
    (sliceKind : SliceKind) (pointer length : Nat) : List Value :=
  let localValue := source_value Extracted.«ir::body_events».Types.«LocalReference».mk [.signed .i32 first.toInt]
  let field := source_value Extracted.«ir::body_events».Types.«FieldReference».mk [.signed .i32 first.toInt]
  let declaration := source_value Extracted.«ir::body_events».Types.«LocalDeclaration».mk
    [.signed .i32 first.toInt, referenceValue kind]
  [source_value Extracted.«ir::body_events».Types.«Event».«ExpressionCast»
      [source_value Extracted.«ir::body_events».Types.«CastTarget».mk [referenceValue kind]],
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionString»
      [source_value Extracted.«ir::body_events».Types.«StringValue».mk
        [.rawSlice (.scalar (.signed .i32)) pointer length, .signed .i32 first.toInt]],
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionLocal» [localValue],
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionStruct»
      [source_value Extracted.«ir::body_events».Types.«StructFields».mk
        [.signed .i32 first.toInt, .signed .i32 second.toInt]],
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionEnumeration»
      [source_value Extracted.«ir::body_events».Types.«EnumVariant».mk
        [.signed .i32 first.toInt, .signed .i32 second.toInt, .signed .i32 third.toInt]],
    matchingEvent kind first second,
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionField» [field],
    callEvent first second,
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionTypedSliceFromRawParts»
      [source_value Extracted.«ir::body_events».Types.«SliceElement».mk [sliceKindValue sliceKind, .signed .i32 first.toInt]],
    source_value Extracted.«ir::body_events».Types.«Event».«MatchArmHeader»
      [source_value Extracted.«ir::body_events».Types.«MatchArm».mk [.signed .i32 first.toInt, .signed .i32 second.toInt]],
    source_value Extracted.«ir::body_events».Types.«Event».«MatchBinding» [localValue],
    source_value Extracted.«ir::body_events».Types.«Event».«PlaceLocal» [localValue],
    source_value Extracted.«ir::body_events».Types.«Event».«PlaceField» [field],
    source_value Extracted.«ir::body_events».Types.«Event».«StatementLet» [declaration],
    source_value Extracted.«ir::body_events».Types.«Event».«StatementLetUninitialized» [declaration]]

theorem aggregateCodecs (first second third : Int32) (kind : Reference) (sliceKind : SliceKind)
    (pointer length : Nat) (pointerFits : pointer < 2 ^ 64) (lengthFits : length < 2 ^ 64) :
    ∀ event ∈ aggregateEvents first second third kind sliceKind pointer length,
      NativeStoreSpec 64 extractedProgram eventType event 40 := by
  simp only [aggregateEvents, List.forall_mem_cons]
  repeat' first | apply And.intro | native_store | exact List.forall_mem_nil _

def scalarEvents (value : Int32) (flag : Bool) : List Value :=
  [integer value.toBitVec,
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUsize» [.signed .i32 value.toInt],
    source_value Extracted.«ir::body_events».Types.«Event».«ExpressionConstant» [.signed .i32 value.toInt],
    boolean flag]
theorem scalarCodecs (value : Int32) (flag : Bool) :
    ∀ event ∈ scalarEvents value flag, NativeStoreSpec 64 extractedProgram eventType event 40 := by
  simp only [scalarEvents, List.forall_mem_cons]
  repeat' first | apply And.intro | native_store | exact List.forall_mem_nil _

private def eventId : TypeId := match eventType with | .enumeration id => id | _ => 0
private def eventDeclaration : EnumDecl := (extractedProgram.enumeration? eventId).getD { id := 0, variants := [] }
def eventVariantCount : Nat := eventDeclaration.variants.length
def nullaryEvents : List Value := (List.range eventDeclaration.variants.length).filterMap fun ordinal =>
  if eventDeclaration.variants[ordinal]? = some [] then some (.enumeration eventId ordinal []) else none

theorem nullaryCodecs : ∀ event ∈ nullaryEvents,
    NativeStoreSpec 64 extractedProgram eventType event 40 := by
  intro event member
  obtain ⟨ordinal, inside, found⟩ := List.mem_filterMap.mp member
  have bound : ordinal < eventDeclaration.variants.length := List.mem_range.mp inside
  have fits : ordinal < 256 ^ 4 := Nat.lt_trans bound (by decide +kernel)
  split at found
  · next empty =>
      cases Option.some.inj found
      exact (NativeStoreSpec.enumEmpty (by core_lookup) empty fits).enlarge (by decide)
  · contradiction

/-- Native storage coverage, not source typechecking or catalog validity. -/
def representedEvents (first second third : Int32) (flag : Bool) (kind : Reference)
    (sliceKind : SliceKind) (pointer length : Nat) : List Value :=
  nullaryEvents ++ scalarEvents first flag ++ aggregateEvents first second third kind sliceKind pointer length
theorem representedCodecs (first second third : Int32) (flag : Bool) (kind : Reference)
    (sliceKind : SliceKind) (pointer length : Nat) (pointerFits : pointer < 2 ^ 64) (lengthFits : length < 2 ^ 64) :
    ∀ event ∈ representedEvents first second third flag kind sliceKind pointer length,
      NativeStoreSpec 64 extractedProgram eventType event 40 := by
  simp only [representedEvents, List.mem_append, or_imp, forall_and]
  exact ⟨⟨nullaryCodecs, scalarCodecs first flag⟩,
    aggregateCodecs first second third kind sliceKind pointer length pointerFits lengthFits⟩

#print axioms callCodec
#print axioms matchingCodec
#print axioms sliceKindCodec
#print axioms aggregateCodecs
#print axioms scalarCodecs
#print axioms nullaryCodecs
#print axioms representedCodecs

end IREventCodecProof
