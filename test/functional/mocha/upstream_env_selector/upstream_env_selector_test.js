"use strict";

const assert = require("assert");

const BASE_URL = process.env.BASE_URL || "http://localhost:8000";
const ROUTE_PATH = process.env.ROUTE_PATH || "/api/orders";

// Thin HTTP helper used by all scenarios in this suite.
async function getRoute(path, headers = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    method: "GET",
    headers: {
      Accept: "application/json",
      ...headers,
    },
  });

  const body = await response.json();
  return { response, body };
}

// Echo server exposes selected backend through env; assert that selector routed
// to expected target.
function assertBackend(body, expected) {
  assert.ok(body.environment, "echo response should include environment object");
  assert.strictEqual(body.environment.ECHO_RESPONSE, expected);
}

describe("upstream-env-selector functional suite (mocha)", function () {
  this.timeout(30000);

  it("routes to dev by X-Upstream-Env header", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      "X-Upstream-Env": "dev",
    });

    assert.strictEqual(response.status, 200);
    assertBackend(body, "dev");
  });

  it("routes to prod by X-Upstream-Env header", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      "X-Upstream-Env": "prod",
    });

    assert.strictEqual(response.status, 200);
    assertBackend(body, "prod");
  });

  it("routes by client query selector when default header is absent", async function () {
    const { response, body } = await getRoute(`${ROUTE_PATH}?env=dev`);

    assert.strictEqual(response.status, 200);
    assertBackend(body, "dev");
  });

  it("routes by endpoint header selector", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      "X-Resource-Env": "prod",
    });

    assert.strictEqual(response.status, 200);
    assertBackend(body, "prod");
  });

  it("routes by consumer id request header fallback", async function () {
    const { response, body } = await getRoute(ROUTE_PATH, {
      "X-Consumer-Id": "dev",
    });

    assert.strictEqual(response.status, 200);
    assertBackend(body, "dev");
  });

  it("returns 400 when strict mode is enabled and nothing matches", async function () {
    const { response, body } = await getRoute(ROUTE_PATH);

    assert.strictEqual(response.status, 400);
    assert.strictEqual(body.message, "No matching upstream for request");
  });
});
