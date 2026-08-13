package com.example.gopuff.web;

import com.example.gopuff.config.GopuffProperties;
import com.example.gopuff.dto.AvailabilityResponse;
import com.example.gopuff.dto.OrderDto;
import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.dto.RuntimeConfigDto;
import com.example.gopuff.entity.CustomerOrder;
import com.example.gopuff.entity.Item;
import com.example.gopuff.repository.CustomerOrderRepository;
import com.example.gopuff.repository.ItemRepository;
import com.example.gopuff.service.AvailabilityService;
import com.example.gopuff.service.order.OrderService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class GopuffController {

    private final AvailabilityService availabilityService;
    private final OrderService orderService;
    private final ItemRepository itemRepository;
    private final CustomerOrderRepository orderRepository;
    private final GopuffProperties properties;

    public GopuffController(AvailabilityService availabilityService,
                            OrderService orderService,
                            ItemRepository itemRepository,
                            CustomerOrderRepository orderRepository,
                            GopuffProperties properties) {
        this.availabilityService = availabilityService;
        this.orderService = orderService;
        this.itemRepository = itemRepository;
        this.orderRepository = orderRepository;
        this.properties = properties;
    }

    @GetMapping("/availability")
    public AvailabilityResponse availability(
            @RequestParam double lat,
            @RequestParam double lon,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return availabilityService.availability(lat, lon, page, Math.min(size, 100));
    }

    @GetMapping("/items")
    public List<Item> items() {
        return itemRepository.findAll();
    }

    @PostMapping("/orders")
    public ResponseEntity<OrderDto> place(@Valid @RequestBody PlaceOrderRequest request) {
        CustomerOrder order = orderService.place(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(toDto(order));
    }

    @GetMapping("/orders/{id}")
    public OrderDto getOrder(@PathVariable Long id) {
        return orderRepository.findDetailedById(id)
                .map(GopuffController::toDto)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }

    @GetMapping("/config")
    public RuntimeConfigDto config() {
        Map<String, Object> gopuff = new LinkedHashMap<>();
        gopuff.put("nearby.strategy", properties.getNearby().getStrategy());
        gopuff.put("nearby.prune-radius-miles", properties.getNearby().getPruneRadiusMiles());
        gopuff.put("nearby.max-drive-minutes", properties.getNearby().getMaxDriveMinutes());
        gopuff.put("travel-time.provider", properties.getTravelTime().getProvider());
        gopuff.put("inventory.read-path", properties.getInventory().getReadPath());
        gopuff.put("cache.ttl-seconds", properties.getCache().getTtlSeconds());
        gopuff.put("orders.consistency", properties.getOrders().getConsistency());
        return new RuntimeConfigDto(gopuff);
    }

    static OrderDto toDto(CustomerOrder order) {
        return new OrderDto(
                order.getId(),
                order.getUserId(),
                order.getStatus(),
                order.getCreatedAt(),
                order.getLatitude(),
                order.getLongitude(),
                order.getLines().stream()
                        .map(line -> new OrderDto.OrderLineDto(
                                line.getItem().getId(),
                                line.getItem().getName(),
                                line.getDistributionCenter().getId(),
                                line.getDistributionCenter().getName(),
                                line.getQuantity()))
                        .toList()
        );
    }
}
