# Web3 Extension Types: Identity, Attestation & Escrow

## Context

This analysis follows the [spoon-core integration analysis](./spoon-core-integration-analysis.md) and explores what **identity**, **attestation**, **escrow**, **membership**, and **outcome** types Blueprint-lib would need as Web3 extensions.

The **footy tipping platform** is the grounding use case: a social AFL tipping competition with stablecoin entry fees, identity-verified tip submissions, and prize release to the winner.

### Design Philosophy

Per ADR-5 from the spoon-core analysis, these types ship as **extension repos**, not in core blueprint-lib. Per ADR-2, all enforcement is **server-side** -- Blueprint types automate the correct sequence of operations, but smart contracts and x402 gateways are the security boundary.

---

## Five Extension Type Categories

| Category | Consequences | Preconditions | Purpose |
|----------|-------------|---------------|---------|
| `extensions/identity` | `identity_ops`, `identity_trust_score` | `identity_check`, `did_registered` | DID resolution, verification, challenge-response auth |
| `extensions/attestation` | `attestation_ops`, `store_immutable` | `attestation_check` | Signed claims, immutable storage, credential verification |
| `extensions/escrow` | `escrow_ops` | `escrow_check`, `payment_receipt_check` | Pool creation, deposits, conditional release, refund |
| `extensions/membership` | `membership_ops`, `record_submission` | `membership_check` | Group enrollment, identity-gated submissions with content hashing |
| `extensions/outcome` | `outcome_ops`, `oracle_feed` | `outcome_check` | External results, scoring, winner determination |

**Total: 11 consequences + 7 preconditions** across 5 categories, shipping in 2 extension repos.

### Extension Repo Structure

| Repo | Categories | Rationale |
|------|-----------|-----------|
| `blueprint-web3-identity` | identity + attestation | Identity primitives with no financial dependency |
| `blueprint-web3-escrow` | escrow + membership + outcome | Competition lifecycle types with financial dependency |

---

## Type Definitions

### Category 1: `extensions/identity`

#### Consequence: `identity_ops`

```yaml
identity_ops:
  category: extensions/identity
  description:
    brief: Perform DID identity operations (resolve, verify, challenge, register)
    detail: |
      Unified identity consequence wrapping spoon-core's ERC-8004 identity stack.
      The operation parameter determines what identity action is performed.
      All key-touching operations (register, challenge_sign) MUST run in spawn mode
      sub-workflows to prevent private key leakage.
    notes:
      - "operation: resolve - resolve DID to agent document"
      - "operation: verify - verify DID exists and is resolvable"
      - "operation: challenge - generate random challenge for identity proof"
      - "operation: challenge_verify - verify signed challenge response"
      - "operation: register - register new DID on-chain (spawn mode only)"
      - All operations call spoon-core MCP server via mcp_call()
      - Register requires Turnkey or local key (spawn mode mandatory)

  parameters:
    - name: operation
      type: string
      required: true
      description: "Identity operation: resolve, verify, challenge, challenge_verify, register"
      enum:
        - resolve
        - verify
        - challenge
        - challenge_verify
        - register
      interpolatable: false

    - name: did
      type: string
      required: false
      description: "DID identifier (for resolve, verify, challenge_verify)"
      interpolatable: true

    - name: args
      type: object
      required: false
      description: |
        Operation-specific arguments:
        - resolve: {} (no extra args)
        - verify: {} (no extra args)
        - challenge: { length: 32 } (challenge byte length)
        - challenge_verify: { challenge, signature, did }
        - register: { agent_card, capabilities, service_endpoints }
      interpolatable: true

    - name: store_as
      type: string
      required: false
      description: State field for operation result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      if operation == "resolve":
        # Wraps DIDResolver.resolve()
        result = mcp_call("spoon-identity", "resolve_did", {
          did: interpolate(did)
        })
        # Returns: { did_document, agent_card, reputation, resolution_metadata }
        set_state_value(store_as, result)

      elif operation == "verify":
        # Wraps DIDResolver.verify_did()
        result = mcp_call("spoon-identity", "verify_did", {
          did: interpolate(did)
        })
        # Returns: { exists: bool, resolvable: bool }
        set_state_value(store_as, result)

      elif operation == "challenge":
        # Generate random challenge for identity proof
        challenge = mcp_call("spoon-identity", "generate_challenge", {
          length: args.length ?? 32
        })
        # Returns: { challenge: hex_string, expires_at: iso8601 }
        set_state_value(store_as, challenge)

      elif operation == "challenge_verify":
        # Wraps signature verification against DID's public key
        result = mcp_call("spoon-identity", "verify_challenge", {
          did: interpolate(args.did ?? did),
          challenge: interpolate(args.challenge),
          signature: interpolate(args.signature)
        })
        # Returns: { valid: bool, signer_did: string }
        set_state_value(store_as, result)

      elif operation == "register":
        # MUST be called from spawn mode sub-workflow
        result = mcp_call("spoon-identity", "register_agent", {
          agent_card: interpolate(args.agent_card),
          capabilities: args.capabilities ?? [],
          service_endpoints: args.service_endpoints ?? []
        })
        # Returns: { did: string, agent_id: number, tx_hash: string }
        set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Consequence: `identity_trust_score`

```yaml
identity_trust_score:
  category: extensions/identity
  description:
    brief: Calculate comprehensive trust score for a DID
    detail: |
      Wraps spoon-core's TrustScoreCalculator to produce a composite trust
      score from on-chain reputation submissions and validation records.
      Returns a trust level (untrusted/low/medium/high/verified) with
      confidence score.
    notes:
      - Combines reputation + validation into single score
      - Trust levels based on configurable thresholds
      - Confidence reflects data volume (more submissions = higher confidence)
      - Can be used as input to conditional nodes for trust-gating

  parameters:
    - name: did
      type: string
      required: true
      description: DID to calculate trust score for
      interpolatable: true

    - name: thresholds
      type: object
      required: false
      description: |
        Custom trust level thresholds (defaults to spoon-core defaults):
        { low: 20, medium: 50, high: 75, verified: 90 }
      interpolatable: false

    - name: store_as
      type: string
      required: true
      description: State field for trust score result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      # Wraps TrustScoreCalculator.calculate_trust_score()
      result = mcp_call("spoon-identity", "calculate_trust_score", {
        did: interpolate(did),
        thresholds: thresholds ?? null
      })
      # Returns: {
      #   reputation_score: number (-100 to 100),
      #   validation_status: { is_validated: bool, response_count: number },
      #   trust_level: "untrusted" | "low" | "medium" | "high" | "verified",
      #   confidence: number (0.0 to 1.0)
      # }
      set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Precondition: `identity_check`

```yaml
identity_check:
  category: extensions/identity
  description:
    brief: Check identity status with various aspects
    detail: |
      Unified identity precondition. The aspect parameter determines what
      identity property is checked against a DID stored in state.
    notes:
      - "aspect: verified - DID has been challenge-response verified this session"
      - "aspect: trust_above - trust score above threshold (args.min_level or args.min_score)"
      - "aspect: has_capability - DID has registered capability (args.capability)"
      - State field should contain a resolved DID or verification result

  parameters:
    - name: field
      type: string
      required: true
      description: State field containing DID or identity result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.]*$"
      interpolatable: false

    - name: aspect
      type: string
      required: true
      description: "Identity aspect to check: verified, trust_above, has_capability"
      enum:
        - verified
        - trust_above
        - has_capability
      interpolatable: false

    - name: args
      type: object
      required: false
      description: |
        Aspect-specific arguments:
        - trust_above: { min_level: "medium" } or { min_score: 50 }
        - has_capability: { capability: "tipping" }
      interpolatable: false

  evaluation:
    effect: |
      identity = get_state_value(field)
      if identity == null:
        return false

      if aspect == "verified":
        return identity.valid == true

      elif aspect == "trust_above":
        if args.min_level:
          level_order = ["untrusted", "low", "medium", "high", "verified"]
          actual_index = level_order.index(identity.trust_level ?? "untrusted")
          required_index = level_order.index(args.min_level)
          return actual_index >= required_index
        elif args.min_score:
          return (identity.reputation_score ?? -100) >= args.min_score

      elif aspect == "has_capability":
        capabilities = identity.capabilities ?? []
        return args.capability in capabilities
    reads:
      - "state.${field}"
    functions:
      - get_state_value

  since: "1.0.0"
```

