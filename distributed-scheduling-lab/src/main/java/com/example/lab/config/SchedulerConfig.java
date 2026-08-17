package com.example.lab.config;

import com.example.lab.coordination.CoordinatorRouter;
import com.example.lab.events.EventBus;
import com.example.lab.processing.ProcessingSimulator;
import com.example.lab.scheduling.SchedulerInstance;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/**
 * Registers the three simulated scheduler instances (scheduler-1/2/3).
 *
 * IMPORTANT: all three share one JVM (same connection pools, same Redis
 * connection). This simulates a cluster for coordination-behavior purposes;
 * it does NOT simulate network partitions. Sharing the JVM actually makes
 * contention more aggressive, since all schedulers fire on near-identical
 * timing — which is exactly what we want to demonstrate.
 *
 * Key invariant (spec §16 #4): instance count is unknowable and irrelevant.
 * Schedulers join and leave freely (kill/revive); correctness comes from
 * atomic claims and idempotent writes, never from membership tracking.
 */
@Configuration
@EnableScheduling
public class SchedulerConfig {

    /**
     * A multi-threaded scheduler so the three instances and the sweeper run
     * concurrently — with the default single thread they would execute
     * serially and never contend.
     */
    @Bean(name = "taskScheduler")
    public ThreadPoolTaskScheduler taskScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(8);
        scheduler.setThreadNamePrefix("sched-");
        scheduler.setDaemon(true);
        return scheduler;
    }

    @Bean(name = "scheduler-1")
    public SchedulerInstance scheduler1(CoordinatorRouter router,
                                        ProcessingSimulator processor,
                                        EventBus events,
                                        @Value("${lab.batch-size:5}") int batchSize) {
        return new SchedulerInstance("scheduler-1", router, processor, events, batchSize);
    }

    @Bean(name = "scheduler-2")
    public SchedulerInstance scheduler2(CoordinatorRouter router,
                                        ProcessingSimulator processor,
                                        EventBus events,
                                        @Value("${lab.batch-size:5}") int batchSize) {
        return new SchedulerInstance("scheduler-2", router, processor, events, batchSize);
    }

    @Bean(name = "scheduler-3")
    public SchedulerInstance scheduler3(CoordinatorRouter router,
                                        ProcessingSimulator processor,
                                        EventBus events,
                                        @Value("${lab.batch-size:5}") int batchSize) {
        return new SchedulerInstance("scheduler-3", router, processor, events, batchSize);
    }
}
