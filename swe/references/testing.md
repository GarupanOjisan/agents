# Testing Reference

Source references:
- Anthropic public Agent Skills repository: https://github.com/anthropics/skills
- Anthropic webapp-testing skill pattern: use Playwright against rendered local apps.

## TDD Loop

For a bug:

1. Write a failing test that reproduces the observed behavior.
2. Run only that test and confirm it fails for the expected reason.
3. Implement the smallest fix.
4. Run the focused test.
5. Run the relevant broader suite.

For a feature:

1. Define acceptance behavior.
2. Add focused tests for behavior and edge cases.
3. Implement in small increments.
4. Verify integration and user-facing flow.

## UI Verification

- Start the local dev server when the app needs one.
- Use a real browser or Playwright for dynamic UI.
- Wait for the rendered state before inspecting DOM.
- Capture screenshots for layout-sensitive changes.
- Check console errors and failed network requests.
- Test desktop and mobile viewports when layout is touched.

## Backend / API Verification

- Cover success, validation failure, authorization failure, and external dependency failure.
- Use fixtures that communicate business meaning.
- Avoid brittle tests that assert implementation details.
- Include regression tests for bugs.

## CI

- Prefer the smallest command that validates the changed surface first.
- Then run the repo's standard test/lint command if available.
- Report commands that could not be run and why.
