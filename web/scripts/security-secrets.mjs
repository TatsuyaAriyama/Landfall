import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const repositoryRoot = resolve(import.meta.dirname, "../..");
const tracked = execFileSync("git", ["ls-files", "-z"], {
  cwd: repositoryRoot,
  encoding: "utf8",
}).split("\0").filter(Boolean);

const secretPatterns = [
  { name: "Stripe live secret key", value: /\bsk_live_[A-Za-z0-9]{16,}\b/g },
  { name: "Stripe live restricted key", value: /\brk_live_[A-Za-z0-9]{16,}\b/g },
  { name: "Stripe webhook secret", value: /\bwhsec_[A-Za-z0-9]{16,}\b/g },
  {
    name: "Google service account private key",
    value: new RegExp(["-----BEGIN", "PRIVATE KEY-----"].join(" "), "g"),
  },
];

const findings = [];
for (const file of tracked) {
  let body;
  try {
    body = readFileSync(resolve(repositoryRoot, file), "utf8");
  } catch {
    continue;
  }
  for (const pattern of secretPatterns) {
    if (pattern.value.test(body)) findings.push(`${file}: ${pattern.name}`);
    pattern.value.lastIndex = 0;
  }
}

if (findings.length > 0) {
  console.error("Potential committed secrets found:");
  for (const finding of findings) console.error(`- ${finding}`);
  process.exit(1);
}

console.log(`Secret scan passed (${tracked.length} tracked files).`);
