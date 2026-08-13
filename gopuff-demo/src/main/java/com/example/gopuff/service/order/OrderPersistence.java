package com.example.gopuff.service.order;

import com.example.gopuff.dto.PlaceOrderRequest;
import com.example.gopuff.entity.CustomerOrder;
import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.entity.Item;
import com.example.gopuff.entity.OrderLine;
import com.example.gopuff.repository.CustomerOrderRepository;
import com.example.gopuff.repository.DistributionCenterRepository;
import com.example.gopuff.repository.InventoryRepository;
import com.example.gopuff.repository.ItemRepository;
import com.example.gopuff.service.inventory.InventoryReadService;
import com.example.gopuff.service.inventory.InventorySnapshot;
import com.example.gopuff.service.inventory.DbInventoryLoader;
import com.example.gopuff.service.nearby.NearbyDc;
import com.example.gopuff.service.nearby.NearbyService;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

@Service
public class OrderPersistence {

    private final NearbyService nearbyService;
    private final InventoryRepository inventoryRepository;
    private final ItemRepository itemRepository;
    private final DistributionCenterRepository dcRepository;
    private final CustomerOrderRepository orderRepository;
    private final InventoryReadService inventoryReadService;
    private final DbInventoryLoader dbInventoryLoader;
    private final TransactionTemplate serializableTx;
    private final TransactionTemplate defaultTx;

    public OrderPersistence(NearbyService nearbyService,
                            InventoryRepository inventoryRepository,
                            ItemRepository itemRepository,
                            DistributionCenterRepository dcRepository,
                            CustomerOrderRepository orderRepository,
                            InventoryReadService inventoryReadService,
                            DbInventoryLoader dbInventoryLoader,
                            PlatformTransactionManager txManager) {
        this.nearbyService = nearbyService;
        this.inventoryRepository = inventoryRepository;
        this.itemRepository = itemRepository;
        this.dcRepository = dcRepository;
        this.orderRepository = orderRepository;
        this.inventoryReadService = inventoryReadService;
        this.dbInventoryLoader = dbInventoryLoader;
        this.serializableTx = new TransactionTemplate(txManager);
        this.serializableTx.setIsolationLevel(TransactionDefinition.ISOLATION_SERIALIZABLE);
        this.defaultTx = new TransactionTemplate(txManager);
        this.defaultTx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
    }

    public CustomerOrder placeSerializable(PlaceOrderRequest request, int retries) {
        RuntimeException last = null;
        for (int attempt = 1; attempt <= retries; attempt++) {
            try {
                return serializableTx.execute(status -> placeInTransaction(request, true));
            } catch (InsufficientInventoryException e) {
                throw e;
            } catch (TransactionSystemException | DataAccessException e) {
                last = new ConcurrentOrderException("Serialization conflict, retrying", e);
            }
        }
        throw last != null ? last : new ConcurrentOrderException("Could not place order");
    }

    public CustomerOrder placeReadCommitted(PlaceOrderRequest request) {
        return defaultTx.execute(status -> placeInTransaction(request, true));
    }

    private CustomerOrder placeInTransaction(PlaceOrderRequest request, boolean invalidate) {
        List<NearbyDc> nearby = nearbyService.findNearby(request.lat(), request.lon());
        if (nearby.isEmpty()) {
            throw new InsufficientInventoryException("No distribution center can deliver to this location in time");
        }
        List<Long> dcIds = nearby.stream().map(n -> n.dc().getId()).toList();
        List<InventorySnapshot> stock = dbInventoryLoader.loadForDcs(dcIds);
        List<StockAllocator.Allocation> plan = StockAllocator.allocate(nearby, request.lines(), stock);

        CustomerOrder order = new CustomerOrder();
        order.setUserId(request.userId());
        order.setLatitude(request.lat());
        order.setLongitude(request.lon());
        order.setStatus("CONFIRMED");
        order.setCreatedAt(Instant.now());

        Set<Long> touchedDcs = new HashSet<>();
        for (StockAllocator.Allocation allocation : plan) {
            int updated = inventoryRepository.decrementIfAvailable(allocation.inventoryId(), allocation.quantity());
            if (updated != 1) {
                throw new InsufficientInventoryException("Inventory changed while placing the order");
            }
            Item item = itemRepository.findById(allocation.itemId()).orElseThrow();
            DistributionCenter dc = dcRepository.findById(allocation.dcId()).orElseThrow();
            OrderLine line = new OrderLine();
            line.setOrder(order);
            line.setItem(item);
            line.setDistributionCenter(dc);
            line.setQuantity(allocation.quantity());
            order.getLines().add(line);
            touchedDcs.add(allocation.dcId());
        }

        CustomerOrder saved = orderRepository.save(order);
        orderRepository.flush();
        if (invalidate) {
            inventoryReadService.invalidateDcs(touchedDcs);
        }
        return orderRepository.findDetailedById(saved.getId()).orElse(saved);
    }
}
