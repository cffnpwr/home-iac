import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// NOTE: 新しいインスタンスの作成と再起動の待機時間
const WAIT_READY_TIMEOUT = Temporal.Duration.from({ minutes: 15 });
const WAIT_READY_INTERVAL = Temporal.Duration.from({ seconds: 10 });

const mode = process.argv[2];
if (mode !== "wait-ready" && mode !== "delete") {
  console.error(`Invalid mode: ${JSON.stringify(mode)}, expected "wait-ready" or "delete"`);
  process.exit(1);
}

const input: unknown = await Bun.stdin.json();

if (typeof input !== "object" || input === null) {
  console.error("Invalid input value: not an object");
  process.exit(1);
}
if (!("node_name" in input) || typeof input.node_name !== "string" || input.node_name === "") {
  console.error("Input value does not have node_name");
  process.exit(1);
}
if (!("talosconfig" in input) || typeof input.talosconfig !== "string" || input.talosconfig === "") {
  console.error("Input value does not have talosconfig");
  process.exit(1);
}
if (!("talos_endpoint" in input) || typeof input.talos_endpoint !== "string" || input.talos_endpoint === "") {
  console.error("Input value does not have talos_endpoint");
  process.exit(1);
}
const nodeName = input.node_name;
const talosEndpoint = input.talos_endpoint;

const credentialsDir = await mkdtemp(join(tmpdir(), "kube-node-"));
const cleanup = () => rm(credentialsDir, { recursive: true, force: true });
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, async () => {
    await cleanup();
    process.exit(1);
  });
}
const talosconfigPath = join(credentialsDir, "talosconfig");
const kubeconfigPath = join(credentialsDir, "kubeconfig");
await writeFile(talosconfigPath, input.talosconfig, { mode: 0o600 });

const run = async (command: string[]) => {
  const proc = Bun.spawn(command, {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { stdout, stderr, exitCode };
};

const kubectl = (...args: string[]) => run(["kubectl", "--kubeconfig", kubeconfigPath, ...args]);

const fetchKubeconfig = async () => {
  const result = await run([
    "talosctl",
    "--talosconfig",
    talosconfigPath,
    "--endpoints",
    talosEndpoint,
    "--nodes",
    talosEndpoint,
    "kubeconfig",
    "--merge=false",
    kubeconfigPath,
  ]);
  if (result.exitCode !== 0) {
    console.error(`Failed to fetch kubeconfig from ${talosEndpoint}: ${result.stderr.trim()}`);
    return false;
  }
  return true;
};

const waitReady = async () => {
  const deadline = Temporal.Now.instant().add(WAIT_READY_TIMEOUT);
  let lastStatus = "";
  while (Temporal.Instant.compare(Temporal.Now.instant(), deadline) < 0) {
    const result = await kubectl(
      "get",
      "node",
      nodeName,
      "--output",
      "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}",
    );
    if (result.exitCode === 0 && result.stdout.trim() === "True") {
      console.log(`Node ${nodeName} is Ready`);
      return true;
    }
    lastStatus = result.exitCode === 0 ? `Ready=${result.stdout.trim()}` : result.stderr.trim();
    await Bun.sleep(WAIT_READY_INTERVAL.total("milliseconds"));
  }
  console.error(`Node ${nodeName} did not become Ready within ${WAIT_READY_TIMEOUT.total("seconds")}s, last status: ${lastStatus}`);
  return false;
};

const deleteNode = async () => {
  const result = await kubectl("delete", "node", nodeName, "--ignore-not-found", "--wait");
  if (result.exitCode !== 0) {
    console.error(`Failed to delete node ${nodeName}: ${result.stderr.trim()}`);
    return false;
  }
  console.log(`Node ${nodeName} is deleted or did not exist`);
  return true;
};

let succeeded = false;
try {
  if (await fetchKubeconfig()) {
    succeeded = mode === "wait-ready" ? await waitReady() : await deleteNode();
  }
} finally {
  await cleanup();
}
process.exit(succeeded ? 0 : 1);
