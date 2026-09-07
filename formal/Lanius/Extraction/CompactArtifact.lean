import Lanius.Extraction.ArtifactPackChecker
import Lanius.Extraction.GeneratedGrammar

namespace Lanius.Extraction

/-! A compact, fixed-width wire format for per-program syntax certificates.

The producer is untrusted. Decoding yields only ordinary `Artifact` data, and
the existing verified checkers establish every invariant before downstream
proofs may use it. Keeping the wire payload in one string literal avoids
elaborating millions of generated Lean syntax nodes.
-/

private structure DecodeState where
  bytes : ByteArray
  offset : Nat

private abbrev DecodeM := StateT DecodeState Option

private def readHexDigit : DecodeM Nat := do
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

private def readHexNat : Nat → Nat → DecodeM Nat
  | 0, value => pure value
  | remaining + 1, value => do
      let digit ← readHexDigit
      readHexNat remaining (value * 16 + digit)

private def readU32 : DecodeM Nat :=
  readHexNat 8 0

private def readByte : DecodeM UInt8 := do
  pure (UInt8.ofNat (← readHexNat 2 0))

private def ensureRemaining (needed : Nat) : DecodeM Unit := do
  let state ← get
  if needed ≤ state.bytes.size - state.offset then
    pure ()
  else
    failure

private def readMany (count : Nat) (read : DecodeM α) : DecodeM (List α) := do
  let mut values := #[]
  for _ in [0:count] do
    values := values.push (← read)
  pure values.toList

private def readBytes (count : Nat) : DecodeM ByteArray := do
  ensureRemaining (count * 2)
  let mut bytes := ByteArray.empty
  for _ in [0:count] do
    bytes := bytes.push (← readByte)
  pure bytes

private def readToken : DecodeM Token := do
  let kind ← readU32
  let start ← readU32
  let finish ← readU32
  pure ⟨kind, ⟨0, start, finish⟩⟩

private def readSemanticKind : DecodeM Nat := do
  let first ← readU32
  let encodedSecond ← readU32
  if encodedSecond = 0 then
    pure first
  else
    pure (2147483648 + first + (encodedSecond - 1) * 32768)

private def readChild : DecodeM ParseChild := do
  let tag ← readU32
  let payload ← readU32
  match tag with
  | 1 => pure (.token payload)
  | 2 => pure (.node payload)
  | _ => failure

private def readNode : DecodeM ParseNode := do
  let productionId ← readU32
  let some production := laniusGrammar.production? productionId
    | failure
  let start ← readU32
  let finish ← readU32
  let childCount ← readU32
  ensureRemaining (childCount * 16)
  let children ← readMany childCount readChild
  pure ⟨productionId, production.lhs, start, finish, children⟩

private def readArtifact : DecodeM Artifact := do
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

private def readPack : DecodeM ArtifactPack := do
  let formatVersion ← readU32
  if formatVersion != 1 then failure
  let unitCount ← readU32
  ensureRemaining (unitCount * 40)
  let units ← readMany unitCount readArtifact
  if units.isEmpty then failure
  let state ← get
  if state.offset != state.bytes.size then failure
  pure ⟨schemaVersion, units⟩

def decodeCompactArtifactPack? (encoded : String) : Option ArtifactPack :=
  (readPack.run { bytes := encoded.toUTF8, offset := 0 }).map (·.1)

inductive CompactSyntaxUnitsValid : List Artifact → Prop where
  | nil : CompactSyntaxUnitsValid []
  | cons
      (head : ParseArtifactValid artifact)
      (tail : CompactSyntaxUnitsValid artifacts) :
      CompactSyntaxUnitsValid (artifact :: artifacts)

private def checkCompactSyntaxUnits :
    (artifacts : List Artifact) →
      Option (ArtifactPackChecker.Evidence
        (CompactSyntaxUnitsValid artifacts))
  | [] => some ⟨.nil⟩
  | head :: tail => do
      if accepted : checkParseArtifact head = true then
        let checkedTail ← checkCompactSyntaxUnits tail
        pure ⟨.cons (checkParseArtifact_sound accepted) checkedTail.proof⟩
      else
        none

structure CheckedCompactSyntaxPack (encoded : String) where
  pack : ArtifactPack
  decoded : decodeCompactArtifactPack? encoded = some pack
  schema : pack.schema_version = schemaVersion
  units : CompactSyntaxUnitsValid pack.units

