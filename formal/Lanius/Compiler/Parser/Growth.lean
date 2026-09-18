import Lanius.Compiler.ParserModel

namespace Lanius.Compiler.Parser

/-- Later-position processing cannot extend an earlier chart. State records
may still grow, so this is stronger than membership preservation but weaker
than equality of the whole workspace. -/
def ChartsUnchangedBefore (position : Nat) (before after : LogicalWorkspace) : Prop :=
  ∀ earlier, earlier < position → after.chart earlier = before.chart earlier

theorem ChartsUnchangedBefore.refl : ChartsUnchangedBefore position workspace workspace :=
  fun _ _ => rfl

theorem ChartsUnchangedBefore.trans
    (first : ChartsUnchangedBefore position before middle)
    (last : ChartsUnchangedBefore position middle after) :
    ChartsUnchangedBefore position before after :=
  fun earlier bound => (last earlier bound).trans (first earlier bound)

theorem ChartsUnchangedBefore.weaken (stable : ChartsUnchangedBefore position before after)
    (bound : earlier ≤ position) : ChartsUnchangedBefore earlier before after :=
  fun queried less => stable queried (Nat.lt_of_lt_of_le less bound)

theorem Append.chartsUnchangedBefore
    (appended : Append capacity position seed before outcome after)
    (bound : first ≤ position) : ChartsUnchangedBefore first before after := by
  intro earlier less
  cases appended with
  | existing => rfl
  | full => rfl
  | inserted =>
      exact appendChart_other before.chart (by omega)

theorem appendLogical_chartsUnchangedBefore (capacity position : Nat)
    (seed : StateSeed) (workspace : LogicalWorkspace) :
    ChartsUnchangedBefore position workspace (appendLogical capacity position seed workspace).2 :=
  (appendLogical_refines _ rfl).chartsUnchangedBefore (Nat.le_refl position)

end Lanius.Compiler.Parser
