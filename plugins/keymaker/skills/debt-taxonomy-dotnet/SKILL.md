---
name: debt-taxonomy-dotnet
description: .NET / C# suppression mechanisms, safe-removal recipes, NuGet package-manager variance, and upgrade-tier examples for the keymaker crew. Apply when stack detection (debt-taxonomy) finds a .NET project. Load into keymaker and twin.
---

# Debt taxonomy — .NET / C#

Apply this skill when `debt-taxonomy` stack detection finds a .NET project (`*.csproj`,
`*.sln`, `Directory.Packages.props`, `global.json`). Classification rubric and blast-radius
gate are in the core `debt-taxonomy` skill.

## Suppression mechanisms

| Mechanism | Scope | Safe-removal notes |
|---|---|---|
| `#pragma warning disable CS####` / `restore` | Block | Removal re-enables for that block only. Delete both the `disable` and matching `restore`. |
| `[SuppressMessage("category", "id")]` | Member/type | Check for a `Justification` param — a meaningful one may be legitimate (rubric class 1). |
| `<NoWarn>CS####;CS####</NoWarn>` in `.csproj` | Project-wide | Single line, large blast radius — expand to **diagnostic count** before gating. Remove only the target ID from the list, not the whole element. |
| `<NoWarn>` in `Directory.Build.props` | Solution-wide | Even larger; treat as tier 2 unless the diagnostic count is tiny. |
| `.editorconfig` `dotnet_diagnostic.CS####.severity = none/silent` | Folder-scoped | Count diagnostics under the folder, not just this line. Restore to `warning`/`error` to re-enable. |
| `GlobalSuppressions.cs` (`[assembly: SuppressMessage(...)]`) | Assembly-wide | File may hold many entries — enumerate each as a **separate finding**; remove only the targeted entry. |
| `[Fact(Skip="…")]`, `[Theory(Skip="…")]` | Test | Rubric class 4 (needs-investigation). Never un-skip without confirmation. |

## Analyzer / nullability notes

- **Nullable reference types** (`CS86xx`): the common debt cluster. A `#pragma warning disable CS8602` often hides a missing null-check — usually rubric class 2 (trivially fixable: add `?.`, null-guard, or `!` only where provably non-null).
- **Obsolete-API warnings** (`CS0618`): frequently caused by an old dependency — the fix may be an upgrade pointer, not a code edit. Flag the link.
- A suppression whose diagnostic no longer fires (`dotnet build` shows no warning at that line after removal) is class 2, stale — just delete it.

## Stale heuristics (grep-only, for audit `stale` scope)

Per the core skill: audit must not build. These are grep-only signals that a suppression
is a *candidate* for removal; `/keymaker:open` proves it via the twin (`dotnet build` of
the affected project, then check the diagnostic is absent).

| Mechanism | Grep-only stale heuristic |
|---|---|
| `#pragma warning disable CS####` … `restore` | Candidate when the surrounded line(s) have no obvious trigger for that diagnostic — e.g. a `disable CS8602` (nullable deref) block over a line with no `.` member access; a `disable CS0168` (unused variable) block over a line with no declaration. Also candidate when `restore` is missing or far from `disable`, suggesting cargo-cult retention. |
| `[SuppressMessage("category", "id", Justification = "…")]` | Candidate when the targeted member has no obvious construct that triggers the rule (e.g. `CA1062` argument-null check on a member with no parameters). A meaningful `Justification` may still be legitimate (rubric class 1) — flag, do not assume. |
| `<NoWarn>` in `.csproj` / `Directory.Build.props` | **Out of scope for `stale` audit (v1).** Grep for a rule ID in source returns zero for virtually any active project-wide warning (the ID lives in pragmas, not in the code the diagnostic fires on), so the signal is structurally inverted and high-noise. Proof of staleness requires a build; defer to `/keymaker:open` where the twin can run `dotnet build`. |
| `.editorconfig` `dotnet_diagnostic.CS####.severity = none/silent` | **Out of scope for `stale` audit (v1).** Same inversion as `<NoWarn>`: the rule ID does not appear in the source the diagnostic fires on. Final proof requires a build; defer to `/keymaker:open`. |
| `GlobalSuppressions.cs` (`[assembly: SuppressMessage(...)]`) | Each entry is a separate candidate. Heuristic: grep the `Target` symbol in `*.cs` source files (`grep -rn --include="*.cs" "<symbol>" src/`) — if the target member no longer exists in source, the suppression is a strong candidate. |
| `[Fact(Skip="…")]`, `[Theory(Skip="…")]` | Never a stale candidate — skipped tests are rubric class 4 (needs-investigation), not removable without confirmation. |

## Behavior sensitivity (which fixes need tests, not just a clean build)

Tag every finding before delegating (see core `debt-taxonomy`):

**Behavior-preserving** — `<NoWarn>` removal of a stale diagnostic, an `any`-equivalent cast tightening, unused-using/variable cleanup, a justification-only edit. "Compiles clean" is a sufficient gate.

**Behavior-sensitive** — adding a real **null-guard** for a `CS8602` fix changes control flow (an early return or default vs. a thrown `NullReferenceException`), so the *behavior under null* changes. Likewise re-enabling an analyzer that forces a logic change (e.g. `CA2007` ConfigureAwait, disposal fixes). Acceptance gate must be **tests-green**; with no test command configured, the orchestrator warns and requires acknowledgement.

## Package-manager variance (NuGet)

These are the concrete commands the core `debt-taxonomy` *Upgrade workflow* delegates here:

| Step | Command / location |
|---|---|
| Discover outdated | `dotnet list package --outdated` (add `--include-transitive` to see pulled-in deps); `dotnet-outdated` if installed |
| Version location | **Central Package Management** — if `Directory.Packages.props` exists, the version is the `<PackageVersion>` there, update in **one place**; otherwise it's the `<PackageReference Include="X" Version="Y" />` in **each** `.csproj` — update every occurrence |
| Apply | edit the version, then `dotnet restore` |
| Verify | `dotnet build <project>.csproj` — capture output to a file and grep for errors (`context-discipline`) |

- **Conflict signal:** transitive conflicts surface as `NU1605` (downgrade) / `NU1107` (version conflict) → report and stop; never silently add a binding redirect or downgrade pin.
- **Release-notes URL** (core workflow step 2 fallback when Context7 has nothing): the package's NuGet page `https://www.nuget.org/packages/<id>`, or its project/repo `/releases` page when the `.nuspec` `projectUrl` points at a Git host.

## Upgrade-tier examples (.NET)

| Upgrade | Tier | Notes |
|---|---|---|
| `Newtonsoft.Json 12 → 13` | 1 | Major, but API-stable for most uses; pull migration notes via Context7 |
| `EF Core 7 → 8` | 1 | Usually API-stable |
| `EF Core 6 → 7` | 2 if raw SQL / provider changes required | Otherwise 1 |
| **TFM bump** (`net6.0 → net8.0`) | **2 — outline only** | Changes the `<TargetFramework>`; ripples through analyzers, dependencies, runtime behavior |
| SDK major (`global.json` `sdk.version`) | 2 — outline only | Platform-scale |
| Optimizely CMS major | 2 — outline only | Content-model and API migration is a project |
