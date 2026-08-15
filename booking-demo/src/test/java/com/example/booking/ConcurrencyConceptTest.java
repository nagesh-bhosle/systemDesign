package com.example.booking;

import com.example.booking.dto.ConceptResult;
import com.example.booking.service.ConceptDemoService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
class ConcurrencyConceptTest {

    @Autowired
    ConceptDemoService demos;

    @Test
    void pessimisticLockAllowsOnlyOneWinner() {
        ConceptResult result = demos.pessimisticLock(10, 20);
        assertThat(result.isInvariantHeld()).isTrue();
        assertThat(result.getFinalState().get("successCount")).isEqualTo(1L);
    }

    @Test
    void optimisticLockAllowsOnlyOneWinner() {
        ConceptResult result = demos.optimisticLock(8, 30);
        assertThat(result.isInvariantHeld()).isTrue();
    }

    @Test
    void atomicUpdateDoesNotOversellLastTicket() {
        ConceptResult result = demos.atomicUpdate(10, 1);
        assertThat(result.isInvariantHeld()).isTrue();
    }

    @Test
    void atomicCounterHasNoLostUpdates() {
        ConceptResult result = demos.atomicCounter(4, 25);
        assertThat(result.isInvariantHeld()).isTrue();
        assertThat(result.getFinalState().get("value")).isEqualTo(100);
    }

    @Test
    void uniqueConstraintKeepsOneRow() {
        ConceptResult result = demos.uniqueConstraint(8, 20);
        assertThat(result.isInvariantHeld()).isTrue();
        assertThat(result.getFinalState().get("rowCount")).isEqualTo(1);
    }

    @Test
    void holdAllowsOnlyOneHolder() {
        ConceptResult result = demos.holdAndConfirm(6, 15, 30);
        assertThat(result.isInvariantHeld()).isTrue();
    }
}
