package com.example.kaboocampostproject.global.config;

import com.example.kaboocampostproject.domain.auth.jwt.JwtAccessDeniedHandler;
import com.example.kaboocampostproject.domain.auth.jwt.JwtAuthenticationEntryPoint;
import com.example.kaboocampostproject.domain.auth.jwt.JwtFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.filter.CorsFilter;

@EnableWebSecurity
@Configuration
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationEntryPoint jwtAuthenticationEntryPoint;
    private final JwtAccessDeniedHandler jwtAccessDeniedHandler;

    @Bean // 빈에 등록하면 spring이 전역 필터에도 등록해버릴 수 있음 (필터 두번 동작됨)
    public FilterRegistrationBean<JwtFilter> jwtFilterRegistration(JwtFilter jwtFilter) {
        FilterRegistrationBean<JwtFilter> filterFilterRegistrationBean = new FilterRegistrationBean<>(jwtFilter);
        filterFilterRegistrationBean.setEnabled(false);// 서블릿 컨테이너 자동등록 방지
        return filterFilterRegistrationBean;
    }


    // 허용할 URL을 배열의 형태로 관리
    private final String[] allowedUrls = {
            //회원가입
            "api/members",
            // 로그인 로그아웃
            "/api/auth" //로그인, 로그아웃, 토큰 재발급
    };

    @Bean
    @Order(0)
    SecurityFilterChain docsChain(HttpSecurity http) throws Exception {
        http
                .securityMatcher(
                        "/",
                        "/swagger-ui/**",
                        "/swagger-resources/**",
                        "/v3/api-docs/**"
                )
                .csrf(AbstractHttpConfigurer::disable)
                .authorizeHttpRequests(a -> a.anyRequest().permitAll());
        return http.build();
    }

    @Bean
    @Order(1)
    public SecurityFilterChain apiChain(HttpSecurity http, JwtFilter jwtFilter) throws Exception {

        http
                .securityMatcher("/api/**")
                .csrf(AbstractHttpConfigurer::disable)//커스텀 필터 따로 사용(기본은 세션기반)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(httpBasic -> httpBasic.disable())//헤더에 비번 담아서 보내는 basic인증방식 jwt에서는 비활성화
                .sessionManagement(session -> session//세션 비활성화(무상태)
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .cors(Customizer.withDefaults())//bean에서 corsConfigurationSource 찾아와서 알아서 등록
                .authorizeHttpRequests(a -> a
                        .requestMatchers(allowedUrls).permitAll()
                        .anyRequest().authenticated()
                )
                .exceptionHandling(ex -> ex
                        .accessDeniedHandler(jwtAccessDeniedHandler)
                        .authenticationEntryPoint(jwtAuthenticationEntryPoint)
                )
                .addFilterAfter(jwtFilter, CorsFilter.class);

        return http.build();
    }

    @Bean
    @Order(99)
    SecurityFilterChain fallbackChain(HttpSecurity http) throws Exception {
        http
                .securityMatcher("/**")
                .csrf(AbstractHttpConfigurer::disable)
                .authorizeHttpRequests(a -> a.anyRequest().denyAll());
        return http.build();
    }

    @Bean
    public BCryptPasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
