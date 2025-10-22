package com.example.kaboocampostproject.global.cursor;

import jakarta.annotation.Nullable;

import java.util.List;

public record PageSlice<T>(
        List<T> items,
        String nextCursor,
        boolean hasNext
) {
    public static <T> PageSlice<T> empty() {
        return new PageSlice<>(List.of(), null, false);
    }
}
