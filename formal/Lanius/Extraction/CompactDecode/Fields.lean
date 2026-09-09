import Lanius.Extraction.CompactDecode.Hex
import Lanius.Extraction.CompactOutput.Tokens.Write

namespace Lanius.Extraction.CompactDecode

open CompactOutput
open Lanius.Compiler.Lexer

theorem readToken_encoding (token : RawToken)
    (kindFit : token.kind.gpuCode < 4294967296)
    (startFit : token.start < 4294967296) (finishFit : token.finish < 4294967296)
    (encoded : EncodedAt bytes offset (Tokens.encoding token)) :
    readToken.run { bytes := bytes, offset := offset } =
      some (⟨token.kind.gpuCode, ⟨0, token.start, token.finish⟩⟩,
        { bytes := bytes, offset := offset + 24 }) := by
  have kind := readU32_hex kindFit encoded.left.left
  have start := readU32_hex startFit encoded.left.right
  have finish := readU32_hex finishFit encoded.right
  simp only [hexDigits_length, List.length_append] at start finish
  simp only [readToken, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at kind start finish
  rw [kind]
  simp only [Option.bind_some]
  rw [start]
  simp only [Option.bind_some]
  rw [finish]
  simp [StateT.pure, pure, Nat.add_assoc]

theorem readSemanticKind_fields (firstFit : first < 4294967296) (secondFit : second < 4294967296)
    (encoded : EncodedAt bytes offset (hexDigits first 8 ++ hexDigits second 8)) :
    readSemanticKind.run { bytes := bytes, offset := offset } =
      some ((if second = 0 then first else 2147483648 + first + (second - 1) * 32768),
        { bytes := bytes, offset := offset + 16 }) := by
  have firstRead := readU32_hex firstFit encoded.left
  have secondRead := readU32_hex secondFit encoded.right
  simp only [hexDigits_length] at secondRead
  simp only [readSemanticKind, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at firstRead secondRead
  rw [firstRead]
  simp only [Option.bind_some]
  rw [secondRead]
  simp only [Option.bind_some]
  split <;> simp_all [StateT.pure, pure, Nat.add_assoc]

theorem readChild_fields (tagFit : tag = 1 ∨ tag = 2) (payloadFit : payload < 4294967296)
    (encoded : EncodedAt bytes offset (hexDigits tag 8 ++ hexDigits payload 8)) :
    readChild.run { bytes := bytes, offset := offset } =
      some ((if tag = 1 then ParseChild.token payload else ParseChild.node payload),
        { bytes := bytes, offset := offset + 16 }) := by
  have tagRead := readU32_hex (by omega : tag < 4294967296) encoded.left
  have payloadRead := readU32_hex payloadFit encoded.right
  simp only [hexDigits_length] at payloadRead
  simp only [readChild, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at tagRead payloadRead
  rw [tagRead]
  simp only [Option.bind_some]
  rw [payloadRead]
  simp only [Option.bind_some]
  rcases tagFit with rfl | rfl <;> simp [StateT.pure, pure, Nat.add_assoc]

end Lanius.Extraction.CompactDecode
