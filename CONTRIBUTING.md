# Contributing to SwiftDeadCode

Thank you for your interest in improving SwiftDeadCode! This document outlines how to report issues, propose enhancements, and submit pull requests so we can keep the project healthy and easy to maintain.

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to uphold its principles. If you encounter unacceptable behavior, please report it to the maintainers.

## Getting Started

1. **Fork the repository** and create a branch for your work. Use a descriptive branch name such as `feature/improve-reporting` or `fix/demangler-crash`.
2. **Install dependencies** using the Swift Package Manager:
   ```bash
   swift build
   ```
3. **Run the test suite** to ensure everything passes before making changes:
   ```bash
   swift test
   ```
4. If you plan to integrate the tool with an Xcode project, review `README.md` for the current setup instructions.

## Design and Scope

- SwiftDeadCode focuses on comparing debug and release link maps and reporting application-owned debug-only symbols. Please open an issue to discuss major feature ideas before implementation.
- Keep the CLI experience focused and well-documented. New flags or configuration options should have accompanying documentation updates and, when possible, tests.
- Avoid committing unrelated formatting changes. If you need to reformat, do so in a dedicated pull request.

## Submitting Changes

1. **Add or update tests** to cover your change. We aim for meaningful test coverage that protects against regressions.
2. **Document user-facing changes**. Update `README.md` or inline comments so users understand new behavior.
3. **Run `swift test`** and ensure it passes locally. Mention the command in your pull request description.
4. **Commit with a clear message** explaining what the change does and why.
5. **Open a pull request** against `main`. Fill out the template (if applicable) and provide context, especially for non-obvious decisions.

## Reporting Bugs

When you encounter a bug:
- Check existing issues to avoid duplicates.
- Create a new issue with:
  - Steps to reproduce
  - Expected vs. actual behavior
  - Relevant logs or report output
  - Environment details (Xcode version, Swift version, OS, etc.)

## Feature Requests

We welcome ideas that improve the developer experience or analysis accuracy. Please open an issue describing the problem you want to solve, why it matters, and any implementation thoughts you have.

## Questions or Discussions

If you are unsure about the right approach, feel free to open a discussion or issue tagged as “question.” The maintainers and community are happy to help.

Thank you for contributing!
