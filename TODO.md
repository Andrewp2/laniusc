# TODO

## GPU Prefix Scans

- Upgrade delimiter rank assignment to a true segmented prefix scan. The current
  lexer close-retag path already does the important GPU-side parallel prefix
  scans for delimiter depth and count offsets; rank assignment is kept as a
  deterministic transitional pass so parser work can continue.

## Parser

- Replace the current witness-projected partial-parse table with a real LLP
  table construction pass. The grammar now covers the current file/function/
  block/statement/type/expression surface and the CPU parser accepts that
  surface, but the GPU production stream is still a projection rather than a
  complete accepting parse.
- Add parse acceptance/error reporting so random parser fuzz can distinguish
  valid trees from partial-parse forests instead of only checking stream
  consistency.
