package com.example.kaboocampostproject.global.validator;

import com.example.kaboocampostproject.global.validator.annotation.ValidName;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

public class NameValidator implements ConstraintValidator<ValidName, String> {

    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        if (value == null) return false;
        return value.length() >= 2 && value.length() <= 12;
    }
}