#### Precondition: `did_registered`

```yaml
did_registered:
  category: extensions/identity
  description:
    brief: Check if a DID is registered on-chain
    detail: |
      Lightweight check that a DID exists in the on-chain registry.
      Does not perform full resolution -- just checks registration status.
      Useful as a gate before expensive operations.
    notes:
      - Network operation (calls on-chain registry)
      - Faster than full resolve -- only checks existence
      - Returns false for unregistered or revoked DIDs

  parameters:
    - name: did
      type: string
      required: true
      description: DID to check registration for
      interpolatable: true

  evaluation:
    effect: |
      result = mcp_call("spoon-identity", "verify_did", {
        did: interpolate(did)
      })
      return result.exists == true
    reads: []
    functions:
      - mcp_call
      - interpolate

  since: "1.0.0"
```

---

### Category 2: `extensions/attestation`

#### Consequence: `attestation_ops`

```yaml
attestation_ops:
  category: extensions/attestation
  description:
    brief: Create and verify signed attestations (claims about agents or events)
    detail: |
      Wraps spoon-core's AttestationManager for creating verifiable claims.
      Attestations are signed data structures that assert something about a
      subject (e.g., "player X won the 2025 season"). They can be stored
      on-chain via reputation/validation registries or off-chain in NeoFS/IPFS.
    notes:
      - "operation: create - create and sign a new attestation"
      - "operation: verify - verify an attestation's signature"
      - "operation: submit_reputation - submit attestation as reputation score on-chain"
      - "operation: submit_validation - submit attestation as validation decision on-chain"
      - Create and submit operations touch private keys (spawn mode recommended)

  parameters:
    - name: operation
      type: string
      required: true
      description: "Attestation operation: create, verify, submit_reputation, submit_validation"
      enum:
        - create
        - verify
        - submit_reputation
        - submit_validation
      interpolatable: false

    - name: args
      type: object
      required: true
      description: |
        Operation-specific arguments:
        - create: { subject_did, claim_type, claim_data, evidence_urls }
        - verify: { attestation } (the attestation object to verify)
        - submit_reputation: { subject_did, score, evidence }
        - submit_validation: { subject_did, is_valid, evidence }
      interpolatable: true

    - name: store_as
      type: string
      required: false
      description: State field for result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      if operation == "create":
        # Wraps AttestationManager.create_attestation()
        result = mcp_call("spoon-identity", "create_attestation", {
          subject_did: interpolate(args.subject_did),
          claim_type: interpolate(args.claim_type),
          claim_data: interpolate(args.claim_data),
          evidence: args.evidence_urls ?? []
        })
        # Returns: { attestation: { issuer, subject, claim, signature, timestamp } }
        set_state_value(store_as, result.attestation)

      elif operation == "verify":
        # Wraps AttestationManager.verify_attestation()
        attestation = get_state_value(args.attestation) if is_string(args.attestation) else args.attestation
        result = mcp_call("spoon-identity", "verify_attestation", {
          attestation: attestation
        })
        # Returns: { valid: bool, issuer_did: string }
        set_state_value(store_as, result)

      elif operation == "submit_reputation":
        # Wraps AttestationManager.submit_reputation_on_chain()
        result = mcp_call("spoon-identity", "submit_reputation", {
          subject_did: interpolate(args.subject_did),
          score: args.score,  # -100 to 100
          evidence: interpolate(args.evidence ?? "")
        })
        # Returns: { tx_hash: string, success: bool }
        set_state_value(store_as, result)

      elif operation == "submit_validation":
        # Wraps AttestationManager.submit_validation_on_chain()
        result = mcp_call("spoon-identity", "submit_validation", {
          subject_did: interpolate(args.subject_did),
          is_valid: args.is_valid,
          evidence: interpolate(args.evidence ?? "")
        })
        # Returns: { tx_hash: string, success: bool }
        set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Consequence: `store_immutable`

```yaml
store_immutable:
  category: extensions/attestation
  description:
    brief: Store content immutably in decentralized storage (NeoFS/IPFS)
    detail: |
      Wraps spoon-core's DIDStorageClient for publishing content to NeoFS
      (primary) with IPFS backup. Returns content-addressed URIs that can
      be used as evidence in attestations or for audit trails.

      Use for any data that must be tamper-evident: tip submissions,
      competition results, signed claims, audit records.
    notes:
      - Primary storage is NeoFS, IPFS is automatic backup
      - Returns content-addressed URI (neofs:// and/or ipfs://)
      - Content is immutable once stored
      - Bearer tokens control read access (public or gated)
      - "operation: publish - store new content"
      - "operation: fetch - retrieve stored content by URI"

  parameters:
    - name: operation
      type: string
      required: true
      description: "Storage operation: publish, fetch"
      enum:
        - publish
        - fetch
      interpolatable: false

    - name: content
      type: any
      required: false
      description: Content to store (for publish operation, serialized to JSON)
      interpolatable: true

    - name: uri
      type: string
      required: false
      description: Content URI to fetch (for fetch operation)
      interpolatable: true

    - name: args
      type: object
      required: false
      description: |
        Operation-specific arguments:
        - publish: { container_id, attributes, public } (public defaults to true)
        - fetch: {} (no extra args)
      interpolatable: true

    - name: store_as
      type: string
      required: true
      description: State field for result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      if operation == "publish":
        # Wraps DIDStorageClient.publish_credential() / publish_did_document()
        serialized = json_dumps(interpolate(content))
        result = mcp_call("spoon-storage", "publish_object", {
          content: serialized,
          container_id: args.container_id ?? null,
          attributes: args.attributes ?? {},
          public: args.public ?? true
        })
        # Returns: { neofs_uri: string, ipfs_uri: string, content_hash: string }
        set_state_value(store_as, result)

      elif operation == "fetch":
        result = mcp_call("spoon-storage", "fetch_object", {
          uri: interpolate(uri)
        })
        # Returns: { content: object, fetched_from: "neofs" | "ipfs" }
        set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Precondition: `attestation_check`

```yaml
attestation_check:
  category: extensions/attestation
  description:
    brief: Check attestation validity or properties
    detail: |
      Unified attestation precondition. The aspect parameter determines
      what property of an attestation stored in state is checked.
    notes:
      - "aspect: valid_signature - attestation signature is cryptographically valid"
      - "aspect: issued_by - attestation was issued by specific DID (args.issuer)"
      - "aspect: claim_type - attestation has specific claim type (args.type)"
      - "aspect: not_expired - attestation is still within validity period"

  parameters:
    - name: field
      type: string
      required: true
      description: State field containing attestation object
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.]*$"
      interpolatable: false

    - name: aspect
      type: string
      required: true
      description: "Attestation aspect to check: valid_signature, issued_by, claim_type, not_expired"
      enum:
        - valid_signature
        - issued_by
        - claim_type
        - not_expired
      interpolatable: false

    - name: args
      type: object
      required: false
      description: |
        Aspect-specific arguments:
        - issued_by: { issuer: "did:erc8004:..." }
        - claim_type: { type: "season_winner" }
      interpolatable: false

  evaluation:
    effect: |
      attestation = get_state_value(field)
      if attestation == null:
        return false

      if aspect == "valid_signature":
        result = mcp_call("spoon-identity", "verify_attestation", {
          attestation: attestation
        })
        return result.valid == true

      elif aspect == "issued_by":
        return attestation.issuer == args.issuer

      elif aspect == "claim_type":
        return attestation.claim?.type == args.type

      elif aspect == "not_expired":
        if attestation.expires_at == null:
          return true  # No expiry = always valid
        return now_iso8601() < attestation.expires_at
    reads:
      - "state.${field}"
    functions:
      - get_state_value
      - mcp_call
      - now_iso8601

  since: "1.0.0"
```

---

### Category 3: `extensions/escrow`

#### Consequence: `escrow_ops`

```yaml
escrow_ops:
  category: extensions/escrow
  description:
    brief: Manage escrow pools (create, deposit, release, refund)
    detail: |
      Manages stablecoin escrow pools via a smart contract. This is a NEW
      contract deployment requirement -- x402 is pay-and-go (no hold), while
      escrow is hold-and-release (conditional).

      The escrow contract holds funds until release conditions are met. The
      contract enforces rules; the workflow automates the interaction sequence.

      IMPORTANT: All escrow operations involve key signing and MUST run in
      spawn mode sub-workflows to prevent state leakage.
    notes:
      - "operation: create_pool - deploy or initialize a new escrow pool"
      - "operation: deposit - deposit funds into an existing pool"
      - "operation: release - release funds to a recipient (requires authority)"
      - "operation: refund - return funds to depositors (requires authority or timeout)"
      - "operation: status - check pool balance, depositors, and state"
      - Contract is the enforcement layer, not the workflow
      - Requires new smart contract (not part of spoon-core today)
      - Spawn mode mandatory for deposit, release, refund

  parameters:
    - name: operation
      type: string
      required: true
      description: "Escrow operation: create_pool, deposit, release, refund, status"
      enum:
        - create_pool
        - deposit
        - release
        - refund
        - status
      interpolatable: false

    - name: pool_id
      type: string
      required: false
      description: Pool identifier (for all operations except create_pool)
      interpolatable: true

    - name: args
      type: object
      required: false
      description: |
        Operation-specific arguments:
        - create_pool: { name, entry_fee_usdc, max_participants, authority_did, release_conditions }
        - deposit: { amount_usdc, depositor_did }
        - release: { recipient_did, amount_usdc, reason }
        - refund: { reason } (refunds all depositors pro-rata)
        - status: {} (no extra args)
      interpolatable: true

    - name: store_as
      type: string
      required: false
      description: State field for result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      if operation == "create_pool":
        result = mcp_call("spoon-escrow", "create_pool", {
          name: interpolate(args.name),
          entry_fee_usdc: args.entry_fee_usdc,
          max_participants: args.max_participants ?? null,
          authority_did: interpolate(args.authority_did),
          release_conditions: args.release_conditions ?? {}
        })
        # Returns: { pool_id: string, contract_address: string, tx_hash: string }
        set_state_value(store_as, result)

      elif operation == "deposit":
        result = mcp_call("spoon-escrow", "deposit", {
          pool_id: interpolate(pool_id),
          amount_usdc: args.amount_usdc,
          depositor_did: interpolate(args.depositor_did)
        })
        # Returns: { tx_hash: string, new_balance: number, depositor_count: number }
        set_state_value(store_as, result)

      elif operation == "release":
        result = mcp_call("spoon-escrow", "release", {
          pool_id: interpolate(pool_id),
          recipient_did: interpolate(args.recipient_did),
          amount_usdc: args.amount_usdc,
          reason: interpolate(args.reason ?? "")
        })
        # Returns: { tx_hash: string, amount_released: number, remaining_balance: number }
        set_state_value(store_as, result)

      elif operation == "refund":
        result = mcp_call("spoon-escrow", "refund_all", {
          pool_id: interpolate(pool_id),
          reason: interpolate(args.reason ?? "")
        })
        # Returns: { tx_hash: string, refund_count: number, total_refunded: number }
        set_state_value(store_as, result)

      elif operation == "status":
        result = mcp_call("spoon-escrow", "pool_status", {
          pool_id: interpolate(pool_id)
        })
        # Returns: {
        #   pool_id, name, balance_usdc, depositor_count,
        #   depositors: [{ did, amount, timestamp }],
        #   state: "open" | "locked" | "released" | "refunded",
        #   authority_did, created_at
        # }
        set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Precondition: `escrow_check`

```yaml
escrow_check:
  category: extensions/escrow
  description:
    brief: Check escrow pool status and conditions
    detail: |
      Unified escrow precondition. The aspect parameter determines what
      property of an escrow pool is checked.
    notes:
      - "aspect: pool_open - pool is accepting deposits"
      - "aspect: depositor_registered - specific DID has deposited (args.did)"
      - "aspect: balance_above - pool balance above threshold (args.min_usdc)"
      - "aspect: pool_full - pool has reached max_participants"
      - Requires network call to query contract state

  parameters:
    - name: pool_id
      type: string
      required: true
      description: Escrow pool identifier
      interpolatable: true

    - name: aspect
      type: string
      required: true
      description: "Escrow aspect to check: pool_open, depositor_registered, balance_above, pool_full"
      enum:
        - pool_open
        - depositor_registered
        - balance_above
        - pool_full
      interpolatable: false

    - name: args
      type: object
      required: false
      description: |
        Aspect-specific arguments:
        - depositor_registered: { did: "did:erc8004:..." }
        - balance_above: { min_usdc: 100 }
      interpolatable: true

  evaluation:
    effect: |
      status = mcp_call("spoon-escrow", "pool_status", {
        pool_id: interpolate(pool_id)
      })

      if aspect == "pool_open":
        return status.state == "open"

      elif aspect == "depositor_registered":
        return status.depositors.any(d => d.did == interpolate(args.did))

      elif aspect == "balance_above":
        return status.balance_usdc >= args.min_usdc

      elif aspect == "pool_full":
        if status.max_participants == null:
          return false  # No cap = never full
        return status.depositor_count >= status.max_participants
    reads: []
    functions:
      - mcp_call
      - interpolate

  since: "1.0.0"
```

#### Precondition: `payment_receipt_check`

```yaml
payment_receipt_check:
  category: extensions/escrow
  description:
    brief: Verify x402 payment receipt stored in state
    detail: |
      Verifies that a payment receipt (from an x402 transaction) stored in
      state is valid. This is the precondition proposed in the spoon-core
      analysis (threat T1.3 mitigation).
    notes:
      - "aspect: valid - receipt signature is cryptographically valid"
      - "aspect: amount_gte - receipt amount >= threshold (args.min_usdc)"
      - "aspect: payer_is - receipt payer matches expected DID (args.did)"
      - Receipt is the decoded X-PAYMENT-RESPONSE header from x402

  parameters:
    - name: field
      type: string
      required: true
      description: State field containing payment receipt
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.]*$"
      interpolatable: false

    - name: aspect
      type: string
      required: true
      description: "Receipt aspect to check: valid, amount_gte, payer_is"
      enum:
        - valid
        - amount_gte
        - payer_is
      interpolatable: false

    - name: args
      type: object
      required: false
      description: |
        Aspect-specific arguments:
        - amount_gte: { min_usdc: 10 }
        - payer_is: { did: "did:erc8004:..." }
      interpolatable: true

  evaluation:
    effect: |
      receipt = get_state_value(field)
      if receipt == null:
        return false

      if aspect == "valid":
        return receipt.success == true and receipt.tx_hash != null

      elif aspect == "amount_gte":
        return (receipt.amount_usdc ?? 0) >= args.min_usdc

      elif aspect == "payer_is":
        return receipt.payer == interpolate(args.did)
    reads:
      - "state.${field}"
    functions:
      - get_state_value
      - interpolate

  since: "1.0.0"
