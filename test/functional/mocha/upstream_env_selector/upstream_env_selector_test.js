"use strict";

const assert = require("assert");
const crypto = require("crypto");

const BASE_URL = process.env.BASE_URL || "http://localhost:8000";
const ROUTE_PATH = process.env.ROUTE_PATH || "/api/orders";
const UPSTREAM_VALUES = ["dev", "prod", "qa"];

const JWT_CREDS_BY_CLIENT_ID = {
  dev_client: { key: "dev-client-key", secret: "dev-client-secret" },
  prod_client: { key: "prod-client-key", secret: "prod-client-secret" },
  qa_client: { key: "qa-client-key", secret: "qa-client-secret" },
  staging_client: { key: "staging-client-key", secret: "staging-client-secret" },
  perf_client: { key: "perf-client-key", secret: "perf-client-secret" },
  neutral_client: { key: "neutral-client-key", secret: "neutral-client-secret" },
};

function createJwtWithClientId(clientId) {
  const creds = JWT_CREDS_BY_CLIENT_ID[clientId];
  if (!creds) {
    throw new Error(`missing JWT credentials for client-id ${clientId}`);
  }

  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({
    iss: creds.key,
    "client-id": clientId,
    exp: 2208988800,
  })).toString("base64url");
  const signingInput = `${header}.${payload}`;
  const signature = crypto.createHmac("sha256", creds.secret).update(signingInput).digest("base64url");
  return `${signingInput}.${signature}`;
}

