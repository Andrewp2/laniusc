// Per-scalar UTS #46 behaviour of the JavaScript runtime's URL host parser.
// stdin: a JSON array of code points, or [] for planes 0-3 and 14 (the other
// planes have no assigned scalars). For each non-ASCII scalar c, parse the
// hosts x+c, c, U+05D0+c and U+05D0+c+U+05D0, and print "HEX FLAGS HOSTNAME":
// FLAGS has one 0/1 per probe and HOSTNAME is the first successful probe's
// hostname (or "-"). The contexts separate leading-mark rejection and the
// Bidi_Class groups {R AL AN}, {EN NSM}, {ES CS ET ON BN} and {L}.
"use strict";
const probes = [(c) => "x" + c, (c) => c, (c) => "א" + c, (c) => "א" + c + "א"];
const chunks = [];
process.stdin.on("data", (chunk) => chunks.push(chunk));
process.stdin.on("end", () => {
  let points = JSON.parse(Buffer.concat(chunks).toString("utf8") || "[]");
  if (points.length === 0) {
    for (let cp = 0x80; cp < 0x40000; cp++) points.push(cp);
    for (let cp = 0xe0000; cp < 0xf0000; cp++) points.push(cp);
  }
  const lines = [];
  for (const cp of points) {
    if (cp < 0x80 || (cp >= 0xd800 && cp <= 0xdfff)) continue;
    const c = String.fromCodePoint(cp);
    let flags = "", first = "-";
    for (const probe of probes) {
      let host = null;
      try { host = new URL("http://" + probe(c) + "/").hostname; } catch (error) { host = null; }
      flags += host === null ? "0" : "1";
      if (host !== null && first === "-") first = host;
    }
    lines.push(cp.toString(16).toUpperCase() + " " + flags + " " + first);
    if (lines.length >= 65536) { process.stdout.write(lines.join("\n") + "\n"); lines.length = 0; }
  }
  if (lines.length) process.stdout.write(lines.join("\n") + "\n");
});
