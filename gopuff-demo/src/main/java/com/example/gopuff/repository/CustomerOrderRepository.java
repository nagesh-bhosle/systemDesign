package com.example.gopuff.repository;

import com.example.gopuff.entity.CustomerOrder;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface CustomerOrderRepository extends JpaRepository<CustomerOrder, Long> {

    @Query("""
            SELECT o FROM CustomerOrder o
            LEFT JOIN FETCH o.lines l
            LEFT JOIN FETCH l.item
            LEFT JOIN FETCH l.distributionCenter
            WHERE o.id = :id
            """)
    Optional<CustomerOrder> findDetailedById(@Param("id") Long id);
}
