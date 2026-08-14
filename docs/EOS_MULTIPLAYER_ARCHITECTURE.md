# EOS Home Island Multiplayer Architecture

Status: protocol contract for implementation and acceptance testing

Scope: invite-only, host-mediated Home Island sessions with at most 8 sailors

Minimum OS: iOS/iPadOS 17
Protocol version: `1.0`

## 1. Decision summary

Landfall uses a hybrid architecture, not EOS P2P as the only source of truth.

- EOS Connect identifies the live participant, EOS Lobby defines live membership and the current **network host**, and EOS P2P carries low-latency session traffic.
- The trusted backend remains the control plane for room membership, the immutable island owner, durable island checkpoints, canonical chat evidence, reports, and blocks.
- P2P uses a star: every guest exchanges packets only with the current network host. A guest-to-guest mesh is forbidden.
- `PrivateIslandRoom.hostUid` means **island owner / edit authority**. It is never changed by host migration.
- EOS Lobby owner means **network host / relay authority**. It may change whenever EOS migrates the lobby owner.
- A migrated network host may relay the last valid island snapshot but may not edit it. If the island owner is absent, the island is read-only.
- Lobby-owner notification is the only authority for an unplanned network-host change. Clients must not run an independent election; that would allow split brain.

EOS P2P alone cannot provide offline-host visits, a durable island, durable chat history, or trustworthy moderation evidence after all peers leave. Those requirements are why the backend checkpoint/chat paths remain in the design.

## 2. Existing model boundary

The transport must not encode Swift structs with `Codable`, JSON, property lists, or `MemoryLayout`. Wire DTOs are explicit binary schemas and are converted at the UI/SceneKit boundary.

| Existing type | Transport representation | Rule |
| --- | --- | --- |
| `HomeIslandRemotePlayerState` | quantized `PlayerSample` / `WorldFrameMember` plus reliable discrete state | Keep interpolation time, velocity, sequence, link nonce, and slot outside the existing renderer model. Convert to the existing type only after validation and interpolation. |
| `HomeIslandSnapshot` | `SnapshotManifest`, binary placement document, chunks, and owner-authored deltas | Never transmit `ownerKey`. Add transport metadata `revision` and SHA-256 outside the existing model. Preserve placement transforms as finite IEEE-754 `Float32`. |
| `PrivateIslandChatMessage` | `ChatSubmit`, low-latency `ChatCommit`, and backend canonical acknowledgement | Derive the sender from the EOS remote Product User ID and backend identity binding, never from a claimed payload field. `createdAt` becomes canonical only after backend acknowledgement. |

Existing limits remain protocol limits:

- at most 8 lobby members;
- at most 120 island placements;
- positions are finite and inside the current island bound (`abs(x) <= 80`, `abs(z) <= 80`);
- chat is at most 500 user-perceived characters and also at most 2,048 UTF-8 bytes.

## 3. Identities, roles, and trust

### 3.1 Required identifiers

The session coordinator keeps these values distinct:

| Name | Lifetime | Source |
| --- | --- | --- |
| `roomID` | durable | trusted backend |
| `islandOwnerUID` | durable and immutable for a room | trusted backend; currently `room.hostUid` |
| `localPUID` | EOS login session | EOS Connect |
| `networkHostPUID` | current lobby term | EOS Lobby owner |
| `hostEpoch` | one network-host term | current Lobby owner, see section 9 |
| `memberSlot` | live room membership | host roster, values `0...7` |
| `linkNonce` | one guest-host P2P link | 64 random bits generated for each handshake |

The backend must issue a short-lived signed join ticket binding at least:

```text
roomID, backendUID, eosPUID, islandOwnerRole, expiration, oneTimeNonce
```

An invite code is a locator, not authentication. The EOS PUID-to-backend UID mapping is accepted only after the join ticket is verified. Tickets must expire quickly and must not be reusable for another room.

### 3.2 Authority matrix

| Operation | Authority |
| --- | --- |
| Lobby membership and current relay | current EOS Lobby owner |
| Position validation and live world-frame order | current network host |
| Placement add/update/remove | original island owner only |
| Durable island revision | trusted backend owner-authorized checkpoint |
| Fast chat display order | current network host |
| Canonical chat author/time/evidence | trusted backend, written under the sender's authenticated identity |
| Report and block state | trusted backend / local account policy |

A player-hosted network host is not a trusted server. It can disrupt or lie about transient live state. It must never be allowed to mint a durable owner edit or another sailor's canonical chat message.

