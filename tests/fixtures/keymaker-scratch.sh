#!/usr/bin/env bash
# Builds a planted-debt scratch repo for exercising keymaker's verification matrix
# (plugins/keymaker/README.md). Prints the repo path on stdout; everything else
# goes to stderr, so it composes:
#
#   repo="$(bash tests/fixtures/keymaker-scratch.sh)"
#   cd "$repo" && claude --plugin-dir /path/to/plugins/keymaker -p "/keymaker:audit src/"
#
# Why a generator instead of a committed fixture: a git repo can't be nested
# inside this one, and the matrix rows need real `git init`/commits to assert
# against. The plant is deliberately small — marker files, not a working build.
#
#   --stack ts|dotnet   which taxonomy to plant for (default ts)
#   --dir <path>        where to build (default: a fresh mktemp dir)
#
# The plant covers the justification rows specifically (keymaker 0.8.0): for each
# stack, same-rule suppressions where some carry a meaningful native justification
# and some don't, plus a justified-AND-stale one and an annotated skipped test —
# the two documented filter exemptions.
set -uo pipefail

stack=ts
dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    # The arg-count guard is load-bearing: `shift 2` with one argument left fails
    # *without shifting*, and with no `set -e` the loop would spin on the same $1
    # forever rather than erroring.
    --stack)
      [ "$#" -ge 2 ] || { echo "FATAL: --stack needs a value (ts|dotnet)" >&2; exit 1; }
      stack="$2"; shift 2 ;;
    --dir)
      [ "$#" -ge 2 ] || { echo "FATAL: --dir needs a path" >&2; exit 1; }
      dir="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" >&2; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
case "$stack" in ts|dotnet) ;; *) echo "--stack must be ts or dotnet" >&2; exit 1 ;; esac

command -v git >/dev/null 2>&1 || { echo "FATAL: git is required" >&2; exit 1; }

if [ -z "$dir" ]; then
  dir="$(mktemp -d "${TMPDIR:-/tmp}/keymaker-scratch.XXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
fi
mkdir -p "$dir" || { echo "FATAL: cannot create $dir" >&2; exit 1; }

w() {
  mkdir -p "$dir/$(dirname "$1")" || { echo "FATAL: could not create the directory for $1" >&2; exit 1; }
  cat > "$dir/$1" || { echo "FATAL: could not write $1" >&2; exit 1; }
}

# Crew-config block: keymaker reads these slots, and an unset one makes it ask —
# which a headless run cannot answer. Plan dir is outside .claude/ because Claude
# Code treats that directory as sensitive and refuses edits there.
w CLAUDE.md <<'EOF'
# Scratch fixture

## Crew configuration

- **Base branch:** main
- **Backend test command:** none
- **Frontend test command:** none
- **Backend build command:** none
- **Frontend build command:** none
- **Plan directory:** docs/plans/
EOF

if [ "$stack" = ts ]; then
  w package.json <<'EOF'
{
  "name": "keymaker-scratch",
  "version": "1.0.0",
  "private": true,
  "devDependencies": { "eslint": "^9.0.0", "typescript": "^5.4.0" }
}
EOF
  w tsconfig.json <<'EOF'
{ "compilerOptions": { "strict": true, "target": "ES2022" } }
EOF

  # Row: justified excluded. Three no-explicit-any sites; the third carries a
  # meaningful ESLint `--` description, so a correct audit reports two and
  # accounts for one as justified.
  w src/orders/total.ts <<'EOF'
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function total(order: any): number {
  return order.lines.reduce((sum: number, l: any) => sum + l.price, 0);
}
EOF
  w src/orders/format.ts <<'EOF'
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function format(order: any): string {
  return `Order ${order.id}`;
}
EOF
  w src/orders/vendor.ts <<'EOF'
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- third-party webhook payload is genuinely untyped
export function fromWebhook(payload: any): string {
  return String(payload.id);
}
EOF

  # Row: `stale` ignores justifications. Justified AND stale (no `any` on the
  # next line, so the rule can no longer fire) — must still appear under `stale`.
  w src/users/lookup.ts <<'EOF'
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- kept while the legacy client is around
export function userName(id: string): string {
  return id.trim();
}
EOF

  # Row: skipped tests never excluded, however descriptive the annotation.
  w tests/orders.test.ts <<'EOF'
import { total } from "../src/orders/total";

// Skipped deliberately: the pricing service contract changes next sprint.
it.skip("totals an order with discounts", () => {
  expect(total({ lines: [] })).toBe(0);
});
EOF
else
  w Directory.Packages.props <<'EOF'
<Project>
  <PropertyGroup><ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally></PropertyGroup>
</Project>
EOF
  w src/Orders/Orders.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup>
</Project>
EOF

  # Justified vs unjustified: bare #pragma (no trailing reason) vs one carrying
  # the conventional trailing comment, plus a SuppressMessage with Justification.
  w src/Orders/OrderService.cs <<'EOF'
namespace Orders;

public class OrderService
{
    public string Describe(Order order)
    {
#pragma warning disable CS8602
        return order.Customer.Name;
#pragma warning restore CS8602
    }
}
EOF
  w src/Orders/OrderReport.cs <<'EOF'
namespace Orders;

public class OrderReport
{
    public string Title(Order order)
    {
#pragma warning disable CS8602 // EF Include() guarantees Customer is populated on this path
        return order.Customer.Name;
#pragma warning restore CS8602
    }
}
EOF
  w src/Orders/Validation.cs <<'EOF'
using System.Diagnostics.CodeAnalysis;

namespace Orders;

public class Validation
{
    [SuppressMessage("Design", "CA1062", Justification = "arguments are validated by the ASP.NET model binder before this runs")]
    public static bool IsValid(Order order) => order.Total > 0;
}
EOF
  w tests/Orders.Tests/OrderServiceTests.cs <<'EOF'
using Xunit;

namespace Orders.Tests;

public class OrderServiceTests
{
    [Fact(Skip = "pricing service contract changes next sprint")]
    public void DescribesAnOrder() { }
}
EOF
fi

git init -q -b main "$dir" >/dev/null 2>&1 || { echo "FATAL: git init failed in $dir" >&2; exit 1; }
git -C "$dir" config user.email scratch@example.invalid
git -C "$dir" config user.name "Keymaker Scratch"
git -C "$dir" config commit.gpgsign false
git -C "$dir" add -A >/dev/null 2>&1
git -C "$dir" commit -q -m "scratch: planted debt fixture ($stack)" >/dev/null 2>&1 \
  || { echo "FATAL: seed commit failed in $dir" >&2; exit 1; }

{
  printf 'Built %s scratch repo at: %s\n' "$stack" "$dir"
  printf 'Planted for the justification rows:\n'
  if [ "$stack" = ts ]; then
    printf '  unjustified no-explicit-any : src/orders/total.ts, src/orders/format.ts\n'
    printf '  justified   no-explicit-any : src/orders/vendor.ts (ESLint -- description)\n'
    printf '  justified AND stale         : src/users/lookup.ts (no any left on the line)\n'
    printf '  annotated skipped test      : tests/orders.test.ts (it.skip)\n'
  else
    printf '  unjustified CS8602          : src/Orders/OrderService.cs (bare #pragma)\n'
    printf '  justified   CS8602          : src/Orders/OrderReport.cs (trailing reason)\n'
    printf '  justified   CA1062          : src/Orders/Validation.cs (Justification param)\n'
    printf '  annotated skipped test      : tests/Orders.Tests/OrderServiceTests.cs\n'
  fi
} >&2

printf '%s\n' "$dir"
