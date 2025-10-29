package com.example.kaboocampostproject.domain.auth.email;

import com.example.kaboocampostproject.global.metadata.MailVerifyMetadata;
import lombok.RequiredArgsConstructor;
import lombok.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;
import org.springframework.stereotype.Service;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import jakarta.mail.internet.MimeMessage;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.Year;

@Component
@RequiredArgsConstructor
public class EmailSender {
    private final JavaMailSender javaMailSender;
    private final TemplateEngine templateEngine;


    public void sendVerificationEmail(String to, String verificationCode, int ttlMinutes) {
        try {
            // 이메일 컨텍스트에 변수 주입
            Context context = new Context();
            context.setVariable("verificationCode", verificationCode);
            context.setVariable("ttlMinutes", ttlMinutes);
            context.setVariable("year", Year.now().getValue());

            // HTML 템플릿 렌더링
            String htmlContent = templateEngine.process("mail/verify-email-form", context);

            // 메일 생성
            MimeMessage mimeMessage = javaMailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(
                    mimeMessage,
                    MimeMessageHelper.MULTIPART_MODE_MIXED_RELATED,
                    StandardCharsets.UTF_8.name()
            );

            helper.setTo(to);
            helper.setSubject("[Millions] 이메일 인증 코드 안내");
            helper.setText(htmlContent, true); // true = HTML 본문으로 전송

            // 발송
            javaMailSender.send(mimeMessage);

        } catch (Exception e) {
            throw new IllegalStateException("이메일 전송 중 오류 발생: " + e.getMessage(), e);
        }
    }
}