## 4. Lobby and P2P topology

Create an invite-only EOS Lobby with a maximum of 8 members and automatic lobby-owner migration enabled. The exact SDK field name (currently exposed in EOS SDKs as the inverse `bDisableHostMigration`) must be confirmed against the pinned iOS EOS SDK header during adapter implementation.

Lobby attributes carry only small discovery/state metadata:

```text
protocolMajor = 1
protocolMinor = 0
roomIDHash
hostEpoch
rosterGeneration
checkpointRevision
checkpointHashPrefix
```

Do not put the island snapshot or chat history into lobby attributes.

P2P socket name: `LFISLAND1`. Each guest establishes one bidirectional connection with `networkHostPUID`. The host accepts a connection request only if all of the following are true:

1. the remote PUID is a current member of the same EOS Lobby;
2. the PUID is bound to a valid backend join ticket for this room;
3. the remote is not blocked by session policy;
4. the topology expects that link (host-to-member, or member-to-current-host);
5. per-peer and room capacity limits are not exceeded.

Packets from a lobby member on an unexpected guest-to-guest link are closed and ignored. Live motion uses delayed delivery disabled so stale samples are not queued before a connection exists. Control and reliable resync packets may use delayed delivery only while the same authenticated handshake is active.

## 5. Wire format

### 5.1 Encoding rules

- The Landfall application packet limit is **1,024 bytes**, including the 48-byte header. This deliberately stays below the EOS SDK transport maximum; the pinned SDK header remains the final integration check.
- Maximum payload is **976 bytes**.
- All multibyte integers use network byte order (big endian).
- Snapshot floats are IEEE-754 binary32 in network byte order and must be finite.
- Realtime positions are integer centimeters; yaw is quantized `UInt16` over `[0, 2pi)`.
- Strings are UTF-8 with an explicit unsigned byte length. Invalid UTF-8 is rejected, not repaired.
- A decoder consumes exactly `headerBytes + payloadBytes`. Truncation, integer overflow, and unexpected trailing bytes are errors.
- Version 1 never compresses packets. A compressed flag is rejected. This avoids decompression bombs and is unnecessary for the current 32 KiB snapshot cap.
- Optional future fields use payload-local TLVs: `type: UInt8`, `length: UInt16`, then `length` bytes. Unknown optional TLVs are skipped after bounds checks. Required fields remain fixed.

### 5.2 Fixed header

Every application packet begins with this 48-byte header:

| Offset | Bytes | Field | Version 1 requirement |
| ---: | ---: | --- | --- |
| 0 | 4 | `magic` | ASCII `LFEP` (`4C 46 45 50`) |
| 4 | 1 | `protocolMajor` | `1` |
| 5 | 1 | `protocolMinor` | `0` |
| 6 | 1 | `kind` | registered in section 6 |
| 7 | 1 | `flags` | defined below |
| 8 | 2 | `headerBytes` | exactly `48` |
| 10 | 2 | `payloadBytes` | `0...976`; exact remaining byte count |
| 12 | 4 | `hostEpoch` | nonzero after `Welcome`; `0` is allowed only for initial `Hello` |
| 16 | 4 | `sequence` | per link, epoch, and stream |
| 20 | 4 | `hostTickMs` | monotonic host milliseconds modulo `2^32`; zero in pre-welcome `Hello` |
| 24 | 1 | `senderSlot` | `0...7`; `0xFF` before slot assignment |
| 25 | 1 | `stream` | must equal the EOS channel on which the packet arrived |
| 26 | 1 | `fragmentIndex` | zero based |
| 27 | 1 | `fragmentCount` | `1` for unfragmented; otherwise `2...255` and index must be smaller |
| 28 | 8 | `linkNonce` | random per handshake; binds delayed packets to one link incarnation |
| 36 | 8 | `messageID` | random transport dedupe/group ID; zero only for nonfragmented motion/ping |
| 44 | 4 | `reserved` | must be zero in version 1 |

Flags:

```text
bit 0  ACK_REQUIRED
bit 1  IS_ACK
bit 2  KEYFRAME
bit 3  FINAL_FRAGMENT
bit 4  COMPRESSED       (must be 0 in v1)
bit 5  BACKEND_COMMITTED
bits 6...7              (must be 0 in v1)
```

`FINAL_FRAGMENT` must agree with `fragmentIndex == fragmentCount - 1`. Each fragment has its own sequence; all fragments of one logical message share `messageID`. Reassembly is capped per message and per peer before any allocation.

