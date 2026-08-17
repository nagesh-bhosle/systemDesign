package com.example.lab.scheduling;

import com.example.lab.coordination.Coordinator;
import com.example.lab.coordination.CoordinatorRouter;
import com.example.lab.domain.Message;
import com.example.lab.domain.MessageType;
import com.example.lab.events.EventBus;
import com.example.lab.events.ProcessingEvent;
import com.example.lab.processing.ProcessingSimulator;
import org.springframework.scheduling.annotation.Scheduled;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * One simulated cluster node. Three of these run inside the same JVM and poll
 * every lab.scheduler-poll-ms (default 3s), each claiming work through the
 * CoordinatorRouter.
 *
 * Key invariants (spec §16):
 *  #1 at-most-once successful processing — completion goes through the
 *     coordinator's guarded complete(); a lost race yields false and is
 *     reported as LATE_WRITE_REJECTED, never as an error;
 *  #2 never lost — if this instance is killed mid-processing it simply stops
 *     before completing; the lease expires and the sweeper requeues the row;
 *  #4 instance count is unknowable and irrelevant — this node knows nothing
 *     about the other nodes; correctness comes from atomic claims and
 *     idempotent writes.
 */
public class SchedulerInstance {

    private final String name;                    // "scheduler-1", etc.
    private final CoordinatorRouter router;
    private final ProcessingSimulator processor;
    private final EventBus events;
    private final int batchSize;

    private final AtomicBoolean alive = new AtomicBoolean(true);
    private final AtomicReference<String> currentWork = new AtomicReference<>("idle");

    public SchedulerInstance(String name,
                             CoordinatorRouter router,
                             ProcessingSimulator processor,
                             EventBus events,
                             int batchSize) {
        this.name = name;
        this.router = router;
        this.processor = processor;
        this.events = events;
        this.batchSize = batchSize;
    }

    @Scheduled(fixedDelayString = "${lab.scheduler-poll-ms:3000}")
    public void poll() {
        if (!alive.get()) {
            return;                               // a dead instance does nothing
        }
        for (MessageType type : MessageType.values()) {
            if (!alive.get()) {
                return;
            }
            Coordinator c = router.forType(type);
            List<Message> batch = c.claimBatch(name, batchSize);
            for (Message m : batch) {
                if (!alive.get()) {
                    // Killed while holding a claim: abandon the work WITHOUT
                    // completing it. The lease expires and the sweeper requeues
                    // the row — this is exactly the crash Scripts B/C simulate.
                    currentWork.set("idle");
                    return;
                }
                currentWork.set(type + " #" + m.getId());
                events.publish(ProcessingEvent.claimed(m, name));
                try {
                    processor.process(m);         // sleeps 500-1500 ms (or 40s for the slow message)
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    currentWork.set("idle");
                    return;
                }
                if (!alive.get()) {
                    // Died during processing (e.g. the 40s slow message):
                    // do NOT write the completion — it is no longer ours to write.
                    currentWork.set("idle");
                    return;
                }
                UUID token = m.getClaimToken();
                boolean ok = c.complete(m, name, token);
                events.publish(ok
                        ? ProcessingEvent.completed(m, name)
                        : ProcessingEvent.lateWriteRejected(m, name));
                currentWork.set("idle");
            }
        }
    }

    public void kill() {
        alive.set(false);
    }    // simulate crash / scale-down

    public void revive() {
        alive.set(true);
    }    // simulate scale-up

    public boolean isAlive() {
        return alive.get();
    }

    public String getName() {
        return name;
    }

    public String getCurrentWork() {
        return currentWork.get();
    }
}
