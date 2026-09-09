import Lanius.Extraction.CompactOutput.Unit.State
import Lanius.Extraction.CompactOutput.Tokens.Call

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Lexer Lanius.Extraction.CanonicalTokens.CanonicalizeModel

theorem Owned.tokens (owned : Owned memory position contents before)
    (checked : Tokens.Checked program byte digit word) (inputId lengthId countId : VarId)
    (tokens : List RawToken) (inputLength sourceLength capacity : Nat)
    (inputNotCursor : inputId ≠ 19) (lengthNotCursor : lengthId ≠ 19) (countNotCursor : countId ≠ 19)
    (input : I32Prefix memory.base inputCell physicalCapacity (encodeTokens tokens))
    (inputRead : memory.base.local? inputId = some (.slice i32 inputCell [] 0 physicalCapacity))
    (lengthRead : memory.base.local? lengthId = some (.signed .i32 inputLength))
    (countRead : memory.base.local? countId = some (.signed .i32 tokens.length))
    (sourceRead : memory.base.local? 3 = some (.signed .i32 sourceLength))
    (distinct : memory.outputCell ≠ inputCell)
    (inputRoom : 3 * tokens.length ≤ inputLength) (lengthFit : inputLength ≤ 2147483647)
    (sourceFit : sourceLength ≤ 2147483647)
    (fields : ∀ token ∈ tokens, token.kind.gpuCode ≤ 2147483647 ∧ token.start ≤ token.finish ∧ token.finish ≤ sourceLength)
    (outputRead : memory.base.local? 16 = some (.slice i32 memory.outputCell [] 0 memory.initialContents.length))
    (capacityRead : memory.base.local? 17 = some (.signed .i32 capacity))
    (room : capacity ≤ memory.initialContents.length) (capacityFit : capacity ≤ 2147483647) :
    ∃ after, Evaluates program.core before
        (.assign .set (.local 19) (.call checked.source.function.id
          [read inputId, read lengthId, read countId, read 3, read 16, read 17, read 19])) .unit after ∧
      Owned memory (appendAll capacity (Tokens.encodeAll tokens) position contents).position
        (appendAll capacity (Tokens.encodeAll tokens) position contents).contents after ∧
      CellEffect memory.writes before after := by
  have output : before.local? 16 = some (.slice i32 memory.outputCell [] 0 contents.length) := by
    simpa only [owned.length] using owned.local (by decide) outputRead (by intro same; cases same)
  obtain ⟨written, run, backing, effect⟩ := checked.write tokens inputLength sourceLength capacity position owned.frame.wellFormed
    (owned.input input distinct) distinct inputRoom lengthFit sourceFit fields
    (by simpa only [owned.length] using room) capacityFit owned.backing
    (.cons (local_evaluates program.core (owned.local inputNotCursor inputRead (by intro same; cases same)))
      (.cons (local_evaluates program.core (owned.local lengthNotCursor lengthRead (by intro same; cases same)))
        (.cons (local_evaluates program.core (owned.local countNotCursor countRead (by intro same; cases same)))
          (.cons (local_evaluates program.core (owned.local (by decide) sourceRead (by intro same; cases same)))
            (.cons (local_evaluates program.core output) (.cons
              (local_evaluates program.core (owned.local (by decide) capacityRead (by intro same; cases same)))
              (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (.nil _ _))))))))
  exact owned.assign run effect backing (appendAll_length _ _ _ _)

end Lanius.Extraction.CompactOutput.Unit