```

---

### Category 4: `extensions/membership`

#### Consequence: `membership_ops`

```yaml
membership_ops:
  category: extensions/membership
  description:
    brief: Manage group membership (enroll, remove, list)
    detail: |
      Manages membership in identity-gated groups. Members are identified by
      DID and enrollment can require conditions (e.g., escrow deposit, trust
      level). Membership state can be stored on-chain or in NeoFS depending
      on the group's persistence requirements.
    notes:
      - "operation: enroll - add DID to group"
      - "operation: remove - remove DID from group"
      - "operation: list - list all members"
      - "operation: status - check specific member's status"
      - Enrollment can be gated by preconditions (checked externally)
      - Group state stored in escrow contract or NeoFS

  parameters:
    - name: operation
      type: string
      required: true
      description: "Membership operation: enroll, remove, list, status"
      enum:
        - enroll
        - remove
        - list
        - status
      interpolatable: false

    - name: group_id
      type: string
      required: true
      description: Group identifier (typically matches escrow pool_id)
      interpolatable: true

    - name: args
      type: object
      required: false
      description: |
        Operation-specific arguments:
        - enroll: { did, display_name, metadata }
        - remove: { did, reason }
        - list: {} (no extra args)
        - status: { did }
      interpolatable: true

    - name: store_as
      type: string
      required: false
      description: State field for result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      if operation == "enroll":
        result = mcp_call("spoon-escrow", "membership_enroll", {
          group_id: interpolate(group_id),
          did: interpolate(args.did),
          display_name: interpolate(args.display_name ?? ""),
          metadata: args.metadata ?? {}
        })
        # Returns: { member_id: string, enrolled_at: iso8601, member_count: number }
        set_state_value(store_as, result)

      elif operation == "remove":
        result = mcp_call("spoon-escrow", "membership_remove", {
          group_id: interpolate(group_id),
          did: interpolate(args.did),
          reason: interpolate(args.reason ?? "")
        })
        set_state_value(store_as, result)

      elif operation == "list":
        result = mcp_call("spoon-escrow", "membership_list", {
          group_id: interpolate(group_id)
        })
        # Returns: { members: [{ did, display_name, enrolled_at, metadata }], count: number }
        set_state_value(store_as, result)

      elif operation == "status":
        result = mcp_call("spoon-escrow", "membership_status", {
          group_id: interpolate(group_id),
          did: interpolate(args.did)
        })
        # Returns: { enrolled: bool, enrolled_at, display_name, metadata }
        set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Consequence: `record_submission`

