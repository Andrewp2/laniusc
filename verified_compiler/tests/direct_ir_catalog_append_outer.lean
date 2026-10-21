import verified_compiler.tests.direct_ir_type_ref
import Lanius.Core.Bindings
import Lanius.Semantics.RawSlice

namespace IRCatalogAppendProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

def source := Extracted.«ir::body_catalog».Functions.«append».core
def countId : TypeId := match source.bindingStatement 0 with
  | .letLocal _ (.slice (.structure id)) _ _ => id
  | _ => 0
def bodyType : Ty := match source.bindingStatement 1 with
  | .letLocal _ (.slice type) _ _ => type
  | _ => .unit
def eventType : Ty := match source.bindingStatement 2 with
  | .letLocal _ (.slice type) _ _ => type
  | _ => .unit
def referenceType : Ty := match referenceValue .Invalid with
  | .enumeration id _ _ => .enumeration id
  | _ => .unit
def outerCondition : Expr := match source.bindingStatement 3 with
  | .letLocal _ _ _ (.sequence (.ifThenElse condition _ _) _) => condition
  | _ => .value (.boolean false)

/-- Public represented values; backing storage is a separate, branch-sensitive obligation. -/
structure Arguments where
  rowsAddress : Nat
  rowsLength : Nat
  countAddress : Nat
  countLength : Nat
  capacity : Int32
  id : Int32
  parameters : Int32
  result : Reference
  eventsAddress : Nat
  eventsLength : Nat
  resultAddress : Nat
  resultLength : Nat
  hasResultTypes : Bool
  sourceCapacity : Int32
  eventCount : Int32
  next : Int32

def Arguments.count (input : Arguments) : Value :=
  .rawSlice (.structure countId) input.countAddress input.countLength
def Arguments.rows (input : Arguments) : Value :=
  .rawSlice bodyType input.rowsAddress input.rowsLength
def Arguments.catalog (input : Arguments) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«Catalog».mk
    [input.rows, input.count, .signed .i32 input.capacity.toInt]
def Arguments.signature (input : Arguments) : Value :=
  source_value Extracted.«ir::body_catalog».Types.«FunctionSignature».mk
    [.signed .i32 input.id.toInt, referenceValue input.result, .signed .i32 input.parameters.toInt]
def Arguments.region (input : Arguments) : Value :=
  source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType input.eventsAddress input.eventsLength,
      .rawSlice referenceType input.resultAddress input.resultLength,
      .boolean input.hasResultTypes, .signed .i32 input.sourceCapacity.toInt]
def Arguments.values (input : Arguments) : List Value :=
  [input.catalog, input.signature, input.region, .signed .i32 input.eventCount.toInt]
def Arguments.call (input : Arguments) : Expr := .call source.id (input.values.map Expr.value)
def Arguments.CountRead (input : Arguments) (state : State) : Prop :=
  readRawSliceIndex extractedProgram state (.structure countId) input.countAddress input.countLength 0 =
    .ok (.structure countId [.signed .i32 input.next.toInt])

end IRCatalogAppendProof
