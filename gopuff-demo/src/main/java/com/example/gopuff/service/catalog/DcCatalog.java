package com.example.gopuff.service.catalog;

import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.repository.DistributionCenterRepository;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

@Component
public class DcCatalog {

    private final DistributionCenterRepository repository;
    private final AtomicReference<List<DistributionCenter>> snapshot = new AtomicReference<>(List.of());

    public DcCatalog(DistributionCenterRepository repository) {
        this.repository = repository;
    }

    @Scheduled(initialDelay = 0, fixedRateString = "${gopuff.nearby.dc-sync-ms:300000}")
    public void refresh() {
        snapshot.set(List.copyOf(repository.findAll()));
    }

    public List<DistributionCenter> all() {
        List<DistributionCenter> current = snapshot.get();
        if (current.isEmpty()) {
            refresh();
            current = snapshot.get();
        }
        return current;
    }
}
