package com.example.kaboocampostproject.global.error;

import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.validation.ConstraintViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.HashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    // 컨트롤러 메서드에서 @Valid 어노테이션을 사용하여 DTO의 유효성 검사를 수행
    @ExceptionHandler(MethodArgumentNotValidException.class)
    protected ResponseEntity<CustomResponse<Map<String, String>>> handleMethodArgumentNotValidException(
            MethodArgumentNotValidException ex) {
        // 검사에 실패한 필드와 그에 대한 메시지를 저장하는 Map
        Map<String, String> errors = new HashMap<>();//이렇게 두면 에러 여러개가 들어왔을때 마지막 것만 찍히므로 MultiValueMap로 리팩토링 필요
        ex.getBindingResult().getFieldErrors().forEach(error ->
                errors.put(error.getField(), error.getDefaultMessage())
        );
        BaseErrorCode validationErrorCode = GeneralErrorCode.VALIDATION_FAILED; // BaseErrorCode로 통일
        CustomResponse<Map<String, String>> errorResponse = CustomResponse.onFailure(
                validationErrorCode.getCode(),
                validationErrorCode.getMessage(),
                errors
        );
        // 에러 코드, 메시지와 함께 errors를 반환
        return ResponseEntity.status(validationErrorCode.getHttpStatus()).body(errorResponse);
    }

    //@RequestParam, @PathVariable, @ModelAttribute 같은 메서드 파라미터 자체에 붙은 제약조건 어노테이션 위반 시
    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<?> handleConstraintViolationException(ConstraintViolationException e) {
        return ResponseEntity
                .status(GeneralErrorCode.VALIDATION_FAILED.getHttpStatus())
                .body(GeneralErrorCode.VALIDATION_FAILED.getCode());
    }

    @ExceptionHandler(CustomException.class)
    public ResponseEntity<CustomResponse<Void>> customExceptionHandler(CustomException customException){

        BaseErrorCode errorCode = customException.getErrorCode();

        return ResponseEntity.status(errorCode.getHttpStatus())
                .body(CustomResponse.onFailure(errorCode.getCode(), errorCode.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<CustomResponse<Void>> customExceptionHandler(Exception exception){
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(CustomResponse.onFailure("500", "서버 내부 오류가 발생했습니다."));
    }
}
