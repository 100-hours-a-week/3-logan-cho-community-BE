package com.example.jpatest.entity;

import jakarta.persistence.Entity;


import jakarta.persistence.*;
import lombok.*;


@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
@Entity
public class User extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(length = 100)
    private String email;
    @Column(length = 100)
    private String password;
    @Column(length = 50)
    private String name;


}