---
name: backend-java
description: Java/JVM backend stack conventions — Maven vs Gradle detection, Spring conventions, the src/main/java layout, and running the build as strictly as the project configures. Load when the resolved backend stack is java.
---

# Backend: Java

You are working in a JVM backend: Maven or Gradle, the `src/main/java` layout, and whatever
framework the project already uses (Spring Boot, Quarkus, Micronaut, or plain Jakarta — follow
the project).

## Detect the build tool before running anything

- `pom.xml` → **Maven** (`mvn`, or `./mvnw` when the wrapper is committed).
- `build.gradle` / `build.gradle.kts` / `settings.gradle*` → **Gradle** (`./gradlew` when the
  wrapper is committed).
- Both present → the project is mid-migration or multi-module. Ask `morpheus` rather than
  picking one.

**Always prefer the committed wrapper** (`./mvnw`, `./gradlew`) over a system `mvn`/`gradle`: the
wrapper pins the version the project builds with, and a system tool of a different major version
produces failures that are about the tool, not the code.

## Layout

`src/main/java` (production), `src/main/resources` (config, templates), `src/test/java` (tests —
`oracle`'s lane, not yours). In a multi-module build each module repeats that layout under its own
directory, and the reactor order in `pom.xml`/`settings.gradle` is what decides build order — a
new module is not picked up until it is declared there.

## Idiom

- Constructor injection over field injection; it keeps the class constructible in a test without a
  container.
- Don't catch and swallow. If you catch, either handle it or wrap it with the cause
  (`new XException(msg, e)`) — a caught exception logged and dropped loses the stack.
- Keep framework annotations on the boundary (controller, repository, configuration) rather than
  spreading them through domain classes.
- `Optional` is a return type, not a field or a parameter type.

## Build

Use the one-shot backend build command from crew config — typically `./mvnw -B verify` or
`./gradlew build`. Never run a watch/serve command as the build: `mvn spring-boot:run`,
`./gradlew bootRun`, `./gradlew --continuous`/`-t`, and `quarkus:dev` never terminate.

Run it as strict as the project configures:

- **Never skip a non-test check.** `-Dcheckstyle.skip`, `-Dspotbugs.skip`, `-Denforcer.skip` and
  friends each remove a part of the gate you were asked to run.
  `-DskipTests`/`-Dmaven.test.skip=true`/`-x test` are the exception: the crew runs tests through
  the separate **backend test command**, which `oracle` owns, so a build command that excludes
  them is deliberate. Don't add a test-skipping flag the command doesn't have, and don't report
  one it does have as a weakening. Note that `-Dmaven.test.skip=true` also skips *compiling* the
  tests, so a test that no longer compiles stays invisible until `oracle` runs — say so if you
  see it where `-DskipTests` would do.
- **Never narrow the reactor.** `-pl <module>` builds one module of many and can report clean
  while a sibling is broken. `-am`/`-amd` change which modules build too. Keep the configured shape.
- **Never go below the default log level.** Maven's `-q` hides warnings; Gradle's `-q` does the
  same. Keep the configured verbosity or raise it.
- **A Gradle up-to-date build proves nothing.** Gradle's incremental tasks report `UP-TO-DATE` and
  re-emit no warnings, so an unchanged tree can print a clean build a real compile would not. If
  the output shows the compile tasks were up to date, report that — not a clean build.
- **`-Dmaven.compiler.failOnWarning=false`, a lowered `--release`, or a disabled
  `-Werror`** are project settings, not invocation flags. Don't add them.

If the command **you were given** already carries one of these, don't rewrite it and don't report
the build clean: name the weakening as your first finding.

**A zero exit code is not "clean".** Javac warnings, Checkstyle/SpotBugs/PMD findings, and
deprecation notes all coexist with a successful build unless the project fails on them. Read the
warning summary and report each finding as its rule id, `file:line`, and a count per id — not the
raw log (`context-discipline`).

## `target/` and `build/` are per-writer state

Maven's `target/` and Gradle's `build/` are per-build-writer directories, and the Gradle daemon
takes a lock on the project. Two concurrent runs against the same module either block or produce
half-written outputs. If another crew build/test/lint run may be live against the same project,
either wait for it or get your own output directory before starting, and say which you did in your
findings. The **shared, read-mostly** part is the dependency cache (`~/.m2/repository`,
`GRADLE_USER_HOME`) — point every build at one rather than isolating it.

## Docs

When a docs MCP (e.g. Context7) is available, consult it for current, version-specific API docs
for the framework or driver rather than relying on memory; fetch the specific topic, not a dump
(`context-discipline`).
