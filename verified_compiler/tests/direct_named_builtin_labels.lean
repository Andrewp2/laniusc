import GeneratedDirectCore

-- Source type names must not capture primitive labels in their own payloads.
example : _root_.Bool → Extracted.«app::main».Types.Bool :=
  Extracted.«app::main».Types.Bool.mk
example : _root_.String → Extracted.«app::main».Types.String :=
  Extracted.«app::main».Types.String.mk
