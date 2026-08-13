package com.example.gopuff.repository;

import com.example.gopuff.entity.DistributionCenter;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface DistributionCenterRepository extends JpaRepository<DistributionCenter, Long> {
    Optional<DistributionCenter> findByName(String name);
}