```yaml
record_submission:
  category: extensions/membership
  description:
    brief: Record an identity-gated, content-hashed submission
    detail: |
      Records a submission from a verified member. The submission content is
      hashed (SHA-256) and the hash is stored immutably. The actual content
      can be stored encrypted (only revealed at deadline) or in plaintext.

      Used for tipping competitions, voting, sealed-bid auctions, or any
      scenario where submissions must be:
      1. Identity-bound (who submitted)
      2. Tamper-evident (content hash)
      3. Timestamped (when submitted)
      4. Optionally sealed (content hidden until reveal)
    notes:
      - Content is SHA-256 hashed before storage
      - Hash stored in NeoFS for immutability
      - Content can be stored encrypted (sealed) or plaintext (open)
      - Submission includes submitter DID and timestamp
      - Duplicate submissions from same DID can be allowed or rejected (args.allow_update)

  parameters:
    - name: group_id
      type: string
      required: true
      description: Group/competition identifier
      interpolatable: true

    - name: round_id
      type: string
      required: true
      description: Round/period identifier (e.g., "round_15")
      interpolatable: true

    - name: submitter_did
      type: string
      required: true
      description: DID of the submitter (must be enrolled member)
      interpolatable: true

    - name: content
      type: any
      required: true
      description: Submission content (will be serialized and hashed)
      interpolatable: true

    - name: sealed
      type: boolean
      required: false
      default: false
      description: If true, content is encrypted and only hash is visible until reveal
      interpolatable: false

    - name: allow_update
      type: boolean
      required: false
      default: false
      description: If true, allows replacing previous submission for same round
      interpolatable: false

    - name: store_as
      type: string
      required: true
      description: State field for submission receipt
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      serialized = json_dumps(interpolate(content))
      content_hash = sha256(serialized)

      result = mcp_call("spoon-escrow", "record_submission", {
        group_id: interpolate(group_id),
        round_id: interpolate(round_id),
        submitter_did: interpolate(submitter_did),
        content_hash: "sha256:" + content_hash,
        content: serialized if not sealed else null,
        encrypted_content: encrypt(serialized) if sealed else null,
        allow_update: allow_update ?? false,
        timestamp: now_iso8601()
      })
      # Returns: {
      #   submission_id: string,
      #   content_hash: "sha256:...",
      #   storage_uri: "neofs://...",
      #   timestamp: iso8601,
      #   replaced_previous: bool
      # }
      set_state_value(store_as, result)
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Precondition: `membership_check`

```yaml
membership_check:
  category: extensions/membership
  description:
    brief: Check group membership status
    detail: |
      Unified membership precondition. The aspect parameter determines what
      membership property is checked.
    notes:
      - "aspect: enrolled - DID is an active member of the group"
      - "aspect: has_submitted - member has submitted for a specific round (args.round_id)"
      - "aspect: group_size_above - group has at least N members (args.min_members)"

  parameters:
    - name: group_id
      type: string
      required: true
      description: Group identifier
      interpolatable: true

    - name: aspect
      type: string
      required: true
      description: "Membership aspect to check: enrolled, has_submitted, group_size_above"
      enum:
        - enrolled
        - has_submitted
        - group_size_above
      interpolatable: false

    - name: args
      type: object
      required: false
      description: |
        Aspect-specific arguments:
        - enrolled: { did: "did:erc8004:..." }
        - has_submitted: { did: "did:erc8004:...", round_id: "round_15" }
        - group_size_above: { min_members: 4 }
      interpolatable: true

  evaluation:
    effect: |
      if aspect == "enrolled":
        result = mcp_call("spoon-escrow", "membership_status", {
          group_id: interpolate(group_id),
          did: interpolate(args.did)
        })
        return result.enrolled == true

      elif aspect == "has_submitted":
        result = mcp_call("spoon-escrow", "submission_status", {
          group_id: interpolate(group_id),
          round_id: interpolate(args.round_id),
          did: interpolate(args.did)
        })
        return result.submitted == true

      elif aspect == "group_size_above":
        result = mcp_call("spoon-escrow", "membership_list", {
          group_id: interpolate(group_id)
        })
        return result.count >= args.min_members
    reads: []
    functions:
      - mcp_call
      - interpolate

  since: "1.0.0"
