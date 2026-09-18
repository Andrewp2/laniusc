import Lanius.X86.Encode.Direct
import Lanius.X86.Buffer.Writer

namespace Lanius.X86.Encode.Direct

open Lanius.Core Lanius.X86.Buffer

theorem attempt (checked : Source.CheckedRegisterWrapper program form kind) (width : Register.Width)
    (destination source : Fin 16) (capacity : Nat) (before : Writer.Result)
    (storage : capacity ≤ before.values.length) (bounded : capacity ≤ 2147483647) :
    Writer.Spec program.core checked.source.function.id
      (inputs kind (.slice Source.i32 cell [] 0 before.values.length) capacity before.cursor width.bits destination.val source.val)
      cell before (before.append capacity (config kind width destination source).size
        (fun values start => writtenBytes values start (config kind width destination source).bytes)) := by
  apply Writer.reserve
  · intro start cursor room
    simpa only [Writer.Spec, Writer.Stored, cursor] using succeeds checked width destination source capacity start room storage bounded
  · exact rejects_capacity checked width destination source _ capacity before.cursor (by omega)

end Lanius.X86.Encode.Direct
