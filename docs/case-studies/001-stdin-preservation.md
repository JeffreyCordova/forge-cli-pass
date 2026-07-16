# Case study: Preserving standard input across asynchronous shell execution

## Summary

During real-world use of `glab-pass`, a GitLab API request using
`glab api --input -` failed because the JSON request body did not reach the
parent `glab` process.

The command worked when the same request body was supplied through a regular
file, isolating the failure to standard-input forwarding rather than GitLab
authentication, request formatting, project permissions, or API behavior.

The root cause was the interaction between POSIX shell asynchronous execution
and standard input. `glab-pass` runs `glab` asynchronously so that the wrapper
can handle HUP, INT, and TERM, perform conditional authentication-state
writeback, clean up transient state, and preserve documented signal statuses.

Under the supported shell implementations, the asynchronous child could receive
standard input from `/dev/null` instead of inheriting the caller's original
input stream.

The correction explicitly preserves the caller's standard input on a private
file descriptor before starting the asynchronous command and restores it for
`glab`.

A byte-for-byte regression test now runs under Dash, Bash in POSIX mode, and
BusyBox `ash`. The fix was released as `v0.1.1`.

## Context

`forge-cli-pass` provides command-compatible wrappers around the GitHub CLI and
GitLab CLI while keeping durable wrapper-managed authentication state in
`pass`.

`gh-pass` can replace itself directly with `gh`, but `glab-pass` has additional
responsibilities:

1. restore the complete GitLab CLI configuration from `pass`
2. stage that configuration in a protected temporary directory
3. run `glab`
4. detect eligible authentication-state changes
5. write changed state back to `pass`
6. remove the transient runtime directory
7. preserve parent, wrapper, and signal status semantics

To perform recovery and cleanup after HUP, INT, and TERM, `glab-pass` launches
`glab` as an asynchronous child and waits for it.

This process topology created a compatibility risk that did not exist in the
simpler `gh-pass` execution path.

## Expected compatibility contract

For an allowed ordinary command, the wrapper is expected to preserve:

- argument order
- argument boundaries
- empty arguments
- standard input
- standard output
- standard error
- the exact ordinary parent exit status when wrapper obligations succeed

The wrapper may deliberately reject credential-management or
credential-disclosure operations, but it should not otherwise alter the
ordinary parent CLI interface.

A command such as:

```sh
printf '%s\n' '{"description":"example"}' |
    glab-pass api \
        --method PUT \
        --header 'Content-Type: application/json' \
        projects/PROJECT_ID \
        --input -
```

must deliver the JSON bytes to `glab` exactly as direct invocation would.

## Observed failure

The issue appeared while adding GitLab project metadata through the API.

The original request used a here-document connected to `glab-pass`:

```sh
cat <<'JSON' | src/glab-pass api \
    --hostname gitlab.com \
    --method PUT \
    --header 'Content-Type: application/json;charset=UTF-8' \
    projects/PROJECT_ID \
    --input -
{
  "description": "GitLab mirror of forge-cli-pass: command-compatible gh and glab wrappers backed by pass.",
  "topics": [
    "authentication",
    "cli",
    "credential-management",
    "github-cli",
    "gitlab-cli",
    "linux",
    "pass",
    "password-store",
    "posix-shell",
    "shell-script"
  ]
}
JSON
```

GitLab returned HTTP 400 with an error indicating that no update parameter had
been supplied.

The request syntax, endpoint, content type, and JSON fields were valid, but the
server behaved as though the request body were empty.

## Investigation

### Initial hypotheses

Several plausible causes were considered:

1. The project path might require URL encoding.
2. The API might require a numeric project ID.
3. `glab api --input -` might require an explicit JSON content type.
4. The `topics` field might use a different request shape.
5. The wrapper might not be forwarding standard input.

The first four hypotheses concerned GitLab API usage. They were tested or
eliminated without resolving the failure.

### File-input comparison

The same JSON body was written to a temporary file and supplied using:

```sh
glab-pass api \
    --method PUT \
    --header 'Content-Type: application/json;charset=UTF-8' \
    projects/PROJECT_ID \
    --input "$request_file"
```

That request succeeded.

This comparison established that:

- authentication was working
- the API endpoint was correct
- the project ID was correct
- the JSON structure was accepted
- the content-type header was accepted
- `glab-pass` could perform the operation when stdin was not involved

The remaining difference was the use of `--input -`.

### Wrapper execution analysis

The relevant execution shape was:

```sh
GLAB_CONFIG_DIR=$runtime_dir command glab "$@" &
child_pid=$!

wait "$child_pid"
```

