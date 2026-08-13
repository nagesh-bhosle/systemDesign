package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.entity.AtomicCounter;
import com.example.booking.entity.UnsafeCounter;
import com.example.booking.repository.AtomicCounterRepository;
import com.example.booking.repository.UnsafeCounterRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CounterService {

    private final UnsafeCounterRepository unsafeCounters;
    private final AtomicCounterRepository atomicCounters;

    public CounterService(UnsafeCounterRepository unsafeCounters, AtomicCounterRepository atomicCounters) {
        this.unsafeCounters = unsafeCounters;
        this.atomicCounters = atomicCounters;
    }

    @Transactional
    public BookOutcome incrementUnsafe(Long id, Long userId, int delayMs, DemoClock clock) {
        UnsafeCounter counter = unsafeCounters.findById(id).orElseThrow();
        int seen = counter.getValue();
        clock.event(userId, "READ value=" + seen);
        DemoClock.sleep(delayMs);
        counter.setValue(seen + 1);
        unsafeCounters.save(counter);
        clock.event(userId, "WRITE value=" + (seen + 1) + " (lost update if another user wrote in between)");
        return BookOutcome.ok("Wrote " + (seen + 1));
    }

    @Transactional
    public BookOutcome incrementAtomic(Long id, Long userId, DemoClock clock) {
        clock.event(userId, "UPDATE atomic_counter SET counter_value = counter_value + 1");
        int rows = atomicCounters.increment(id, 1);
        AtomicCounter counter = atomicCounters.findById(id).orElseThrow();
        clock.event(userId, "rows=" + rows + " value now=" + counter.getValue());
        return BookOutcome.ok("Atomic increment, value=" + counter.getValue());
    }
}
