import Lanius.Extraction.Entry.Prefix
import Lanius.Extraction.Entry.Framing

namespace Lanius.Extraction.Entry
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- New startup locals. Buffer and pointer names outside this list remain
live while grammar decoding and output framing allocate their temporaries. -/
def startupLocals (literal : Grammar.LiteralStage) (framing : Framing.Stage) : List VarId :=
  [literal.setup.text, literal.setup.cursor.locals.source, literal.setup.cursor.locals.cursor,
    framing.opening, framing.closing, framing.position]

/-- The original allocated slices and pointer aliases remain available at
the file loop. Array contents may change, and helpers may add borrowed views. -/
structure Retained (literal : Grammar.LiteralStage) (framing : Framing.Stage)
    (before after : State) : Prop where
  views : ∀ view ∈ before.i32ArrayViews, view ∈ after.i32ArrayViews
  bindings : ∀ id, id ∉ startupLocals literal framing → after.cellId? id = before.cellId? id
  locals : ∀ id, id ∉ startupLocals literal framing → ∀ value,
    (∀ elements, value ≠ .array elements) →
    before.local? id = some value → after.local? id = some value

theorem Retained.buffer (kept : Retained literal framing before after)
    (history : Allocation.HostReady buffers initial allocated)
    (aliases : Pointers.AliasFrame pointerAliases allocated before)
    (registry : Allocation.Registry before) (finalRegistry : Allocation.Registry after)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (buffer : Allocation.Buffer) (member : buffer ∈ buffers)
    (notAlias : buffer.binding ∉ pointerAliases.map Pointers.Alias.name)
    (notStartup : buffer.binding ∉ startupLocals literal framing) :
    ∃ view values, view ∈ before.i32ArrayViews ∧ view ∈ after.i32ArrayViews ∧
      view.length = buffer.count ∧ (values : List Int).length = buffer.count ∧
      before.local? buffer.binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 buffer.count) ∧
      after.local? buffer.binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 values.length) ∧
      after.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values values)) } :=
  Pointers.retainedBuffer history aliases registry finalRegistry names buffer member notAlias kept.views
    (kept.locals buffer.binding notStartup)

end Lanius.Extraction.Entry
