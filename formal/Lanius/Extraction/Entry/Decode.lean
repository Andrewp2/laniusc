import Lanius.Extraction.Entry.Word
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.Entry.Hex

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

def byteExpression (word : Expr) (lane : Nat) : Expr :=
  .binary .bitAnd (if lane = 0 then word else
    .binary .shiftRight word (.value (.signed .i32 (lane * 8 : Nat))))
    (.value (.signed .i32 255))

theorem evaluatesByte (word : Int) (lane : Nat) (laneBound : lane < 4)
    (nonnegative : 0 ≤ word) (bounded : word ≤ 2147483647)
    (evaluated : Evaluates program before expression (.signed .i32 word) before) :
    Evaluates program before (byteExpression expression lane)
      (.signed .i32 (word / (2 ^ (lane * 8) : Nat) % 256)) before := by
  by_cases zero : lane = 0
  · subst lane
    simp only [byteExpression, if_pos rfl, Nat.zero_mul, Nat.pow_zero, Int.natCast_one, Int.ediv_one]
    apply evaluatesEagerBinary (by decide) (by decide) evaluated
      (show Evaluates program before (.value (.signed .i32 255)) (.signed .i32 255) before from evaluatesValue)
    have masked := Input.mask_low_byte program.target word
    rw [wrapSigned_i32_of_nonnegative program.target word nonnegative bounded] at masked
    simpa only [evalBinaryValue, BEq.rfl, if_true] using masked
  · simp only [byteExpression, if_neg zero]
    exact Input.evaluates_unpacked_byte word lane laneBound evaluated evaluatesValue

theorem Checked.decodeLane (checked : Checked program) (word : Int) (lane digit : Nat)
    (laneBound : lane < 4) (digitBound : digit < 16)
    (nonnegative : 0 ≤ word) (bounded : word ≤ 2147483647)
    (digitMatch : word / (2 ^ (lane * 8) : Nat) % 256 = hexDigit digit)
    (wellFormed : StateWellFormed before)
    (evaluated : Evaluates program.core before expression (.signed .i32 word) before) :
    ∃ after, Evaluates program.core before
      (.call checked.source.function.id [byteExpression expression lane]) (.signed .i32 digit) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have byte := evaluatesByte word lane laneBound nonnegative bounded evaluated
  rw [digitMatch] at byte
  exact checked.decode digit digitBound wellFormed (.cons byte (.nil _ _))

def wordExpression (function : Lanius.FunctionId) (binding : Lanius.VarId) : Expr :=
  let digit := fun lane => Expr.call function [byteExpression (.local binding) lane]
  .binary .bitOr
    (.binary .bitOr
      (.binary .bitOr (.binary .shiftLeft (digit 0) (.value (.signed .i32 12)))
        (.binary .shiftLeft (digit 1) (.value (.signed .i32 8))))
      (.binary .shiftLeft (digit 2) (.value (.signed .i32 4)))) (digit 3)

