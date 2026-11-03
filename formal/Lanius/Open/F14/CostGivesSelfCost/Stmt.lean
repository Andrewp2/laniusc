import Lanius.Faithful.SelfBounded

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.X86.Machine
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfDriver
open Lanius.Faithful.SelfCompiler
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.SelfAgree
open Lanius.Faithful.SelfShort
open Lanius.Faithful.Termination
open Lanius.Faithful.SelfBounded
open Lanius.Faithful.SelfTotal

/-- A wrapped compile (`costW`, `plus` and `times` wrapping) of fewer than
`2 ^ 31` words that costs under `2 ^ 61` gives the self program's compile a
cost at the same fuel. With it, a compile with no cost has a wrapped cost
past any heap limit below `2 ^ 61`, which replaces the panic reason. -/
def Lanius.Open.CostGivesSelfCost : Prop :=
  ∀ (W : List (BitVec 32)), W.length < 2 ^ 31 →
    ∀ N k, costW N W = some k → k < 2 ^ 61 → ∃ c, selfCost N W = some c