### 5.3 Epoch and sequence comparison

`hostEpoch` and `sequence` are unsigned serial numbers. A value `a` is newer than `b` exactly when:

```swift
Int32(bitPattern: a &- b) > 0
```

Comparisons are valid only inside a window smaller than `2^31`; implementations must never advance or buffer a larger window. An older epoch is always dropped. Within the current epoch, dedupe/order state is keyed by:

```text
(linkNonce, authenticatedSenderPUID, stream)
```

`sequence` increments for every packet sent on that stream. It does not reset during an ordinary reconnect in the same host epoch. A newly accepted `linkNonce` invalidates queued packets from the old link. Reliable logical operations additionally use their stable UUID/revision so retransmission across a new link remains idempotent.

## 6. Streams, reliability, and packet kinds

Do not mix reliability classes on one EOS channel.

| EOS channel | Stream | EOS reliability | Packet kinds | Application rule |
| ---: | --- | --- | --- | --- |
| 0 | session control | Reliable Ordered | `Hello`, `Welcome`, `Ready`, `Reject`, `HostClaim`, `Roster`, `ResyncRequest`, `ResyncComplete` | state-machine gated; handshake timeout applies |
| 1 | motion | Unreliable Unordered | `PlayerSample`, `WorldFrame` | latest valid sequence wins; never retransmit |
| 2 | discrete world | Reliable Ordered | `DiscreteSubmit`, `DiscreteCommit`, `WorldKeyframe` | seat, stand, scene, phase, arrival/departure; idempotent event UUID |
| 3 | chat | Reliable Ordered | `ChatSubmit`, `ChatCommit`, `ChatReject`, `ChatBacklog`, `ChatTombstone` | client UUID dedupe and explicit commit/reject |
| 4 | snapshot control/delta | Reliable Ordered | `SnapshotManifest`, `SnapshotAck`, `SnapshotNack`, `SnapshotDelta`, `SnapshotFullRequest` | revision/base-revision validation |
| 5 | snapshot data | Reliable Unordered | `SnapshotChunk` | index/hash validation; missing bitmap repair |
| 6 | diagnostics | Unreliable Unordered | `Ping`, `Pong`, `Metrics` | bounded; no gameplay dependency |

Registered version 1 kind values:

```text
0x01 Hello                0x02 Welcome
0x03 Ready                0x04 Reject
0x05 HostClaim            0x06 Roster
0x07 ResyncRequest        0x08 ResyncComplete

0x10 PlayerSample         0x11 WorldFrame
0x20 DiscreteSubmit       0x21 DiscreteCommit
0x22 WorldKeyframe

0x30 ChatSubmit           0x31 ChatCommit
0x32 ChatReject           0x33 ChatBacklog
0x34 ChatTombstone

0x40 SnapshotManifest     0x41 SnapshotAck
0x42 SnapshotNack         0x43 SnapshotDelta
0x44 SnapshotFullRequest  0x45 SnapshotChunk

0x50 Ping                 0x51 Pong
0x52 Metrics
```

Unknown kinds from the same major version are ignored only after the full envelope is safely consumed. An unsupported major version gets one bounded `Reject(unsupportedVersion)` response and then the link closes.

## 7. Connection state machine

```text
idle
  -> authorizing
  -> lobbyJoined
  -> linkOpening
  -> handshaking
  -> syncing
  -> ready

ready -> reconnecting -> handshaking
ready -> migrating    -> handshaking (with new Lobby owner)
any   -> closing      -> idle
```

### 7.1 Guest handshake

1. Verify backend membership and obtain the signed join ticket.
2. Join the EOS Lobby and read its current owner.
3. Generate a cryptographically random `linkNonce`; open only the owner link.
4. Send `Hello` on channel 0 containing supported major/minor range, app build, room hash, join-ticket reference, last accepted host epoch, last world keyframe, checkpoint revision/hash, chat backend cursor, and roster generation.
5. Host validates EOS receive metadata and ticket, assigns/resumes a slot, then sends `Welcome`: accepted protocol version, current host epoch/tick, slot, complete PUID-to-slot roster, checkpoint/chat digests, and required sync actions.
6. Guest synchronizes roster, checkpoint, chat cursor, reliable discrete state, and a world keyframe. It stays invisible to other players until validation and atomic snapshot application complete.
7. Guest sends `Ready` with the applied revisions/hashes. Host adds it to the next roster/world frame and returns `ResyncComplete`.

Before `ready`, only channel 0, requested snapshot chunks, and requested chat backlog are accepted. Motion and edit submissions are dropped.

