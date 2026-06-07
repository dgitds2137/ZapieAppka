from __future__ import annotations

from pathlib import Path
import sys
import traceback

REPO_ROOT = Path(__file__).resolve().parent.parent
TESTS_DIR = Path(__file__).resolve().parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

import test_google_oauth_endpoints as endpoint_tests
import test_google_oauth_foundations as foundation_tests


TEST_CASES = [
    (
        "service:start_signed_state",
        foundation_tests.test_google_start_returns_signed_state_and_redirect,
    ),
    (
        "service:start_no_secret_required",
        foundation_tests.test_google_start_does_not_require_client_secret,
    ),
    (
        "service:start_rejects_bad_redirect",
        foundation_tests.test_google_start_rejects_unknown_redirect_uri,
    ),
    (
        "service:callback_verified_email",
        foundation_tests.test_google_callback_exchanges_code_and_uses_verified_email,
    ),
    (
        "service:callback_rejects_unverified_email",
        foundation_tests.test_google_callback_rejects_unverified_email,
    ),
    (
        "endpoint:start_success",
        endpoint_tests.test_google_auth_start_endpoint_success,
    ),
    (
        "endpoint:start_failure",
        endpoint_tests.test_google_auth_start_endpoint_failure,
    ),
    (
        "endpoint:callback_success",
        endpoint_tests.test_google_auth_callback_endpoint_success,
    ),
    (
        "endpoint:callback_failure",
        endpoint_tests.test_google_auth_callback_endpoint_failure,
    ),
]


def main() -> int:
    total = len(TEST_CASES)
    passed = 0

    print("Google OAuth foundation suite")
    print(f"Cases: {total}")

    for label, fn in TEST_CASES:
        try:
            fn()
        except Exception as exc:  # pragma: no cover
            print(f"[FAIL] {label}")
            print(f"  {exc}")
            formatted = traceback.format_exc().strip().splitlines()
            for line in formatted[-8:]:
                print(f"  {line}")
        else:
            passed += 1
            print(f"[PASS] {label}")

    print(f"Summary: {passed}/{total} passed")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
