import { spawnSync } from "node:child_process";

// NOTE: ephemeralのピアはオフラインが10分を超えるまで残るため、jobの終了時に削除
//       mainがnetbirdのサービスを起動する前に失敗した場合、STATE_netbirdは設定されない
const netbird = process.env.STATE_netbird;
if (netbird) {
  const result = spawnSync("sudo", [netbird, "deregister"], { stdio: "inherit" });
  if (result.status !== 0) {
    console.log("::warning::Could not deregister the NetBird peer. The ephemeral peer is removed after 10 minutes offline.");
  }
}
