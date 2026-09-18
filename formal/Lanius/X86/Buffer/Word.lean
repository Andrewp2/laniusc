import Lanius.X86.Buffer.Reservation
import Lanius.X86.Word.Core
import Lanius.Separation.SliceStore

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source

def byteAt (word : Int) (lane : Nat) : Int := word / (2 ^ (lane * 8) : Nat) % 256

def writtenFrom (position : Nat) (word : Int) (lane : Nat) (count : Nat)
    (values : List Int) : List Int :=
  match count with
  | 0 => values
  | count + 1 => writtenFrom position word (lane + 1) count
      (values.set (position + lane) (byteAt word lane))

def writtenWord (values : List Int) (position : Nat) (word : Int) : List Int :=
  writtenFrom position word 0 4 values

/-- Read emitted bytes from the compiler's one-i32-per-byte output buffer.
Callers establish that the selected slots contain bytes. -/
def byteSlice (values : List Int) (position count : Nat) : List UInt8 :=
  ((values.drop position).take count).map (fun value => UInt8.ofNat value.toNat)

theorem byteSlice_get (within : index < count) :
    (byteSlice values position count)[index]? =
      values[position + index]?.map (fun value => UInt8.ofNat value.toNat) := by
  simp only [byteSlice, List.getElem?_map, List.getElem?_take_of_lt within, List.getElem?_drop]

@[simp] theorem writtenFrom_length :
    (writtenFrom position word lane count values).length = values.length := by
  induction count generalizing lane values with
  | zero => rfl
  | succ count ih => simp only [writtenFrom, ih, List.length_set]

@[simp] theorem writtenWord_length : (writtenWord values position word).length = values.length :=
  writtenFrom_length

theorem writtenFrom_frame (outside : index < position + lane ∨ position + lane + count ≤ index) :
    (writtenFrom position word lane count values)[index]? = values[index]? := by
  induction count generalizing lane values with
  | zero => rfl
  | succ count ih =>
      rw [writtenFrom, ih (by omega), List.getElem?_set_ne (by omega)]

theorem writtenWord_frame (outside : index < position ∨ position + 4 ≤ index) :
    (writtenWord values position word)[index]? = values[index]? :=
  writtenFrom_frame (by simpa using outside)

theorem writtenWord_lane (room : position + 4 ≤ values.length) (bound : lane < 4) :
    (writtenWord values position word)[position + lane]? = some (byteAt word lane) := by
  have cases : lane = 0 ∨ lane = 1 ∨ lane = 2 ∨ lane = 3 := by omega
  have h0 : position < values.length := by omega
  have h1 : position + 1 < values.length := by omega
  have h2 : position + 2 < values.length := by omega
  have h3 : position + 3 < values.length := by omega
  rcases cases with rfl | rfl | rfl | rfl <;>
    simp [writtenWord, writtenFrom, h0, h1, h2, h3]

