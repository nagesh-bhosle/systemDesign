package com.example.gopuff.repository;

import com.example.gopuff.entity.Inventory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import jakarta.persistence.LockModeType;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface InventoryRepository extends JpaRepository<Inventory, Long> {

    @Query("""
            SELECT i FROM Inventory i
            JOIN FETCH i.item
            JOIN FETCH i.distributionCenter
            WHERE i.distributionCenter.id IN :dcIds
            """)
    List<Inventory> findByDcIds(@Param("dcIds") Collection<Long> dcIds);

    @Query("""
            SELECT i FROM Inventory i
            JOIN FETCH i.item
            JOIN FETCH i.distributionCenter
            WHERE i.item.id = :itemId AND i.distributionCenter.id IN :dcIds
            """)
    List<Inventory> findByItemAndDcIds(@Param("itemId") Long itemId, @Param("dcIds") Collection<Long> dcIds);

    Optional<Inventory> findByItemIdAndDistributionCenterId(Long itemId, Long dcId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT i FROM Inventory i WHERE i.id = :id")
    Optional<Inventory> lockById(@Param("id") Long id);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE Inventory i SET i.quantity = i.quantity - :qty WHERE i.id = :id AND i.quantity >= :qty")
    int decrementIfAvailable(@Param("id") Long id, @Param("qty") int qty);
}
