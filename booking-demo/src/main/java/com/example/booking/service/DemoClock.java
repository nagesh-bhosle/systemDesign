package com.example.booking.service;

import com.example.booking.dto.ConceptResult.TimelineEvent;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

public class DemoClock {

    private final long startedAtNanos = System.nanoTime();
    private final List<TimelineEvent> events = new CopyOnWriteArrayList<>();

    public void event(long userId, String step) {
        long atMs = (System.nanoTime() - startedAtNanos) / 1_000_000L;
        events.add(new TimelineEvent(userId, atMs, step));
    }

    public List<TimelineEvent> snapshot() {
        List<TimelineEvent> copy = new ArrayList<>(events);
        copy.sort(Comparator.comparingLong(TimelineEvent::getAtMs).thenComparingLong(TimelineEvent::getUserId));
        return copy;
    }

    public static void sleep(int delayMs) {
        if (delayMs <= 0) {
            return;
        }
        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted during demo delay", e);
        }
    }
}
