# Haskell authority protocol contract

## Reducer

The authority is one long-lived process:

```haskell
step
  :: AuthorityState
  -> Fact
  -> Either ProtocolFault (AuthorityState, [Directive])
```

Continuations and decision state remain inside Haskell. The wire carries identifiers,
objective facts, directives, and effect results. Rust must not serialize a Rust-made
decision as if it were a fact.

Representative state:

```haskell
data AuthorityState = AuthorityState
  { epoch      :: AuthorityEpoch
  , health     :: HealthyOrPoisoned
  , sessions   :: Map SessionId SessionState
  , scopes     :: Map ScopeId ScopeState
  , effects    :: Map EffectId EffectState
  }

data SessionState = SessionState
  { activeTurn :: Maybe TurnState
  , mailbox    :: MailboxState
  , history    :: HistoryState
  , window     :: WindowState
  , agents     :: AgentState
  , guardian   :: GuardianState
  }
```

Every fact and directive carries:

- `authority_epoch`;
- `scope_id`;
- monotonic `sequence`;
- `revision` where state is versioned;
- `correlation_id`, and `effect_id` for effects;
- payload hash for idempotent replay.

## Fact families

- `SubmissionReceived`, `SessionSnapshot`, `SubmissionChannelClosed`
- `PendingInputsObserved`, `InjectionRequested`, `HookFinished`
- `StepCaptured`, `ContextUsageObserved`, `SnapshotCaptured`
- `ModelStreamOpened`, `ModelEvent`, `ModelStreamFailed`
- `CallObserved`, `ParseFacts`, `PolicyFacts`, `CacheFacts`
- `RunnerFinished`, `ToolFinished`, `UserApprovalFinished`
- `NetworkRequest`, `GuardianFinished`, `AgentStatusObserved`
- `AgentThreadCreated`, `AgentInitialSubmitResult`
- `AppendFinished`, `FlushFinished`, `RolloutLoaded`, `PersistFinished`
- `TimerFired`, `CancellationRequested`, `ChildExited`, `EffectAck`

## Directive families

- `DispatchSubmission`, `CompatibilityIgnore`
- `ReserveTurn`, `StartTask`, `CancelTask`, `AwaitTaskGrace`, `ForceAbort`, `FinishTask`
- `InjectCurrentTurn`, `QueueNextTurn`, `RejectInjection`
- `CaptureStep`, `CaptureWorld`, `RunHook`
- `OpenModelStream`, `CloseModelStream`, `ScheduleTimer`
- `PublishTool`, `RejectCall`, `AcquirePermit`, `InvokeRunner`, `CancelTool`
- `PromptUser`, `ReviewWithGuardian`, `RunSandboxAttempt`
- `PersistExecRule`, `PersistNetworkRule`, `UpdateLiveProxy`, `CacheApproval`, `RecordPermission`
- `RegisterNetworkCall`, `ResolveNetwork`, `CancelOwner`
- `AppendRollout`, `FlushRollout`, `LoadRollout`, `Deliver`
- `ReserveAgentSlot`, `CreateAgent`, `CommitAgent`, `SendAgentCommunication`,
  `InstallCompletionWatcher`, `ReleaseAgentResource`, `CloseAgentTree`
- `SpawnReviewer`, `SubmitReview`, `InterruptReviewer`, `FinishGuardian`,
  `UpdateGuardianCircuit`, `AbortTurn`
- `LaunchEmbeddedHaskell`, `ConnectCompatibleLocalDaemon`, `UseExternalRemote`
- `EmitLifecycle`, `PoisonAuthority`, `CloseScope`

Concrete wire tags and arities are versioned and exhaustively checked. Unknown tag,
wrong arity, invalid enum, duplicate sequence, wrong scope, stale revision, or illegal
phase is a protocol fault.

## Transaction

Every authority scope follows:

```text
OPEN
  -> PLAN
  -> DIRECTIVE
  -> EFFECT_RESULT
  -> PERSIST_RESULT (when state is durable)
  -> CONFIRM
  -> TERMINAL
  -> CLOSE
```

Rules:

1. A directive authorizes one identified effect, not a class of future effects.
2. The Rust adapter reports the real effect result; it cannot map failure to success.
3. Haskell advances confirmed state only after the required effect and persistence results.
4. Replayed `effect_id` with the same payload hash is idempotent; a different payload poisons.
5. Each scope has exactly one `OPEN`, terminal, and `CLOSE`.
6. Scope leases are non-cloneable. A normal `CLOSE` disarms the lease; Rust `Drop`, cancellation,
   panic, EOF, timeout, or early return poisons the authority and abandons all open scopes.

## Fail-closed behavior

The following permanently poison the local authority instance:

- sidecar EOF, exit, write failure, response timeout, or failed handshake;
- malformed frame, wrong protocol hash, unknown tag, bad arity or enum;
- sequence/revision rollback, cross-scope response, duplicate conflicting ID;
- missing/duplicate terminal or close;
- directive impossible in the current phase;
- adapter loss after an effect whose result cannot be proven.

After poison:

- the current dangerous operation is denied or cancelled;
- no new local scope is admitted;
- no Rust reference fallback is created;
- a new CLI process may start a new sidecar, but the poisoned session is not silently resumed.

## Effect permits

Effect-capable Rust methods require a private `AuthorityPermit` constructed only by the
directive interpreter. This mechanically prevents ordinary call sites from starting tools,
approvals, agent mutations, Guardian transitions, or task lifecycle effects.

Production telemetry exposes:

- `rust_decisions` — must remain zero;
- `orphan_effects` — must remain zero;
- counts of opens, terminals, closes, poison events, and protocol faults.

## Rust reference

The original Rust reducer is retained only for differential tests behind a test-only feature.
It is not a production runtime selection and must be absent from release dependency/symbol scans.
