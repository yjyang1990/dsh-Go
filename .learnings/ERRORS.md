# Errors

Command failures and integration errors.

---

## [ERR-20261121-002] stale-edit-and-script

**Logged**: 2026-11-21T10:40:00Z
**Priority**: low
**Status**: resolved
**Area**: tooling

### Summary
Several exact Serena needles and one inline TypeScript edit script failed while the remote transport patch was being applied.

### Errors
- ValueError: Error: No matches of search expression found.
- Expected comma, got async
- Expected semicolon, closing brace, or end of file

### Context
The Serena session was initially stale and the script mixed Dart multiline text with JavaScript template syntax. Re-activating the repository, reading the current symbol body, and using smaller replacements resolved the issue.

### Suggested Fix
Re-activate the current project after context restoration and prefer symbol-level reads before exact edits.

### Metadata
- Reproducible: yes
- Related Files: packages/dsh_client/lib/src/files_api.dart, packages/dsh_client/test/deliverables_test.dart

---

## [ERR-20261121-003] protocol-test-search-regex

**Logged**: 2026-11-21T13:26:10Z
**Priority**: low
**Status**: pending
**Area**: tests

### Summary
A grep query containing unescaped parentheses was rejected before source inspection.

### Error
```
grep pattern rejected by ripgrep: rg: regex parse error: (?:readFile() ... unclosed group
```

### Context
- Attempted to search `packages/dsh_remote/test` and `packages/dsh_client/lib/src/files_api.dart` for the readFile call signature.
- The command used a regex with literal parentheses.

### Suggested Fix
Use a literal or escaped pattern for method calls, then inspect the matching file.

### Metadata
- Reproducible: yes
- Related Files: packages/dsh_remote/test/remote_client_test.dart, packages/dsh_client/lib/src/files_api.dart

---

## [ERR-20261121-004] learnings-append-ambiguous

**Logged**: 2026-11-21T13:26:20Z
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
An append edit used a generic horizontal-rule needle that matched multiple existing entries.

### Error
```
old_string matched 2 times in .learnings/ERRORS.md
```

### Context
The error log contains multiple entries, so an unqualified `---` is ambiguous.

### Suggested Fix
Anchor append edits to a unique existing entry or use a controlled file append.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

---

## [ERR-20261121-005] remote-message-search-regex

**Logged**: 2026-11-21T13:31:30+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
A grep batch used an unescaped literal parenthesis and was rejected before searching remote message code.

### Error
```
grep pattern rejected by ripgrep: rg: regex parse error: (?:RemoteMessage() ... unclosed group
```

### Context
- Attempted to locate RemoteMessage and RPC response handling under packages.
- The pattern contained a literal method-call parenthesis.

### Suggested Fix
Use escaped parentheses or a literal search string before inspecting matching files.

### Metadata
- Reproducible: yes
- Related Files: packages/dsh_remote/lib

---
## [ERR-20261121-006] upstream-tree-json-truncated

**Logged**: 2026-11-21T13:36:55+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
Parsing the upstream GitHub tree response failed because the web fetch truncated JSON at 100000 characters.

### Error
```
SyntaxError: Unterminated string in JSON at position 100000 (line 1 column 100001)
```

### Context
- Attempted to parse the recursive GitHub tree response in memory to filter remote and bridge files.

### Suggested Fix
Fetch the API response to a file with curl or use the tree endpoint in smaller scoped requests.

### Metadata
- Reproducible: yes
- Related Files: packages/dsh_remote/lib/src/carrier/tunnel_carrier.dart

---

## [ERR-20261121-007] attachment-edit-script-syntax

**Logged**: 2026-11-21T13:40:00+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
An inline edit script for the remote attachment regression failed while embedding a multiline Dart string.

### Error
```
Expected comma, got )
```

### Context
The script constructed source text inside JavaScript and terminated the string before the Dart replacement was complete.

### Suggested Fix
Use Serena symbol edits or structured file writes instead of nested multiline string interpolation.

### Metadata
- Reproducible: yes
- Related Files: packages/dsh_remote/lib/src/carrier/tunnel_carrier.dart, packages/dsh_remote/test/remote_client_test.dart

---

## [ERR-20261121-008] learnings-edit-anchor

**Logged**: 2026-11-21T13:42:00+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
Two append attempts used ambiguous or invalid edit anchors while recording the preceding script failure.

### Error
```
old_string matched 6 times in .learnings/ERRORS.md
old_string was not found in .learnings/ERRORS.md
invalid arguments: old_string and new_string must differ
```

### Context
The log contains repeated separators and the first anchor was not unique.

### Suggested Fix
Read the complete file once, then write the preserved content plus new entries.

### Metadata
- Reproducible: yes
- Related Files: .learnings/ERRORS.md

---

## [ERR-20261121-009] client-heartbeat-test-flake

**Logged**: 2026-11-21T13:48:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
The full dsh_client test suite and isolated heartbeat test failed in an unrelated healthy control ping/pong case.

### Error
```
Bad state: StreamSink is closed
dart:_http _WebSocketImpl.add
test/dsh_go_heartbeat_test.dart 302:53 _HostConnection.send
test/dsh_go_heartbeat_test.dart 283:39 _Host.handle.<fn>
```

### Context
The workspace-file focused tests passed. The failure occurs in the existing heartbeat fixture while the fake host sends after its WebSocket sink closed.

### Suggested Fix
Treat this as an existing flaky test until its fixture lifecycle is repaired.

### Metadata
- Reproducible: yes
- Related Files: packages/dsh_client/test/dsh_go_heartbeat_test.dart

---

## [ERR-20261121-010] flutter-apk-locator

**Logged**: 2026-11-21T13:52:30+08:00
**Priority**: medium
**Status**: pending
**Area**: build

### Summary
The arm64 profile Flutter build completed Gradle assemble work but Flutter exited because it could not locate the generated APK.

### Error
```
Gradle build failed to produce an .apk file. It's likely that this file was generated under /Users/yyj/Documents/Deepseek Harness/dsh-go/app/build, but the tool couldn't find it.
```

### Context
Command: `flutter build apk --profile --target-platform android-arm64` from `app/`. Gradle ran for 193.8 seconds.

### Suggested Fix
Inspect the build outputs and use the repository APK build entry or the actual flavor output path.

### Metadata
- Reproducible: pending
- Related Files: app/build, tooling/build-apk.sh

---

## [ERR-20261121-011] session-device-search-timeout

**Logged**: 2026-11-21T13:55:00+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
Searching current session events for a prior adb connection command exceeded the tool timeout.

### Error
```
tool call timed out after 30000ms
```

### Context
The device is currently absent from adb devices, so a session-history search was attempted to recover the earlier connection hint.

### Suggested Fix
Use bounded local logs or wait for the operator device connection rather than repeatedly scanning session history.

### Metadata
- Reproducible: pending
- Related Files: .learnings/ERRORS.md

---

## [ERR-20261121-012] adb-device-wait-timeout

**Logged**: 2026-11-21T13:58:00+08:00
**Priority**: medium
**Status**: pending
**Area**: device

### Summary
The bounded wait for the Huawei device ended without an adb device.

### Error
```
command: timeout 90 adb wait-for-device
exit code: 124
```

### Context
`adb devices -l` remains empty after the arm64 profile APK was built. The APK cannot be installed or exercised until the physical device reconnects.

### Suggested Fix
Reconnect the Huawei device or restore its adb network/USB transport, then install the built APK and capture the viewer screen.

### Metadata
- Reproducible: pending
- Related Files: app/build/app/outputs/flutter-apk/app-arm64-profile.apk

---
