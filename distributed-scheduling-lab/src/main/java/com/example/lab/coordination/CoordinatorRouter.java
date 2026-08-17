package com.example.lab.coordination;

import com.example.lab.domain.MessageType;
import com.example.lab.repo.MessageRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Maps MessageType -> Coordinator.
 *
 * - lab.mode=naive        -> a NaiveCoordinator per type (Script A: watch
 *                            duplicates appear on BOTH queues);
 * - lab.mode=coordinated  -> RedisLockCoordinator for INTRADAY,
 *                            DbClaimCoordinator for EOD.
 *
 * Key invariant (spec §16 #3): coordination is per-strategy; recovery is
 * shared. The two strategies claim differently, but one LeaseSweeper
 * reconciles both.
 */
@Component
public class CoordinatorRouter {

    private final NaiveCoordinator naiveIntraday;
    private final NaiveCoordinator naiveEod;
    private final RedisLockCoordinator redisLock;
    private final DbClaimCoordinator dbClaim;
    private final String mode;

    public CoordinatorRouter(MessageRepository repo,
                             RedisLockCoordinator redisLock,
                             DbClaimCoordinator dbClaim,
                             @Value("${lab.mode:coordinated}") String mode) {
        // One broken coordinator per type: the Coordinator interface routes
        // by handles(), so a single shared instance could only scan one
        // queue and would starve the other in naive mode.
        this.naiveIntraday = new NaiveCoordinator(repo, MessageType.INTRADAY);
        this.naiveEod = new NaiveCoordinator(repo, MessageType.EOD);
        this.redisLock = redisLock;
        this.dbClaim = dbClaim;
        this.mode = mode == null ? "coordinated" : mode.trim().toLowerCase();
    }

    public Coordinator forType(MessageType type) {
        if ("naive".equals(mode)) {
            return type == MessageType.INTRADAY ? naiveIntraday : naiveEod;
        }
        // coordinated (default)
        return type == MessageType.INTRADAY ? redisLock : dbClaim;
    }

    public String mode() {
        return mode;
    }
}
