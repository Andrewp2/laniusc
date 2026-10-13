import verified_compiler.tests.direct_ir_owned_queries_fields

namespace IRBodyOwnedInputs

open Lanius Lanius.Core

/-- The same dependent native rows as a total semantic view. Outside the
    represented count the value is arbitrary and no native read is required. -/
def NormalTable.rowValue (normal : NormalTable table heap) (index : Nat) : AllocationRow :=
  if inside : index < normal.count then (normal.rows index inside).row
  else {
    source := {
      unit := Int32.ofNat 0
      kind := .Invalid
      isPublic := false
      item := Int32.ofNat 0
      declaration := Int32.ofNat 0
      name := Int32.ofNat 0
      target := Int32.ofNat 0
      ordinal := Int32.ofNat 0 }
    declarationId := Int32.ofNat 0
    coreId := Int32.ofNat 0 }

theorem NormalTable.rowValue_inside (normal : NormalTable table heap) (inside : index < normal.count) :
    normal.rowValue index = (normal.rows index inside).row := by
  simp only [NormalTable.rowValue, dif_pos inside]

/-- Exact signed record fields for the staged entry guard; no backing is implied. -/
structure RawInputs where
  owner : Int32
  source : Value
  sourceWords : Int32
  tokens : Value
  tokenCount : Int32
  tokenStorage : Nat
  nodes : Value
  children : Value
  nodeCount : Int32
  childCount : Int32
  allocationTable : AllocationTable
  allocationTail : Fin 5 → Value
  signatureData : Value
  signatureCount : Int32
  signatureTail : Fin 10 → Value
  resolutions : Value
  aliases : Value
  valueData : Value
  valueCount : Int32
  valueNames : Value
  contexts : Value
  sourceCatalog : Value
  tokenCatalog : Value
  globalDeclarations : Value
  trees : Value

def RawInputs.signatureValue (input : RawInputs) : Value :=
  source_value Extracted.«lowering::signature_index».Types.«Table».mk
    [input.signatureData, .signed .i32 input.signatureCount.toInt,
      input.signatureTail 0, input.signatureTail 1, input.signatureTail 2, input.signatureTail 3,
      input.signatureTail 4, input.signatureTail 5, input.signatureTail 6, input.signatureTail 7,
      input.signatureTail 8, input.signatureTail 9]
def RawInputs.valuesValue (input : RawInputs) : Value :=
  source_value Extracted.«lowering::value_catalog».Types.«ValueTable».mk
    [input.valueData, .signed .i32 input.valueCount.toInt]
def RawInputs.value (input : RawInputs) : Value :=
  source_value Extracted.«lowering::body_context».Types.«BodyLoweringInputs».mk
    [.signed .i32 input.owner.toInt,
      source_value Extracted.«lowering::body_context».Types.«WordRegion».mk
        [input.source, .signed .i32 input.sourceWords.toInt],
      source_value Extracted.«verified::token».Types.«TokenTable».mk
        [input.tokens, .signed .i32 input.tokenCount.toInt, .pointer input.tokenStorage],
      source_value Extracted.«verified::syntax_tree».Types.«Tree».mk
        [input.nodes, input.children, .signed .i32 input.nodeCount.toInt, .signed .i32 input.childCount.toInt],
      source_value Extracted.«lowering::allocation».Types.«Index».mk
        [input.allocationTable.value, input.allocationTail 0, input.allocationTail 1,
          input.allocationTail 2, input.allocationTail 3, input.allocationTail 4],
      input.signatureValue, input.resolutions, input.aliases, input.valuesValue, input.valueNames,
      input.contexts, input.sourceCatalog, input.tokenCatalog, input.globalDeclarations, input.trees]

structure RawWorkspace where
  expressionData : Value
  expressionCount : Value
  expressionCapacity : Int32
  codes : Value
  depths : Value
  typeData : Value
  typeCount : Value
  typeCapacity : Int32
  aliasScratch : Value
  aliasCapacity : Int32
  typeOutput : Value
  typeOutputCount : Int32
  events : Value
  catalog : Value

def RawWorkspace.value (workspace : RawWorkspace) : Value :=
  source_value Extracted.«lowering::body_context».Types.«BodyLoweringWorkspace».mk
    [source_value Extracted.«verified::surface_expr».Types.«ExpressionArena».mk
        [workspace.expressionData, workspace.expressionCount, .signed .i32 workspace.expressionCapacity.toInt],
      workspace.codes, workspace.depths,
      source_value Extracted.«verified::surface_type».Types.«TypeArena».mk
        [workspace.typeData, workspace.typeCount, .signed .i32 workspace.typeCapacity.toInt],
      source_value Extracted.«lowering::body_context».Types.«WordRegion».mk
        [workspace.aliasScratch, .signed .i32 workspace.aliasCapacity.toInt],
      source_value Extracted.«lowering::types».Types.«Results».mk
        [workspace.typeOutput, .signed .i32 workspace.typeOutputCount.toInt],
      workspace.events, workspace.catalog]

/-- These clauses precede the first possible header construction. -/
def RawInputs.beforeHeaderReject (input : RawInputs) : Prop :=
  input.owner.toInt ≤ -2 ∨ input.sourceWords.toInt ≤ -1 ∨ input.tokenCount.toInt ≤ -1 ∨
    input.nodeCount.toInt ≤ 0 ∨ input.allocationTable.count.toInt ≤ -1

/-- Reached descriptor rejection retains the header's actual borrow effect. -/
def RawInputs.afterHeaderReject (input : RawInputs) (workspace : RawWorkspace) : Prop :=
  input.signatureCount.toInt ≤ 0 ∨ input.valueCount.toInt ≤ -1 ∨
    workspace.expressionCapacity.toInt ≤ 0 ∨ workspace.typeCapacity.toInt ≤ 0 ∨
    workspace.typeOutputCount.toInt ≤ 0

def selectedRow (owner : Int32) (row : AllocationRow) : Prop :=
  row.source.kind = .Function ∧ (owner.toInt = -1 ∨ row.source.unit.toInt = owner.toInt)
def selectedRowBool (owner : Int32) (row : AllocationRow) : Bool :=
  kindSame row.source.kind .Function &&
    (decide (owner.toInt = -1) || decide (row.source.unit.toInt = owner.toInt))

theorem selectedRowBool_iff (owner : Int32) (row : AllocationRow) :
    selectedRowBool owner row = true ↔ selectedRow owner row := by
  simp only [selectedRowBool, selectedRow, Bool.and_eq_true, Bool.or_eq_true,
    decide_eq_true_eq, kindSame_iff]

#print axioms selectedRowBool_iff
#print axioms NormalTable.rowValue_inside

end IRBodyOwnedInputs
