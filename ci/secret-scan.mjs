#!/usr/bin/env node
// ci/secret-scan.mjs — a committed, dependency-free secret scan, not a container pull.
//
// Why not gitleaks: the runner reaches ghcr (ghcr.io/cirruslabs/flutter:stable pulls green on
// both apps), but an anonymous manifest probe of the gitleaks image could not confirm a tag, and
// shipping a job whose image cannot be resolved produces a pipeline that is red for a reason
// unrelated to the code. This fleet already hand-rolls its OSV client (ci/dep-audit.mjs) for the
// same reason: a gate you cannot resolve is a gate you cannot trust. The cost of this choice is
// coverage — gitleaks has ~150 rules and entropy analysis; this has the patterns below — and the
// cost is stated rather than hidden.
//
// Observational first: the job runs with allow_failure: true and prints a count. Turning it into
// a door is a decision for after the first count exists, not before it.
//
// Nothing here ever prints a matched value. A secret reaching a log line is the exact incident
// class this scanner exists to catch (a runners_token once arrived in a transcript).
//
//   node ci/secret-scan.mjs                 scan this repo's history, print findings
//   node ci/secret-scan.mjs --selftest      prove the scan can fire, then exit
//
// Exit codes: 0 = scan completed (findings or not — it is observational), 9 = the scanner itself
// is broken (git missing, self-test failing). A broken scanner must not look like a clean repo.

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const PATTERNS = [
  ["gitlab-pat", /\bglpat-[A-Za-z0-9_-]{14,}\b/g],
  ["aws-access-key", /\b(AKIA|ASIA)[0-9A-Z]{16}\b/g],
  ["private-key-block", /-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY(?: BLOCK)?-----/g],
  ["credentials-in-url", /\b(?:https?|git|ssh|ftp):\/\/[^\s/'":@]{1,64}:[^\s/'"@]{6,}@[^\s/]+/g],
  // `Authorization: Bearer <tok>` has NO colon after Bearer — requiring one made this rule
  // decorative, and the self-test caught it: a pattern that never fires is worse than no pattern
  // because the report says "scanned".
  ["bearer-token", /\bBearer\s+["']?[A-Za-z0-9+/.=_-]{20,}/gi],
  ["token-header", /\bAuthorization\s*:\s*(?:Basic|Token)\s+["']?[A-Za-z0-9+/.=_-]{12,}/gi],
  ["secret-assignment", /["']?(?:private[_-]?token|access[_-]?token|api[_-]?key|secret[_-]?key|password|passwd)["']?\s*[:=]\s*["'][^"'\s]\S{6,}["']/gi],
  // The quoted rule above cannot see an env file (`LB_SIGNING_PASSWORD=…`). This variant is
  // deliberately narrow — uppercase env key, secret-ish suffix, literal value — because matching
  // unquoted assignments generally would flag every YAML scalar in the repo and the noise would
  // bury the one line that matters.
  ["env-secret-assignment", /^[+-]?\s*(?:export\s+)?[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|ACCESS_KEY)[A-Z0-9_]*=(?!\$|\{|<)[^\s]{8,}/gm],
];
// Files whose job is to contain the shapes we look for. Excluding the scanner from its own
// findings is not hiding a finding; the self-test still exercises every pattern.
const SKIP = [/ci\/secret-scan\.(mjs|js)$/, /(^|\/)\.git\//, /\.(png|jpg|jpeg|gif|webp|ttf|woff2?|ap_?k|jar|zip|lock)$/i];
const MAX_DIFF_BYTES = 48 << 20;   // work bound, not memory bound
const CAP = Number(process.env.SECRET_SCAN_CAP || 800);   // commits read; the tip is not where removed values live   // bound the work; a truncated scan says so instead of claiming zero

function redact(s) {
  const head = s.slice(0, 4).replace(/[^A-Za-z0-9]/g, "?");
  return `${head}…(${s.length} chars, redacted)`;
}
// `http://admin:admin@localhost` is a shape every dev repo contains. Filtering it is only honest
// if the filter announces itself, so skipped candidates are counted and printed.
// Skipping a candidate is a decision to be blind to something, so the rule is the narrowest one
// that removes the noise a dev repo actually contains: the password is a known placeholder, the
// password repeats the username, or it is too short to be a real key. A GENERIC USERNAME IS NOT A
// REASON TO SKIP — the first version of this filter skipped anything whose user was "user", which
// would have hidden `user:sekrit123@192.168.1.98`, the exact shape this fleet leaked. The
// self-test caught it; the positive sample below is that line.
const PLACEHOLDER_WORDS = /^(?:admin|pass|password|secret|test|testing|demo|sample|changeme|dummy|example|placeholder|xxx+|12345\d*)$/;
let skippedPlaceholder = 0, skippedInterpolated = 0;
function isPlaceholderUserinfo(rest) {
  const i = rest.indexOf(":");
  if (i < 0) return false;
  const u = rest.slice(0, i).toLowerCase(), pw = rest.slice(i + 1);
  if (!pw || pw.length < 8) return true;
  if (u && pw.toLowerCase() === u) return true;
  // A shell interpolation is a template, not a value: `http://user:$TOKEN@host` is the CI line
  // that WRITES a credential, and it appears six times in the vault's history. Reporting it as a
  // leaked secret every build would train everyone to ignore the report, so it is filtered here —
  // and counted, because "6 shapes were skipped" is information the reader needs. The write sites
  // themselves are a separate finding, and pass4 D6c already counts them by write-pattern.
  if (pw.includes("$") || u.includes("$")) { skippedInterpolated++; return true; }
  return PLACEHOLDER_WORDS.test(pw);
}
function scanText(text, where, out) {
  for (const [name, re] of PATTERNS) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (name === "credentials-in-url") {
        const rest = m[0].slice(m[0].indexOf("://") + 3);
        if (isPlaceholderUserinfo(rest.slice(0, rest.lastIndexOf("@") > 0 ? rest.lastIndexOf("@") : rest.length))) { skippedPlaceholder++; continue; }
      }
      out.push({ pattern: name, where, match: redact(m[0]) });
      if (m.index === re.lastIndex) re.lastIndex++;
    }
  }
}

function selftest() {
  const dir = fs.mkdtempSync("/tmp/secret-scan-selftest-");
  let fired = 0;
  try {
    for (const [name, re] of PATTERNS) {
      // One synthetic sample per pattern: if a rule never fires, the scan is decorative.
      const sample = {
        "gitlab-pat": "x glpat-AbCdEf1234567890XYZ y",
        "aws-access-key": "AKIA1234567890ABCDEF",
        "private-key-block": "-----BEGIN OPENSSH PRIVATE KEY-----",
        "credentials-in-url": "http://user:sekrit123@192.168.1.98/x",   // generic user, real-shaped pw
        "bearer-token": "Authorization: Bearer abcdef0123456789ABCDEF0123",
        "token-header": "Authorization: Basic dXNlcjpwYXNzd29yZDEyMzQ1",
        "secret-assignment": 'password = "hunter2hunter2"',
        "env-secret-assignment": "export LB_SIGNING_PASSWORD=Sup3rSecretValue",
      }[name];
      const out = [];
      scanText(sample, `selftest:${name}`, out);
      const hit = out.some((f) => f.pattern === name);
      console.log(`SECRET-SCAN|selftest ${name}: ${hit ? "fires" : "DID NOT FIRE"}`);
      if (hit) fired++;
    }
    // Negative control: the clean text must score zero, or the rules are noise.
    const clean = [
      'password = process.env.LB_FAKE_PASSWORD',
      "url = 'http://192.168.1.98/api/v4'",
      "api = 'http://admin:admin@localhost:8080/x'",           // placeholder userinfo, filtered
      "db = 'postgres://vault:vault@10.0.0.1/db'",             // password repeats the user, filtered
      "db = 'postgres://svc:password@10.0.0.1/db'",            // password is a placeholder word, filtered
      "API_URL=https://api.steinerdevelopers.dev/v1",          // env-shaped but not a secret suffix
      "glpat-notarealvalue",                                   // too short for the pattern
      "git = 'http://ciuser:$CAPTURE_CI_TOKEN@192.168.1.98'", // interpolated template, filtered
      '{"a":1}',
    ].join("\n");
    const cout = [];
    scanText(clean, "selftest:clean", cout);
    console.log(`SECRET-SCAN|selftest clean-text findings: ${cout.length} ${cout.length === 0 ? "(expected 0)" : "— RULES TOO BROAD: " + cout.map((f) => f.pattern).join(",")}`);
    if (fired !== PATTERNS.length || cout.length !== 0) {
      console.log("SECRET-SCAN|FAULT self-test failed — a scan that cannot fire, or fires on nothing, must not report a clean repo");
      process.exit(9);
    }
    console.log(`SECRET-SCAN|selftest ok: ${fired}/${PATTERNS.length} patterns fire, clean text scores zero`);
    process.exit(0);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
if (process.argv.includes("--selftest")) selftest();

const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const SELF = path.relative(root, path.resolve(new URL(import.meta.url).pathname));
const skip = (p) => SKIP.some((r) => r.test(p)) || p === SELF;

const findings = [];
let commitsScanned = 0, commitsSeen = 0, truncated = false, bytes = 0;
try {
  // -U0 keeps the diff to changed lines; --no-color because a highlight break splits a secret.
  // %x02 lets git emit the separator; asking JS to splice control characters into a format string
  // is how the commit column ended up holding the subject line.
  // -c core.quotePath=false: without it git escapes any non-ASCII path, and the report would name
  // a file that does not exist. Only added lines are scanned; binary additions are not decoded
  // (a secret compiled into an asset is out of scope for a text scan). Memory is bounded by
  // maxBuffer — the byte cap below bounds the WORK, so a repo larger than the buffer is a FAULT
  // with a message, not a quiet zero.
  const log = execFileSync("git", ["-c", "core.quotePath=false", "log", "-p", "-U0", "--no-color", "--all", `--max-count=${CAP}`, "--format=%x02%h %s"], { encoding: "utf8", maxBuffer: 96 << 20 });
  let curFile = "", curSha = "";
  for (const line of log.split("\n")) {
    if (line.startsWith("\x02")) { curSha = line.slice(1).split(" ")[0]; commitsSeen++; continue; }
    // git writes "+++ b/<path>\t<timestamp>": strip at whitespace. Stripping at "/t" (the first
    // attempt) truncated app/test/... to "app", which would have made every finding in the test
    // lane point at a directory that is not a file.
    if (line.startsWith("+++ b/")) { curFile = line.slice(6).split(/\s/)[0].replace(/^b\//, ""); continue; }
    if (!line.startsWith("+") || line.startsWith("+++")) continue;
    bytes += line.length;
    if (skip(curFile)) continue;
    if (bytes > MAX_DIFF_BYTES) { truncated = true; break; }
    commitsScanned++;
    scanText(line.slice(1), `${curFile}@${curSha}`, findings);
  }
} catch (e) {
  console.log(`SECRET-SCAN|FAULT cannot read history: ${e.message} — reporting zero findings here would be a lie`);
  process.exit(9);
}

const byPattern = {};
for (const f of findings) byPattern[f.pattern] = (byPattern[f.pattern] || 0) + 1;
for (const f of findings.slice(0, 25)) console.log(`SECRET-SCAN|${f.pattern} in ${f.where} :: ${f.match}`);
console.log(`SECRET-SCAN|findings=${findings.length} across ${Object.keys(byPattern).length} pattern(s): ${Object.entries(byPattern).map(([k, v]) => `${k}=${v}`).join(", ") || "none"}`);
// The cap counts COMMITS; lines are a different number and comparing them was a real bug — it
// printed "cap nearly hit" from 66,695 lines against an 800-commit cap.
console.log(`SECRET-SCAN|scanned ${commitsSeen} commit(s), ${commitsScanned} added line(s), cap ${CAP}${commitsSeen >= CAP ? " — CAP REACHED: history is deeper than this scan; the count above is a floor, raise SECRET_SCAN_CAP or accept the bound" : ""}${skippedPlaceholder ? `; ${skippedPlaceholder} placeholder credential URL(s) filtered (password repeats user / known placeholder / under 8 chars)` : ""}${skippedInterpolated ? `; ${skippedInterpolated} interpolated URL(s) like http://user:$TOKEN@host skipped as templates — those lines are credential WRITE sites, counted by pass4 D6c, not leaked values` : ""}`);
if (truncated) console.log(`SECRET-SCAN|TRUNCATED at ${Math.round(bytes >> 20)} MiB of diff — the count above is a floor, not a total`);
fs.writeFileSync("secret-scan.json", JSON.stringify({ ts: new Date().toISOString(), findings, truncated, patterns: PATTERNS.map((p) => p[0]) }, null, 2) + "\n");
console.log(`SECRET-SCAN|artifact secret-scan.json written (${findings.length} findings; values redacted)`);
console.log("SECRET-SCAN|status=observational — allow_failure is set on this job; a count, not yet a door");
process.exit(0);
