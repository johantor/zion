---
name: tests-junit
description: JVM backend test conventions — JUnit 5 in src/test/java, Surefire vs Failsafe, Maven and Gradle targeted reruns. Load when the resolved backend stack is java.
---

# Backend tests: JUnit (JVM)

Detect the JUnit generation from the project's dependencies before writing — the two are not
source-compatible:

- `junit-jupiter` / `org.junit.jupiter.api.Test` → **JUnit 5 (Jupiter)**. `@Test`,
  `@BeforeEach`/`@AfterEach`, `@Disabled`, `@ParameterizedTest`, `Assertions.assertX`.
- `junit:junit:4.x` / `org.junit.Test` → **JUnit 4**. `@Before`/`@After`, `@Ignore`,
  `Assert.assertX`, `@RunWith`.
- Both present (the vintage engine) → a migration in progress. Write new tests against Jupiter and
  leave the JUnit 4 ones alone unless asked.

Check for `AssertJ` (`assertThat(x).isEqualTo(y)`) and `Mockito` before writing assertions or
doubles — if the project uses them, follow it rather than dropping to bare `Assertions`.

## Layout

Tests live in `src/test/java`, mirroring the production package path, with resources in
`src/test/resources`. A test in the **same package** as its subject can reach package-private
members without any reflection — prefer that to widening a production member's visibility for a
test's sake.

In a multi-module build each module has its own `src/test/java`; a test belongs to the module whose
code it exercises, not to a central test module.

## Unit vs integration is a naming convention, and it is load-bearing

Maven runs the two with different plugins, selected **by class name**:

- **Surefire** runs unit tests: `*Test.java`, `Test*.java`, `*Tests.java`, `*TestCase.java` —
  during the `test` phase.
- **Failsafe** runs integration tests: `IT*.java`, `*IT.java`, `*ITCase.java` — during
  `integration-test`, after the app is packaged.

So a slow, container-backed test named `FooTest` runs in the fast unit phase and slows every
build, and a genuine unit test named `FooIT` never runs under `mvn test` at all. Name by which
plugin should own it. Gradle has no such default — it uses whatever the `test`/`integrationTest`
source sets and filters declare, so read the build script rather than assuming.

## Writing

- One behavior per test, named for the behavior. `@DisplayName` carries the sentence when the
  method name can't.
- `@ParameterizedTest` with `@ValueSource`/`@CsvSource`/`@MethodSource` for the same assertion over
  several inputs, rather than a loop that reports only its first failure.
- `assertThrows(X.class, () -> …)` returns the exception — assert on its message or cause rather
  than only on its type.
- Prefer constructor injection and a plain `new` in the test to spinning a framework context;
  reserve `@SpringBootTest` for tests that genuinely need the container, and use the sliced
  annotations (`@WebMvcTest`, `@DataJpaTest`) when only one layer is under test.
- `@BeforeAll` is shared across the class, so anything mutable there leaks between tests. It must
  be `static` under the default per-method lifecycle; with `@TestInstance(PER_CLASS)` it need not
  be, so don't reject a non-static one before checking the class's lifecycle.

## Running

Run tests using the repository's backend test command from crew config, through the committed
wrapper (`./mvnw`, `./gradlew`) when there is one.

A **targeted rerun** is a filter, not a full build:

- Maven: `./mvnw test -Dtest=FooTest` · `-Dtest=FooTest#methodName` · `-Dtest='FooTest#a+b'`.
  Failsafe's equivalent is `-Dit.test=FooIT`.
- Gradle: `./gradlew test --tests 'com.example.FooTest'` ·
  `--tests 'com.example.FooTest.methodName'`.

Notes on reading a run:

- **Gradle caches and skips.** A `test` task reported `UP-TO-DATE` or `FROM-CACHE` did not execute
  anything; use `--rerun-tasks` (or `cleanTest test`) when you need a real run, and never read an
  up-to-date task as a pass.
- **A build failure is not a test failure.** A compile error in `src/test/java` fails the build
  before any test runs — report it as a build failure.
- Read the surefire/failsafe summary, not just the exit code, and report skipped counts rather
  than folding them into "green".

Never make a test pass with `@Disabled`/`@Ignore`, and never weaken an assertion to whatever the
code currently returns. If the production code is wrong, say so and hand it back.
