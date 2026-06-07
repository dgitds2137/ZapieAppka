# Frontend QA Tests

This folder contains focused Flutter QA tests for critical business flows.

Run:

```bash
cd zapieapp
flutter test test/qa
```

### What is covered

- Checkout flow + admin dashboard repository contracts.
- End-to-end role path: customer -> employee -> driver using mocked API responses.
- Kitchen ETA override endpoint (`/admin/catalog/kitchen-eta`).
- `AuthSession` role helper behavior (`isAdmin`, `isEmployee`, `isDriver`, `isStaff`, `isUser`).

### How to extend

Add more tests in `test/qa` (for example `delivery_flow_test.dart`, `admin_catalog_test.dart`) using `http.testing.MockClient` and explicit mocked JSON responses.
