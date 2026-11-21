# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---

## [LRN-20261121-001] correction

**Logged**: 2026-11-21T10:34:00Z
**Priority**: high
**Status**: in_progress
**Area**: backend

### Summary
Remote image preview failures must be traced through the remote file transport, not addressed only with a retry affordance.

### Details
The reported Android workflow opens an image on a connected computer. The app selects remote byte materialization for a remote connection, but `DshClient.readFile` only falls back to `GET /api/file` after a `DshProtocolException`. A remote HTTP host that lacks `workspaceFiles/readBytes` can return HTTP 404 or 405, which currently bypasses that fallback and reaches the preview error page.

### Suggested Action
Keep compatibility fallback behavior aligned with the documented HTTP file route and cover unavailable readBytes endpoints with a client regression test.

### Metadata
- Source: user_feedback
- Related Files: packages/dsh_client/lib/src/files_api.dart, packages/dsh_client/test/deliverables_test.dart
- Tags: remote-files, image-preview, correction

---
