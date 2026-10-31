import { spawnSync } from "node:child_process";
import path from "node:path";

// NOTE: JavaScriptのactionは、inputを`INPUT_<大文字にしたinputの名前>`の環境変数で受け取る
const result = spawnSync("bash", [path.join(import.meta.dirname, "up.sh")], {
  stdio: "inherit",
  env: {
    ...process.env,
    SETUP_KEY: process.env["INPUT_SETUP-KEY"],
    WAIT_ADDRESS: process.env["INPUT_WAIT-ADDRESS"],
  },
});
process.exitCode = result.status ?? 1;
