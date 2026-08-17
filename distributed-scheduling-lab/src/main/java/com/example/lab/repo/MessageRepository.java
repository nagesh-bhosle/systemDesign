package com.example.lab.repo;

import com.example.lab.domain.Message;
import com.example.lab.domain.MessageStatus;
import com.example.lab.domain.MessageType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface MessageRepository extends JpaRepository<Message, Long> {

    List<Message> findTop50ByTypeAndStatusOrderByCreatedAt(
            MessageType type, MessageStatus status);

    // --- shared guarded completion (idempotent) ---
    // processed_count is incremented on every successful transition so
    // naive-mode duplicates become visible as processed_count > 1.
    //
    // Key invariant (spec §16 #1): a message may be processed at most once
    // successfully. This guard — not hope about claims never colliding — is
    // what enforces it. A return of 0 means the caller no longer owns the
    // claim; that is a normal, harmless late write.
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Transactional
    @Query("UPDATE Message m SET m.status = 'DONE', m.processedAt = :now, " +
           "m.processedCount = m.processedCount + 1 " +
           "WHERE m.id = :id AND m.status = 'PROCESSING' " +
           "AND m.claimedBy = :instance AND m.claimToken = :token")
    int completeIfOwned(@Param("id") Long id,
                        @Param("instance") String instance,
                        @Param("token") UUID token,
                        @Param("now") Instant now);

    // --- Redis strategy bookkeeping (guarded) ---
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Transactional
    @Query("UPDATE Message m SET m.status = 'PROCESSING', m.claimedBy = :inst, " +
           "m.claimToken = :token, m.claimedAt = :now, " +
           "m.attempts = m.attempts + 1 " +
           "WHERE m.id = :id AND m.status = 'NEW'")
    int markProcessing(@Param("id") Long id,
                       @Param("inst") String inst,
                       @Param("token") UUID token,
                       @Param("now") Instant now);

    // --- DB strategy atomic claim (PostgreSQL dialect) ---
    //
    // NOTE: deliberately NOT annotated with @Modifying. A modifying query goes
    // through executeUpdate(), which discards the RETURNING result set. Executed
    // as a selection instead, PostgreSQL hands back the updated rows and
    // Hibernate maps them onto Message entities. The @Transactional caller
    // (DbClaimCoordinator.claimBatch) commits the flip to PROCESSING.
    //
    // Key invariant (spec §16 #4): correctness comes from this atomic claim —
    // concurrent instances either lock the row or SKIP LOCKED past it — never
    // from knowing how many instances exist.
    @Transactional
    @Query(value = """
            WITH batch AS (
                SELECT id FROM messages
                WHERE status = 'NEW' AND type = 'EOD'
                ORDER BY created_at
                LIMIT :batchSize
                FOR UPDATE SKIP LOCKED
            )
            UPDATE messages m
            SET status      = 'PROCESSING',
                claimed_by  = :inst,
                claim_token = :token,
                claimed_at  = :now,
                attempts    = attempts + 1
            FROM batch b
            WHERE m.id = b.id
            RETURNING m.*
            """, nativeQuery = true)
    List<Message> claimEodBatch(@Param("inst") String inst,
                                @Param("token") UUID token,
                                @Param("now") Instant now,
                                @Param("batchSize") int batchSize);

    // --- lease sweeper (shared by both strategies) ---
    //
    // Key invariant (spec §16 #2): a message is never lost. If an instance dies
    // mid-processing, its claim goes stale and this query flips the row back to
    // NEW so a survivor picks it up. Recovery never depends on instances
    // announcing their death.
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Transactional
    @Query("UPDATE Message m SET m.status = 'NEW', m.claimedBy = null, " +
           "m.claimToken = null, m.claimedAt = null " +
           "WHERE m.status = 'PROCESSING' AND m.claimedAt < :expiredBefore")
    int requeueExpired(@Param("expiredBefore") Instant expiredBefore);

    // --- naive (deliberately broken) operations: NO status guard, NO token ---
    // Used only by NaiveCoordinator in lab.mode=naive to demonstrate the
    // double-processing failure mode (processed_count > 1).
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Transactional
    @Query("UPDATE Message m SET m.status = 'PROCESSING', m.claimedBy = :inst, " +
           "m.claimedAt = :now, m.attempts = m.attempts + 1 " +
           "WHERE m.id = :id")
    int naiveMarkProcessing(@Param("id") Long id,
                            @Param("inst") String inst,
                            @Param("now") Instant now);

    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Transactional
    @Query("UPDATE Message m SET m.status = 'DONE', m.processedAt = :now, " +
           "m.processedCount = m.processedCount + 1 " +
           "WHERE m.id = :id")
    int naiveComplete(@Param("id") Long id,
                      @Param("now") Instant now);

    // --- stats for the dashboard ---
    long countByStatusAndType(MessageStatus status, MessageType type);

    long countByProcessedCountGreaterThan(int processedCount);

    // --- reset ---
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Transactional
    @Query(value = "TRUNCATE TABLE messages", nativeQuery = true)
    void truncateMessages();
}