The wrapper required asynchronous execution for its signal-handling model.

In POSIX shell execution, an asynchronous command running without job control
may not retain the caller's original standard input. The shell may arrange for
the command's standard input to behave as though it were connected to
`/dev/null`.

As a result, `glab` received end-of-file when it attempted to read the request
body for `--input -`.

## Root cause

`glab-pass` preserved parent arguments and output streams but implicitly relied
on asynchronous child execution to preserve descriptor 0.

That assumption was invalid across the supported POSIX shell environment.

The wrapper's signal-management architecture therefore violated the documented
ordinary-command compatibility contract for stdin-dependent commands.

The defect was not specific to the GitLab metadata endpoint. It could affect
any allowed `glab` operation that reads from standard input, including:

- `glab api --input -`
- commands consuming piped content
- commands reading redirected files through descriptor 0
- future stdin-dependent `glab` operations

## Security and reliability impact

The defect did not disclose credential material, overwrite the durable password
store, or weaken temporary-file permissions.

Its impact was nevertheless security-relevant because the wrapper mediates a
security-sensitive command boundary.

### Integrity impact

A command could execute without receiving the intended request body. Depending
on the parent command, this could cause:

- an incomplete API operation
- a request with default or missing values
- incorrect automation behavior
- misleading server-side validation errors

### Compatibility impact

The wrapper claimed to preserve ordinary parent command behavior. Losing stdin
violated that contract.

### Operational impact

The failure initially appeared to be an authentication or API-formatting
problem, increasing diagnostic ambiguity and operator effort.

### Maintenance impact

The issue demonstrated that argument forwarding alone is insufficient for
command compatibility. File descriptors and process topology must also be
treated as part of the public interface.

## Considered corrections

### Run `glab` synchronously

Running `glab` directly in the foreground would naturally preserve stdin.

This was rejected because it would undermine the accepted signal-handling
architecture. The wrapper must retain control so it can:

- observe HUP, INT, and TERM
- terminate the child
- evaluate interrupted authentication state
- perform conditional writeback
- clean up the runtime directory
- preserve documented signal-derived statuses

### Copy stdin into a temporary file

The wrapper could read all caller input into a file and redirect that file into
`glab`.

This was rejected because it would:

- change streaming behavior
- delay parent startup until end-of-file
- add storage and cleanup obligations
- potentially retain non-credential input on disk
- fail for unbounded or interactive streams
- introduce unnecessary mediation of caller data

### Pipe stdin through an intermediary process

A helper process such as `cat` could relay input to `glab`.

This was rejected because it would add:

- another process
- another failure mode
- more complex signal behavior
- possible exit-status ambiguity
- no benefit over preserving the existing descriptor directly

### Preserve the original file descriptor

The selected correction duplicates the caller's descriptor 0 onto a private
descriptor before asynchronous execution.

The child then receives that preserved descriptor as its standard input, and
the extra descriptor is closed where no longer needed.

This approach:

- preserves streaming behavior
- does not buffer input
- does not create another temporary file
- does not introduce an intermediary process
- retains the existing asynchronous child model
- applies to pipes, redirected files, terminals, and other descriptor-backed
  input sources

## Selected implementation

Before launching `glab`, the wrapper preserves standard input on descriptor 9:

```sh
if ! exec 9<&0; then
    startup_failure 'failed to preserve standard input'
fi
```

The asynchronous parent command explicitly receives that descriptor as its
standard input:

```sh
GLAB_CONFIG_DIR=$runtime_dir command glab "$@" <&9 9<&- &
child_pid=$!
```

The wrapper then closes its copy:

```sh
exec 9<&-
```

The descriptor handling has three important properties:

1. Descriptor 0 is duplicated before asynchronous execution can alter its
   behavior.
2. The child receives the preserved input as descriptor 0.
3. Descriptor 9 is closed in both the child invocation and the wrapper after
   startup, avoiding an unnecessary inherited descriptor.

Failure to preserve standard input is treated as a wrapper startup failure
rather than silently executing `glab` with different input semantics.

## Regression-test design

The existing fake `glab` fixture already captured arguments, configuration
paths, permissions, mutation behavior, status codes, and signals.

It was extended with opt-in standard-input capture.

The capture is disabled by default so tests that do not provide stdin cannot
block waiting for input.

When enabled, the fixture copies standard input to a test-owned file:

```sh
case ${FAKE_GLAB_CAPTURE_STDIN:-0} in
0)
    ;;

1)
    cat >"$FAKE_GLAB_STDIN_LOG" || exit 68
    ;;

*)
    printf 'fake glab: invalid stdin capture mode: %s\n' \
        "$FAKE_GLAB_CAPTURE_STDIN" >&2
    exit 64
    ;;
esac
```

