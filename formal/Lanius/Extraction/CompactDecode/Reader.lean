import Lanius.Extraction.Artifact
import Lanius.Extraction.GeneratedGrammar

namespace Lanius.Extraction.CompactDecode

structure DecodeState where
  bytes : ByteArray
  offset : Nat

abbrev DecodeM := StateT DecodeState Option

def readHexDigit : DecodeM Nat := do
  let state ← get
  let some byte := state.bytes[state.offset]?
    | failure
  let value := byte.toNat
  let digit ←
    if 48 ≤ value ∧ value ≤ 57 then some (value - 48)
    else if 97 ≤ value ∧ value ≤ 102 then some (value - 87)
    else none
  set { state with offset := state.offset + 1 }
  pure digit

def readHexNat : Nat → Nat → DecodeM Nat
  | 0, value => pure value
  | remaining + 1, value => do
      let digit ← readHexDigit
      readHexNat remaining (value * 16 + digit)

def readU32 : DecodeM Nat :=
  readHexNat 8 0

def readByte : DecodeM UInt8 := do
  pure (UInt8.ofNat (← readHexNat 2 0))

def ensureRemaining (needed : Nat) : DecodeM Unit := do
  let state ← get
  if needed ≤ state.bytes.size - state.offset then
    pure ()
  else
    failure

def readMany (count : Nat) (read : DecodeM α) : DecodeM (List α) := do
  let mut values := #[]
  for _ in [0:count] do
    values := values.push (← read)
  pure values.toList

def readBytes (count : Nat) : DecodeM ByteArray := do
  ensureRemaining (count * 2)
  let mut bytes := ByteArray.empty
  for _ in [0:count] do
    bytes := bytes.push (← readByte)
  pure bytes

def readToken : DecodeM Token := do
  let kind ← readU32
  let start ← readU32
  let finish ← readU32
  pure ⟨kind, ⟨0, start, finish⟩⟩

def readSemanticKind : DecodeM Nat := do
  let first ← readU32
  let encodedSecond ← readU32
  if encodedSecond = 0 then
    pure first
  else
    pure (2147483648 + first + (encodedSecond - 1) * 32768)

def readChild : DecodeM ParseChild := do
  let tag ← readU32
  let payload ← readU32
  match tag with
  | 1 => pure (.token payload)
  | 2 => pure (.node payload)
  | _ => failure

def readNode : DecodeM ParseNode := do
  let productionId ← readU32
  let some production := laniusGrammar.production? productionId
    | failure
  let start ← readU32
  let finish ← readU32
  let childCount ← readU32
  ensureRemaining (childCount * 16)
  let children ← readMany childCount readChild
  pure ⟨productionId, production.lhs, start, finish, children⟩

def readArtifact : DecodeM Artifact := do
  let pathBytes ← readBytes (← readU32)
  let some path := String.fromUTF8? pathBytes
    | failure
  let sourceBytes ← readBytes (← readU32)
  let rawCount ← readU32
  ensureRemaining (rawCount * 24)
  let rawTokens ← readMany rawCount readToken
  let tokenCount ← readU32
  ensureRemaining (tokenCount * 40)
  let tokens ← readMany tokenCount readToken
  let semanticKinds ← readMany tokens.length readSemanticKind
  let nodeCount ← readU32
  ensureRemaining (nodeCount * 32)
  let nodes ← readMany nodeCount readNode
  if nodes.isEmpty then failure
  pure {
    Artifact.empty with
    sources := [{
      path
      bytes := sourceBytes.toList.map UInt8.toNat
    }]
    raw_tokens := some rawTokens
    tokens
    semantic_token_kinds := semanticKinds
    parse_nodes := nodes
    parse_root := some (nodes.length - 1)
  }

def readPack : DecodeM ArtifactPack := do
  let formatVersion ← readU32
  if formatVersion != 1 then failure
  let unitCount ← readU32
  ensureRemaining (unitCount * 40)
  let units ← readMany unitCount readArtifact
  if units.isEmpty then failure
  let state ← get
  if state.offset != state.bytes.size then failure
  pure ⟨schemaVersion, units⟩

end Lanius.Extraction.CompactDecode

