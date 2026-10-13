// The upstream installer prompts via /dev/tty even when stdin is redirected.
// A new session has no controlling terminal, so activation uses its defaults.
const { spawnSync } = require("node:child_process");

const result = spawnSync(process.argv[2], process.argv.slice(3), {
  detached: true,
  stdio: ["ignore", "inherit", "inherit"],
  env: { ...process.env, TERM: "dumb" },
});

if (result.error) {
  console.error(result.error.message);
}
process.exit(result.status ?? 1);
