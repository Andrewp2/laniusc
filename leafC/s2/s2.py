"""S2: move the layout definitions RefHeld reaches into Mini/Layout.lean. Run from formal/."""
import re
M = 'Lanius/Mini/Refs/Model.lean'; S = 'Lanius/Mini/Source.lean'; L = 'Lanius/Mini/Layout.lean'
m = open(M).read(); s = open(S).read()
def cut(text, start, end):
    i = text.index(start); j = text.index(end, i)
    return text[:i] + text[j:], text[i:j]
# Access, bytes, narrow
m, access = cut(m, 'inductive Access where', '/-- `target` = the slot at `address`')
m, kinds = cut(m, '/-- How an element of an array of this type is packed', '/-- Two lists of widths')
m, subs = cut(m, '/-! ## Sub-places -/', '/-! ## Homes -/')
s, addressed = cut(s, '/-- A place a reference or a borrowed slice names', '/-- The static region as `str` values see it')
old_ptr = addressed[addressed.index('/-- The pointer of a slice'):]
addressed = addressed[:addressed.index('/-- The pointer of a slice')]
new_ptr = '''/-- The pointer of a slice of a sliced place in native layout: its lowest
byte for packed `i32` and `u8` elements, which run up from it, and its top
word for the others, whose words run down from it (SEMANTIC_DECISIONS
"References: the memory model" point 4). -/
def Addressed.pointer (x : Addressed) : Nat :=
  match x.ty with
  | .array .i32 _ => x.address
  | .array (.uint .uint8) _ => x.address
  | _ => x.address + 8 * (x.ty.words - 1)

'''
head = '''module

public import Lanius.Mini.SourceCore
import all Lanius.Mini.Compiler.P.Lists_empty

@[expose] public section

/-! # Native layout and references (F5, trusted)

The layout definitions a reference's representation reaches
(`SrcType.HoldsAt.ref`, `RefHeld`): how a value's words lie in memory
(`SrcType.words`, SEMANTIC_DECISIONS "References: the memory model" point 4),
where a field or element of it starts (`SrcType.sub`), the places references
name (`Addressed`) and what a reference's word is (`RefTo`, `RefHeld`, point
5). Moved here from `Refs/Model.lean` in stage 1 (S2), so that `HoldsAt` can
use them; the rest of the model (slots, homes, code) stays there.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)

/-! ## Accesses -/

/-- How one slot of a value is read and written in memory: one byte, or a
4- or 8-byte little-endian word. -/
'''
# access starts at 'inductive Access where'; Model had the docstring before it
doc = '''/-- How one slot of a value is read and written in memory: one byte, or a
4- or 8-byte little-endian word. -/
'''
assert doc in m
m = m.replace(doc, '', 1)
layout = head + access + kinds + '/-! ## Places -/\n\n' + addressed + new_ptr + subs + 'end Lanius.Mini\n'
open(L, 'w').write(layout)
open(M, 'w').write(m)
s = s.replace('public import Lanius.Mini.SourceCore\n', 'public import Lanius.Mini.SourceCore\npublic import Lanius.Mini.Layout\n', 1)
open(S, 'w').write(s)
print(old_ptr)
