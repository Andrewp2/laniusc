import Lanius.Basic

namespace Lanius.Compiler.Phase

/- A compiler phase may decline to produce an output.  `Except e β` phases
   can use `Option` after their error is discharged by a separate contract. -/
abbrev Partial (α β : Type) := α → Option β

def compose (second : Partial β γ) (first : Partial α β) : Partial α γ :=
  fun input => first input >>= second

/- Success contracts deliberately say nothing about failures or publication. -/
def Refines (spec : α → β → Prop) (phase : Partial α β) : Prop :=
  ∀ ⦃input output⦄, phase input = some output → spec input output

def Complete (spec : α → β → Prop) (phase : Partial α β) : Prop :=
  ∀ ⦃input⦄, (∃ output, spec input output) →
    ∃ output, phase input = some output ∧ spec input output

def Progress (ready : α → Prop) (phase : Partial α β) : Prop :=
  ∀ ⦃input⦄, ready input → ∃ output, phase input = some output

/- `published` denotes an externally visible artifact for this invocation. -/
def FailureSafe (published : α → Prop) (phase : Partial α β) : Prop :=
  ∀ ⦃input⦄, phase input = none → ¬ published input

def RelComp (first : α → β → Prop) (second : β → γ → Prop) : α → γ → Prop :=
  fun input output => ∃ middle, first input middle ∧ second middle output

theorem refines_compose
    (first : Partial α β) (second : Partial β γ)
    (firstSpec : α → β → Prop) (secondSpec : β → γ → Prop)
    (wholeSpec : α → γ → Prop)
    (hFirst : Refines firstSpec first) (hSecond : Refines secondSpec second)
    (bridge : ∀ ⦃input middle output⦄,
      firstSpec input middle → secondSpec middle output → wholeSpec input output) :
    Refines wholeSpec (compose second first) := by
  intro input output result
  cases hFirstRun : first input with
  | none => simp [compose, hFirstRun] at result
  | some middle =>
    have hSecondRun : second middle = some output := by
      simpa [compose, hFirstRun] using result
    exact bridge (hFirst hFirstRun) (hSecond hSecondRun)

theorem complete_compose
    (first : Partial α β) (second : Partial β γ)
    (firstSpec : α → β → Prop) (secondSpec : β → γ → Prop)
    (hFirst : Complete firstSpec first) (hSecond : Complete secondSpec second)
    (secondTotal : ∀ ⦃input middle⦄, firstSpec input middle →
      ∃ output, secondSpec middle output) :
    Complete (RelComp firstSpec secondSpec) (compose second first) := by
  intro input expected
  rcases expected with ⟨output, middle, hFirstSpec, _⟩
  rcases hFirst ⟨middle, hFirstSpec⟩ with ⟨middle', hFirstRun, hFirstSpec'⟩
  rcases secondTotal hFirstSpec' with ⟨output', hSecondSpec⟩
  rcases hSecond ⟨output', hSecondSpec⟩ with ⟨output'', hSecondRun, hSecondSpec'⟩
  exact ⟨output'', by simp [compose, hFirstRun, hSecondRun], middle',
    hFirstSpec', hSecondSpec'⟩

theorem progress_compose
    (first : Partial α β) (second : Partial β γ) (ready : α → Prop)
    (middleReady : β → Prop)
    (hFirst : Progress ready first)
    (hMiddle : ∀ ⦃input middle⦄, ready input → first input = some middle → middleReady middle)
    (hSecond : Progress middleReady second) :
    Progress ready (compose second first) := by
  intro input hReady
  rcases hFirst hReady with ⟨middle, hFirstRun⟩
  rcases hSecond (hMiddle hReady hFirstRun) with ⟨output, hSecondRun⟩
  exact ⟨output, by simp [compose, hFirstRun, hSecondRun]⟩

end Lanius.Compiler.Phase
