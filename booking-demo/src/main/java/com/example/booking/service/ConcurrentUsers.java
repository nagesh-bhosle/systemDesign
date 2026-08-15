package com.example.booking.service;

import com.example.booking.dto.BookOutcome;
import com.example.booking.dto.ConceptResult;
import com.example.booking.dto.ConceptResult.UserAttempt;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;

public final class ConcurrentUsers {

    private ConcurrentUsers() {
    }

    public static List<UserAttempt> run(int userCount, Function<Long, BookOutcome> action) {
        ExecutorService pool = Executors.newFixedThreadPool(userCount);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<UserAttempt>> futures = new ArrayList<>();
        try {
            for (int i = 1; i <= userCount; i++) {
                long userId = i;
                futures.add(pool.submit(() -> {
                    start.await();
                    long t0 = System.nanoTime();
                    try {
                        BookOutcome outcome = action.apply(userId);
                        long ms = (System.nanoTime() - t0) / 1_000_000L;
                        return new UserAttempt(userId, outcome.isSuccess(), outcome.getMessage(), ms);
                    } catch (Exception e) {
                        long ms = (System.nanoTime() - t0) / 1_000_000L;
                        return new UserAttempt(userId, false, e.getClass().getSimpleName() + ": " + e.getMessage(), ms);
                    }
                }));
            }
            start.countDown();
            List<UserAttempt> results = new ArrayList<>();
            for (Future<UserAttempt> future : futures) {
                results.add(future.get(60, TimeUnit.SECONDS));
            }
            return results;
        } catch (Exception e) {
            throw new IllegalStateException("Concurrent demo failed", e);
        } finally {
            pool.shutdownNow();
        }
    }

    public static long successCount(List<UserAttempt> users) {
        return users.stream().filter(UserAttempt::isSuccess).count();
    }

    public static ConceptResult base(String concept, String title) {
        ConceptResult result = new ConceptResult();
        result.setConcept(concept);
        result.setTitle(title);
        return result;
    }
}
