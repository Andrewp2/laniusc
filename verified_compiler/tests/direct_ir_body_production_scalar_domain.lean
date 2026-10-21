import verified_compiler.tests.direct_ir_body_production_inputs_context
import verified_compiler.tests.direct_ir_body_production_scalar_decimal
import verified_compiler.tests.direct_ir_body_production_main_stream
import Lanius.Surface

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof

def ascii (text : String) : List Int := text.toList.map (fun character => character.toNat)
def integerToken : Value := source_value Extracted.«verified::token».Types.«TokenKind».«Integer» []
def booleanToken (flag : Bool) : Value := if flag then
  source_value Extracted.«verified::token».Types.«TokenKind».«TrueKeyword» [] else
  source_value Extracted.«verified::token».Types.«TokenKind».«FalseKeyword» []

/-- Original token row and source words, with no assumed token query/decoder run. -/
structure OriginalToken (input : Inputs) (state : State) (index : Nat) (text : String) (expected : Value)
    extends NativeToken input state.heap index where
  sourceAddress : Nat
  sourceCapacity : Nat
  origin : Nat
  kindMatches : kind = expected
  startMatches : start = Int.ofNat origin
  finishMatches : finish = Int.ofNat (origin + text.toList.length)
  source : input.source = .rawSlice (.scalar (.signed .i32)) sourceAddress sourceCapacity
  span : origin + text.toList.length ≤ input.sourceLength
  sourceBound : input.sourceLength ≤ sourceCapacity
  sourceFits : input.sourceLength < 2 ^ 31
  tokensFit : input.tokenCount < 2 ^ 31
  words : ∀ offset, offset < text.toList.length →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) sourceAddress sourceCapacity (origin + offset) =
      .ok (.signed .i32 ((ascii text)[offset]?.getD 0))

def OriginalToken.afterReads (token : OriginalToken input before index text expected)
    (reads : HeapReads before.heap after.heap) : OriginalToken input after index text expected := {
  token with
  toNativeToken := token.toNativeToken.afterReads reads
  words := fun offset bound => reads.rawSlice (token.words offset bound) }

/-- Independent lexical values and ranges; not a successful-parser predicate. -/
inductive ScalarSpelling : Surface.Expr → Reference → Prop where
  | boolean (flag : Bool) : ScalarSpelling (.literal (.boolean flag)) .Bool
  | decimal (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude < 2 ^ 31) :
      ScalarSpelling (.literal (.integer text)) .I32
  | negative (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude ≤ 2 ^ 31) :
      ScalarSpelling (.unary .negative (.literal (.integer text))) .I32

/-- The emitted body is selected by the same independent spelling witness,
    including the minimum's direct signed-integer representation. -/
inductive ScalarSpelling.Selects : {expression : Surface.Expr} → {result : Reference} →
    ScalarSpelling expression result → IRBodyProductionProof.ReturnBody → Prop where
  | boolean (flag : Bool) : Selects (ScalarSpelling.boolean flag) (.boolean flag)
  | decimal (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude < 2 ^ 31) :
      Selects (ScalarSpelling.decimal spelled bound) (.integer (Int32.ofInt magnitude))
  | negative (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude ≤ 2 ^ 31)
      (ordinary : magnitude < 2 ^ 31) :
      Selects (ScalarSpelling.negative spelled bound) (.negative (Int32.ofInt magnitude))
  | minimum (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude ≤ 2 ^ 31)
      (minimum : magnitude = 2 ^ 31) :
      Selects (ScalarSpelling.negative spelled bound) (.integer (Int32.ofInt (-2147483648)))

def emptyBinary (production tail : Int) : Prop :=
  (production, tail) ∈ [(105, 117), (118, 120), (121, 123), (124, 126), (127, 129),
    (130, 132), (133, 136), (137, 142), (143, 146), (147, 150), (151, 155), (160, 164)]

/-- Evidence about the existing native syntax, not a second syntax tree.
    Natural parser wrappers are admitted instead of requiring an unwrapped leaf. -/
