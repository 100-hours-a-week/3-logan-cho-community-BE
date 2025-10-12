package com.example.kaboocampostproject.global.cursor;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Base64;

@Component
@RequiredArgsConstructor
public class CursorCodec {

    private static final Base64.Encoder ENC = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder DEC = Base64.getUrlDecoder();
    private final ObjectMapper om;

    public String encode(Cursor c) {
        try {
            byte[] json = om.writeValueAsBytes(c);
            return ENC.encodeToString(json);
        } catch (Exception e) {
            throw new IllegalStateException("인코딩 실패", e);
        }
    }

    public Cursor decode(String token) {
        try {
            byte[] json = DEC.decode(token);
            return om.readValue(json, Cursor.class);
        } catch (Exception e) {
            throw new IllegalArgumentException("디코딩 실패", e);
        }
    }
}
