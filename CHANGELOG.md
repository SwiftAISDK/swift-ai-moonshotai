# Changelog

## 1.1.2

- Avoid repeated recursive MFJS array/tuple conversion while preserving prefix items, unions, boolean schemas and input values. Reviewed npm delta: @ai-sdk/moonshotai 3.0.87 to 3.0.92. Validation: `node Scripts/test-packages.mjs` passed all 52 owning suites and 1731 facade tests; tooling 27/27, generation/isolation checks, standalone exports and 106 minimum/latest consumers, documentation check and 101-page build passed. Publication requires green exact-source Swift 6.3.3 CI. Paid/live verification and full-package parity are not claimed.
  Compatibility: Compatible behavior/header correction. Original public selectors are preserved. npm baselines and Swift SemVer are independent; this reviewed delta does not establish full-package or live-service parity.
