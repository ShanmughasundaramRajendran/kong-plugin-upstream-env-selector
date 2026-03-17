import requests
import pytest


def _get_environment_value(response: requests.Response) -> str:
    body = response.json()
    return body["environment"]["ECHO_RESPONSE"]


@pytest.mark.functional
class TestDynamicRouting:
    def test_selects_primary_upstream_when_no_selectors(self, base_url, route_path, default_headers):
        response = requests.get(f"{base_url}{route_path}", headers=default_headers, timeout=10)
        assert response.status_code == 200
        assert _get_environment_value(response) == "it"

    def test_selects_by_default_header(self, base_url, route_path, default_headers):
        headers = {**default_headers, "X-Upstream-Env": "dev"}
        response = requests.get(f"{base_url}{route_path}", headers=headers, timeout=10)
        assert response.status_code == 200
        assert _get_environment_value(response) == "dev"

    def test_default_header_has_highest_priority(self, base_url, route_path, default_headers):
        headers = {
            **default_headers,
            "X-Upstream-Env": "qa",
            "X-Upstream-Env-AP": "prod",
            "X-Upstream-Env-EP": "dev",
        }
        response = requests.get(
            f"{base_url}{route_path}",
            headers=headers,
            params={"apUpsByQP": "dev", "epUpsByQP": "prod"},
            timeout=10,
        )
        assert response.status_code == 200
        assert _get_environment_value(response) == "qa"

    def test_access_policy_header_before_query(self, base_url, route_path, default_headers):
        headers = {**default_headers, "X-Upstream-Env-AP": "prod"}
        response = requests.get(
            f"{base_url}{route_path}",
            headers=headers,
            params={"apUpsByQP": "dev"},
            timeout=10,
        )
        assert response.status_code == 200
        assert _get_environment_value(response) == "prod"

    def test_endpoint_policy_query_fallback(self, base_url, route_path, default_headers):
        response = requests.get(
            f"{base_url}{route_path}",
            headers=default_headers,
            params={"epUpsByQP": "dev"},
            timeout=10,
        )
        assert response.status_code == 200
        assert _get_environment_value(response) == "dev"

    def test_explicit_x_client_id_is_ignored(self, base_url, route_path, default_headers):
        headers = {**default_headers, "client_id": "perf_client"}
        response = requests.get(f"{base_url}{route_path}", headers=headers, timeout=10)
        assert response.status_code == 200
        assert _get_environment_value(response) == "it"

    def test_sni_selector(self, route_path, default_headers, run_sni_tests):
        if not run_sni_tests:
            pytest.skip("RUN_SNI_TESTS is not true")

        response = requests.get(
            f"https://access-sni-dev.local:8443{route_path}",
            headers=default_headers,
            timeout=10,
            verify=False,
        )
        assert response.status_code == 200
        assert _get_environment_value(response) == "dev"
