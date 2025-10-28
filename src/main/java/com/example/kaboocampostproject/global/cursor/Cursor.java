package com.example.kaboocampostproject.global.cursor;

import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;

import java.time.Instant;

public record Cursor(
        CursorStrategy strategy,
        Pos pos
) {
    public enum CursorStrategy {
        RECENT,
        POPULAR
    }

    @JsonTypeInfo(
            use = JsonTypeInfo.Id.NAME,      // 이름으로 타입 식별하라
            include = JsonTypeInfo.As.PROPERTY,
            property = "type"                // JSON에 추가될 필드명
    )
    @JsonSubTypes({
            @JsonSubTypes.Type(value = CreatedAtPos.class, name = "createdAtPos"),
            @JsonSubTypes.Type(value = ViewPos.class, name = "viewPos")
    })
    public interface Pos{
        String id();
    }
    public record CreatedAtPos(String id, Instant createdAt) implements Pos{}
    public record ViewPos(String id, Instant createdAt, Long view) implements Pos{}

}