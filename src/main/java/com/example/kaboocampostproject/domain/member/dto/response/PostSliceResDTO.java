package com.example.kaboocampostproject.domain.member.dto.response;

import java.util.List;

public record PostSliceResDTO(
    List<Item> items,
    String nextCursor,
    boolean hasNext
) {
    public record Item(String title, long view, long likes) {}
}
