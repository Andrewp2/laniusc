import Lanius.X86.Lower.Operation.Arithmetic
import Lanius.X86.Buffer.Writer

namespace Lanius.X86.Lower.Operation.Arithmetic

open Lanius.Core Lanius.X86.Buffer

theorem attempt {parent : Source.Operation.Checked emitters} (checked : Source.Operation.Arithmetic.Checked parent)
    (operation : Machine.Alu) (capacity : Nat) (before : Writer.Result)
    (storage : capacity ≤ before.values.length) (bounded : capacity ≤ 2147483647) :
    Writer.Spec emitters.pack.program.core parent.internal.source.function.id
      (inputs (.slice Source.i32 cell [] 0 before.values.length) capacity before.cursor operation)
      cell before (before.append capacity 2 (fun values start => writtenBytes values start (Encode.Arithmetic.config operation 0 1).bytes)) := by
  apply Writer.reserve
  · intro start cursor room
    have size : (Encode.Arithmetic.config operation 0 1).size = 2 := by cases operation <;> rfl
    constructor
    intro caller expressions state wellFormed evaluated backing
    obtain ⟨after, run, output, effect, heap⟩ := (succeeds checked operation capacity start room storage bounded).call
      wellFormed (by simpa only [cursor] using evaluated) backing
    exact ⟨after, by simpa only [size] using run, output.1, effect, heap⟩
  · exact rejects checked operation _ capacity before.cursor (by omega)

end Lanius.X86.Lower.Operation.Arithmetic