The behavioral test:

1. creates a payload containing multiple lines and shell-sensitive characters
2. enables fixture stdin capture
3. pipes the payload into `glab-pass`
4. asserts parent success
5. compares the captured bytes with the original payload

The comparison is file-based and byte-oriented rather than based on shell
command substitution, which could remove trailing newline characters.

## Cross-shell verification

The regression runs through the existing supported-shell matrix:

- Dash
- Bash in POSIX mode
- BusyBox `ash`

The complete verification interface also runs:

- ShellCheck in POSIX `sh` mode
- syntax checks under all three shells
- existing GitHub-wrapper behavioral tests
- GitLab staging, writeback, failure, policy, and signal tests
- installation and development-link tests

After the correction, the suite completed:

| Suite | Executions |
|---|---:|
| `gh-pass` behavioral tests | 51 |
| `glab-pass` behavioral tests | 93 |
| Installation tests | 8 |
| **Total** | **152** |

The stdin regression passed under every supported shell.

## Real-world confirmation

After the implementation change, the original piped GitLab API request
succeeded through `glab-pass`.

This confirmation was important because the fixture test established controlled
behavior, while the real API request verified the complete operational path:

```text
user shell
    → glab-pass
    → private GitLab config staging
    → preserved stdin
    → glab
    → GitLab API
    → state validation
    → cleanup
```

The combination of fixture evidence and real-world confirmation reduced the
risk of fixing only the test harness rather than the actual integration.

## Release handling

The correction changed observable wrapper behavior and therefore received a
patch release.

The release process included:

1. updating `VERSION` to `0.1.1`
2. adding the fix to `CHANGELOG.md`
3. running the complete local verification interface
4. pushing the release commit to GitHub and GitLab
5. confirming GitHub Actions passed on the exact release commit
6. creating a signed annotated `v0.1.1` tag
7. pushing the tag to both upstreams
8. verifying that both remote tags resolved to the intended commit
9. publishing the canonical GitHub release from the existing tag

The existing `v0.1.0` release and tag were not changed.

## Lessons

### Process topology is part of command compatibility

A wrapper can preserve `"$@"` perfectly and still alter parent behavior through
file descriptors, signals, environment variables, process groups, terminal
state, or working-directory changes.

### Real use complements fixture testing

The original suite exercised complex signal and authentication-state behavior,
but it did not include stdin-dependent commands.

The defect appeared during an ordinary maintenance operation against the real
GitLab API.

### Regression tests should encode the property, not only the incident

The new test does not special-case the metadata endpoint or JSON payload.

It asserts the broader property:

> Bytes supplied to `glab-pass` through standard input reach the parent `glab`
> process unchanged.

### Security tooling requires explicit failure semantics

Silently replacing stdin with an empty stream would have been easier to overlook
than a crash. Treating compatibility as a security property made the behavior a
release-worthy defect rather than an incidental shell quirk.

### A small fix can validate the maintenance system

The correction exercised the project's complete maintenance loop:

```text
field observation
    → hypothesis reduction
    → root-cause analysis
    → portable implementation
    → cross-shell regression
    → local verification
    → CI verification
    → signed patch release
```

That loop is part of the security value of the project, not merely release
administration.

## Related evidence

- [`../../src/glab-pass`](../../src/glab-pass)
- [`../../tests/test-glab-pass.sh`](../../tests/test-glab-pass.sh)
- [`../../tests/fixtures/bin/glab`](../../tests/fixtures/bin/glab)
- [`../threat-model.md`](../threat-model.md)
  - TM-09: wrapper changes parent command behavior
  - TM-11: upstream behavior invalidates assumptions
- [`../security-assurance.md`](../security-assurance.md)
  - SA-06: parent arguments and standard input are preserved
  - SA-11: verification is repeatable across supported shells
- [`../decisions/0004-language-platform-shell-and-utility-baseline.md`](../decisions/0004-language-platform-shell-and-utility-baseline.md)
- [`../decisions/0006-exit-status-and-failure-precedence.md`](../decisions/0006-exit-status-and-failure-precedence.md)
- [`../decisions/0007-signal-time-writeback-and-cleanup.md`](../decisions/0007-signal-time-writeback-and-cleanup.md)
- [`../decisions/0012-github-actions-verification.md`](../decisions/0012-github-actions-verification.md)
- [`../decisions/0013-versioning-and-release-publication.md`](../decisions/0013-versioning-and-release-publication.md)
- [`../../CHANGELOG.md`](../../CHANGELOG.md)
