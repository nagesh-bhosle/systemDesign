package com.example.esdemo.repository;

import com.example.esdemo.entity.LocationArea;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface LocationAreaRepository extends JpaRepository<LocationArea, Long> {
    Optional<LocationArea> findByName(String name);
}