// Thin HTTP helper used by all scenarios in this suite.
async function getRoute(path, options = {}) {
  const headers = options.headers || {};
  const query = options.query || {};
  const queryString = new URLSearchParams(query).toString();
  const fullPath = queryString ? `${path}?${queryString}` : path;

  const response = await fetch(`${BASE_URL}${fullPath}`, {
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

// Echo server exposes selected backend through env; assert that selector routed
// to expected target.
function assertBackend(body, expected) {
  assert.ok(body.environment, "echo response should include environment object");
  assert.strictEqual(body.environment.ECHO_RESPONSE, expected);
}

function assertOkAndBackend(response, body, expected) {
  assert.strictEqual(response.status, 200);
  assertBackend(body, expected);
}

const SOURCES = [
  { id: "default_header", kind: "header", key: "X-Upstream-Env" },
  { id: "access_header", kind: "header", key: "X-Client-Env" },
  { id: "access_query", kind: "query", key: "env" },
  { id: "endpoint_header", kind: "header", key: "X-Resource-Env" },
  { id: "endpoint_query", kind: "query", key: "resource_env" },
  { id: "client_id", kind: "header", key: "X-Client-Id" },
];

const VALUES_BY_SOURCE = [
  ["dev", "prod", "qa"],
  ["dev", "prod", "qa"],
  ["dev", "prod", "qa"],
  ["dev", "prod", "qa"],
  ["dev", "prod", "qa"],
  ["dev_client", "prod_client", "qa_client"],
];
const VALID_BY_SOURCE = ["dev", "prod", "qa", "dev", "prod", "qa_client"];
const CLIENT_APPLICATIONS = [
  { id: "dev_client", expected: "dev" },
  { id: "prod_client", expected: "prod" },
  { id: "qa_client", expected: "qa" },
  { id: "staging_client", expected: "staging" },
  { id: "perf_client", expected: "perf" },
];

function createRequestOptions() {
  return { headers: {}, query: {} };
}

function setSourceValue(options, source, value) {
  if (source.kind === "header") {
    options.headers[source.key] = value;
  } else {
    options.query[source.key] = value;
  }
}

function differentValue(value) {
  return UPSTREAM_VALUES.find((candidate) => candidate !== value);
}

function expectedForSelectorValue(value) {
  if (value.endsWith("_client")) {
    return value.replace(/_client$/, "");
  }
  return value;
}

describe("upstream-env-selector functional suite (mocha)", function () {
  this.timeout(120000);

  describe("single-source sanity checks", function () {
    SOURCES.forEach((source, index) => {
      VALUES_BY_SOURCE[index].forEach((value, valueIndex) => {
        it(`routes by ${source.id}=${value}`, async function () {
          const options = createRequestOptions();
          setSourceValue(options, source, value);

          const { response, body } = await getRoute(ROUTE_PATH, options);
          assertOkAndBackend(response, body, UPSTREAM_VALUES[valueIndex]);
        });
      });
    });
  });

  describe("all valid source-combination masks", function () {
    const totalMasks = (1 << SOURCES.length) - 1;

    for (let mask = 1; mask <= totalMasks; mask += 1) {
      it(`routes by highest-priority source for mask=${mask.toString(2).padStart(SOURCES.length, "0")}`, async function () {
        const options = createRequestOptions();
        let expected = null;

        for (let i = 0; i < SOURCES.length; i += 1) {
          if ((mask & (1 << i)) === 0) {
            continue;
          }

          const value = VALID_BY_SOURCE[i];
          setSourceValue(options, SOURCES[i], value);
          if (expected === null) {
            expected = expectedForSelectorValue(value);
          }
        }

        const { response, body } = await getRoute(ROUTE_PATH, options);
        assertOkAndBackend(response, body, expected);
      });
    }
  });

  describe("fallback with invalid higher-priority selectors", function () {
    SOURCES.forEach((winnerSource, winnerIndex) => {
      VALUES_BY_SOURCE[winnerIndex].forEach((winnerValue) => {
        it(`falls back to ${winnerSource.id}=${winnerValue} when all higher sources are invalid`, async function () {
          const options = createRequestOptions();

          for (let i = 0; i < winnerIndex; i += 1) {
            setSourceValue(options, SOURCES[i], "unknown");
          }

        setSourceValue(options, winnerSource, winnerValue);

          for (let i = winnerIndex + 1; i < SOURCES.length; i += 1) {
            setSourceValue(options, SOURCES[i], differentValue(winnerValue));
          }

          const { response, body } = await getRoute(ROUTE_PATH, options);
          assertOkAndBackend(response, body, expectedForSelectorValue(winnerValue));
        });
      });
    });
  });

  describe("exact-match behavior (no normalization)", function () {
    SOURCES.forEach((source) => {
      it(`does not match mixed-case value for ${source.id}=PrOd`, async function () {
        const options = createRequestOptions();
        setSourceValue(options, source, "PrOd");

        const { response, body } = await getRoute(ROUTE_PATH, options);
        assertOkAndBackend(response, body, "prod");
      });
    });

    for (let i = 0; i < SOURCES.length - 1; i += 1) {
      it(`falls through from invalid ${SOURCES[i].id} to next valid ${SOURCES[i + 1].id}`, async function () {
        const options = createRequestOptions();
        setSourceValue(options, SOURCES[i], "invalid-value");
        setSourceValue(options, SOURCES[i + 1], VALID_BY_SOURCE[i + 1]);

        const { response, body } = await getRoute(ROUTE_PATH, options);
        assertOkAndBackend(response, body, expectedForSelectorValue(VALID_BY_SOURCE[i + 1]));
      });
    }
  });

  describe("no-match behavior", function () {
    it("keeps default route when nothing is provided", async function () {
      const { response, body } = await getRoute(ROUTE_PATH);
      assertOkAndBackend(response, body, "prod");
    });

    it("keeps default route when all selectors are invalid", async function () {
      const options = createRequestOptions();
      SOURCES.forEach((source) => setSourceValue(options, source, "unknown"));

      const { response, body } = await getRoute(ROUTE_PATH, options);
      assertOkAndBackend(response, body, "prod");
    });
  });

  describe("client application combinations (3-5 client ids)", function () {
    CLIENT_APPLICATIONS.forEach((consumer) => {
      it(`routes by JWT client-id ${consumer.id}`, async function () {
        const { response, body } = await getRoute(ROUTE_PATH, {
          headers: { Authorization: `Bearer ${createJwtWithClientId(consumer.id)}` },
        });
        assertOkAndBackend(response, body, consumer.expected);
      });
    });

    it("JWT client-id is ignored when default header is present", async function () {
      const { response, body } = await getRoute(ROUTE_PATH, {
        headers: {
          "X-Upstream-Env": "qa",
          Authorization: `Bearer ${createJwtWithClientId("dev_client")}`,
        },
      });
      assertOkAndBackend(response, body, "qa");
    });

    it("JWT client-id is ignored when access policy header is present", async function () {
      const { response, body } = await getRoute(ROUTE_PATH, {
        headers: {
          "X-Client-Env": "dev",
          Authorization: `Bearer ${createJwtWithClientId("prod_client")}`,
        },
      });
      assertOkAndBackend(response, body, "dev");
    });

    it("falls back to JWT client-id when all higher selectors are invalid", async function () {
      const { response, body } = await getRoute(ROUTE_PATH, {
        headers: {
          "X-Upstream-Env": "unknown",
          "X-Client-Env": "unknown",
          "X-Resource-Env": "unknown",
          Authorization: `Bearer ${createJwtWithClientId("qa_client")}`,
        },
        query: {
          env: "unknown",
          resource_env: "unknown",
        },
      });
      assertOkAndBackend(response, body, "qa");
    });
  });
});
