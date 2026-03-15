"use strict";

const assert = require("assert");
const crypto = require("crypto");

const BASE_URL = process.env.BASE_URL || "http://localhost:8000";
const ROUTE_PATH = process.env.ROUTE_PATH || "/private/684130/developer-platform/gateway/clients";
const SNI_BASE_URL = process.env.SNI_BASE_URL || "https://access-sni-dev.local:8443";
const RUN_SNI_TESTS = process.env.RUN_SNI_TESTS === "true";

const JWT_CREDS_BY_CLIENT_ID = {
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
    client_id: clientId,
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

describe("dynamic-routing functional suite (single-policy config)", function () {
  this.timeout(120000);

  it("selects primary upstream when no selectors are present", async function () {
    const { response, body } = await getRoute(ROUTE_PATH);
    assert.strictEqual(response.status, 200);
    assertBackend(body, "it");
  });

  it("selects by default X-Upstream-Env header", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env": "dev",
      },
    });
    assert.strictEqual(response.status, 200);
    assertBackend(body, "dev");
  });

  it("keeps default header as highest priority", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Env": "qa",
        "X-Upstream-Selector": "prod",
      },
      query: {
        upsByQP: "dev",
      },
    });
    assert.strictEqual(response.status, 200);
    assertBackend(body, "qa");
  });

  it("uses selector header before selector query", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Upstream-Selector": "prod",
      },
      query: {
        upsByQP: "dev",
      },
    });
    assert.strictEqual(response.status, 200);
    assertBackend(body, "prod");
  });

  it("uses selector query when selector header is absent", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      query: {
        upsByQP: "dev",
      },
    });
    assert.strictEqual(response.status, 200);
    assertBackend(body, "dev");
  });

  it("ignores explicit X-Client-Id without authenticated consumer context", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      headers: {
        "X-Client-Id": "perf_client",
      },
    });
    assert.strictEqual(response.status, 200);
    assertBackend(body, "it");
  });

  it("selects upstream by sni when enabled", async function () {
    if (!RUN_SNI_TESTS) {
      this.skip();
    }

    const { response, body } = await getRoute(ROUTE_PATH, {
      baseUrl: SNI_BASE_URL,
      headers: {
        Host: "access-sni-dev.local",
      },
    });
    assert.strictEqual(response.status, 200);
    assertBackend(body, "dev");
  });
});
