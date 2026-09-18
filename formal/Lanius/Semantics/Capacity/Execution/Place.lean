import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem place (valid : config.Valid) (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.place allowed input = true)
    (evaluated : evalPlace (fuel + 1) program before input = .done result after) :
    evalPlace (fuel + 1) program (state config before) input = .done (resolvedPlace config result) (state config after) ∧
      Ready config after ∧ PlaceReady config result := by
  cases input with
  | «local» id =>
    simp only [evalPlace, show (state config before).cellId? id = before.cellId? id from rfl] at evaluated ⊢
    cases found : before.cellId? id with
    | none => simp [found] at evaluated
    | some root =>
      have lower := ready.localCell found
      have reachable : config.reachable root = true := by simp [Config.reachable, lower]
      have different : root ≠ config.root := Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le valid.old lower))
      simp only [found, cellEntry] at evaluated ⊢
      cases selected : before.cellEntry? root with
      | none => simp [selected] at evaluated
      | some entry =>
        have sameId : entry.id = root := by simpa using List.find?_some selected
        simp only [selected, Outcome.done.injEq] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        refine ⟨?_, ready, reachable, fun same => False.elim (different same), ?_⟩
        · cases entry with
          | mk cellId contents =>
            change cellId = root at sameId
            cases contents <;> simp [selected, cell, resolvedPlace, sameId, stored_reachable config reachable different]
        · intro entryValue initialized
          change entry.value = some entryValue at initialized
          exact ready.cellClosed reachable (by simp [State.cell?, selected, initialized])
  | field base field =>
    simp only [evalPlace] at evaluated ⊢
    cases baseRun : evalPlace fuel program before base with
    | done resolved next =>
      obtain ⟨transport, nextReady, placeReady⟩ := step.place ready (show Fragment.place allowed base = true from supported) baseRun
      rw [transport]
      simp only [baseRun] at evaluated
      cases contents : resolved.value with
      | none => simp [contents] at evaluated
      | some entry =>
        cases entry <;> simp only [contents] at evaluated
        all_goals try contradiction
        case «structure» id fields =>
          cases selected : fields[field]? with
          | none => simp [selected] at evaluated
          | some entry =>
            simp only [selected, Outcome.done.injEq] at evaluated
            obtain ⟨rfl, rfl⟩ := evaluated
            refine ⟨by simp [resolvedPlace, contents, value, selected], nextReady, placeReady.reachable, ?_, ?_⟩
            · intro _; simp
            · intro result same
              cases same
              exact (closeds_iff config fields).mp (placeReady.contents _ contents) entry (List.mem_of_getElem? selected)
    | _ => simp [baseRun] at evaluated
  | index base indexExpression =>
    have parts : Fragment.place allowed base = true ∧ Fragment.expression allowed indexExpression = true := by
      simpa only [Fragment.place, Bool.and_eq_true] using supported
    simp only [evalPlace] at evaluated ⊢
    cases baseRun : evalPlace fuel program before base with
    | done resolved afterBase =>
      obtain ⟨transport, baseReady, placeReady⟩ := step.place ready parts.1 baseRun
      rw [transport]
      simp only [baseRun] at evaluated
      cases contents : resolved.value with
      | none => simp [contents] at evaluated
      | some entry =>
        cases entry <;> simp only [contents] at evaluated
        all_goals try contradiction
        case array elements =>
          simp only [resolvedPlace, contents, Option.map_some, value]
          cases indexRun : evalExpr fuel program afterBase indexExpression with
          | done indexValue afterIndex =>
            obtain ⟨indexTransport, indexReady, _⟩ := step.expression baseReady parts.2 indexRun
            rw [indexTransport]
            simp only [indexRun] at evaluated
            simp only [integerIndex]
            cases converted : Semantics.integerIndex indexValue with
            | error reason => simp [converted] at evaluated
            | ok index =>
              simp only [converted] at evaluated ⊢
              cases selected : elements[index]? with
              | none => simp [selected] at evaluated
              | some entry =>
                simp only [selected, Outcome.done.injEq] at evaluated
                obtain ⟨rfl, rfl⟩ := evaluated
                refine ⟨by simp [selected, resolvedPlace], indexReady, placeReady.reachable, ?_, ?_⟩
                · intro _; simp
                · intro result same
                  cases same
                  exact (closeds_iff config elements).mp (placeReady.contents _ contents) entry (List.mem_of_getElem? selected)
          | _ => simp [indexRun] at evaluated
        case slice type root path start length =>
          have reachable : config.reachable root = true := placeReady.contents _ contents
          simp only [resolvedPlace, contents, Option.map_some, value]
          cases indexRun : evalExpr fuel program afterBase indexExpression with
          | done indexValue afterIndex =>
            obtain ⟨indexTransport, indexReady, _⟩ := step.expression baseReady parts.2 indexRun
            rw [indexTransport]
            simp only [indexRun] at evaluated
            simp only [integerIndex]
            cases converted : Semantics.integerIndex indexValue with
            | error reason => simp [converted] at evaluated
            | ok index =>
              simp only [converted] at evaluated ⊢
              split at evaluated
              · rename_i inside
                have expandedInside := Nat.lt_of_lt_of_le inside (extent_le config root path length)
                change index < (if root = config.root ∧ path = [] then length + config.tail.length else length) at expandedInside
                rw [if_pos expandedInside]
                cases read : sliceValues afterIndex root path start length with
                | error reason => simp [read] at evaluated
                | ok elements =>
                  simp only [read] at evaluated
                  cases selected : elements[index]? with
                  | none => simp [selected] at evaluated
                  | some entry =>
                    obtain ⟨expanded, readTransport, selectedTransport, entryClosed⟩ := slice_index config indexReady reachable inside read selected
                    simp only [extent] at readTransport
                    simp only [readTransport, selectedTransport]
                    simp only [selected, Outcome.done.injEq] at evaluated
                    obtain ⟨rfl, rfl⟩ := evaluated
                    refine ⟨rfl, indexReady, reachable, ?_, ?_⟩
                    · intro _; simp
                    · intro result same; cases same; exact entryClosed
              · contradiction
          | _ => simp [indexRun] at evaluated
    | _ => simp [baseRun] at evaluated

end Lanius.Semantics.Capacity.Execution