### 7.2 Timers

| Timer | Value | Result |
| --- | ---: | --- |
| EOS lobby join | 10 s | fail with a retryable UI error |
| link open / `Hello` to `Welcome` | 5 s | close link and retry |
| ordinary sync | 10 s | request one full resync |
| maximum full snapshot sync | 20 s | close/retry; never show partial island |
| ping interval | 2 s | record RTT/offset only |
| suspect host | 3 missed pings / 6 s | pause submissions and query Lobby owner |
| disconnected slot grace | 15 s | preserve slot and avatar identity |

The Lobby owner-change notification, not the ping timer, authorizes migration.

## 8. Realtime player state and interpolation

### 8.1 Motion payload

Guests send `PlayerSample` at no more than 10 Hz and only after meaningful change. The 16-byte member body used by both sample and aggregate world frames is:

| Bytes | Field |
| ---: | --- |
| 1 | slot |
| 1 | flags (`visible`, `hasVelocity`, reserved) |
| 1 | pose code |
| 1 | scene code |
| 1 | phase code |
| 1 | reserved zero |
| 2 | signed x centimeters |
| 2 | signed z centimeters |
| 2 | yaw quantized over one turn |
| 2 | signed x velocity cm/s |
| 2 | signed z velocity cm/s |

Seat placement UUID/slot and arrival nonce are not repeated in motion. They are reliable discrete events. String enums are converted to a versioned numeric allowlist by the adapter and unknown values are rejected.

The host validates sender identity, slot, finite/range-converted coordinates, transition legality, and speed. A default walking limit of 6 m/s is enforced unless a reliable arrival/scene transition explicitly authorizes a teleport. It then fans out one `WorldFrame` containing all active member bodies at 10 Hz. Every frame is self-contained for motion, so losing one does not make the next frame undecodable.

### 8.2 Renderer buffer

Network timing metadata remains outside `HomeIslandRemotePlayerState`.

- Keep 4 to 6 accepted frames per player.
- Estimate host clock offset using `Ping`/`Pong`; use monotonic time only.
- Render at `estimatedHostNow - interpolationDelay`.
- Start at 150 ms; adapt to observed jitter, clamped to 100...250 ms.
- Interpolate x/z linearly or with a bounded Hermite curve. Interpolate yaw on the shortest arc.
- Extrapolate using validated velocity for at most 250 ms, then freeze at idle.
- Fade a state that has no update for 3 s. Keep its identity/slot for the 15 s reconnect grace.
- Snap when correction distance is greater than 3 m, matching the existing renderer threshold. Otherwise reconcile over about 200 ms.
- A reliable seat, stand, scene, phase, or arrival event flushes incompatible buffered motion and snaps to its authoritative anchor.

`arrivalNonce` and discrete event UUIDs are deduped so reconnect, retransmit, and migration cannot replay arrival animation or system chat.

## 9. Reconnect and network-host migration

### 9.1 Ordinary reconnect

On a recoverable network loss, retry after approximately `0.5, 1, 2, 4, 8, 15` seconds with 0...20% jitter. Re-query Lobby membership and owner before each new handshake. Never assume the previous P2P peer is still host.

The reconnecting member sends the same authenticated PUID, a new `linkNonce`, and its world/checkpoint/chat/roster cursors. During the 15-second grace the host returns the same slot, then sends only the missing reliable records plus a complete current world keyframe. After grace expiry it is a fresh join and old remote state is removed.

Backgrounding should attempt a graceful departure but correctness must not depend on it. Foreground always re-queries the Lobby and handshakes again. Delayed packets carrying the previous link nonce or host epoch are dropped.

### 9.2 Planned handoff

1. Current network host chooses a foreground member with a healthy link, recent checkpoint acknowledgement, and low RTT.
2. It sends a reliable handoff digest: epoch, roster/generation, member cursors, backend checkpoint revision/hash, pending snapshot transfer IDs, and chat cursor.
3. Candidate acknowledges the digest.
4. Current owner uses the EOS Lobby promote-member operation.
5. Only after the Lobby owner-change notification does the candidate become network host, advance `hostEpoch`, publish the Lobby epoch attribute, and send `HostClaim`.
6. All members reconnect/retarget to the new owner and send migration reports; old host leaves only after the candidate's acknowledgement or a bounded timeout.

Target: ready traffic resumes within 2 seconds of the owner-change notification.

### 9.3 Unplanned migration