/-- The four resulting i32 slots contain the exact little-endian bytes of the
Core word, not merely the output of another copy of the store algorithm. -/
theorem writtenWord_bytes (room : position + 4 ≤ values.length) :
    ((writtenWord values position word).drop position).take 4 =
      (i32Bytes word).map (fun byte => (byte.toNat : Int)) := by
  apply List.ext_getElem?
  intro lane
  by_cases bound : lane < 4
  · rw [List.getElem?_take_of_lt bound, List.getElem?_drop, writtenWord_lane room bound]
    rw [List.getElem?_map, Lanius.Extraction.Input.shifted_byte_is_storage_byte word lane bound]
    have nonnegative : 0 ≤ byteAt word lane := Int.emod_nonneg _ (by decide)
    have small : byteAt word lane < 256 := Int.emod_lt_of_pos _ (by decide)
    have smallNat : (byteAt word lane).toNat < 256 := by omega
    change some (byteAt word lane) = some ((UInt8.ofNat (byteAt word lane).toNat).toNat : Int)
    congr 1
    rw [UInt8.toNat_ofNat']
    omega
  · rw [List.getElem?_eq_none (by simp only [List.length_take]; omega)]
    rw [List.getElem?_eq_none (by simp only [List.length_map, i32Bytes_length]; omega)]

theorem writtenWord_byteSlice (room : position + 4 ≤ values.length) :
    byteSlice (writtenWord values position word) position 4 = i32Bytes word := by
  simp only [byteSlice, writtenWord_bytes room, List.map_map]
  change (i32Bytes word).map (fun byte => UInt8.ofNat byte.toNat) = i32Bytes word
  simp only [UInt8.ofNat_toNat]
  exact List.map_id _

/-- Decode the bytes produced by the source word-store and calculate the
architectural near-transfer target. No intended displacement is supplied to
the decoder. Opcode decoding and executable-target validity remain separate. -/
theorem writtenWord_target (base : Int) (field target : Nat)
    (room : field + 4 ≤ values.length) (fieldBound : field + 4 ≤ 2147483647)
    (targetBound : target ≤ 2147483647) :
    nearTarget (BitVec.ofInt 64 (base + (field + 4 : Nat)))
      (BitVec.ofInt 32 (decodeI32 (byteSlice
        (writtenWord values field (relativeDisplacement (field + 4) target)) field 4))) =
      BitVec.ofInt 64 (base + target) := by
  rw [writtenWord_byteSlice room]
  obtain ⟨lower, upper⟩ := relativeDisplacement_fits (field + 4) target fieldBound targetBound
  rw [Lanius.Extraction.Input.decode_encoded_i32_value _ lower (by omega)]
  exact nearTarget_relocated base (field + 4) target fieldBound targetBound

structure WordResources (state : State) (cell : CellId) (position : Nat)
    (word : Int) (values : List Int) : Prop where
  wellFormed : StateWellFormed state
  sliceRead : state.local? 0 = some (.slice i32 cell [] 0 values.length)
  positionRead : state.local? 1 = some (.signed .i32 position)
  wordRead : state.local? 2 = some (.signed .i32 word)
  backing : state.cellEntry? cell = some {
    id := cell, value := some (.array (signedI32Values values)) }

private theorem mask_low_byte (target : Target) (word : Int) :
    evalSignedBinary target .bitAnd .i32 word 255 = .ok (.signed .i32 (word % 256)) := by
  have normalized : wrapSigned target .i32 word % 4294967296 = word % 4294967296 := by
    change (if word % 4294967296 ≥ 2147483648 then word % 4294967296 - 4294967296
      else word % 4294967296) % 4294967296 = word % 4294967296
    split <;> omega
  have result := Lanius.Extraction.Input.mask_low_byte target word
  change (Except.ok (.signed .i32 (wrapSigned target .i32
    (Nat.land (wrapSigned target .i32 word % 4294967296).toNat 255 : Nat))) :
    Except Lanius.Trap Value) = _ at result
  rw [normalized] at result
  exact result

theorem word_byte (program : Program) (word : Int) (lane : Nat) (bound : lane < 4)
    (wordRead : before.local? 2 = some (.signed .i32 word)) :
    Evaluates program before (wordByte lane) (.signed .i32 (byteAt word lane)) before := by
  by_cases zero : lane = 0
  · subst lane
    simp only [wordByte, ↓reduceIte, byteAt, Nat.zero_mul, Nat.pow_zero, Int.natCast_one, Int.ediv_one]
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program wordRead)
      (show Evaluates program before (number 255) (.signed .i32 255) before from ⟨1, rfl⟩)
    simpa only [evalBinaryValue, BEq.rfl, ↓reduceIte] using mask_low_byte program.target word
  · simpa only [wordByte, if_neg zero, byteAt, Source.read, Source.number,
      show ((255 : Nat) : Int) = 255 from rfl] using
      Lanius.Extraction.Input.evaluates_unpacked_byte word lane bound
        (local_evaluates program wordRead)
        (show Evaluates program before (number (lane * 8)) (.signed .i32 (lane * 8 : Nat)) before from ⟨1, rfl⟩)

theorem word_index (program : Program) (position lane : Nat)
    (bounded : position + lane ≤ 2147483647)
    (positionRead : before.local? 1 = some (.signed .i32 position)) :
    Evaluates program before (wordIndex lane) (.signed .i32 (position + lane : Nat)) before := by
  by_cases zero : lane = 0
  · simpa only [wordIndex, zero, ↓reduceIte, Nat.add_zero] using local_evaluates program positionRead
  · simpa only [wordIndex, if_neg zero, Source.read, Source.number, Int.ofNat_eq_natCast] using evaluatesNatI32Add
      (local_evaluates program positionRead)
      (show Evaluates program before (number lane) (.signed .i32 lane) before from ⟨1, rfl⟩) bounded

