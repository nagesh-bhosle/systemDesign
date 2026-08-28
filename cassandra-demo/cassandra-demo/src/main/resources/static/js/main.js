// Cassandra Demo - page behaviors wired to the real REST endpoints.

function el(id) {
    return document.getElementById(id);
}

function show(el, text) {
    if (!el) return;
    el.hidden = false;
    el.textContent = typeof text === "string" ? text : JSON.stringify(text, null, 2);
}

async function getJson(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(res.status + " " + res.statusText);
    return res.json();
}

async function getText(url) {
    const res = await fetch(url);
    return res.text();
}

// Cluster status: GET /api/cluster/status -> plain text
async function loadClusterStatus(nameEl, nodesEl) {
    try {
        const text = await getText("/api/cluster/status");
        const name = /cluster:\s*Optional\[(.+?)\],/i.exec(text) || /cluster:\s*(.+?),/i.exec(text);
        const nodes = /nodes:\s*(\d+)/i.exec(text);
        if (nameEl && name) nameEl.textContent = name[1];
        if (nodesEl && nodes) nodesEl.textContent = nodes[1];
    } catch (e) {
        if (nameEl) nameEl.textContent = "unavailable";
        if (nodesEl) nodesEl.textContent = "?";
    }
}

// Rows list: GET /write-support/all -> SensorReading[]
function renderReadings(container, rows) {
    if (!container) return;
    container.textContent = "";
    if (!Array.isArray(rows) || rows.length === 0) {
        container.innerHTML = '<span class="muted">No readings yet - add one below.</span>';
        return;
    }
    for (const r of rows) {
        const div = document.createElement("div");
        div.className = "row-item";
        div.innerHTML =
            '<span class="k">' + (r.sensorId || r.id || "?") + "</span>" +
            '<span class="v">temp ' + r.temperature + "°C · hum " + r.humidity + "%</span>";
        container.appendChild(div);
    }
}

async function loadReadings(elId) {
    try {
        renderReadings(el(elId), await getJson("/write-support/all"));
    } catch (e) {
        const c = el(elId);
        if (c) c.innerHTML = '<span class="muted">Could not load readings: ' + e.message + "</span>";
    }
}

// ---------- Page bootstrapping ----------

document.addEventListener("DOMContentLoaded", function () {
    // Home
    loadClusterStatus(el("cluster-name"), el("node-count"));

    // Partitioning page
    if (el("pk-go")) {
        el("pk-go").addEventListener("click", async () => {
            const key = el("pk-input").value.trim() || "sensor-42";
            try {
                show(el("pk-out"), await getText("/partition/key?key=" + encodeURIComponent(key)));
            } catch (e) { show(el("pk-out"), "Error: " + e.message); }
        });
        loadReadings("pk-rows");
    }

    // Clustering page
    if (el("cl-rows")) loadReadings("cl-rows");

    // Topology page
    if (el("ct-refresh")) {
        const refresh = async () => {
            try { show(el("ct-status"), await getText("/demo/node-scaling/status")); }
            catch (e) { show(el("ct-status"), "Error: " + e.message); }
            loadClusterStatus(el("ct-name"), el("ct-nodes"));
        };
        el("ct-refresh").addEventListener("click", refresh);
        el("ct-add").addEventListener("click", async () => {
            const ip = el("ct-ip").value.trim() || "10.0.0.7";
            await getText("/demo/node-scaling/add-node?nodeIp=" + encodeURIComponent(ip));
            refresh();
        });
        el("ct-remove").addEventListener("click", async () => {
            const ip = el("ct-ip").value.trim() || "10.0.0.7";
            await getText("/demo/node-scaling/remove-node?nodeIp=" + encodeURIComponent(ip));
            refresh();
        });
        refresh();
    }

    // Consistency page
    if (el("ec-run")) {
        el("ec-run").addEventListener("click", async () => {
            try { show(el("ec-out"), await getText("/eventual-consistency")); }
            catch (e) { show(el("ec-out"), "Error: " + e.message); }
        });
    }

    // Versioned writes page
    if (el("ws-save")) {
        el("ws-save").addEventListener("click", async () => {
            const body = {
                id: el("ws-id").value.trim() || "reading-" + Date.now(),
                sensorId: el("ws-sensor").value.trim() || "sensor-42",
                temperature: parseFloat(el("ws-temp").value) || 20.0,
                humidity: parseFloat(el("ws-hum").value) || 50.0,
                timestamp: new Date().toISOString()
            };
            try {
                const res = await fetch("/write-support/add", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(body)
                });
                if (!res.ok) throw new Error(res.status + " " + res.statusText);
                show(el("ws-out"), "Saved:\n" + JSON.stringify(await res.json(), null, 2));
                loadReadings("ws-rows");
            } catch (e) { show(el("ws-out"), "Error: " + e.message); }
        });
        loadReadings("ws-rows");
    }

    // Snowflake page
    if (el("sf-go")) {
        el("sf-go").addEventListener("click", async () => {
            const n = Math.min(Math.max(parseInt(el("sf-count").value, 10) || 5, 1), 50);
            try {
                const list = await getJson("/snowflake/generateBatch?count=" + n);
                show(el("sf-out"), list.map(x => x.id).join("\n"));
                const box = el("sf-list");
                box.textContent = "";
                for (const item of list) {
                    const div = document.createElement("div");
                    div.className = "row-item";
                    div.innerHTML =
                        '<span class="k">' + item.id + "</span>" +
                        '<span class="v">worker ' + item.workerId + " · seq " + item.sequence + "</span>";
                    box.appendChild(div);
                }
            } catch (e) { show(el("sf-out"), "Error: " + e.message); }
        });
    }

    // SQL vs CQL page
    if (el("cq-go")) {
        el("cq-go").addEventListener("click", async () => {
            try { show(el("cq-out"), await getText("/sql-vs-cql")); }
            catch (e) { show(el("cq-out"), "Error: " + e.message); }
        });
    }
});