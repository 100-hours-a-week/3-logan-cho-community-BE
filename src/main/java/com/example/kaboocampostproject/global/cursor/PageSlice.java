package com.example.kaboocampostproject.global.cursor;

import jakarta.annotation.Nullable;

import java.util.List;

public record PageSlice<T>(
        @Nullable String parentId,
        List<T> items,
        String nextCursor,
        boolean hasNext
) {
}
