// NOTE: Terraformのplanが応答の無い接続で止まり続けないための上限
const FETCH_TIMEOUT_MS = 30_000;

const query: unknown = await Bun.stdin.json();

if (typeof query !== "object" || query === null) {
  console.error(`Invalid input value: ${JSON.stringify(query)}`);
  process.exit(1);
}
if (!("url" in query) || typeof query.url !== "string") {
  console.error(`Input value does not have URL: ${JSON.stringify(query)}`);
  process.exit(1);
}
const url = URL.parse(query.url);
if (url === null) {
  console.error(`Input value is not a valid URL: ${JSON.stringify(query.url)}`);
  process.exit(1);
}

const response = await fetch(url, {
  redirect: "manual",
  signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
});
await response.body?.cancel();

const location = response.headers.get("location");
if (response.status < 300 || response.status >= 400 || location === null) {
  console.error(`Input value is not a redirect URL: ${JSON.stringify(query.url)}, status: ${response.status}, location: ${location}`);
  process.exit(1);
}

console.log(JSON.stringify({ url: new URL(location, url).href }));