1. On host suspicion, pause placement commits, reliable discrete submissions, and chat ordering. Local movement may continue visually but is not committed.
2. Query the EOS Lobby and wait for its owner-change notification. Do not elect a host through P2P messages.
3. The notified new Lobby owner reads the last Lobby `hostEpoch` and advances it exactly once, then writes the Lobby attribute and broadcasts `HostClaim`. A peer report is never allowed to choose or advance the term. If the Lobby attribute is missing/corrupt, recover the term through the trusted session control plane or recreate the Lobby; do not guess from unauthenticated packets.
4. A peer accepts `HostClaim` only when the EOS sender metadata equals the current Lobby owner and the term is newer. A claim from the old owner or a nonowner is ignored.
5. Every member sends its own latest player state and roster/chat/checkpoint cursors. The host reconstructs motion from each member's self-report, not from another guest's claim.
6. Reload the trusted backend checkpoint. If the island owner is online, it may submit a newer owner-authorized checkpoint/delta after resync. If the owner is absent, discard uncheckpointed edit candidates and remain read-only.
7. Reconcile backend canonical chat and idempotently resend the local sender's unacknowledged client message IDs.
8. Publish a complete roster, reliable world keyframe, snapshot manifest if needed, then `ResyncComplete`.

Target: ready traffic resumes within 8 seconds of the owner-change notification. If the installed EOS SDK/platform configuration cannot automatically migrate a Lobby owner, the fallback is explicit lobby recreation plus backend restore; a client-side election is still forbidden.

An old host returning later joins as a guest. It cannot reclaim network authority unless EOS promotes it, and it can never gain island edit authority unless it is the immutable island owner.

## 10. Island snapshot synchronization

### 10.1 Canonical and live revisions

Maintain two explicit concepts:

- `candidateRevision`: owner-authored live state visible optimistically in the session;
- `checkpointRevision`: the latest owner-authorized snapshot accepted by the trusted backend.

Only `checkpointRevision` survives an owner-absent migration. A network host may validate and relay an owner delta but may not create one. A backend revision/hash conflict fails closed and requests a full canonical checkpoint.

Persist a checkpoint after 2 seconds without another edit or after 16 operations, whichever happens first. Successful backend persistence publishes its revision/hash to peers. These values are transport metadata; they do not change `HomeIslandSnapshot` itself.

### 10.2 Binary snapshot document

The full document excludes `ownerKey` and contains:

```text
schemaVersion:   UInt16
placementCount: UInt16 (0...120)
repeat placementCount times:
    placementID: 16 raw UUID bytes
    assetIDBytes: UInt8 (0...64)
    assetID:      UTF-8 bytes
    x:            Float32
    z:            Float32
    yaw:          Float32
    scale:        Float32
```

Maximum encoded document size is 32,768 bytes. Decode in a temporary value, use checked arithmetic, validate UUID uniqueness, approved assets and per-asset rules, sanitize using the same domain rules as current persistence, verify count and SHA-256, and only then atomically replace the displayed island. Never apply a partial document.

### 10.3 Manifest and chunks

`SnapshotManifest` fixed fields:

```text
transferID UInt64
schemaVersion UInt16
reserved UInt16 = 0
revision UInt64
baseRevision UInt64          // 0 for full snapshot
byteCount UInt32             // <= 32768
chunkDataBytes UInt16        // <= 900
chunkCount UInt16            // <= 37
placementCount UInt16        // <= 120
reserved UInt16 = 0
sha256 [32]UInt8
```

`SnapshotChunk` payload:

```text
transferID UInt64
chunkIndex UInt16
chunkCount UInt16
byteOffset UInt32
dataLength UInt16            // <= 900
reserved UInt16 = 0
data [dataLength]UInt8
```

Chunks may arrive out of order or more than once. Reassembly permits at most one 32 KiB transfer per peer and two outgoing full transfers at the host. After 750 ms without progress, send `SnapshotNack` with the missing-index bitmap. Timeout after 5 seconds and retry the transfer at most three times before reconnect/full-backend recovery. `SnapshotAck` is sent only after hash, decode, validation, and atomic apply succeed.

### 10.4 Live deltas

Owner changes use add/update/remove operations with `baseRevision`, `newRevision`, stable operation UUID, and at most 16 operations or 900 payload bytes per packet. The relay accepts them only from the authenticated island owner. A receiver applies a delta only when its current candidate revision exactly equals `baseRevision`; otherwise it requests a full snapshot. Duplicate operation UUIDs are no-ops.

