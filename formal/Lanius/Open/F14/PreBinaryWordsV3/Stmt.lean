import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `binary_words`'s precondition, at any budget, for any program's compile.
Replaces `PreBinaryWordsV2`. Why it holds: `compileSource` returns a binary only
when its image is within `image_limit` (`2 ^ 30`). `compile_program` checks
this as the sizes add up (`room_after`, SEMANTIC_DECISIONS "The image limit
checked as the sizes add up"). Every count `binary_words` adds up is below
`2 ^ 31`: `pack_round`'s and `round_join`'s byte counts, the entries and the
word count. Its fuel (`2 ^ 20` rounds of 4096 words) covers the image. -/
def Lanius.Open.PreBinaryWordsV3 : Prop :=
  ∀ (p : Lanius.Mini.SrcProgram) (n b : Nat), Pre_binary_words n (Lanius.Mini.compileSource p) b
