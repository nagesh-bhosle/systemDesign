package com.example.lab.scheduling;

import com.example.lab.events.EventBus;
import com.example.lab.events.ProcessingEvent;
import com.example.lab.repo.MessageRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/**
 * Shared crash-recovery daemon for BOTH strategies.
 *
 * Key invariants (spec §16):
 *  #2 a message is never lost — rows whose claim went stale (owning instance
 *     died, Redis TTL expired, DB lease lapsed) are flipped back to NEW so a
 *     survivor picks them up. Recovery never depends on an instance announcing
 *     its death;
 *  #3 coordination is per-strategy; recovery is shared — for EOD it reclaims
 *     rows whose owner died, for INTRADAY it reconciles DB state after the
 *     Redis lock has already expired on its own.
 */
@Component
public class LeaseSweeper {

    private static final Logger log = LoggerFactory.getLogger(LeaseSweeper.class);

    private final MessageRepository repo;
    private final EventBus events;
    private final Duration lease;

    public LeaseSweeper(MessageRepository repo,
                        EventBus events,
                        @Value("${lab.lease-seconds:30}") long leaseSeconds) {
        this.repo = repo;
        this.events = events;
        this.lease = Duration.ofSeconds(leaseSeconds);
    }

    @Scheduled(fixedDelay = 5000)
    public void sweep() {
        int requeued = repo.requeueExpired(Instant.now().minus(lease));
        if (requeued > 0) {
            log.info("lease sweeper requeued {} stale message(s)", requeued);
            events.publish(ProcessingEvent.requeued(requeued));
        }
    }
}
