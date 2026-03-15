import os
import time

import pytest
import requests


@pytest.fixture(scope="session")
def base_url() -> str:
    return os.getenv("BASE_URL", "http://localhost:8000")


@pytest.fixture(scope="session")
def route_path() -> str:
    return os.getenv("ROUTE_PATH", "/private/684130/developer-platform/gateway/clients")


@pytest.fixture(scope="session")
def run_sni_tests() -> bool:
    return os.getenv("RUN_SNI_TESTS", "false").lower() == "true"


@pytest.fixture(scope="session")
def default_headers() -> dict:
    return {
        "Accept": "application/json",
        "Authorization": (
            "Bearer "
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJpc3MiOiJuZXV0cmFsLWNsaWVudC1rZXkiLCJjbGllbnRfaWQiOiJuZXV0cmFsX2NsaWVudCIsImV4cCI6MjIwODk4ODgwMH0."
            "FngrKhY_xwXeTuOiQIshBs1ypUTOOkHvBb2O-tOyAmo"
        ),
    }


@pytest.fixture(scope="session", autouse=True)
def wait_for_kong(base_url: str):
    last_err = None
    for _ in range(30):
        try:
            res = requests.get(base_url, timeout=2)
            if res.status_code < 500:
                return
        except requests.RequestException as exc:
            last_err = exc
        time.sleep(1)

    raise RuntimeError(f"Kong did not become ready at {base_url}. Last error: {last_err}")
