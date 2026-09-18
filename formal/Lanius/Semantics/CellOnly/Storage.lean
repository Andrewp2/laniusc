import Lanius.Semantics.CellOnly.Step

namespace Lanius.Semantics.CellOnly

open Lanius.Core Lanius.Separation

theorem argumentsFrame (step : Step fuel program allowed)
    (supported : expressions allowed inputs = true)
    (evaluated : evalExprs (fuel + 1) program before inputs = .done result after) :
    HeapFrame before after := by
  cases inputs with
  | nil => cases evaluated; exact HeapFrame.refl _
  | cons input rest =>
    simp only [expressions, Bool.and_eq_true] at supported
    simp only [evalExprs] at evaluated
    repeat' first | split at evaluated | contradiction
    all_goals
      obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
      exact (step.expression supported.1 (by assumption)).trans (step.expressions supported.2 (by assumption))

theorem placeFrame (step : Step fuel program allowed)
    (supported : place allowed input = true)
    (evaluated : evalPlace (fuel + 1) program before input = .done result after) :
    HeapFrame before after := by
  cases input with
  | «local» id =>
    simp only [evalPlace] at evaluated
    repeat' first | split at evaluated | contradiction
    all_goals cases evaluated; exact HeapFrame.refl _
  | field base field =>
    simp only [place] at supported
    simp only [evalPlace] at evaluated
    repeat' first | split at evaluated | contradiction
    all_goals
      obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
      exact step.place supported (by assumption)
  | index base index =>
    simp only [place, Bool.and_eq_true] at supported
    simp only [evalPlace] at evaluated
    repeat' first | split at evaluated | contradiction
    all_goals
      obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
      exact (step.place supported.1 (by assumption)).trans (step.expression supported.2 (by assumption))

end Lanius.Semantics.CellOnly