```

---

### Category 5: `extensions/outcome`

#### Consequence: `outcome_ops`

```yaml
outcome_ops:
  category: extensions/outcome
  description:
    brief: Manage competition outcomes (score, rank, determine winner)
    detail: |
      Processes submissions against actual results to produce scores,
      rankings, and winner determination. Operates on submission records
      and oracle feed data to compute outcomes.
    notes:
      - "operation: score_round - score all submissions for a round against actual results"
      - "operation: aggregate_scores - compute cumulative scores across rounds"
      - "operation: determine_winner - find winner(s) based on aggregate scores"
      - Scoring logic is parameterized (exact match, margin-based, etc.)
      - Tie-breaking rules configurable

  parameters:
    - name: operation
      type: string
      required: true
      description: "Outcome operation: score_round, aggregate_scores, determine_winner"
      enum:
        - score_round
        - aggregate_scores
        - determine_winner
      interpolatable: false

    - name: group_id
      type: string
      required: true
      description: Competition/group identifier
      interpolatable: true

    - name: args
      type: object
      required: true
      description: |
        Operation-specific arguments:
        - score_round: { round_id, actual_results, scoring_rules }
        - aggregate_scores: { rounds } (array of round_ids, or "all")
        - determine_winner: { tie_break_rules }
      interpolatable: true

    - name: store_as
      type: string
      required: true
      description: State field for result
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: computation
    tool: null
    effect: |
      if operation == "score_round":
        # Fetch all submissions for round
        submissions = mcp_call("spoon-escrow", "get_submissions", {
          group_id: interpolate(group_id),
          round_id: interpolate(args.round_id)
        })

        actual = interpolate(args.actual_results)
        rules = args.scoring_rules ?? { type: "exact_match", points_per_correct: 1 }

        scores = []
        for submission in submissions:
          content = json_parse(submission.content)
          score = apply_scoring(content, actual, rules)
          scores.push({
            did: submission.submitter_did,
            round_id: args.round_id,
            score: score,
            breakdown: score.breakdown
          })

        set_state_value(store_as, {
          round_id: args.round_id,
          scores: scores,
          scored_at: now_iso8601()
        })

      elif operation == "aggregate_scores":
        # Aggregate across rounds
        rounds = args.rounds ?? "all"
        aggregated = mcp_call("spoon-escrow", "aggregate_scores", {
          group_id: interpolate(group_id),
          rounds: rounds
        })
        # Returns: { leaderboard: [{ did, total_score, rounds_played, avg_score }] }
        set_state_value(store_as, aggregated)

      elif operation == "determine_winner":
        # Get aggregated scores and apply tie-breaking
        aggregated = get_state_value(args.scores_field ?? "computed.aggregated_scores")
        tie_rules = args.tie_break_rules ?? { strategy: "most_rounds_won" }

        leaderboard = aggregated.leaderboard.sort_by(-total_score)
        top_score = leaderboard[0].total_score

        winners = leaderboard.filter(p => p.total_score == top_score)

        if len(winners) == 1:
          winner = winners[0]
        else:
          # Apply tie-breaking
          winner = apply_tie_break(winners, tie_rules)

        set_state_value(store_as, {
          winner_did: winner.did,
          final_score: winner.total_score,
          is_tie_broken: len(winners) > 1,
          leaderboard: leaderboard,
          determined_at: now_iso8601()
        })
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Consequence: `oracle_feed`

```yaml
oracle_feed:
  category: extensions/outcome
  description:
    brief: Fetch external results from an oracle or data feed
    detail: |
      Retrieves actual results from an external data source (oracle, API,
      or manual input). For the footy tipping use case, this fetches AFL
      match results. For other use cases, it could fetch stock prices,
      weather data, election results, etc.

      The oracle is untrusted -- results should be stored immutably and
      can be challenged within a dispute window.
    notes:
      - "source: api - fetch from HTTP API endpoint"
      - "source: manual - accept manually entered results (via user_prompt)"
      - "source: contract - read from on-chain oracle contract"
      - Results are stored with source attribution for auditability
      - Consider storing results immutably (via store_immutable) for dispute resolution

  parameters:
    - name: source
      type: string
      required: true
      description: "Oracle source type: api, manual, contract"
      enum:
        - api
        - manual
        - contract
      interpolatable: false

    - name: args
      type: object
      required: true
      description: |
        Source-specific arguments:
        - api: { url, headers, transform } (transform = jq-like expression)
        - manual: { prompt, schema } (presented via user_prompt)
        - contract: { address, method, params }
      interpolatable: true

    - name: store_as
      type: string
      required: true
      description: State field for oracle results
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.\\[\\]]*$"
      interpolatable: false

  payload:
    kind: tool_call
    tool: null
    requires:
      network: true
    effect: |
      if source == "api":
        response = http_get(interpolate(args.url), {
          headers: args.headers ?? {}
        })
        if args.transform:
          results = apply_transform(response, args.transform)
        else:
          results = response

      elif source == "manual":
        # This would typically be preceded by a user_prompt node
        # that collects the results into state
        results = get_state_value(args.results_field)

      elif source == "contract":
        results = mcp_call("spoon-escrow", "read_contract", {
          address: interpolate(args.address),
          method: args.method,
          params: args.params ?? []
        })

      set_state_value(store_as, {
        results: results,
        source: source,
        fetched_at: now_iso8601(),
        source_metadata: {
          url: args.url ?? null,
          contract: args.address ?? null
        }
      })
    state_writes:
      - "${store_as}"
    state_reads: []

  since: "1.0.0"
```

#### Precondition: `outcome_check`

```yaml
outcome_check:
  category: extensions/outcome
  description:
    brief: Check outcome and competition state
    detail: |
      Unified outcome precondition. The aspect parameter determines what
      competition outcome property is checked.
    notes:
      - "aspect: round_scored - specific round has been scored (args.round_id)"
      - "aspect: winner_determined - competition has a winner"
      - "aspect: all_rounds_complete - all expected rounds have been scored (args.total_rounds)"

  parameters:
    - name: field
      type: string
      required: true
      description: State field containing outcome data
      pattern: "^[a-zA-Z_][a-zA-Z0-9_.]*$"
      interpolatable: false

    - name: aspect
      type: string
      required: true
      description: "Outcome aspect to check: round_scored, winner_determined, all_rounds_complete"
      enum:
        - round_scored
        - winner_determined
        - all_rounds_complete
      interpolatable: false

    - name: args
      type: object
      required: false
      description: |
        Aspect-specific arguments:
        - round_scored: { round_id: "round_15" }
        - all_rounds_complete: { total_rounds: 23 }
      interpolatable: false

  evaluation:
    effect: |
      data = get_state_value(field)
      if data == null:
        return false

      if aspect == "round_scored":
        if data.round_id:
          return data.round_id == args.round_id and data.scores != null
        return false

      elif aspect == "winner_determined":
        return data.winner_did != null

      elif aspect == "all_rounds_complete":
        scored_rounds = data.scored_rounds ?? []
        return len(scored_rounds) >= args.total_rounds
    reads:
      - "state.${field}"
    functions:
      - get_state_value

  since: "1.0.0"
```

---

## Complete Footy Tipping Workflow

Four phases showing how all 18 types compose into a real application.

### Phase 1: Season Creation

```yaml
name: footy_tipping_season_create
description: Create a new AFL tipping competition season
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.2.0
  extensions:
    - hiivmind/blueprint-web3-identity@v1.0.0
    - hiivmind/blueprint-web3-escrow@v1.0.0

initial_state:
  season_name: "AFL 2026"
  entry_fee_usdc: 10
  max_players: 20
  total_rounds: 23

nodes:
  start:
    type: action
    description: Create escrow pool for entry fees
    actions:
      - type: init_log
        workflow_name: footy_tipping_season_create
        workflow_version: "1.0"

      - type: escrow_ops
        operation: create_pool
        args:
          name: "${season_name}"
          entry_fee_usdc: "${entry_fee_usdc}"
          max_participants: "${max_players}"
          authority_did: "${organizer_did}"
          release_conditions:
            type: authority_release
            dispute_window_days: 7
        store_as: pool

      - type: mutate_state
        operation: set
        field: computed.season
        value:
          pool_id: "${computed.pool.pool_id}"
          name: "${season_name}"
          total_rounds: "${total_rounds}"
          created_at: "${computed.pool.tx_hash}"

      - type: store_immutable
        operation: publish
        content:
          type: season_config
          name: "${season_name}"
          pool_id: "${computed.pool.pool_id}"
          entry_fee_usdc: "${entry_fee_usdc}"
          max_players: "${max_players}"
          total_rounds: "${total_rounds}"
          organizer_did: "${organizer_did}"
        args:
          attributes:
            type: season_config
            season: "${season_name}"
        store_as: season_config_storage
    on_success: display_season_created
    on_failure: end_error

  display_season_created:
    type: action
    actions:
      - type: display
        format: markdown
        title: "Season Created"
        content: |
          **${season_name}** competition created!

          - Pool ID: `${computed.pool.pool_id}`
          - Entry Fee: $${entry_fee_usdc} USDC
          - Max Players: ${max_players}
          - Rounds: ${total_rounds}
          - Config stored: ${computed.season_config_storage.neofs_uri}

          Share the Pool ID with players for registration.
      - type: finalize_log
        outcome: success
    on_success: end_success
    on_failure: end_error

endings:
  end_success:
    type: success
    message: Season created successfully
    output:
      pool_id: "${computed.pool.pool_id}"
      season_config_uri: "${computed.season_config_storage.neofs_uri}"
  end_error:
    type: error
    message: Failed to create season
```

