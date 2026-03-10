"use strict";

const assert = require("assert");
const crypto = require("crypto");

// Functional suite validates ACCESS phase selector precedence against the local Kong stack.
// `rewrite` and `log` phases are intentionally not implemented in this plugin.
const BASE_URL = process.env.BASE_URL || "http://localhost:8000";
const ROUTE_PATH = process.env.ROUTE_PATH || "/private/684130/developer-platform/gateway/clients";
const ENDPOINT_SNI_ROUTE_PATH = process.env.ENDPOINT_SNI_ROUTE_PATH || "/private/684130/developer-platform/gateway/clients-endpoint-sni";
const ACCESS_SNI_BASE_URL = process.env.ACCESS_SNI_BASE_URL || "https://access-sni-dev.local:8443";
const ENDPOINT_SNI_BASE_URL = process.env.ENDPOINT_SNI_BASE_URL || "https://endpoint-sni-qa.local:8443";
const RUN_SNI_TESTS = process.env.RUN_SNI_TESTS === "true";

const JWT_CREDS_BY_CLIENT_ID = {
  dev_client: { key: "dev-client-key", secret: "dev-client-secret" },
  prod_client: { key: "prod-client-key", secret: "prod-client-secret" },
  qa_client: { key: "qa-client-key", secret: "qa-client-secret" },
  it_client: { key: "it-client-key", secret: "it-client-secret" },
  perf_client: { key: "perf-client-key", secret: "perf-client-secret" },
  neutral_client: { key: "neutral-client-key", secret: "neutral-client-secret" },
};

function createJwtWithClientId(clientId) {
  const creds = JWT_CREDS_BY_CLIENT_ID[clientId];
  if (!creds) {
    throw new Error(`missing JWT credentials for client_id ${clientId}`);
  }

  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({
    iss: creds.key,
    "client_id": clientId,
    exp: 2208988800,
  })).toString("base64url");

  const signingInput = `${header}.${payload}`;
  const signature = crypto.createHmac("sha256", creds.secret).update(signingInput).digest("base64url");

  return `${signingInput}.${signature}`;
}

async function getRoute(path, options = {}) {
  const headers = options.headers || {};
  const query = options.query || {};
  const queryString = new URLSearchParams(query).toString();
  const fullPath = queryString ? `${path}?${queryString}` : path;
  const baseUrl = options.baseUrl || BASE_URL;

  const response = await fetch(`${baseUrl}${fullPath}`, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${createJwtWithClientId("neutral_client")}`,
      ...headers,
    },
  });

  const body = await response.json().catch(() => ({}));
  return { response, body };
}

function assertBackend(body, expected) {
  assert.ok(body.environment, "echo response should include environment object");
  assert.strictEqual(body.environment.ECHO_RESPONSE, expected);
}

function assertOkAndBackend(response, body, expected) {
  assert.strictEqual(response.status, 200);
  assertBackend(body, expected);
}

describe("dynamic-routing functional suite (image-aligned precedence)", function () {
  this.timeout(120000);

  it("should select primary upstream when no custom selectors and no X-Upstream-Header header", async function () {
    const { response, body } = await getRoute(ROUTE_PATH);
    assertOkAndBackend(response, body, "it");
  });

  it("should select upstream based on default X-Upstream-Header header", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Header": "dev",
      },
    });
    assertOkAndBackend(response, body, "dev");
  });

  it("should select default header over access and endpoint selectors", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Header": "qa",
        "X-Upstream-Env-AP": "dev",
        "X-Upstream-Env-EP": "prod",
      },
      query: {
        apUpsByQP: "prod",
        epUpsByQP: "dev",
      },
    });
    assertOkAndBackend(response, body, "qa");
  });

  it("should select upstream by access policy header over query", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env-AP": "qa",
      },
      query: {
        apUpsByQP: "dev",
      },
    });
    assertOkAndBackend(response, body, "qa");
  });

  it("should select upstream by access policy query over endpoint policy header", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env-EP": "qa",
      },
      query: {
        apUpsByQP: "dev",
      },
    });
    assertOkAndBackend(response, body, "dev");
  });

  it("should select upstream by endpoint policy header over endpoint policy query", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env-EP": "qa",
      },
      query: {
        epUpsByQP: "dev",
      },
    });
    assertOkAndBackend(response, body, "qa");
  });

  it("should select upstream by endpoint policy query when higher selectors are absent", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      query: {
        epUpsByQP: "dev",
      },
    });
    assertOkAndBackend(response, body, "dev");
  });

  it("should fall back from invalid higher selectors to valid endpoint query", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env-AP": "unknown",
        "X-Upstream-Env-EP": "unknown",
      },
      query: {
        apUpsByQP: "unknown",
        epUpsByQP: "qa",
      },
    });
    assertOkAndBackend(response, body, "qa");
  });

  it("should route by authenticated consumer mapping when no higher selectors match", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        Authorization: `Bearer ${createJwtWithClientId("it_client")}`,
      },
    });
    assertOkAndBackend(response, body, "it");
  });

  it("should route by OIDC introspection client_id when header is present", async function () {
    const introspection = Buffer.from(JSON.stringify({
      client_id: "perf_client",
      active: true,
    })).toString("base64");

    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        Authorization: `Bearer ${createJwtWithClientId("neutral_client")}`,
        "X-Introspection-Response": introspection,
      },
    });
    assertOkAndBackend(response, body, "perf");
  });

  it("should route by explicit X-Client-Id header when no higher selectors match", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Client-Id": "perf_client",
        Authorization: `Bearer ${createJwtWithClientId("neutral_client")}`,
      },
    });
    assertOkAndBackend(response, body, "perf");
  });

  it("should keep OIDC client_id/X-Client-Id as lower priority than selectors", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env-AP": "dev",
        "X-Client-Id": "perf_client",
        Authorization: `Bearer ${createJwtWithClientId("qa_client")}`,
      },
    });
    assertOkAndBackend(response, body, "dev");
  });

  it("should select upstream by access-policy SNI", async function () {
    if (!RUN_SNI_TESTS) {
      this.skip();
    }

    const { response, body } = await getRoute(ROUTE_PATH, {
      baseUrl: ACCESS_SNI_BASE_URL,
      headers: {
        Host: "access-sni-dev.local",
      },
    });
    assertOkAndBackend(response, body, "dev");
  });

  it("should select upstream by endpoint-policy SNI", async function () {
    if (!RUN_SNI_TESTS) {
      this.skip();
    }

    const { response, body } = await getRoute(ENDPOINT_SNI_ROUTE_PATH, {
      baseUrl: ENDPOINT_SNI_BASE_URL,
      headers: {
        Host: "endpoint-sni-qa.local",
      },
    });
    assertOkAndBackend(response, body, "qa");
  });
});