inductive OriginalScalar (input : Inputs) (state : State) : Nat → Surface.Expr → List Nat → Prop where
  | boolean (node : NativeNode input.tree state.heap index)
      (production : node.production = if flag then 185 else 186) (count : node.count = 1)
      (child : NativeChild input.tree state.heap node.first) (kind : child.kind = .TokenChild)
      (payload : child.payload = Int.ofNat token)
      (spelling : OriginalToken input state token (if flag then "true" else "false") (booleanToken flag)) :
      OriginalScalar input state index (.literal (.boolean flag)) [index]
  | integer (node : NativeNode input.tree state.heap index) (production : node.production = 175)
      (count : node.count = 1) (child : NativeChild input.tree state.heap node.first)
      (kind : child.kind = .TokenChild) (payload : child.payload = Int.ofNat token)
      (spelling : OriginalToken input state token text integerToken) :
      OriginalScalar input state index (.literal (.integer text)) [index]
  | negative (node : NativeNode input.tree state.heap index) (production : node.production = 157)
      (count : node.count = 2) (child : NativeChild input.tree state.heap (node.first + 1))
      (kind : child.kind = .StateChild) (payload : child.payload = Int.ofNat operand)
      (minus : NativeChild input.tree state.heap node.first) (minusKind : minus.kind = .TokenChild)
      (minusPayload : minus.payload = Int.ofNat minusToken)
      (minusSpelling : OriginalToken input state minusToken "-"
        (source_value Extracted.«verified::token».Types.«TokenKind».«Minus» []))
      (operandSyntax : OriginalScalar input state operand (.literal (.integer text)) route) :
      OriginalScalar input state index (.unary .negative (.literal (.integer text))) (index :: route)
  | wrapper (node : NativeNode input.tree state.heap index)
      (production : node.production = 104 ∨ node.production = 159 ∨ node.production = 172)
      (slot : Nat) (selected : slot = if node.production = 172 then 1 else 0) (inside : slot < node.count)
      (child : NativeChild input.tree state.heap (node.first + slot)) (kind : child.kind = .StateChild)
      (payload : child.payload = Int.ofNat operand) (operandSyntax : OriginalScalar input state operand expression route) :
      OriginalScalar input state index expression (index :: route)
  | binaryEnd (node : NativeNode input.tree state.heap index) (count : node.count = 2)
      (left : NativeChild input.tree state.heap node.first) (leftKind : left.kind = .StateChild)
      (leftPayload : left.payload = Int.ofNat operand)
      (tail : NativeChild input.tree state.heap (node.first + 1)) (tailKind : tail.kind = .StateChild)
      (tailPayload : tail.payload = Int.ofNat tailIndex) (ending : NativeNode input.tree state.heap tailIndex)
      (production : emptyBinary node.production ending.production)
      (operandSyntax : OriginalScalar input state operand expression route) :
      OriginalScalar input state index expression (index :: tailIndex :: route)

structure NaturalScalar (input : Inputs) (state : State) (root : Nat) where
  expression : Surface.Expr
  result : Reference
  spelling : ScalarSpelling expression result
  route : List Nat
  «syntax» : OriginalScalar input state root expression route
  distinct : route.Nodup

theorem OriginalScalar.afterReads (original : OriginalScalar input before root expression route)
    (reads : HeapReads before.heap after.heap) : OriginalScalar input after root expression route := by
  induction original with
  | boolean node production count child kind payload spelling =>
      exact .boolean (node.afterReads reads) production count (child.afterReads reads) kind payload
        (spelling.afterReads reads)
  | integer node production count child kind payload spelling =>
      exact .integer (node.afterReads reads) production count (child.afterReads reads) kind payload
        (spelling.afterReads reads)
  | negative node production count child kind payload minus minusKind minusPayload minusSpelling operand ih =>
      exact .negative (node.afterReads reads) production count (child.afterReads reads) kind payload
        (minus.afterReads reads) minusKind minusPayload (minusSpelling.afterReads reads) ih
  | wrapper node production slot selected inside child kind payload operand ih =>
      exact .wrapper (node.afterReads reads) production slot selected inside (child.afterReads reads) kind payload ih
  | binaryEnd node count left leftKind leftPayload tail tailKind tailPayload ending production operand ih =>
      exact .binaryEnd (node.afterReads reads) count (left.afterReads reads) leftKind leftPayload
        (tail.afterReads reads) tailKind tailPayload (ending.afterReads reads) production ih

def NaturalScalar.afterReads (scalar : NaturalScalar input before root) (reads : HeapReads before.heap after.heap) :
    NaturalScalar input after root := { scalar with «syntax» := scalar.syntax.afterReads reads }

theorem OriginalScalar.routeInside (original : OriginalScalar input state root expression route) :
    ∀ index ∈ route, index < input.tree.nodeCount := by
  induction original with
  | boolean node production count child kind payload spelling =>
      intro index member
      simp only [List.mem_singleton] at member
      subst index
      exact node.inside
  | integer node production count child kind payload spelling =>
      intro index member
      simp only [List.mem_singleton] at member
      subst index
      exact node.inside
  | negative node production count child kind payload minus minusKind minusPayload minusSpelling operand ih =>
      intro index member
      simp only [List.mem_cons] at member
      rcases member with same | member
      · subst index; exact node.inside
      · exact ih index member
  | wrapper node production slot selected inside child kind payload operand ih =>
      intro index member
      simp only [List.mem_cons] at member
      rcases member with same | member
      · subst index; exact node.inside
      · exact ih index member
  | binaryEnd node count left leftKind leftPayload tail tailKind tailPayload ending production operand ih =>
      intro index member
      simp only [List.mem_cons] at member
      rcases member with same | same | member
      · subst index; exact node.inside
      · subst index; exact ending.inside
      · exact ih index member

/-- The real caller's node_count supplies the independently justified route depth. -/
theorem NaturalScalar.routeBound (scalar : NaturalScalar input state root) :
    scalar.route.length ≤ input.tree.nodeCount :=
  input.tree.routeBound scalar.route scalar.distinct scalar.syntax.routeInside

#print axioms OriginalScalar.routeInside
#print axioms NaturalScalar.routeBound
#print axioms OriginalToken.afterReads
#print axioms OriginalScalar.afterReads
#print axioms NaturalScalar.afterReads

end IRBodyProductionScalar
