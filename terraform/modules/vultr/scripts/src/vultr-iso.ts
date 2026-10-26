const VULTR_API_URL = "https://api.vultr.com/v2";
// NOTE: Terraformのapplyが応答の無い接続で止まり続けないための上限
const FETCH_TIMEOUT = Temporal.Duration.from({ seconds: 30 });
const ISO_STATES = ["ready", "isomounting", "isomounted"] as const;

export type IsoState = (typeof ISO_STATES)[number];

export class VultrApiError extends Error {
  override readonly name = "VultrApiError" as const;

  constructor(
    method: string,
    path: string,
    detail: string,
    options?: ErrorOptions,
  ) {
    super(`Vultr API ${method} ${path} failed: ${detail}`, options);
  }
}

const requestVultrApi = async (
  apiKey: string,
  method: "GET" | "POST",
  path: string,
): Promise<unknown> => {
  let response: Response;
  try {
    response = await fetch(`${VULTR_API_URL}${path}`, {
      method,
      headers: { Authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(FETCH_TIMEOUT.total("milliseconds")),
    });
  } catch (error) {
    throw new VultrApiError(method, path, "request error", { cause: error });
  }
  const body = await response.text();
  if (!response.ok) {
    throw new VultrApiError(method, path, `status ${response.status}, body ${body}`);
  }

  return body === "" ? undefined : JSON.parse(body);
};

export const getIsoState = async (
  apiKey: string,
  instanceId: string,
): Promise<IsoState> => {
  const path = `/instances/${instanceId}/iso`;
  const body = await requestVultrApi(apiKey, "GET", path);
  const state = typeof body === "object" && body !== null && "iso_status" in body
    && typeof body.iso_status === "object" && body.iso_status !== null && "state" in body.iso_status
    ? body.iso_status.state
    : undefined;
  const isoState = ISO_STATES.find((s) => s === state);
  if (isoState === undefined) {
    throw new VultrApiError("GET", path, `unexpected ISO state ${JSON.stringify(state)}, expected one of ${ISO_STATES.join(", ")}`);
  }

  return isoState;
};

export const detachIso = async (
  apiKey: string,
  instanceId: string,
): Promise<void> => {
  await requestVultrApi(apiKey, "POST", `/instances/${instanceId}/iso/detach`);
};
