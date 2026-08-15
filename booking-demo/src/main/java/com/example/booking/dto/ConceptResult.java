package com.example.booking.dto;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class ConceptResult {

    private String concept;
    private String title;
    private String problem;
    private String howThisEndpointWorks;
    private String expectedInvariant;
    private String actualOutcome;
    private boolean invariantHeld;
    private List<UserAttempt> users = new ArrayList<>();
    private List<TimelineEvent> timeline = new ArrayList<>();
    private Map<String, Object> finalState = new LinkedHashMap<>();
    private String watchInDebugger;
    private String relatedManualApis;

    public String getConcept() {
        return concept;
    }

    public void setConcept(String concept) {
        this.concept = concept;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getProblem() {
        return problem;
    }

    public void setProblem(String problem) {
        this.problem = problem;
    }

    public String getHowThisEndpointWorks() {
        return howThisEndpointWorks;
    }

    public void setHowThisEndpointWorks(String howThisEndpointWorks) {
        this.howThisEndpointWorks = howThisEndpointWorks;
    }

    public String getExpectedInvariant() {
        return expectedInvariant;
    }

    public void setExpectedInvariant(String expectedInvariant) {
        this.expectedInvariant = expectedInvariant;
    }

    public String getActualOutcome() {
        return actualOutcome;
    }

    public void setActualOutcome(String actualOutcome) {
        this.actualOutcome = actualOutcome;
    }

    public boolean isInvariantHeld() {
        return invariantHeld;
    }

    public void setInvariantHeld(boolean invariantHeld) {
        this.invariantHeld = invariantHeld;
    }

    public List<UserAttempt> getUsers() {
        return users;
    }

    public void setUsers(List<UserAttempt> users) {
        this.users = users;
    }

    public List<TimelineEvent> getTimeline() {
        return timeline;
    }

    public void setTimeline(List<TimelineEvent> timeline) {
        this.timeline = timeline;
    }

    public Map<String, Object> getFinalState() {
        return finalState;
    }

    public void setFinalState(Map<String, Object> finalState) {
        this.finalState = finalState;
    }

    public String getWatchInDebugger() {
        return watchInDebugger;
    }

    public void setWatchInDebugger(String watchInDebugger) {
        this.watchInDebugger = watchInDebugger;
    }

    public String getRelatedManualApis() {
        return relatedManualApis;
    }

    public void setRelatedManualApis(String relatedManualApis) {
        this.relatedManualApis = relatedManualApis;
    }

    public static class UserAttempt {
        private long userId;
        private boolean success;
        private String message;
        private long elapsedMs;

        public UserAttempt() {
        }

        public UserAttempt(long userId, boolean success, String message, long elapsedMs) {
            this.userId = userId;
            this.success = success;
            this.message = message;
            this.elapsedMs = elapsedMs;
        }

        public long getUserId() {
            return userId;
        }

        public void setUserId(long userId) {
            this.userId = userId;
        }

        public boolean isSuccess() {
            return success;
        }

        public void setSuccess(boolean success) {
            this.success = success;
        }

        public String getMessage() {
            return message;
        }

        public void setMessage(String message) {
            this.message = message;
        }

        public long getElapsedMs() {
            return elapsedMs;
        }

        public void setElapsedMs(long elapsedMs) {
            this.elapsedMs = elapsedMs;
        }
    }

    public static class TimelineEvent {
        private long userId;
        private long atMs;
        private String step;

        public TimelineEvent() {
        }

        public TimelineEvent(long userId, long atMs, String step) {
            this.userId = userId;
            this.atMs = atMs;
            this.step = step;
        }

        public long getUserId() {
            return userId;
        }

        public void setUserId(long userId) {
            this.userId = userId;
        }

        public long getAtMs() {
            return atMs;
        }

        public void setAtMs(long atMs) {
            this.atMs = atMs;
        }

        public String getStep() {
            return step;
        }

        public void setStep(String step) {
            this.step = step;
        }
    }
}
