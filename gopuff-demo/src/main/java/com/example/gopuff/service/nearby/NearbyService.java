package com.example.gopuff.service.nearby;

import java.util.List;

public interface NearbyService {
    List<NearbyDc> findNearby(double lat, double lon);
}
