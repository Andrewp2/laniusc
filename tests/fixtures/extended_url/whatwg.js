// Reference results from the JavaScript runtime's WHATWG URL implementation.
// stdin: a JSON array of [input, base-or-null]. stdout: a JSON array whose
// items are ["ok", href, protocol, username, password, host, hostname, port,
// pathname, search, hash, origin], ["fail"] or ["base-fail"].
"use strict";
const chunks = [];
process.stdin.on("data", (chunk) => chunks.push(chunk));
process.stdin.on("end", () => {
  const cases = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const results = cases.map(([input, base]) => {
    if (base !== null && !URL.canParse(base)) return ["base-fail"];
    let url;
    try { url = base === null ? new URL(input) : new URL(input, base); } catch (error) { return ["fail"]; }
    return ["ok", url.href, url.protocol, url.username, url.password, url.host, url.hostname, url.port,
      url.pathname, url.search, url.hash, url.origin];
  });
  process.stdout.write(JSON.stringify(results));
});
