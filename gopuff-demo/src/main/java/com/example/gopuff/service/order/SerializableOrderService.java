package com.example.gopuff.service.order;

import com.example.gopuff.config.GopuffProperties;
import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.entity.CustomerOrder;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(name = "gopuff.orders.consistency", havingValue = "postgres-serializable", matchIfMissing = true)
public class SerializableOrderService implements OrderService {

    private final OrderPersistence persistence;
    private final int retries;

    public SerializableOrderService(OrderPersistence persistence, GopuffProperties properties) {
        this.persistence = persistence;
        this.retries = properties.getOrders().getSerializationRetries();
    }

    @Override
    public CustomerOrder place(PlaceOrderRequest request) {
        return persistence.placeSerializable(request, retries);
    }
}
