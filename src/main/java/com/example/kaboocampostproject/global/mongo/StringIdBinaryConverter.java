package com.example.kaboocampostproject.global.mongo;

import org.bson.types.ObjectId;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

@Converter(autoApply = false)  // ← 명시적으로 지정한 필드에만 적용
public class StringIdBinaryConverter implements AttributeConverter<String, byte[]> {
    
    @Override
    public byte[] convertToDatabaseColumn(String attribute) {
        if (attribute == null) {
            return null;
        }
        return new ObjectId(attribute).toByteArray();
    }
    
    @Override
    public String convertToEntityAttribute(byte[] dbData) {
        if (dbData == null) {
            return null;
        }
        return new ObjectId(dbData).toHexString();
    }
}