def compactPackSources (pack : ArtifactPack) : List SourceFile :=
  pack.units.flatMap (fun artifact => artifact.sources)

/-- A syntax certificate whose ordered source names and bytes have also been
checked against an independently supplied input list. -/
structure CheckedCompactSyntaxSourcePack
    (encoded : String) (expectedSources : List SourceFile) where
  checked : CheckedCompactSyntaxPack encoded
  sources : compactPackSources checked.pack = expectedSources

def checkCompactSyntaxArtifactPack?
    (encoded : String) : Option (CheckedCompactSyntaxPack encoded) := do
  match decoded : decodeCompactArtifactPack? encoded with
  | none => none
  | some pack => do
      if schema : pack.schema_version = schemaVersion then
        let units ← checkCompactSyntaxUnits pack.units
        pure { pack, decoded, schema, units := units.proof }
      else
        none

def checkCompactSyntaxArtifactPackSources?
    (encoded : String) (expectedSources : List SourceFile) :
    Option (CheckedCompactSyntaxSourcePack encoded expectedSources) := do
  match decoded : decodeCompactArtifactPack? encoded with
  | none => none
  | some pack => do
      if schema : pack.schema_version = schemaVersion then
        if sources : compactPackSources pack = expectedSources then
          let units ← checkCompactSyntaxUnits pack.units
          pure {
            checked := { pack, decoded, schema, units := units.proof }
            sources
          }
        else
          none
      else
        none

/-- The proposition exposed to execution and bootstrap proofs. Acceptance
cannot be used without recovering the exact decoded pack, its source binding,
and the validity proof for every syntax unit. -/
theorem checkCompactSyntaxArtifactPackSources?_sound
    {encoded : String} {expectedSources : List SourceFile}
    (accepted :
      (checkCompactSyntaxArtifactPackSources? encoded expectedSources).isSome =
        true) :
    ∃ pack,
      decodeCompactArtifactPack? encoded = some pack ∧
      pack.schema_version = schemaVersion ∧
      compactPackSources pack = expectedSources ∧
      CompactSyntaxUnitsValid pack.units := by
  cases found : checkCompactSyntaxArtifactPackSources? encoded expectedSources with
  | none => simp [found] at accepted
  | some checked =>
      exact ⟨checked.checked.pack, checked.checked.decoded,
        checked.checked.schema, checked.sources, checked.checked.units⟩

structure CheckedCompactSurfaceSourcePack
    (encoded : String) (expectedSources : List SourceFile) where
  pack : ArtifactPack
  decoded : decodeCompactArtifactPack? encoded = some pack
  schema : pack.schema_version = schemaVersion
  sources : compactPackSources pack = expectedSources
  surfaceData : ArtifactPackChecker.CheckedUnitSurfaces pack.units
  surfaces : ArtifactPackChecker.UnitsSurfaceValid pack.units

def checkCompactSurfaceArtifactPackSources?
    (encoded : String) (expectedSources : List SourceFile) :
    Option (CheckedCompactSurfaceSourcePack encoded expectedSources) := do
  match decoded : decodeCompactArtifactPack? encoded with
  | none => none
  | some pack => do
      if schema : pack.schema_version = schemaVersion then
        if sources : compactPackSources pack = expectedSources then
          let surfaceData ← ArtifactPackChecker.checkUnitSurfacesCached pack.units
          pure {
            pack, decoded, schema, sources, surfaceData
            surfaces := surfaceData.valid
          }
        else
          none
      else
        none

theorem checkCompactSurfaceArtifactPackSources?_sound
    {encoded : String} {expectedSources : List SourceFile}
    (accepted :
      (checkCompactSurfaceArtifactPackSources? encoded expectedSources).isSome =
        true) :
    ∃ pack,
      decodeCompactArtifactPack? encoded = some pack ∧
      pack.schema_version = schemaVersion ∧
      compactPackSources pack = expectedSources ∧
      ArtifactPackChecker.UnitsSurfaceValid pack.units := by
  cases found : checkCompactSurfaceArtifactPackSources? encoded expectedSources with
  | none => simp [found] at accepted
  | some checked =>
      exact ⟨checked.pack, checked.decoded, checked.schema, checked.sources,
        checked.surfaces⟩

end Lanius.Extraction