theorem Checked.decodeWord (checked : Checked program) (word : Int) (binding : Lanius.VarId)
    (a b c d : Nat) (ha : a < 16) (hb : b < 16) (hc : c < 16) (hd : d < 16)
    (nonnegative : 0 ≤ word) (bounded : word ≤ 2147483647)
    (firstDigit : word % 256 = hexDigit a)
    (secondDigit : word / 256 % 256 = hexDigit b)
    (thirdDigit : word / 65536 % 256 = hexDigit c)
    (fourthDigit : word / 16777216 % 256 = hexDigit d)
    (wellFormed : StateWellFormed before)
    (found : before.local? binding = some (.signed .i32 word)) :
    ∃ after, Evaluates program.core before (wordExpression checked.source.function.id binding)
      (.signed .i32 (a * 4096 + b * 256 + c * 16 + d : Nat)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨one, first, firstEffect, firstHeap⟩ := checked.decodeLane word 0 a (by decide) ha nonnegative bounded
    (by simpa using firstDigit) wellFormed (local_evaluates program.core found)
  have readOne := firstEffect.empty_preserves_local wellFormed found
  obtain ⟨two, second, secondEffect, secondHeap⟩ := checked.decodeLane word 1 b (by decide) hb nonnegative bounded
    (by simpa using secondDigit) firstEffect.wellFormed (local_evaluates program.core readOne)
  have readTwo := secondEffect.empty_preserves_local firstEffect.wellFormed readOne
  obtain ⟨three, third, thirdEffect, thirdHeap⟩ := checked.decodeLane word 2 c (by decide) hc nonnegative bounded
    (by simpa using thirdDigit) secondEffect.wellFormed (local_evaluates program.core readTwo)
  have readThree := thirdEffect.empty_preserves_local secondEffect.wellFormed readTwo
  obtain ⟨after, fourth, fourthEffect, fourthHeap⟩ := checked.decodeLane word 3 d (by decide) hd nonnegative bounded
    (by simpa using fourthDigit) thirdEffect.wellFormed (local_evaluates program.core readThree)
  exact ⟨after, evaluatesWord a b c d ha hb hc hd first second third fourth,
    firstEffect.trans (secondEffect.trans (thirdEffect.trans fourthEffect)),
    firstHeap.trans (secondHeap.trans (thirdHeap.trans fourthHeap))⟩

def packedDigits (a b c d : Nat) : Nat :=
  hexDigit a + hexDigit b * 256 + hexDigit c * 65536 + hexDigit d * 16777216

theorem digitBounds (value : Nat) (bounded : value < 16) :
    48 ≤ hexDigit value ∧ hexDigit value ≤ 102 := by
  unfold hexDigit
  split <;> omega

theorem Checked.decodePackedWord (checked : Checked program) (binding : Lanius.VarId)
    (a b c d : Nat) (ha : a < 16) (hb : b < 16) (hc : c < 16) (hd : d < 16)
    (wellFormed : StateWellFormed before)
    (found : before.local? binding = some (.signed .i32 (packedDigits a b c d))) :
    ∃ after, Evaluates program.core before (wordExpression checked.source.function.id binding)
      (.signed .i32 (a * 4096 + b * 256 + c * 16 + d : Nat)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have ba := digitBounds a ha
  have bb := digitBounds b hb
  have bc := digitBounds c hc
  have bd := digitBounds d hd
  apply checked.decodeWord (packedDigits a b c d) binding a b c d ha hb hc hd
    (by omega) (by unfold packedDigits; omega)
    (by unfold packedDigits; omega) (by unfold packedDigits; omega)
    (by unfold packedDigits; omega) (by unfold packedDigits; omega) wellFormed found

def packedWord (value : Nat) : Nat :=
  packedDigits (value / 4096) (value / 256 % 16) (value / 16 % 16) (value % 16)

theorem Checked.decodeValue (checked : Checked program) (binding : Lanius.VarId)
    (value : Nat) (bounded : value < 65536) (wellFormed : StateWellFormed before)
    (found : before.local? binding = some (.signed .i32 (packedWord value))) :
    ∃ after, Evaluates program.core before (wordExpression checked.source.function.id binding)
      (.signed .i32 value) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have reconstruction : value / 4096 * 4096 + value / 256 % 16 * 256 +
      value / 16 % 16 * 16 + value % 16 = value := by omega
  obtain ⟨after, evaluated, effect, heapFrame⟩ := checked.decodePackedWord binding
    (value / 4096) (value / 256 % 16) (value / 16 % 16) (value % 16)
    (by omega) (by omega) (by omega) (by omega) wellFormed found
  exact ⟨after, reconstruction ▸ evaluated, effect, heapFrame⟩

theorem Checked.storeValue (checked : Checked program) (binding destination : Lanius.VarId)
    (values : List Int) (cell : Lanius.CellId) (index value : Nat) (indexExpression : Expr)
    (bounded : value < 65536) (wellFormed : StateWellFormed before)
    (found : before.local? binding = some (.signed .i32 (packedWord value)))
    (inBounds : index < values.length)
    (sliceLocal : before.local? destination = some (.slice i32 cell [] 0 values.length))
    (indexResult : Evaluates program.core before indexExpression (.signed .i32 index) before)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Evaluates program.core before
      (.assign .set (.index (.local destination) indexExpression)
        (wordExpression checked.source.function.id binding)) .unit after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (values.set index value))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨decoded, evaluated, effect, decodeHeap⟩ := checked.decodeValue binding value bounded wellFormed found
  obtain ⟨after, assigned, contents, effect, storeHeap, _⟩ := evaluatesSliceStore program.core before decoded values destination indexExpression
    (wordExpression checked.source.function.id binding) cell index value wellFormed inBounds
    sliceLocal indexResult evaluated effect backing
  exact ⟨after, assigned, contents, effect, decodeHeap.trans storeHeap⟩

end Lanius.Extraction.Entry.Hex
