package com.example.lab.events;

import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * In-memory pub/sub: every claim / complete / requeue / reject / receive is
 * pushed to all connected browsers. Emitters that complete, error out or time
 * out are removed so dead connections never accumulate.
 */
@Component
public class EventBus {

    private final List<SseEmitter> emitters = new CopyOnWriteArrayList<>();

    public SseEmitter register() {
        SseEmitter emitter = new SseEmitter(0L); // no timeout; dashboard stays open
        emitters.add(emitter);
        emitter.onCompletion(() -> emitters.remove(emitter));
        emitter.onError(e -> emitters.remove(emitter));
        emitter.onTimeout(() -> emitters.remove(emitter));
        return emitter;
    }

    public void publish(ProcessingEvent event) {
        for (SseEmitter emitter : emitters) {
            try {
                emitter.send(SseEmitter.event()
                        .name(event.kind())
                        .data(event, MediaType.APPLICATION_JSON));
            } catch (Exception ex) {
                // browser closed / connection broken — drop it silently
                emitters.remove(emitter);
            }
        }
    }

    public int connectedClients() {
        return emitters.size();
    }
}
