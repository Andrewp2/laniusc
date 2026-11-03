# HomedCorrReturn

- 11-03 (leafA): the return wrapper. The conjunction of HomedCorrKeeps (the caller's locals and references),
  HomesLeave (the caller's homes) and HoldsAtDropHomes (the result). With stage 1's `HoldsAt.ref`, a returned
  reference is a `HoldsAt` too, so `RefTo.drop` needs no statement of its own.
