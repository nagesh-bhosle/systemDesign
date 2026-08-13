package com.example.booking.dto;

public class BookOutcome {
    private boolean success;
    private String message;

    public BookOutcome() {
    }

    public BookOutcome(boolean success, String message) {
        this.success = success;
        this.message = message;
    }

    public static BookOutcome ok(String message) {
        return new BookOutcome(true, message);
    }

    public static BookOutcome fail(String message) {
        return new BookOutcome(false, message);
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
}
