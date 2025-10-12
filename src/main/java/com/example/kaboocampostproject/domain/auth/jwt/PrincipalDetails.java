package com.example.kaboocampostproject.domain.auth.jwt;

import com.example.kaboocampostproject.domain.auth.jwt.dto.AccessClaims;
import lombok.Getter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;


import java.util.Collection;
import java.util.List;

@Getter
public class PrincipalDetails implements UserDetails {

    private final AccessClaims accessClaims;

    // 일반 로그인용 생성자
    public PrincipalDetails(AccessClaims accessClaims) {
        this.accessClaims = accessClaims;
    }

    @Override
    // 권한을 가져오는 메소드
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority(accessClaims.userRole().name()));//권한 가져옴
    }




    // 아래부터는 우리 서비스에서 사용하지 않으나, UserDetails 때문에 무조건 구현하긴 해야함.

    @Override
    public String getUsername() {
        return null;
    }

    @Override
    // 비밀번호를 가져오는 메소드
    public String getPassword() {
        return null;    }

    @Override
    // 사용 가능한지 여부
    public boolean isEnabled() {
        return true;
    }

    @Override
    // 계정이 만료되지 않았는지 여부
    public boolean isAccountNonExpired() {
        return true;
    }

    @Override
    // 계정이 잠겼는지에 대한 여부
    public boolean isAccountNonLocked() {
        return true;
    }

    @Override
    // 비밀번호가 만료되었는지 여부
    public boolean isCredentialsNonExpired() {
        return true;
    }
}