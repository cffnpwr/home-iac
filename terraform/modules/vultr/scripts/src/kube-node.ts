import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { detachIso, getIsoState } from "./vultr-iso.ts";

// NOTE: 新しいインスタンスの作成と再起動の待機時間
const WAIT_READY_TIMEOUT = Temporal.Duration.from({ minutes: 15 });
const WAIT_READY_INTERVAL = Temporal.Duration.from({ seconds: 10 });

const mode = process.argv[2];
if (mode !== "wait-ready" && mode !== "delete" && mode !== "detach-iso") {
  console.error(`Invalid mode: ${JSON.stringify(mode)}, expected "wait-ready", "delete" or "detach-iso"`);
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

let instanceId = "";
let vultrApiKey = "";
if (mode === "detach-iso") {
  if (!("instance_id" in input) || typeof input.instance_id !== "string" || input.instance_id === "") {
    console.error("Input value does not have instance_id");
    process.exit(1);
  }
  if (process.env.VULTR_API_KEY === undefined || process.env.VULTR_API_KEY === "") {
    console.error("Environment variable VULTR_API_KEY is not set");
    process.exit(1);
  }
  instanceId = input.instance_id;
  vultrApiKey = process.env.VULTR_API_KEY;
}

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

const getBootId = async () => {
  const result = await kubectl("get", "node", nodeName, "--output", "jsonpath={.status.nodeInfo.bootID}");
  if (result.exitCode !== 0 || result.stdout.trim() === "") {
    console.error(`Failed to get boot ID of node ${nodeName}: ${result.stderr.trim()}`);

    return undefined;
  }

  return result.stdout.trim();
};

const waitRebooted = async (previousBootId: string) => {
  const deadline = Temporal.Now.instant().add(WAIT_READY_TIMEOUT);
  while (Temporal.Instant.compare(Temporal.Now.instant(), deadline) < 0) {
    const bootId = await getBootId();
    if (bootId !== undefined && bootId !== previousBootId) {
      return await waitReady();
    }
    await Bun.sleep(WAIT_READY_INTERVAL.total("milliseconds"));
  }
  console.error(`Node ${nodeName} did not reboot within ${WAIT_READY_TIMEOUT.total("seconds")}s`);

  return false;
};

const detachNodeIso = async () => {
  let isoState = await getIsoState(vultrApiKey, instanceId);
  while (isoState === "isomounting") {
    await Bun.sleep(WAIT_READY_INTERVAL.total("milliseconds"));
    isoState = await getIsoState(vultrApiKey, instanceId);
  }
  switch (isoState) {
    case "ready":
      console.log(`Instance ${instanceId} has no ISO attached`);

      return true;
    case "isomounted": {
      const bootId = await getBootId();
      if (bootId === undefined) {
        return false;
      }
      await detachIso(vultrApiKey, instanceId);
      console.log(`Detached ISO from instance ${instanceId}, waiting for node ${nodeName} to reboot`);

      return await waitRebooted(bootId);
    }
  }
};

let succeeded = false;
try {
  if (await fetchKubeconfig()) {
    switch (mode) {
      case "wait-ready":
        succeeded = await waitReady();
        break;
      case "delete":
        succeeded = await deleteNode();
        break;
      case "detach-iso":
        succeeded = await detachNodeIso();
        break;
    }
  }
} finally {
  await cleanup();
}
process.exit(succeeded ? 0 : 1);
