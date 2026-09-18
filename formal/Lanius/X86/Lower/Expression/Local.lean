import Lanius.X86.Lower.Expression.Local.Input
import Lanius.X86.Lower.Expression.Local.Emit
import Lanius.X86.Lower.Expression.Wrapper

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The actual local-expression call performs lexical lookup, emits the load,
and restores TOP. Preconditions describe syntax, storage and layout, never execution. -/
theorem compiles {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Local.Checked literal) (c : Context) (valid : c.Valid)
    (binding : Binding c width key slot) (source : Syntax c key) :
    c.Emits emitters.pack.program.core literal.wrapper.source.function.id (Value.Get.kind width)
      (Value.Get.bytes width slot) (afterLocal width c.workspace c.position c.start slot) := by
  have sameTop : (afterLocal width c.workspace c.position c.start slot)[6]? = some c.top := by
    simpa only [afterLocal, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using valid.topFound
  simpa only [Context.Emits, Wrapper.finish_eq sameTop] using
    Wrapper.call literal c (Value.Get.kind width) _ _ valid.topFound (by simp [afterLocal])
      (emit_call checked c valid binding source)

end Lanius.X86.Lower.Expression.Local