theorem store_lane (program : Program) (resources : WordResources before cell position word values)
    (lane : Nat) (bound : lane < 4) (room : position + 4 ≤ values.length)
    (representable : position + 4 ≤ 2147483647) :
    ∃ after, Evaluates program before (wordStore lane) .unit after ∧
      WordResources after cell position word (values.set (position + lane) (byteAt word lane)) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, store, contents, effect, heapFrame, _⟩ := evaluatesSliceStore program before before
    values 0 (wordIndex lane) (wordByte lane) cell (position + lane) (byteAt word lane)
    resources.wellFormed (by omega) resources.sliceRead
    (word_index program position lane (by omega) resources.positionRead)
    (word_byte program word lane bound resources.wordRead)
    (CellEffect.refl resources.wellFormed) resources.backing
  refine ⟨after, store, ⟨effect.wellFormed, ?_, ?_, ?_, contents⟩, effect, heapFrame⟩
  · simpa only [List.length_set] using effect.preserves_local_of_distinct_value resources.wellFormed
      resources.sliceRead resources.backing (by intro same; cases same)
  · exact effect.preserves_local_of_distinct_value resources.wellFormed
      resources.positionRead resources.backing (by intro same; cases same)
  · exact effect.preserves_local_of_distinct_value resources.wellFormed
      resources.wordRead resources.backing (by intro same; cases same)

theorem stores (program : Program) (resources : WordResources before cell position word values)
    (lane count : Nat) (bound : lane + count ≤ 4) (room : position + 4 ≤ values.length)
    (representable : position + 4 ≤ 2147483647) :
    ∃ after, Executes program before (wordStatements lane count)
        (.returned (some (.signed .i32 (position + 4 : Nat)))) after ∧
      WordResources after cell position word (writtenFrom position word lane count values) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  induction count generalizing lane before values with
  | zero =>
      have next := evaluatesNatI32Add (local_evaluates program resources.positionRead)
        (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩) representable
      exact ⟨before, executesSequenceReturned (executesReturnValue next), resources,
        CellEffect.refl resources.wellFormed, HeapFrame.refl before⟩
  | succ count ih =>
      obtain ⟨middle, first, middleResources, firstEffect, firstHeap⟩ :=
        store_lane program resources lane (by omega) room representable
      obtain ⟨after, rest, afterResources, restEffect, restHeap⟩ :=
        ih middleResources (lane + 1) (by omega) (by simpa only [List.length_set] using room)
      exact ⟨after, executesSequence (executesExpression first) rest, afterResources,
        firstEffect.trans restEffect, firstHeap.trans restHeap⟩

def wordValues (output : Value) (position : Nat) (word : Int) : List Value :=
  [output, .signed .i32 position, .signed .i32 word]

def wordBindings (output : Value) (position : Nat) (word : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 3 => (wordValues output position word).get index)

/-- Execute the source-authenticated four stores and return the next cursor.
The source word may be negative. Spare buffer contents need not be zero. -/
theorem word_call (checked : CheckedWord program) (position : Nat) (word : Int)
    (wellFormed : StateWellFormed before) (room : position + 4 ≤ values.length)
    (representable : position + 4 ≤ 2147483647)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (wordValues (.slice i32 cell [] 0 values.length) position word) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (position + 4 : Nat)) after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (writtenWord values position word))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let bindings := wordBindings (.slice i32 cell [] 0 values.length) position word
  have locals (index : Fin 3) : (enterCall before bindings).local? index.val =
      some ((wordValues (.slice i32 cell [] 0 values.length) position word).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before bindings).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  let resources : WordResources (enterCall before bindings) cell position word values :=
    ⟨enterCall_preserves_wellFormed wellFormed, locals ⟨0, by decide⟩,
      locals ⟨1, by decide⟩, locals ⟨2, by decide⟩, calleeBacking⟩
  obtain ⟨completed, run, afterResources, effect, heapFrame⟩ :=
    stores program.core resources 0 4 (by decide) room representable
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, afterResources.backing, called.2,
    HeapFrame.closeCall before bindings heapFrame⟩

end Lanius.X86.Buffer