### Phase 2: Player Registration

```yaml
name: footy_tipping_register
description: Register a player for the tipping competition
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.2.0
  extensions:
    - hiivmind/blueprint-web3-identity@v1.0.0
    - hiivmind/blueprint-web3-escrow@v1.0.0

input_schema:
  pool_id:
    type: string
    required: true
  player_did:
    type: string
    required: true
  player_name:
    type: string
    required: true

nodes:
  start:
    type: action
    actions:
      - type: init_log
        workflow_name: footy_tipping_register
    on_success: check_prerequisites
    on_failure: end_error

  check_prerequisites:
    type: conditional
    description: Verify player DID is registered and pool is open
    condition:
      type: all_of
      conditions:
        - type: did_registered
          did: "${player_did}"
        - type: escrow_check
          pool_id: "${pool_id}"
          aspect: pool_open
        - type: escrow_check
          pool_id: "${pool_id}"
          aspect: depositor_registered
          args:
            did: "${player_did}"
          # Negate: player must NOT already be registered
          # Use none_of wrapper or evaluate_expression
    audit:
      enabled: true
      output: computed.prereq_audit
      messages:
        did_registered: "Player DID is not registered on-chain. Register your DID first."
        escrow_check: "Pool is not accepting registrations or player already registered."
    branches:
      on_true: verify_identity
      on_false: display_prereq_failures

  display_prereq_failures:
    type: action
    actions:
      - type: display
        format: markdown
        title: "Registration Failed"
        content: "Prerequisites not met. Check audit details."
      - type: finalize_log
        outcome: error
    on_success: end_prereq_failed
    on_failure: end_error

  verify_identity:
    type: action
    description: Challenge-response identity verification
    actions:
      - type: identity_ops
        operation: challenge
        args:
          length: 32
        store_as: challenge

      - type: display
        format: markdown
        content: |
          **Identity Verification Required**

          Sign this challenge with your DID private key:
          ```
          ${computed.challenge.challenge}
          ```
    on_success: await_signature
    on_failure: end_error

  await_signature:
    type: user_prompt
    prompt:
      question: "Paste your signed challenge response:"
      header: "Verify"
      options:
        - id: submit_sig
          label: Submit signature
          description: Paste the hex-encoded signature
    on_response:
      submit_sig:
        consequence:
          - type: mutate_state
            operation: set
            field: computed.signature
            value: "${user_responses.await_signature.raw.text}"
        next_node: verify_signature

  verify_signature:
    type: action
    description: Verify the challenge-response signature
    actions:
      - type: identity_ops
        operation: challenge_verify
        args:
          did: "${player_did}"
          challenge: "${computed.challenge.challenge}"
          signature: "${computed.signature}"
        store_as: verification
    on_success: check_verification
    on_failure: end_error

  check_verification:
    type: conditional
    condition:
      type: identity_check
      field: computed.verification
      aspect: verified
    branches:
      on_true: deposit_entry_fee
      on_false: end_identity_failed

  deposit_entry_fee:
    type: reference
    description: Deposit entry fee into escrow (spawn mode for key isolation)
    workflow: hiivmind/blueprint-web3-escrow@v1.0.0:escrow-deposit
    mode: spawn
    input:
      pool_id: "${pool_id}"
      depositor_did: "${player_did}"
    transitions:
      on_success: enroll_member
      on_failure: end_payment_failed
    output_mapping:
      state.computed.deposit_receipt: "output.receipt"

  enroll_member:
    type: action
    description: Add player to competition membership
    actions:
      - type: membership_ops
        operation: enroll
        group_id: "${pool_id}"
        args:
          did: "${player_did}"
          display_name: "${player_name}"
          metadata:
            registered_at: "${computed.deposit_receipt.timestamp}"
            deposit_tx: "${computed.deposit_receipt.tx_hash}"
        store_as: enrollment

      - type: display
        format: markdown
        title: "Registration Complete"
        content: |
          Welcome to the competition, **${player_name}**!

          - Member ID: `${computed.enrollment.member_id}`
          - Players registered: ${computed.enrollment.member_count}
          - Entry fee deposited: confirmed

      - type: finalize_log
        outcome: success
    on_success: end_success
    on_failure: end_error

endings:
  end_success:
    type: success
    message: Player registered successfully
    output:
      member_id: "${computed.enrollment.member_id}"
  end_prereq_failed:
    type: error
    message: Prerequisites not met
  end_identity_failed:
    type: error
    message: Identity verification failed
  end_payment_failed:
    type: error
    message: Entry fee deposit failed
  end_error:
    type: error
    message: Registration failed
```

### Phase 3: Weekly Tips

```yaml
name: footy_tipping_submit_tips
description: Submit weekly tips for a round
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.2.0
  extensions:
    - hiivmind/blueprint-web3-identity@v1.0.0
    - hiivmind/blueprint-web3-escrow@v1.0.0

input_schema:
  pool_id:
    type: string
    required: true
  player_did:
    type: string
    required: true
  round_id:
    type: string
    required: true

nodes:
  start:
    type: action
    actions:
      - type: init_log
        workflow_name: footy_tipping_submit_tips
    on_success: verify_membership
    on_failure: end_error

  verify_membership:
    type: conditional
    description: Check player is enrolled and hasn't already submitted
    condition:
      type: all_of
      conditions:
        - type: membership_check
          group_id: "${pool_id}"
          aspect: enrolled
          args:
            did: "${player_did}"
    branches:
      on_true: check_already_submitted
      on_false: end_not_member

  check_already_submitted:
    type: conditional
    description: Check if player already submitted for this round
    condition:
      type: membership_check
      group_id: "${pool_id}"
      aspect: has_submitted
      args:
        did: "${player_did}"
        round_id: "${round_id}"
    branches:
      on_true: ask_update_tips
      on_false: quick_identity_check

  ask_update_tips:
    type: user_prompt
    prompt:
      question: "You've already submitted tips for ${round_id}. Update them?"
      header: "Update?"
      options:
        - id: update
          label: Update tips
          description: Replace your previous submission
        - id: keep
          label: Keep existing
          description: Keep your current tips
    on_response:
      update:
        next_node: quick_identity_check
      keep:
        consequence:
          - type: finalize_log
            outcome: cancelled
        next_node: end_cancelled

  quick_identity_check:
    type: action
    description: Quick challenge-response auth (abbreviated flow)
    actions:
      - type: identity_ops
        operation: challenge
        args:
          length: 16
        store_as: tip_challenge
    on_success: collect_tips
    on_failure: end_error

  collect_tips:
    type: user_prompt
    prompt:
      question: |
        Enter your tips for ${round_id}.
        Format: one match per line as "HomeTeam > AwayTeam" or "HomeTeam < AwayTeam"

        Also paste your signed challenge: ${computed.tip_challenge.challenge}
      header: "Tips"
      options:
        - id: submit
          label: Submit tips
          description: Enter tips and signed challenge
    on_response:
      submit:
        consequence:
          - type: mutate_state
            operation: set
            field: computed.raw_tips_input
            value: "${user_responses.collect_tips.raw.text}"
        next_node: parse_and_verify

  parse_and_verify:
    type: action
    description: Parse tips, verify signature, record submission
    actions:
      # Parse tips from user input (inline for custom logic)
      - type: inline
        description: Parse tip lines and extract signature
        pseudocode: |
          lines = state.computed.raw_tips_input.split("\n")
          tips = []
          signature = null
          for line in lines:
            line = line.trim()
            if line.startsWith("sig:") or line.startsWith("0x"):
              signature = line.replace("sig:", "").trim()
            elif ">" in line or "<" in line:
              parts = line.split(">" if ">" in line else "<")
              winner = parts[0].trim() if ">" in line else parts[1].trim()
              tips.push({ match: line.trim(), pick: winner })
          state.computed.parsed_tips = tips
          state.computed.tip_signature = signature

      # Verify identity
      - type: identity_ops
        operation: challenge_verify
        args:
          did: "${player_did}"
          challenge: "${computed.tip_challenge.challenge}"
          signature: "${computed.tip_signature}"
        store_as: tip_auth

    on_success: check_auth_and_record
    on_failure: end_error

  check_auth_and_record:
    type: conditional
    condition:
      type: identity_check
      field: computed.tip_auth
      aspect: verified
    branches:
      on_true: record_tips
      on_false: end_auth_failed

  record_tips:
    type: action
    description: Record verified tips with content hash
    actions:
      - type: record_submission
        group_id: "${pool_id}"
        round_id: "${round_id}"
        submitter_did: "${player_did}"
        content: "${computed.parsed_tips}"
        sealed: false
        allow_update: true
        store_as: submission_receipt

      - type: display
        format: markdown
        title: "Tips Submitted"
        content: |
          Your tips for **${round_id}** have been recorded!

          - Content hash: `${computed.submission_receipt.content_hash}`
          - Stored at: ${computed.submission_receipt.storage_uri}
          - Timestamp: ${computed.submission_receipt.timestamp}

          Your tips are tamper-evident -- the hash proves they weren't changed after submission.

      - type: finalize_log
        outcome: success
    on_success: end_success
    on_failure: end_error

endings:
  end_success:
    type: success
    message: Tips submitted
    output:
      submission_id: "${computed.submission_receipt.submission_id}"
      content_hash: "${computed.submission_receipt.content_hash}"
  end_not_member:
    type: error
    message: Not a registered member of this competition
  end_auth_failed:
    type: error
    message: Identity verification failed
  end_cancelled:
    type: success
    message: Kept existing tips
  end_error:
    type: error
    message: Tip submission failed
```