## 11. Chat and moderation

Each submitted chat message has a client-generated UUID. The host derives author PUID/slot from EOS receive metadata, applies membership/block/rate checks, assigns the fast total order `(hostEpoch, chatIndex)`, and broadcasts `ChatCommit`. Clients show an optimistic pending row, then commit or reject it idempotently by UUID.

Default sender limit: burst 2, then at most 5 messages per 10 seconds. The limits are enforced independently by host and backend. The host retains at most the latest 120 fast commits for reconnect, matching current behavior.

At the same time, the authenticated sender writes that UUID/text to the trusted backend. The backend supplies canonical UID, display name, timestamp, safety outcome, and evidence document ID. When the canonical acknowledgement arrives:

- set `BACKEND_COMMITTED` and replace host time/name with canonical values;
- dedupe by client UUID;
- if the backend rejects or removes it, broadcast an ordered tombstone and remove the optimistic/fast row;
- reports reference only the backend evidence ID, never a P2P-only index.

Messages that have not reached the backend are transient and must not be represented as durable moderation evidence. After migration, each client may resend only its own unacknowledged UUIDs; the new host reconciles the backend cursor before ordering them.

Arrival/departure text remains derived from reliable roster/presence transitions and cannot be submitted as user chat. Blocks remain account/backend policy; the local client filters blocked authors immediately. A network host is never permitted to forge another PUID's canonical message.

## 12. Traffic budget and backpressure

At 10 Hz, one 16-byte sample plus the 48-byte header is about 640 B/s of Landfall application data per guest. A host world frame with an 8-byte prefix and eight 16-byte members is 184 bytes including its header, or about 1.84 KiB/s per recipient.

With seven guests moving:

| Direction | Approximate steady application traffic |
| --- | ---: |
| All guest samples into host | 4.5 KiB/s |
| Host world frames to 7 guests | 12.9 KiB/s |
| Control/discrete/chat allowance | 2...5 KiB/s |
| Host steady target | below 30 KiB/s total |
| One guest steady target | below 8 KiB/s total |
| Full snapshot | at most 32 KiB per recipient, burst-only |

EOS/UDP/IP overhead is additional and must be recorded separately in device tests. Snapshot traffic is never included in the steady target.

The adapter must bound its receive loop (for example, no more than 64 packets or 4 ms per service pass) and process codec/session work off the main actor. Configure/observe EOS send and receive queues with a target budget of at least 512 KiB when supported by the pinned SDK. At more than 75% queued capacity for 2 seconds:

1. discard/replace older unsent motion first;
2. reduce world-frame rate from 10 to 5 Hz;
3. pause new snapshot chunks and permit only one transfer;
4. preserve control, discrete events, and chat;
5. if reliable control cannot enqueue, fail the link explicitly and resync instead of pretending the operation committed.

An EOS successful send result means the packet entered the transport path, not that a durable application operation committed. Chat, edits, and discrete actions therefore require their application-level commit/acknowledgement.

## 13. Security and abuse controls

All input is hostile, including input relayed by the current player host.

- Authenticate from EOS receive metadata plus the backend ticket; ignore claimed sender IDs.
- Bind `roomID`, lobby membership, host epoch, PUID, slot, and link nonce before accepting gameplay packets.
- Validate lengths before allocation; cap packet at 1,024 B, snapshot at 32 KiB, placements at 120, chat at 2,048 UTF-8 bytes, fragment count, and outstanding reassemblies.
- Reject NaN/infinity, coordinates outside the current island limit, illegal enum transitions, unknown seat placement/slot, duplicate placement UUID, unapproved asset ID, and unsafe scale using current domain sanitizers.
- Default inbound limits per peer: motion 20/s burst 30 (process latest at 10 Hz), discrete 10/s, chat as in section 11, control 10/s outside handshake, one snapshot receive transfer, and 64 KiB/s burst. Repeated violation closes the link and records bounded telemetry.
- Reject replay with room-bound ticket nonce, lobby owner, host epoch, link nonce, sequence, operation UUID, client chat UUID, and snapshot revision/hash.
- Never use device wall time for authority or ordering.
- Never place backend credentials, invite secrets, email, or raw Firebase tokens in Lobby attributes or P2P packets.
- Redact or keyed-hash EOS PUID/backend UID in production telemetry. Do not log chat or packet payloads.
- Decode/fuzz off the main actor. No payload-controlled recursion or unchecked multiplication is allowed.

