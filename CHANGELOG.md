# Changelog

## 1.1.0

- K3 portable none/minimal/medium map to low and xhigh to high; explicit canonical native effort retains precedence. Exact K2.7 models retain enabled service thinking for portable none with a compatibility warning; explicit disabled thinking remains unsupported. Unknown models send none as disabled thinking. Reviewed upstream: @ai-sdk/moonshotai 3.0.78 to 3.0.82. Validation passed: node Scripts/test-packages.mjs (all 52 owning package suites and the compatibility facade); node Scripts/sdk.mjs generate --check; node --test Scripts/tests/*.test.cjs (27 passed); docs-site check and build (100 pages). Live provider calls were not run.
  Compatibility: Minor release for additive native API; existing static settings and call sites remain compatible. Updated direct dependency minimums are recorded in the manifest. Existing documented JS/framework and native product gaps remain; version-delta review does not imply full parity or live-service testing. Explicit custom authentication skips an unused credential supplier, a deliberate native callback-order adaptation.