### Phase 4: Season Resolution

```yaml
name: footy_tipping_resolve_season
description: Score rounds, determine winner, release escrow
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v3.2.0
  extensions:
    - hiivmind/blueprint-web3-identity@v1.0.0
    - hiivmind/blueprint-web3-escrow@v1.0.0

input_schema:
  pool_id:
    type: string
    required: true
  organizer_did:
    type: string
    required: true

nodes:
  start:
    type: action
    actions:
      - type: init_log
        workflow_name: footy_tipping_resolve_season
    on_success: verify_organizer
    on_failure: end_error

  verify_organizer:
    type: action
    description: Verify caller is the competition organizer
    actions:
      - type: identity_ops
        operation: challenge
        store_as: org_challenge
      # In practice, challenge-response would happen here
      # Simplified for illustration
      - type: escrow_ops
        operation: status
        pool_id: "${pool_id}"
        store_as: pool_status
    on_success: check_authority
    on_failure: end_error

  check_authority:
    type: conditional
    description: Verify organizer DID matches pool authority
    condition:
      type: evaluate_expression
      expression: "computed.pool_status.authority_did == organizer_did"
    branches:
      on_true: fetch_all_results
      on_false: end_unauthorized

  fetch_all_results:
    type: action
    description: Fetch match results for all rounds from AFL API
    actions:
      - type: oracle_feed
        source: api
        args:
          url: "https://api.squiggle.com.au/games?year=2026"
          transform: |
            .games | group_by(.round) | map({
              round_id: ("round_" + .[0].round),
              matches: map({
                home: .hteam,
                away: .ateam,
                winner: (if .hscore > .ascore then .hteam else .ateam end)
              })
            })
        store_as: all_results
    on_success: score_all_rounds
    on_failure: end_error

  score_all_rounds:
    type: action
    description: Score each round's submissions against actual results
    actions:
      # Score all rounds (in practice this would loop)
      - type: outcome_ops
        operation: aggregate_scores
        group_id: "${pool_id}"
        args:
          rounds: "all"
        store_as: aggregated_scores

      - type: outcome_ops
        operation: determine_winner
        group_id: "${pool_id}"
        args:
          scores_field: computed.aggregated_scores
          tie_break_rules:
            strategy: most_rounds_won
        store_as: winner_result
    on_success: display_leaderboard
    on_failure: end_error

  display_leaderboard:
    type: action
    description: Show final standings and confirm prize release
    actions:
      - type: display
        format: table
        title: "Final Leaderboard"
        headers:
          - Rank
          - Player
          - Score
          - Rounds
        content: "${computed.winner_result.leaderboard}"

      - type: display
        format: markdown
        content: |
          **Winner: ${computed.winner_result.winner_did}**
          Score: ${computed.winner_result.final_score}
          Tie-broken: ${computed.winner_result.is_tie_broken}
    on_success: confirm_release
    on_failure: end_error

  confirm_release:
    type: user_prompt
    prompt:
      question: "Release prize pool to winner ${computed.winner_result.winner_did}?"
      header: "Release"
      options:
        - id: release
          label: Release prize
          description: "Release full pool balance to winner"
        - id: dispute
          label: Open dispute
          description: "Flag results for review before releasing"
    on_response:
      release:
        next_node: release_prize
      dispute:
        consequence:
          - type: finalize_log
            outcome: partial
            summary: "Results disputed - prize release deferred"
        next_node: end_disputed

  release_prize:
    type: reference
    description: Release escrow to winner (spawn mode for key isolation)
    workflow: hiivmind/blueprint-web3-escrow@v1.0.0:escrow-release
    mode: spawn
    input:
      pool_id: "${pool_id}"
      recipient_did: "${computed.winner_result.winner_did}"
      reason: "Season winner - ${computed.winner_result.final_score} points"
    transitions:
      on_success: issue_winner_attestation
      on_failure: end_release_failed
    output_mapping:
      state.computed.release_receipt: "output.receipt"

  issue_winner_attestation:
    type: action
    description: Issue signed attestation that player won the season
    actions:
      - type: attestation_ops
        operation: create
        args:
          subject_did: "${computed.winner_result.winner_did}"
          claim_type: season_winner
          claim_data:
            season: "${season_name}"
            pool_id: "${pool_id}"
            final_score: "${computed.winner_result.final_score}"
            release_tx: "${computed.release_receipt.tx_hash}"
          evidence_urls:
            - "${computed.season_config_storage.neofs_uri}"
        store_as: winner_attestation

      - type: store_immutable
        operation: publish
        content: "${computed.winner_attestation}"
        args:
          attributes:
            type: season_winner_attestation
            season: "${season_name}"
        store_as: attestation_storage

      - type: attestation_ops
        operation: submit_reputation
        args:
          subject_did: "${computed.winner_result.winner_did}"
          score: 80
          evidence: "Season winner: ${season_name}"
        store_as: reputation_tx

      - type: display
        format: markdown
        title: "Season Complete"
        content: |
          **${season_name} is complete!**

          - Winner: ${computed.winner_result.winner_did}
          - Prize released: tx ${computed.release_receipt.tx_hash}
          - Winner attestation: ${computed.attestation_storage.neofs_uri}
          - Reputation submitted: tx ${computed.reputation_tx.tx_hash}

      - type: finalize_log
        outcome: success
    on_success: end_success
    on_failure: end_error

endings:
  end_success:
    type: success
    message: Season resolved and prize released
    output:
      winner_did: "${computed.winner_result.winner_did}"
      release_tx: "${computed.release_receipt.tx_hash}"
      attestation_uri: "${computed.attestation_storage.neofs_uri}"
  end_unauthorized:
    type: error
    message: Caller is not the competition organizer
  end_disputed:
    type: success
    message: Results flagged for dispute review
  end_release_failed:
    type: error
    message: Prize release failed
  end_error:
    type: error
    message: Season resolution failed
```

---

## Key Design Decisions

### ADR-6: Blueprint Type vs Raw MCP Call

**Decision:** Create named Blueprint types for repeated, structured interaction patterns. Use raw `run_command` or `web_ops` + MCP for one-off operations.

