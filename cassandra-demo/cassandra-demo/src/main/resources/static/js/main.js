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
    if (!res.ok) throw new Error(res.status + " " + res.statusText);
    return res.text();
}

async function postText(url) {
    const res = await fetch(url, { method: "POST" });
    if (!res.ok) throw new Error(res.status + " " + res.statusText);
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
        const empty = document.createElement("span");
        empty.className = "muted";
        empty.textContent = "No readings yet - add one below.";
        container.appendChild(empty);
        return;
    }
    for (const r of rows) {
        const div = document.createElement("div");
        div.className = "row-item";
        const k = document.createElement("span");
        k.className = "k";
        k.textContent = r.sensorId || r.id || "?";
        const v = document.createElement("span");
        v.className = "v";
        v.textContent = "temp " + r.temperature + "°C · hum " + r.humidity + "%";
        div.appendChild(k);
        div.appendChild(v);
        container.appendChild(div);
    }
}

async function loadReadings(elId) {
    try {
        renderReadings(el(elId), await getJson("/write-support/all"));
    } catch (e) {
        const c = el(elId);
        if (c) {
            c.textContent = "";
            const msg = document.createElement("span");
            msg.className = "muted";
            msg.textContent = "Could not load readings: " + e.message;
            c.appendChild(msg);
        }
    }
}

// One sensor partition, in physical clustering order (newest first)
async function loadReadingsForSensor(elId, sensorId) {
    try {
        renderReadings(el(elId), await getJson("/demo/clustering-order/sensor/" + encodeURIComponent(sensorId)));
    } catch (e) {
        const c = el(elId);
        if (c) {
            c.textContent = "";
            const msg = document.createElement("span");
            msg.className = "muted";
            msg.textContent = "Could not load sensor readings: " + e.message;
            c.appendChild(msg);
        }
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

    // Clustering page: show one sensor partition in physical clustering order
    if (el("cl-rows")) {
        const sensor = (el("cl-sensor") && el("cl-sensor").value.trim()) || "sensor-1";
        loadReadingsForSensor("cl-rows", sensor);
        const go = el("cl-go");
        if (go) {
            go.addEventListener("click", () => {
                const s = (el("cl-sensor").value.trim()) || "sensor-1";
                loadReadingsForSensor("cl-rows", s);
            });
        }
    }

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
            try {
                show(el("ct-status"), await postText("/demo/node-scaling/add-node?nodeIp=" + encodeURIComponent(ip)));
            } catch (e) { show(el("ct-status"), "Error: " + e.message); }
            loadClusterStatus(el("ct-name"), el("ct-nodes"));
        });
        el("ct-remove").addEventListener("click", async () => {
            const ip = el("ct-ip").value.trim() || "10.0.0.7";
            try {
                show(el("ct-status"), await postText("/demo/node-scaling/remove-node?nodeIp=" + encodeURIComponent(ip)));
            } catch (e) { show(el("ct-status"), "Error: " + e.message); }
            loadClusterStatus(el("ct-name"), el("ct-nodes"));
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
            const timestamp = new Date().toISOString();
            const body = {
                key: {
                    sensorId: el("ws-sensor").value.trim() || "sensor-42",
                    id: el("ws-id").value.trim() || "reading-" + Date.now(),
                    timestamp: timestamp
                },
                temperature: parseFloat(el("ws-temp").value) || 20.0,
                humidity: parseFloat(el("ws-hum").value) || 50.0
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
            const n = Math.min(Math.max(parseInt(el("sf-count").value, 10) || 5, 1), 1000);
            try {
                const list = await getJson("/snowflake/generateBatch?count=" + n);
                show(el("sf-out"), list.map(x => x.id).join("\n"));
                const box = el("sf-list");
                box.textContent = "";
                for (const item of list) {
                    const div = document.createElement("div");
                    div.className = "row-item";
                    const k = document.createElement("span");
                    k.className = "k";
                    k.textContent = item.id;
                    const v = document.createElement("span");
                    v.className = "v";
                    v.textContent = "worker " + item.workerId + " · seq " + item.sequence;
                    div.appendChild(k);
                    div.appendChild(v);
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