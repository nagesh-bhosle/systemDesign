package com.example.booking.scheduler;

import com.example.booking.repository.HoldableSeatRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Component
public class HoldCleanupJob {

    private static final Logger log = LoggerFactory.getLogger(HoldCleanupJob.class);

    private final HoldableSeatRepository seats;

    public HoldCleanupJob(HoldableSeatRepository seats) {
        this.seats = seats;
    }

    @Scheduled(fixedRate = 5000)
    @Transactional
    public void releaseExpiredHolds() {
        int released = seats.releaseExpiredHolds(Instant.now());
        if (released > 0) {
            log.info("Released {} expired hold(s)", released);
        }
    }
}
