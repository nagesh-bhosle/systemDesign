package com.example.lab.coordination;

import com.example.lab.domain.Message;
import com.example.lab.domain.MessageType;

import java.util.List;
import java.util.UUID;

/**
 * A claim strategy for one message class. Two correct implementations exist
 * (Redis lock for INTRADAY, DB atomic claim for EOD) plus one deliberately
 * broken baseline (Naive) used to demonstrate why coordination is needed.
 */
public interface Coordinator {

    /**
     * Attempt to claim up to batchSize NEW messages for the given instance.
     * Must be atomic: two concurrent calls from different instances must
     * never return the same message.
     * @return the messages this instance now owns (possibly empty)
     */
    List<Message> claimBatch(String instanceName, int batchSize);

    /**
     * Idempotent completion. Must no-op if the caller no longer owns the
     * claim (token mismatch / lease lost).
     * @return true if this call performed the transition, false if ignored
     */
    boolean complete(Message message, String instanceName, UUID claimToken);

    /** Message type this coordinator handles. */
    MessageType handles();
}
