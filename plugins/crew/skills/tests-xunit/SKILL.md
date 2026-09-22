---
name: tests-xunit
description: .NET backend test conventions — xUnit test authoring and running, integration tests for the .NET layer. Load when the resolved backend stack is dotnet.
---

# Backend tests: xUnit (.NET)

Write and run backend tests using xUnit conventions and the repository's backend test command
from crew config (e.g. `dotnet test`). Integration tests exercise the .NET layer end to end
where the project has them.

## Running

A **targeted rerun** is a `--filter`, not a full run: `dotnet test --filter
"FullyQualifiedName~Namespace.ClassName"` for a class, `~ClassName.MethodName` for one test.

**Discovery is checked with the runner, not the DLL.** `dotnet test --list-tests --filter
"FullyQualifiedName~ClassName"` prints the tests the runner sees in that class; that is how you
confirm a new test is picked up. When it lists nothing, the cause is in the project file, not the
assembly: the test project is missing `Microsoft.NET.Test.Sdk` or `xunit.runner.visualstudio`, is
not in the solution, or has a stale build. Read the `.csproj`/`.sln`, report the gap to
`morpheus`, and never run `strings`, `ildasm` or the like over `bin/` to look for the class.

Read the summary line, not just the exit code: `Total tests: 0` is a failure to report, not a pass.

Never make a test pass with `Skip = "…"`, and never widen an assertion to whatever the code
currently returns. If the production code is wrong, say so and hand it back.
