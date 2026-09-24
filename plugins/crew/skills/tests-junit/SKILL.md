---
name: tests-junit
description: JVM backend test conventions — JUnit 5 in src/test/java, Surefire vs Failsafe, Maven and Gradle targeted reruns. Load when the resolved backend stack is java.
---

# Backend tests: JUnit (JVM)

Detect the JUnit generation from the project's dependencies — the two are not source-compatible:

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

Run the backend test command from crew config through the committed wrapper (`./mvnw`,
`./gradlew`) when there is one.

- **Targeted rerun:** Maven `./mvnw test -Dtest=FooTest` · `-Dtest=FooTest#methodName` ·
  `-Dtest='FooTest#a+b'` (Failsafe: `-Dit.test=FooIT`); Gradle `./gradlew test --tests
  'com.example.FooTest'` · `--tests 'com.example.FooTest.methodName'`.
- **Discovery:** there is no list-tests command. Run the new test targeted and read its `Tests
  run:` line, or the per-class report under `target/surefire-reports/` or
  `build/test-results/test/`. A class the runner never mentions has a naming problem (the
  Surefire/Failsafe patterns above), a module problem, or a missing engine dependency — check the
  build file; never inspect `target/classes` or `build/classes` to look for it.
- **Reading a run:** a Gradle `test` task reported `UP-TO-DATE` or `FROM-CACHE` did not execute
  anything — `--rerun-tasks` (or `cleanTest test`) forces a real run. A compile error in
  `src/test/java` fails the build before any test runs — a build failure, not a test failure.
  Read the surefire/failsafe summary; skipped counts are results.
- **Skip mechanism:** `@Disabled` (Jupiter), `@Ignore` (JUnit 4).