EOS secures its transport according to the pinned SDK/platform behavior, but the application must not describe the player host as a trusted server or assume it cannot inspect relayed gameplay/chat. Privileged and durable decisions stay backend-authorized.

## 14. Acceptance tests

Release is blocked unless all mandatory tests pass against the same pinned EOS SDK/configuration used by production.

### 14.1 Codec and deterministic unit tests

| ID | Test | Pass condition |
| --- | --- | --- |
| C01 | Round-trip and checked-in golden byte vector for every kind | byte-exact on all supported devices; no dependence on Swift layout |
| C02 | Truncate each golden vector at every byte boundary | deterministic decode error; no crash/allocation spike |
| C03 | Header length, payload length, trailing bytes, reserved bits, channel mismatch | packet rejected |
| C04 | Unknown major/minor/kind and optional TLVs | major rejected/closed; safe supported-minor behavior; unknown optional TLV skipped |
| C05 | `UInt32` wrap, duplicate, old/new epoch, old/new link nonce | only the specified newest/current packet accepted |
| C06 | NaN, infinity, position/scale bounds, invalid enums/UTF-8/UUID | rejected before model conversion |
| C07 | 100,000 deterministic random inputs of 0...1,024 B, plus mutation corpus | no crash, hang, out-of-bounds, or unbounded allocation under ASan/UBSan where available |
| C08 | Snapshot 0 and 120 placements; reordered/duplicate/lost chunks | exact final SHA or explicit timeout; never partial apply |
| C09 | Hash mismatch, revision conflict, duplicate UUID, invalid asset, 32 KiB + 1 | rejected and full canonical resync requested |
| C10 | Japanese, combining marks, RTL text, and emoji at chat boundaries | accepted/rejected by 500-character and 2,048-byte rules consistently |
| C11 | Chat duplicate UUID, retry after reconnect, backlog/tombstone | one final row in identical order on all clients |

### 14.2 Deterministic network-chaos suite

Run 2-, 4-, and 8-member simulations across the Cartesian risk set, with seeded replay:

```text
loss:       0, 1, 5, 10, 20 percent
RTT:        20, 80, 200, 400 ms
jitter:     0, 30, 100 ms
reorder:    0, 10, 30 percent
duplicate:  0, 5 percent
bandwidth:  unrestricted, 64 kbit/s
```

Required scenarios and gates:

| ID | Scenario | Pass condition |
| --- | --- | --- |
| N01 | motion, RTT <= 150 ms and loss <= 5% | p95 rendered position error < 0.35 m; time never moves backward; ordinary stall < 500 ms |
| N02 | motion at 10% loss/reorder | no teleport except reliable transition or defined >3 m correction; bounded buffer |
| N03 | reliable seat/scene/arrival under loss/duplication | identical final state; event animation/system line occurs once |
| N04 | guest loss for 1/5/15 s | same slot inside grace, no duplicate avatar, fully ready <= 3 s after transport reconnect |
| N05 | airplane mode, force quit, background 30 s, Wi-Fi/cellular switch | stale avatar fades/removes; reconnect produces one identity and current snapshot/chat |
| N06 | planned host promotion during movement/chat | no split brain; identical roster/order; ready <= 2 s after owner notification |
| N07 | kill host during chat commit | backend-committed message exactly once; uncommitted local UUID resent/rejected explicitly |
| N08 | kill host during snapshot chunk/delta | no partial apply; backend checkpoint hash wins; ready <= 8 s after owner notification |
| N09 | host plus one guest lost; old host returns | one EOS-authorized host; old host is guest; immutable owner rule preserved |
| N10 | partition with competing `HostClaim` | only current Lobby owner's newer epoch accepted; zero durable split-brain commits |
| N11 | 120-placement full sync to 7 peers at 5% loss | exact SHA on all peers <= 5 s, at most two concurrent outgoing transfers |
| N12 | queue saturation / 64 kbit/s | motion sheds first; reliable operations commit or visibly fail; memory remains bounded |

### 14.3 Security tests

| ID | Attack | Pass condition |
| --- | --- | --- |
| S01 | nonmember P2P connection and expired/wrong-room ticket | connection rejected without roster/snapshot disclosure |
| S02 | spoofed sender PUID/slot/island-owner flag | ignored; durable backend unchanged |
| S03 | replay old room, epoch, link nonce, sequence, chat UUID, edit operation | no visible duplicate and no durable mutation |
| S04 | oversize length, fragment flood, snapshot fan-out request | bounded memory/queue; peer throttled or closed |
| S05 | invalid transform, speed, asset, seat, transition | rejected and corrected from next keyframe/checkpoint |
| S06 | malicious migrated host attempts owner edit/another author's chat | backend rejects; other clients reconcile to canonical checkpoint/evidence |
| S07 | malformed corpus under continuous reconnect/migration | no crash, deadlock, main-thread stall, or identity leak in logs |

