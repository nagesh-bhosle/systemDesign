package com.example.lab.scheduling;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Collects the three SchedulerInstance beans (registered by SchedulerConfig)
 * into a name -> instance lookup used by the kill/revive endpoints and the
 * stats API.
 */
@Component
public class SchedulerRegistry {

    private final Map<String, SchedulerInstance> instances = new LinkedHashMap<>();

    public SchedulerRegistry(List<SchedulerInstance> allInstances) {
        for (SchedulerInstance instance : allInstances) {
            instances.put(instance.getName(), instance);
        }
    }

    public Optional<SchedulerInstance> find(String name) {
        return Optional.ofNullable(instances.get(name));
    }

    public List<SchedulerInstance> all() {
        return new ArrayList<>(instances.values());
    }
}
