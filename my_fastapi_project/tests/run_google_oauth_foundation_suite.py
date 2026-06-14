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
        "service:start_without_email_omits_hint",
        foundation_tests.test_google_start_without_email_omits_login_hint_and_state_email,
    ),
    (
        "service:callback_verified_email",
        foundation_tests.test_google_callback_exchanges_code_and_uses_verified_email,
    ),
    (
        "service:callback_without_email_hint_uses_profile",
        foundation_tests.test_google_callback_accepts_missing_email_hint_and_uses_google_profile,
    ),
    (
        "service:callback_rejects_email_mismatch",
        foundation_tests.test_google_callback_rejects_email_mismatch_between_hint_and_google_profile,
    ),
    (
        "service:callback_rejects_unverified_email",
        foundation_tests.test_google_callback_rejects_unverified_email,
    ),
    (
        "service:mobile_id_token_success",
        foundation_tests.test_google_mobile_id_token_creates_standard_session,
    ),
    (
        "service:mobile_id_token_rejects_email_mismatch",
        foundation_tests.test_google_mobile_id_token_rejects_email_mismatch,
    ),
    (
        "service:apple_start_signed_state_and_nonce",
        foundation_tests.test_apple_start_returns_signed_state_and_nonce,
    ),
    (
        "service:apple_start_no_private_key_required",
        foundation_tests.test_apple_start_does_not_require_private_key,
    ),
    (
        "service:apple_bridge_redirect_with_user_payload",
        foundation_tests.test_apple_builds_frontend_callback_redirect_with_user_payload,
    ),
    (
        "service:apple_start_rejects_bad_redirect",
        foundation_tests.test_apple_start_rejects_unknown_redirect_uri,
    ),
    (
        "service:apple_callback_verified_email",
        foundation_tests.test_apple_callback_exchanges_code_and_uses_verified_email,
    ),
    (
        "service:apple_callback_rejects_email_mismatch",
        foundation_tests.test_apple_callback_rejects_email_mismatch,
    ),
    (
        "endpoint:start_success",
        endpoint_tests.test_google_auth_start_endpoint_success,
    ),
    (
        "endpoint:start_success_without_email",
        endpoint_tests.test_google_auth_start_endpoint_success_without_email,
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
    (
        "endpoint:mobile_success",
        endpoint_tests.test_google_auth_mobile_endpoint_success,
    ),
    (
        "endpoint:mobile_failure",
        endpoint_tests.test_google_auth_mobile_endpoint_failure,
    ),
    (
        "endpoint:apple_start_success",
        endpoint_tests.test_apple_auth_start_endpoint_success,
    ),
    (
        "endpoint:apple_start_failure",
        endpoint_tests.test_apple_auth_start_endpoint_failure,
    ),
    (
        "endpoint:apple_callback_success",
        endpoint_tests.test_apple_auth_callback_endpoint_success,
    ),
    (
        "endpoint:apple_callback_failure",
        endpoint_tests.test_apple_auth_callback_endpoint_failure,
    ),
    (
        "endpoint:apple_return_redirect",
        endpoint_tests.test_apple_auth_return_endpoint_redirects_to_frontend_callback,
    ),
    (
        "endpoint:apple_return_post_redirect",
        endpoint_tests.test_apple_auth_return_post_endpoint_redirects_to_frontend_callback,
    ),
]


def main() -> int:
    total = len(TEST_CASES)
    passed = 0

    print("Social auth foundation suite")
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
