package com.example.kaboocampostproject.global.cursor;

import java.time.Instant;

public record Cursor(
        CursorStrategy strategy,
        Pos pos
) {
    public enum CursorStrategy {
        RECENT,
        POPULAR
    }

    public interface Pos{
        String id();
    }
    public record CreatedAtPos(String id, Instant createdAt) implements Pos{}
    public record ViewPos(String id, Instant createdAt, Long view) implements Pos{}

}