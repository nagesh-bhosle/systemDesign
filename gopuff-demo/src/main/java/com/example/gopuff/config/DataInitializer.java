package com.example.gopuff.config;

import com.example.gopuff.entity.DistributionCenter;
import com.example.gopuff.entity.Inventory;
import com.example.gopuff.entity.Item;
import com.example.gopuff.repository.DistributionCenterRepository;
import com.example.gopuff.repository.InventoryRepository;
import com.example.gopuff.repository.ItemRepository;
import com.example.gopuff.service.catalog.DcCatalog;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class DataInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DataInitializer.class);

    private final ItemRepository itemRepository;
    private final DistributionCenterRepository dcRepository;
    private final InventoryRepository inventoryRepository;
    private final DcCatalog dcCatalog;

    public DataInitializer(ItemRepository itemRepository,
                           DistributionCenterRepository dcRepository,
                           InventoryRepository inventoryRepository,
                           DcCatalog dcCatalog) {
        this.itemRepository = itemRepository;
        this.dcRepository = dcRepository;
        this.inventoryRepository = inventoryRepository;
        this.dcCatalog = dcCatalog;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (itemRepository.count() > 0) {
            dcCatalog.refresh();
            log.info("Seed data already present ({} items)", itemRepository.count());
            return;
        }

        Item cheetos = item("CHEETOS", "Cheetos", "Flamin' Hot bag");
        Item water = item("WATER", "Sparkling water", "12oz can");
        Item milk = item("MILK", "Whole milk", "Half gallon");
        Item lastUnit = item("LAST-UNIT", "Last-unit energy drink", "Only one physical can in the network");

        DistributionCenter centerCity = dc("Center City", 39.9526, -75.1652, "19103", 1.0);
        DistributionCenter fishtown = dc("Fishtown", 39.9712, -75.1347, "19125", 1.0);
        DistributionCenter university = dc("University City", 39.9522, -75.1932, "19104", 1.1);
        DistributionCenter camden = dc("Camden (across the river)", 39.9259, -75.1196, "08102", 3.2);
        DistributionCenter kop = dc("King of Prussia", 40.0890, -75.3960, "19406", 1.0);

        stock(cheetos, centerCity, 40);
        stock(cheetos, fishtown, 12);
        stock(water, centerCity, 80);
        stock(water, university, 25);
        stock(milk, fishtown, 8);
        stock(milk, university, 6);
        stock(lastUnit, centerCity, 1);
        stock(cheetos, camden, 50);
        stock(water, kop, 200);

        dcCatalog.refresh();
        log.info("Seeded {} DCs and {} SKUs (LAST-UNIT qty=1 at Center City)", dcRepository.count(), itemRepository.count());
    }

    private Item item(String sku, String name, String description) {
        Item item = new Item();
        item.setSku(sku);
        item.setName(name);
        item.setDescription(description);
        return itemRepository.save(item);
    }

    private DistributionCenter dc(String name, double lat, double lon, String zip, double traffic) {
        DistributionCenter dc = new DistributionCenter();
        dc.setName(name);
        dc.setLatitude(lat);
        dc.setLongitude(lon);
        dc.setZipCode(zip);
        dc.setRegionId(zip.substring(0, 3));
        dc.setTrafficFactor(traffic);
        return dcRepository.save(dc);
    }

    private void stock(Item item, DistributionCenter dc, int qty) {
        Inventory inventory = new Inventory();
        inventory.setItem(item);
        inventory.setDistributionCenter(dc);
        inventory.setQuantity(qty);
        inventoryRepository.save(inventory);
    }
}
