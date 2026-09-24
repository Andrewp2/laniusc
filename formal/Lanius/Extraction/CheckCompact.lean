import Lanius.Extraction.SyntaxCheck.Pack

open Lanius.Extraction
open Lanius.Extraction.SyntaxCheck

def readExpectedSources (paths : List String) : IO (List SourceFile) :=
  paths.mapM fun path => do
    let contents ← IO.FS.readBinFile (System.FilePath.mk path)
    pure { path := path, bytes := contents.toList.map UInt8.toNat }

def firstUnitFailure : List Artifact → Nat → Option (Nat × UnitCheckStage)
  | [], _ => none
  | artifact :: rest, index =>
      match checkUnit artifact with
      | .ok _ => firstUnitFailure rest (index + 1)
      | .error stage => some (index, stage)

def firstInvalidNode (artifact : Artifact) : Option (Nat × ParseNode) := Id.run do
  let nodes := artifact.parse_nodes.toArray
  let productions := laniusGrammar.productions.toArray
  for id in [:nodes.size] do
    if let some node := nodes[id]? then
      if !checkNode laniusGrammar productions artifact.semantic_token_kinds.toArray
          nodes id node then
        return some (id, node)
  return none

def reportParseFailure (artifact : Artifact) : IO Unit := do
  if let [source] := artifact.sources then
    if let some raw := artifact.raw_tokens then
      if let .ok lexer := checkLexerUnit source raw artifact.tokens then
        if let .error stage := checkParseUnit lexer laniusGrammar
            artifact.semantic_token_kinds artifact.parse_nodes artifact.parse_root then
          IO.eprintln s!"parse failure: {repr stage}"
          if stage == .semanticKinds then
            let tokens := lexer.canonical.toArray
            let semantic := artifact.semantic_token_kinds.toArray
            IO.eprintln s!"canonical tokens: {tokens.size}, semantic kinds: {semantic.size}"
            for id in [:min tokens.size semantic.size] do
              if let (some token, some code) := (tokens[id]?, semantic[id]?) then
                if !semanticKindMatches laniusGrammar token code then
                  IO.eprintln s!"first semantic kind mismatch: {id}, token {repr token}, code {code}, canonical {repr (canonicalKind? laniusGrammar code)}"
                  break
          if stage == .nodes then
            if let some (id, node) := firstInvalidNode artifact then
              IO.eprintln s!"first invalid parse node: {id}, {repr node}"
              IO.eprintln s!"expected production: {repr (laniusGrammar.productions[node.production]?)}"

def main (paths : List String) : IO UInt32 := do
  let encoded ← (← IO.getStdin).readToEnd
  let sources ← readExpectedSources paths
  match checkCompactSourcePack encoded sources with
  | .ok _ =>
      IO.println
        "exact source identity, lexer trace, grammar derivation, and independently reconstructed Surface accepted"
      pure 0
  | .error failure =>
      IO.eprintln s!"compact source, lexer, grammar, or Surface certificate checking failed: {repr failure}"
      if let some pack := decodeCompactPack? encoded then
        if let some (index, stage) := firstUnitFailure pack.units 0 then
          IO.eprintln s!"first failing unit: {index} ({(pack.units[index]?.bind (·.sources.head?)).map (·.path)}), {repr stage}"
          if stage == .parse then
            if let some artifact := pack.units[index]? then
              reportParseFailure artifact
      pure 1
