package com.example.gopuff.service.order;

import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.entity.CustomerOrder;

public interface OrderService {
    CustomerOrder place(PlaceOrderRequest request);
}
