import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.SurfaceChecker
import Lean.Meta.LitValues

open Lean Elab Term

namespace Lanius.Extraction

private def cacheElabStringLiteral (stx : Syntax) : TermElabM String := do
  let expression ← elabTermEnsuringType stx (mkConst ``String)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value := Meta.getStringValue? expression
    | throwError "artifact cache quotation requires a string literal"
  pure value

private def cacheElabNatLiteral (stx : Syntax) : TermElabM Nat := do
  let expression ← elabTermEnsuringType stx (mkConst ``Nat)
  synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  let some value ← Meta.getNatValue? expression
    | throwError "artifact cache quotation requires a natural literal"
  pure value

private def cacheElabPack (stx : Syntax) : TermElabM ArtifactPack := do
  let encoded ← cacheElabStringLiteral stx
  match Json.parse encoded >>= fromJson? with
  | .ok pack => pure pack
  | .error message => throwError "invalid extraction artifact pack: {message}"

private def checkedByte (value : Nat) : Option (Fin 256) :=
  if inRange : value < 256 then some ⟨value, inRange⟩ else none

private partial def buildChunkTree (leafSize : Nat) (values : List α) :
    ChunkTree α :=
  if values.length ≤ leafSize || values.length ≤ 1 then .leaf values else
  let leftLength := values.length / 2
  .branch leftLength
    (buildChunkTree leafSize (values.take leftLength))
    (buildChunkTree leafSize (values.drop leftLength))

elab "artifact_pack_unit_tokens% " json:term ", " path:term ", "
    start:term ", " count:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let start ← cacheElabNatLiteral start
  let count ← cacheElabNatLiteral count
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  unless start + count ≤ artifact.tokens.length do
    throwError "token slice exceeds table length"
  pure (toExpr (artifact.tokens.drop start |>.take count))

elab "artifact_pack_unit_source_bytes% " json:term ", " path:term ", "
    sourceIndex:term ", " start:term ", " count:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let sourceIndex ← cacheElabNatLiteral sourceIndex
  let start ← cacheElabNatLiteral start
  let count ← cacheElabNatLiteral count
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  let some source := artifact.sources[sourceIndex]?
    | throwError "source index is absent in unit {expectedPath}"
  unless start + count ≤ source.bytes.length do
    throwError "source-byte slice exceeds source length"
  let values := source.bytes.drop start |>.take count
  let some bytes := values.mapM checkedByte
    | throwError "source-byte slice contains an out-of-range value"
  pure (toExpr bytes)

elab "artifact_pack_unit_token_tree% " json:term ", " path:term ", "
    leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  pure (toExpr (buildChunkTree leafSize artifact.tokens))

elab "artifact_pack_unit_source_byte_tree% " json:term ", " path:term ", "
    sourceIndex:term ", " leafSize:term : term => do
  let expectedPath ← cacheElabStringLiteral path
  let sourceIndex ← cacheElabNatLiteral sourceIndex
  let leafSize ← cacheElabNatLiteral leafSize
  let pack ← cacheElabPack json
  let some artifact := pack.units.find? fun artifact =>
      artifact.sources.any fun source => source.path == expectedPath
    | throwError "artifact pack has no unit for source {expectedPath}"
  let some source := artifact.sources[sourceIndex]?
    | throwError "source index is absent in unit {expectedPath}"
  let some bytes := source.bytes.mapM checkedByte
    | throwError "source contains an out-of-range byte"
  pure (toExpr (buildChunkTree leafSize bytes))

end Lanius.Extraction