**Rationale:** The "codify patterns that emerge from usage" principle (Phase 1 in spoon-core analysis). If a workflow author finds themselves writing the same MCP call shape in multiple workflows, that's a signal to extract a type. The 11 consequences and 7 preconditions here represent patterns that recur across any competition/membership/identity workflow.

**Example:**
- `identity_ops` with `operation: challenge` is a type because every identity-gated action uses challenge-response.
- "Query a specific smart contract view function" stays as a raw MCP call because the call shape varies every time.

### ADR-7: Escrow as a Blueprint Type (Wrapping a Smart Contract)

**Decision:** Yes -- `escrow_ops` wraps a smart contract via MCP, but the contract is the enforcement layer (per ADR-2).

**Rationale:** Escrow hold-and-release is fundamentally different from x402 pay-and-go. x402 handles: "pay $0.001 to access this URL". Escrow handles: "hold $10 from 20 players, release $200 to the winner when the organizer says so". This requires a new smart contract that doesn't exist in spoon-core today.

The Blueprint type automates the correct calling sequence. The smart contract enforces:
- Only the authority DID can release funds
- Refund is possible before release
- Funds cannot be released twice
- Depositor accounting is on-chain

### ADR-8: Two Extension Repos

**Decision:** Split into `blueprint-web3-identity` (identity + attestation) and `blueprint-web3-escrow` (escrow + membership + outcome).

**Rationale:**
- **Identity + attestation** have no financial dependency. They're useful independently (e.g., identity-gated API access without money involved).
- **Escrow + membership + outcome** form a competition lifecycle. Membership is identity-gated (depends on identity repo) but financially linked (deposits required). Outcome depends on membership (submissions) and escrow (prize release).
- Two repos means a project can use identity without bringing in escrow dependency.

### ADR-9: Escrow Smart Contract is a New Deployment Requirement

**Decision:** The escrow contract must be developed and deployed. It's not part of spoon-core's existing x402 infrastructure.

**Rationale:** x402 is a request-response payment protocol (pay, get access). Escrow is a pool-based holding protocol (deposit, hold, conditionally release). The escrow contract needs:
- Pool creation with authority DID
- Deposit tracking per DID
- Authority-gated release
- Timeout-based refund
- On-chain membership registry

This is a meaningful smart contract development effort, not a configuration of existing tools.

### ADR-10: Content Hashing for Submission Integrity

**Decision:** All submissions are SHA-256 hashed at recording time. The hash is stored immutably in NeoFS.

**Rationale:** This provides tamper-evidence for the tipping scenario. Once tips are submitted, the hash proves the content hasn't been modified. Even if the organizer or another player compromises the storage, the hash in NeoFS is immutable evidence of what was actually submitted. This leverages Blueprint's existing `compute_hash` type pattern.

---

## Mapping to Spoon-Core Capabilities

| Blueprint Type | Spoon-Core Class/Function | Module | Exists Today? |
|---------------|--------------------------|--------|---------------|
| `identity_ops` (resolve) | `DIDResolver.resolve()` | `identity/did_resolver.py` | Yes |
| `identity_ops` (verify) | `DIDResolver.verify_did()` | `identity/did_resolver.py` | Yes |
| `identity_ops` (register) | `ERC8004Client.register_agent()` | `identity/erc8004_client.py` | Yes |
| `identity_ops` (challenge) | New -- generate random challenge | -- | No (trivial) |
| `identity_ops` (challenge_verify) | EIP-712 signature verification | `identity/erc8004_client.py` | Partial |
| `identity_trust_score` | `TrustScoreCalculator.calculate_trust_score()` | `identity/attestation.py` | Yes |
| `attestation_ops` (create) | `AttestationManager.create_attestation()` | `identity/attestation.py` | Yes |
| `attestation_ops` (verify) | `AttestationManager.verify_attestation()` | `identity/attestation.py` | Yes |
| `attestation_ops` (submit_reputation) | `AttestationManager.submit_reputation_on_chain()` | `identity/attestation.py` | Yes |
| `attestation_ops` (submit_validation) | `AttestationManager.submit_validation_on_chain()` | `identity/attestation.py` | Yes |
| `store_immutable` (publish) | `DIDStorageClient.publish_credential()` | `identity/storage_client.py` | Yes |
| `store_immutable` (fetch) | `DIDStorageClient.fetch_did_document()` | `identity/storage_client.py` | Yes |
| `escrow_ops` | **New escrow smart contract** | -- | **No** |
| `membership_ops` | **New membership tracking** (in escrow contract or NeoFS) | -- | **No** |
| `record_submission` | **New submission recording** (NeoFS + hash) | -- | **No** (NeoFS client exists) |
| `oracle_feed` (api) | Standard HTTP fetch | -- | Yes (generic) |
| `outcome_ops` | **New scoring/ranking logic** | -- | **No** (application-level) |

### What Needs Building

| Component | Effort | Dependency |
|-----------|--------|------------|
| Challenge-response auth MCP endpoint | Small | spoon-core identity module |
| Escrow smart contract (Solidity) | **Large** | New deployment on Base |
| Escrow MCP server wrapper | Medium | Escrow contract |
| Membership tracking (contract or NeoFS) | Medium | Escrow contract or NeoFS client |
| Submission recording MCP endpoint | Medium | NeoFS client (exists) |
| Scoring/ranking computation | Small | Application logic, no Web3 dependency |
| Blueprint type definitions (this doc) | Small | None (just YAML) |
| Blueprint extension repos | Small | Type definitions |

---

## Relationship to Spoon-Core Analysis

This document builds on and does not conflict with the spoon-core integration analysis:

| Spoon-Core Analysis Concept | This Document |
|-----------------------------|---------------|
| ADR-1: MCP as bridge protocol | All types use `mcp_call()` for spoon-core interaction |
| ADR-2: Server-side enforcement | Escrow contract enforces, workflow automates |
| ADR-3: Spawn mode for key operations | Deposit, release, refund all use spawn mode |
| ADR-4: Definitions free, execution metered | Types are YAML definitions; execution is on-chain |
| ADR-5: Extension repos | Two new repos, not in core blueprint-lib |
| Phase 0: MCP Bridge | All types work through existing MCP infrastructure |
| Phase 1: Codify patterns | These types ARE the codified patterns |
| Threat model T1.3 (receipt forgery) | `payment_receipt_check` precondition |
| Threat model T4.6 (state leakage) | Spawn mode mandatory for all financial operations |
| `payment_check` gap identified | Filled by `payment_receipt_check` + `escrow_check` |

### Metering Types (from spoon-core analysis) vs Escrow Types (this document)

These are **complementary, not overlapping**:

| Metering (spoon-core analysis) | Escrow (this document) |
|-------------------------------|----------------------|
| Pay-per-step execution | Hold-and-release pools |
| Token consumption model | Prize pool model |
| Server deducts on each call | Contract holds until authority releases |
| For: paid skills, premium APIs | For: competitions, auctions, bounties |
| Uses x402 (existing) | Uses new escrow contract |

---

## Glossary (additions to spoon-core analysis)

| Term | Definition |
|------|-----------|
| **Escrow pool** | Smart contract holding funds from multiple depositors, released conditionally by an authority |
| **Authority DID** | The DID authorized to release escrow funds (e.g., competition organizer) |
| **Challenge-response auth** | Identity verification pattern: server generates random bytes, client signs with DID private key, server verifies signature |
| **Content hash** | SHA-256 hash of submission content, stored immutably for tamper evidence |
| **Sealed submission** | Submission where content is encrypted; only the hash is visible until a reveal event |
| **Oracle feed** | External data source providing real-world results (e.g., match scores from an API) |
| **Dispute window** | Time period after results are posted during which participants can challenge outcomes |
| **Trust level** | Categorical rating (untrusted/low/medium/high/verified) derived from on-chain reputation and validation data |
| **NeoFS** | Neo ecosystem distributed file storage, used as primary immutable storage layer |
| **Agent card** | Human-readable metadata about a DID agent, following Google A2A protocol format |
