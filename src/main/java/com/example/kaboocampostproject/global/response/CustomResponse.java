package com.example.kaboocampostproject.global.response;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import org.springframework.http.HttpStatus;

@AllArgsConstructor(access = AccessLevel.PRIVATE)
@JsonPropertyOrder({"isSuccess", "code", "message", "data"})
@Builder
public class CustomResponse<T> {
    @JsonProperty("isSuccess")
    private boolean success;
    @JsonProperty("code")
    private String code;
    @JsonProperty("message")
    private String message;
    @JsonInclude(JsonInclude.Include.NON_NULL) //필드 값이 null 이면 JSON 응답에서 제외됨.
    @JsonProperty("data")
    private T data;


    public static CustomResponse<Void> onSuccess(HttpStatus status) {
        return CustomResponse.<Void>builder()
                .success(true)
                .code(String.valueOf(status.value()))
                .message(status.getReasonPhrase())
                .build();
    }
    public static <T> CustomResponse<T> onSuccess(HttpStatus status, T data) {
        return new CustomResponse<>(
                true,
                String.valueOf(status.value()),
                status.getReasonPhrase(),
                data
        );
    }

    public static CustomResponse<Void> onFailure(String code, String message) {
        return CustomResponse.<Void>builder()
                .success(false)
                .code(code)
                .message(message)
                .build();
    }

}
