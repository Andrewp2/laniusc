import Lanius.Extraction.CompactDecode.Path
import Lanius.Extraction.CompactDecode.Tokens
import Lanius.Extraction.CompactDecode.Nodes

namespace Lanius.Extraction.CompactDecode

/-- Compose the actual field readers, retaining every artifact field.
This is an execution-composition lemma; encoding inverses supply its reads. -/
theorem readArtifact_fields (path : String) (source : ByteArray)
    (raw tokens : List Token) (kinds : List Nat) (nodes : List ParseNode)
    (pathLength : readU32.run s0 = some (path.toUTF8.size, s1))
    (pathBytes : (readBytes path.toUTF8.size).run s1 = some (path.toUTF8, s2))
    (sourceLength : readU32.run s2 = some (source.size, s3))
    (sourceBytes : (readBytes source.size).run s3 = some (source, s4))
    (rawLength : readU32.run s4 = some (raw.length, s5))
    (rawRoom : raw.length * 24 ≤ s5.bytes.size - s5.offset)
    (rawRead : Reads readToken s5 raw s6)
    (tokenLength : readU32.run s6 = some (tokens.length, s7))
    (tokenRoom : tokens.length * 40 ≤ s7.bytes.size - s7.offset)
    (tokenRead : Reads readToken s7 tokens s8)
    (kindCount : kinds.length = tokens.length)
    (kindRead : Reads readSemanticKind s8 kinds s9)
    (nodeLength : readU32.run s9 = some (nodes.length, s10))
    (nodeRoom : nodes.length * 32 ≤ s10.bytes.size - s10.offset)
    (nodeRead : Reads readNode s10 nodes s11) :
    readArtifact.run s0 = if nodes.isEmpty then none else
      some ({ Artifact.empty with
        sources := [{path, bytes := source.toList.map UInt8.toNat}]
        raw_tokens := some raw
        tokens := tokens
        semantic_token_kinds := kinds
        parse_nodes := nodes
        parse_root := some (nodes.length - 1) }, s11) := by
  have rawGuard := ensureRemaining_ok rawRoom
  have tokenGuard := ensureRemaining_ok tokenRoom
  have nodeGuard := ensureRemaining_ok nodeRoom
  have rawRun := rawRead.readMany
  have tokenRun := tokenRead.readMany
  have kindRun := kindRead.readMany
  rw [kindCount] at kindRun
  have nodeRun := nodeRead.readMany
  simp only [readArtifact, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at pathLength pathBytes
  rw [pathLength]
  simp only [Option.bind_some]
  rw [pathBytes]
  simp only [Option.bind_some, fromUTF8_toUTF8]
  dsimp only [StateT.bind]
  dsimp only [StateT.run, bind, StateT.bind, pure, StateT.pure] at sourceLength sourceBytes rawLength rawGuard rawRun tokenLength tokenGuard tokenRun kindRun nodeLength nodeGuard nodeRun ⊢
  rw [sourceLength]
  dsimp only [bind, Option.bind]
  rw [sourceBytes]
  dsimp only [bind, Option.bind]
  rw [rawLength]
  dsimp only [bind, Option.bind]
  rw [rawGuard]
  dsimp only [bind, Option.bind]
  rw [rawRun]
  dsimp only [bind, Option.bind]
  rw [tokenLength]
  dsimp only [bind, Option.bind]
  rw [tokenGuard]
  dsimp only [bind, Option.bind]
  rw [tokenRun]
  dsimp only [bind, Option.bind]
  rw [kindRun]
  dsimp only [bind, Option.bind]
  rw [nodeLength]
  dsimp only [bind, Option.bind]
  rw [nodeGuard]
  dsimp only [bind, Option.bind]
  rw [nodeRun]
  dsimp only [bind, Option.bind]
  split <;> rfl

end Lanius.Extraction.CompactDecode
