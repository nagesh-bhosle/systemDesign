package com.example.lab.coordination;

import com.example.lab.domain.Message;
import com.example.lab.domain.MessageType;
import com.example.lab.repo.MessageRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Strategy 2 — database atomic claim, used for EOD messages.
 *
 * Semantics: one atomic UPDATE that claims a whole batch using
 * FOR UPDATE SKIP LOCKED in a CTE, returning the full claimed rows. The lease
 * (lab.lease-seconds, default 30s) is enforced by the shared LeaseSweeper.
 * The claim and its commit happen in a short transaction; processing happens
 * outside it.
 *
 * Key invariants (spec §16):
 *  #1 at-most-once successful processing — complete() goes through the guarded
 *     completeIfOwned update, so a late write after lease expiry is rejected;
 *  #2 never lost — a dead instance's rows are requeued by the sweeper;
 *  #4 instance count is unknowable and irrelevant — competing claimers either
 *     lock rows or SKIP LOCKED past them; no membership tracking exists.
 */
@Component
public class DbClaimCoordinator implements Coordinator {

    private final MessageRepository repo;

    public DbClaimCoordinator(MessageRepository repo) {
        this.repo = repo;
    }

    @Override
    @Transactional
    public List<Message> claimBatch(String instanceName, int batchSize) {
        UUID batchToken = UUID.randomUUID();
        // One statement: selects candidates, locks them (competitors skip),
        // flips to PROCESSING, returns the rows we actually won.
        return repo.claimEodBatch(instanceName, batchToken, Instant.now(), batchSize);
    }

    @Override
    public boolean complete(Message m, String instanceName, UUID claimToken) {
        return repo.completeIfOwned(
                m.getId(), instanceName, claimToken, Instant.now()) == 1;
    }

    @Override
    public MessageType handles() {
        return MessageType.EOD;
    }
}
