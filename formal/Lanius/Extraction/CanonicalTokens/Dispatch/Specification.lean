import Lanius.Extraction.CanonicalTokens.Dispatch.Branches
import Lanius.Compiler.LexerCanonical

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core

abbrev Row := List Int × Int

def lookup (query : List Int) : List Row → Int → Int
  | [], fallback => fallback
  | row :: rest, fallback => if query = row.1 then row.2 else lookup query rest fallback

def groupRows (program : Program) (group : Group) : List Row :=
  group.rules.map fun rule =>
    ((rule.spelling group.width).map (fun byte => (byte.toNat : Int)), tag program rule.kind)

def rows (program : Program) (groups : List Group) : List Row :=
  groups.flatMap (groupRows program)

def referenceRows : List Row := Lanius.Compiler.Lexer.keywordRules.map fun rule =>
  (rule.spelling.map Int.ofNat, Int.ofNat rule.kind.gpuCode)

theorem lookup_append (query : List Int) (left right : List Row) (fallback : Int) :
    lookup query (left ++ right) fallback = lookup query left (lookup query right fallback) := by
  induction left with
  | nil => rfl
  | cons row rest ih => simp [lookup, ih]

theorem selected_lookup (program : Program) (source : List Int) (start width : Nat)
    (rules : List Rule) (fallback : Int)
    (valid : ∀ rule ∈ rules, ValidRule program width rule)
    (capacity : start + width ≤ source.length) :
    (selected program source start width rules).getD fallback =
      lookup ((source.drop start).take width) (groupRows program ⟨width, rules⟩) fallback := by
  induction rules with
  | nil => rfl
  | cons rule rest ih =>
      have headValid := valid rule (by simp)
      have tailValid := fun candidate member => valid candidate (List.mem_cons_of_mem rule member)
      have spanAgreement := Ascii.matchesBytes_iff_span source start (rule.spelling width)
        (by simpa only [headValid.spelling_length] using capacity)
      rw [headValid.spelling_length] at spanAgreement
      by_cases same : (source.drop start).take width =
          (rule.spelling width).map (fun byte => (byte.toNat : Int))
      · have yes := spanAgreement.mpr same
        simp [selected, yes, groupRows, lookup, same]
      · have no : Ascii.matchesBytes source start (rule.spelling width) = false := by
          apply Bool.eq_false_iff.mpr
          intro yes
          exact same (spanAgreement.mp yes)
        simpa only [selected, no, Bool.false_eq_true, ↓reduceIte, groupRows,
          List.map_cons, lookup, if_neg same] using ih tailValid

theorem lookup_wrong_width (program : Program) (group : Group) (query : List Int) (fallback : Int)
    (valid : ∀ rule ∈ group.rules, ValidRule program group.width rule)
    (different : query.length ≠ group.width) :
    lookup query (groupRows program group) fallback = fallback := by
  obtain ⟨width, rules⟩ := group
  induction rules with
  | nil => rfl
  | cons rule rest ih =>
      have head := valid rule (by simp)
      have unequal : query ≠ (rule.spelling width).map (fun byte => (byte.toNat : Int)) := by
        intro same
        apply different
        simpa only [List.length_map, head.spelling_length] using congrArg List.length same
      simpa only [groupRows, List.map_cons, lookup, if_neg unequal] using
        ih (fun candidate member => valid candidate (List.mem_cons_of_mem rule member)) different

/-- Length dispatch is an optimization of ordinary exact-spelling lookup,
not a different keyword specification. -/
theorem dispatched_lookup (program : Program) (source : List Int) (start width : Nat)
    (fallback : ConstantId) (groups : List Group)
    (valid : ∀ group ∈ groups, ∀ rule ∈ group.rules, ValidRule program group.width rule)
    (capacity : start + width ≤ source.length) :
    dispatched program source start width fallback groups =
      lookup ((source.drop start).take width) (rows program groups) (tag program fallback) := by
  induction groups with
  | nil => rfl
  | cons group rest ih =>
      have head := valid group (by simp)
      have tail := fun candidate member => valid candidate (List.mem_cons_of_mem group member)
      simp only [rows, List.flatMap_cons, lookup_append, dispatched]
      by_cases same : width = group.width
      · rw [if_pos same, ih tail]
        have result := selected_lookup program source start group.width group.rules
          (lookup ((source.drop start).take width) (rows program rest) (tag program fallback))
          head (by simpa only [same] using capacity)
        simpa only [same, groupRows, rows] using result
      · rw [if_neg same, lookup_wrong_width program group _ _ head]
        · exact ih tail
        · have queryLength : ((source.drop start).take width).length = width := by
            simp only [List.length_take, List.length_drop]
            omega
          simpa only [queryLength] using same

end Lanius.Extraction.CanonicalTokens.Dispatch
