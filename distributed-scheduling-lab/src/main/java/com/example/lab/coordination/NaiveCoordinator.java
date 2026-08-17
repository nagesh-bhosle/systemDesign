package com.example.lab.coordination;

import com.example.lab.domain.Message;
import com.example.lab.domain.MessageStatus;
import com.example.lab.domain.MessageType;
import com.example.lab.repo.MessageRepository;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * The broken baseline — kept on purpose, it is the lesson.
 *
 * Deliberately WRONG: SELECT candidates, then blindly UPDATE by id with NO
 * status guard, NO lock and NO claim token. With 3 scheduler instances polling
 * on near-identical timing this WILL double-process within minutes — directly
 * observable as processed_count > 1 and a growing "duplicates" counter on the
 * dashboard. complete() is equally unguarded: it unconditionally flips the row
 * to DONE and increments processed_count, so every racing completion is
 * recorded and visible.
 *
 * Used only when lab.mode=naive (Script A) to demonstrate the failure mode
 * both real strategies fix. One instance per MessageType is registered by the
 * CoordinatorRouter — the Coordinator interface routes by handles(), so a
 * single shared instance could only ever scan one type's queue and would
 * starve the other.
 */
public class NaiveCoordinator implements Coordinator {

    private final MessageRepository repo;
    private final MessageType type;

    public NaiveCoordinator(MessageRepository repo, MessageType type) {
        this.repo = repo;
        this.type = type;
    }

    @Override
    public List<Message> claimBatch(String instanceName, int batchSize) {
        // RACE WINDOW: between this unguarded SELECT and the blind UPDATEs
        // below, any other instance can read and claim the exact same rows.
        List<Message> candidates = repo.findTop50ByTypeAndStatusOrderByCreatedAt(
                type, MessageStatus.NEW);

        List<Message> won = new ArrayList<>();
        for (Message m : candidates) {
            if (won.size() >= batchSize) {
                break;
            }
            // Blind UPDATE by id: no status guard, no token, no lock.
            repo.naiveMarkProcessing(m.getId(), instanceName, Instant.now());
            won.add(m);
        }
        return won;
    }

    @Override
    public boolean complete(Message m, String instanceName, UUID claimToken) {
        // Unconditional: flips to DONE and increments processed_count no
        // matter who claimed the row or how many times it was completed.
        return repo.naiveComplete(m.getId(), Instant.now()) == 1;
    }

    @Override
    public MessageType handles() {
        return type;
    }
}