### 14.4 Real iPhone/iPad matrix

Simulator testing is sufficient for codec/golden/chaos logic only. NAT traversal, relay, backgrounding, thermal behavior, and network transitions require physical devices.

| Class | Minimum device/OS | Required role |
| --- | --- | --- |
| oldest supported small iPhone | iPhone SE (2nd gen) or equivalent, iOS 17 | host worst case and guest |
| older representative iPhone | iPhone XS/11-class, iOS 17 | guest/background/reconnect |
| current midrange iPhone | iPhone 13/15-class, iOS 18 or current supported | host and guest |
| current high-end iPhone | current Pro model/current iOS | host and guest |
| base iPad | iPad 9th/10th generation, iPadOS 17/18 | host and guest |
| current Apple-silicon iPad | M-series iPad Air/Pro/current iPadOS | host and guest |

Mandatory physical runs:

1. two devices on the same Wi-Fi, then reverse host/guest roles;
2. Wi-Fi host to cellular guest and Personal Hotspot, exercising direct and relayed/NAT paths exposed by EOS telemetry;
3. IPv6-only/NAT64 network;
4. four mixed iPhone/iPad devices moving, seating, chatting, and reconnecting;
5. eight devices for 30 minutes with the oldest iPhone as network host, all moving and periodic chat/edit traffic;
6. iPad network host plus seven iPhones for 30 minutes;
7. host promotion/kill during full snapshot, chat, and seat transition;
8. Wi-Fi-to-cellular transition, background/foreground, Low Power Mode, memory pressure, and thermal soak;
9. island owner leaves while migrated network host and guests remain: island immediately becomes read-only and stays at the latest valid backend checkpoint.

Device release gates:

- host steady application traffic below 30 KiB/s average and 60 KiB/s p95, excluding bounded snapshot bursts;
- guest steady application traffic below 8 KiB/s average;
- codec/session processing p95 below 1 ms off-main and applied main-actor work p95 below 1 ms per frame;
- EOS queue does not remain above 75% for more than 2 seconds;
- no unbounded memory growth in a 60-minute soak;
- no unexpected serious thermal escalation attributable to networking and no agreed renderer frame-rate regression;
- all clients finish with the same roster, checkpoint SHA-256, committed chat cursor, and discrete world state.

## 15. Implementation boundaries and integration checklist

Recommended modules, independent of SwiftUI and SceneKit:

```text
EOSIslandPacketCodec       // pure bounded binary encode/decode
EOSIslandTransport         // EOS channel/socket adapter
EOSIslandSessionActor      // state machine, epoch, roster, reconnect/migration
EOSIslandSnapshotSync      // revisions, chunks, hashes, atomic candidate
EOSIslandChatSync          // UUID/order/backend reconciliation
EOSIslandInterpolation     // time samples -> renderer-neutral states
```

Before implementation is merged:

- pin the EOS iOS SDK version and confirm its packet maximum, reliability enum names, lobby migration option, queue APIs, delayed-delivery behavior, and owner-change notification semantics in that exact header;
- keep codec tests in a real test target so malformed packet/fuzz cases do not ship as app-only code;
- keep Firebase/backend UID-to-EOS PUID ticket validation outside the player host;
- instrument direct/relay path, RTT, jitter, loss estimate, queue utilization, migration duration, snapshot bytes/retries, and reason-coded disconnects without raw identity/chat payload;
- ship protocol major changes only with an explicit compatibility/rejection path; never silently reinterpret an existing kind.

Relevant primary EOS references:

- [Epic Online Services Lobbies Interface](https://dev.epicgames.com/documentation/unreal-engine/lobbies-interface-in-unreal-engine)
- [Epic Online Services promote-lobby-member API](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/OnlineServicesInterface/ILobbies/PromoteLobbyMember)
- [EOS P2P SendPacket API](https://dev.epicgames.com/docs/en-US/api-ref/functions/eos-p-2-p-send-packet)
- [EOS packet reliability enum](https://dev.epicgames.com/docs/en-US/api-ref/enums/eos-e-packet-reliability)
- [Epic Games EOS getting-started samples](https://github.com/EpicGames/EOS-Getting-Started)
