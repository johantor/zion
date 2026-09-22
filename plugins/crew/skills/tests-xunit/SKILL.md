---
name: tests-xunit
description: .NET backend test conventions — xUnit test authoring and running, integration tests for the .NET layer. Load when the resolved backend stack is dotnet.
---

# Backend tests: xUnit (.NET)

Write and run backend tests using xUnit conventions and the repository's backend test command
from crew config (e.g. `dotnet test`). Integration tests exercise the .NET layer end to end
where the project has them.

## Running

If your dispatch hands you an artifacts path, add `--artifacts-path <path>` to every `dotnet test`
run: the build and lint gates may be running beside you on their own paths (`backend-dotnet`,
"Parallel gates").

A **targeted rerun** is a `--filter`, not a full run. Every filter is `<property><op><value>`,
so the property is never left off: `dotnet test --filter "FullyQualifiedName~Namespace.ClassName"`
for a class, `--filter "FullyQualifiedName~Namespace.ClassName.MethodName"` for one test.

**Discovery is checked with the runner, not the DLL.** `dotnet test --list-tests --filter
"FullyQualifiedName~Namespace.ClassName"` prints the tests the runner sees in that class; that is
how you confirm a new test is picked up. When it lists nothing, rule out the filter first: rerun
`--list-tests` without it, and if the rest of the project's tests appear, the value is misspelled
or the namespace differs from the folder, so fix the filter. When the unfiltered list is empty too,
the cause is in the project file, not the assembly: the test project is missing
`Microsoft.NET.Test.Sdk` or `xunit.runner.visualstudio`, is not in the solution, or has a stale
build. Read the `.csproj`/`.sln`, report the gap to `morpheus`, and never run `strings`, `ildasm`
or the like over `bin/` to look for the class.

Read the summary line, not just the exit code: `Total tests: 0` is a failure to report, not a pass.

Never make a test pass with `Skip = "…"`, and never widen an assertion to whatever the code
currently returns. If the production code is wrong, say so and hand it back.
