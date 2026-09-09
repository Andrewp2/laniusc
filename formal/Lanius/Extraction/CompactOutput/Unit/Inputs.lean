import Lanius.Extraction.CompactOutput.Unit.Bytes
import Lanius.Extraction.CompactOutput.Unit.Tokens
import Lanius.Extraction.CompactOutput.Unit.Semantic
import Lanius.Extraction.CompactOutput.Unit.Nodes

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer Lanius.Extraction.CanonicalTokens.CanonicalizeModel
open Lanius.Extraction.SemanticTokens

/-- Input contracts contain data, storage, and field bounds, never executions. -/
structure ByteInput (state : State) (inputId lengthId : VarId) (outputCell : CellId) where
  values : List Nat
  cell : CellId
  capacity : Nat
  input : I32Prefix state cell capacity (values.map Int.ofNat)
  inputRead : state.local? inputId = some (.slice i32 cell [] 0 capacity)
  lengthRead : state.local? lengthId = some (.signed .i32 values.length)
  distinct : outputCell ≠ cell
  lengthFit : values.length ≤ 2147483647
  byteBound : ∀ value ∈ values, value < 256

structure TokenInput (state : State) (inputId lengthId countId : VarId)
    (sourceLength : Nat) (outputCell : CellId) where
  tokens : List RawToken
  cell : CellId
  capacity : Nat
  inputLength : Nat
  input : I32Prefix state cell capacity (encodeTokens tokens)
  inputRead : state.local? inputId = some (.slice i32 cell [] 0 capacity)
  lengthRead : state.local? lengthId = some (.signed .i32 inputLength)
  countRead : state.local? countId = some (.signed .i32 tokens.length)
  distinct : outputCell ≠ cell
  inputRoom : 3 * tokens.length ≤ inputLength
  lengthFit : inputLength ≤ 2147483647
  fields : ∀ token ∈ tokens, token.kind.gpuCode ≤ 2147483647 ∧
    token.start ≤ token.finish ∧ token.finish ≤ sourceLength

structure SemanticInput (state : State) (count : Nat) (outputCell : CellId) where
  assignments : List Assignment
  cell : CellId
  capacity : Nat
  inputLength : Nat
  input : I32Prefix state cell capacity (assignments.flatMap Assignment.words)
  inputRead : state.local? 10 = some (.slice i32 cell [] 0 capacity)
  lengthRead : state.local? 11 = some (.signed .i32 inputLength)
  countEqual : assignments.length = count
  distinct : outputCell ≠ cell
  inputRoom : 2 * assignments.length ≤ inputLength
  lengthFit : inputLength ≤ 2147483647
  fields : ∀ assignment ∈ assignments, assignment.first ≤ 2147483647 ∧
    -1 ≤ Assignments.secondWord assignment ∧ Assignments.secondWord assignment < 2147483647

structure NodeInput (state : State) (count : Nat) (outputCell : CellId) where
  records : List RecordVisit
  words : List Int
  cell : CellId
  capacity : Nat
  offsetCell : CellId
  offsetCapacity : Nat
  inputLength : Nat
  input : I32Prefix state cell capacity words
  offsets : I32Prefix state offsetCell offsetCapacity (records.map (fun record => (record.offset : Int)))
  inputRead : state.local? 12 = some (.slice i32 cell [] 0 capacity)
  lengthRead : state.local? 13 = some (.signed .i32 inputLength)
  offsetRead : state.local? 14 = some (.slice i32 offsetCell [] 0 offsetCapacity)
  nodesRead : state.local? 15 = some (.signed .i32 records.length)
  distinctInput : outputCell ≠ cell
  distinctOffsets : outputCell ≠ offsetCell
  inputRoom : words.length ≤ inputLength
  inputFit : inputLength ≤ 2147483647
  nodesFit : records.length ≤ 2147483647
  stored : ∀ record ∈ records, record.Stored 0 words
  fields : ∀ record ∈ records, record.production ≤ 2147483647 ∧
    record.start ≤ 2147483647 ∧ record.finish ≤ 2147483647
  linked : ∀ (index : Nat) (record : RecordVisit), records[index]? = some record →
    ∀ child ∈ record.children, child.Linked 0 records index
  tokenBound : ∀ record ∈ records, ∀ child ∈ record.children, ∀ use,
    child = .token use → use.token < count

structure Inputs (state : State) (outputCell : CellId) (outputLength : Nat) where
  path : ByteInput state 0 1 outputCell
  source : ByteInput state 2 3 outputCell
  raw : TokenInput state 4 5 6 source.values.length outputCell
  canonical : TokenInput state 7 8 9 source.values.length outputCell
  semantic : SemanticInput state canonical.tokens.length outputCell
  nodes : NodeInput state canonical.tokens.length outputCell
  capacity : Nat
  outputRead : state.local? 16 = some (.slice i32 outputCell [] 0 outputLength)
  capacityRead : state.local? 17 = some (.signed .i32 capacity)
  room : capacity ≤ outputLength
  capacityFit : capacity ≤ 2147483647

def Inputs.tailEncoding (inputs : Inputs state outputCell outputLength) : List Nat :=
  Bytes.encoding inputs.path.values ++ hexDigits inputs.source.values.length 8 ++
  Bytes.encoding inputs.source.values ++ hexDigits inputs.raw.tokens.length 8 ++
  Tokens.encodeAll inputs.raw.tokens ++ hexDigits inputs.canonical.tokens.length 8 ++
  Tokens.encodeAll inputs.canonical.tokens ++ Assignments.encodeAll inputs.semantic.assignments ++
  hexDigits inputs.nodes.records.length 8 ++ Nodes.encodeAll inputs.nodes.records

def Inputs.encoding (inputs : Inputs state outputCell outputLength) : List Nat :=
  hexDigits inputs.path.values.length 8 ++ inputs.tailEncoding

end Lanius.Extraction.CompactOutput.Unit
