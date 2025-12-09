# Millions

1,000,000 MAU를 가정하여 커뮤니티 서비스를 설계하였습니다.

## 개발 인원 및 기간
- **개발기간**: 2025-10-01 ~ 2025-12-08
- **개발 인원**: 프론트엔드/백엔드 1명 (본인)

## 기능
- SMTP로 회원가입·복구 이메일 검증 코드 발송
- 회원 복구 선택적으로 수행할 수 있도록 설계
- 게시글/댓글/좋아요/Member CRUD

## 기술 스택
- Java 17, Spring Boot 3.5, Gradle
- MySQL, MongoDB, Redis
- Spring Data JPA, Spring Data MongoDB, Spring Cache
- Spring Mail (Gmail), Springdoc OpenAPI
- AWS SDK v2, AWS SSM, S3, CloudFront

### 확장성 고려
- **member와 member인증정보를 수직 파티셔닝하여, db권한 관리 고려**: 로그인·인증 정보는 별도 스키마로 분리해 최소 권한 부여, 유출·권한 상승 위험을 축소.
- **cursor based pagination의 base64인코딩 및 응답통일**: 커서를 Base64 직렬화해 API 응답 포맷을 표준화하고, 다중 목록 API 재사용성을 확보. CursorCodec 클래스에서 Base64 직렬화/역직렬화 방식으로 커서 통합 관리.
- **jwt, redis, mail 전송 메타데이터 분리**: 발급 키·TTL·메일 템플릿 등 메타값을 설정 enum으로 분리하여 재사용성 증가.
- **응답,예외 통일**: CustomResponse + BaseErrorCode 체계로 성공/실패 페이로드를 일관되게 반환, 클라이언트 파싱 비용을 최소화.
- **SecurityFilterChain 요청 형태 별 분리**: 퍼블릭/인증/관리자 라우트별 체인을 분리해 보안 정책과 예외 응답을 명확히 구분.
- **인증 허용 endpoint yml관리**: 공개 API 목록을 yml로 관리해 배포 없이 화이트리스트 변경 가능, 환경별 정책 분리 용이.

### 성능 개선
- **게시물 조회수 병목 개선**:
  - 조회수 증가 요청 폭주에 대비해 전용 카운터 스레드 + ConcurrentHashMap 기반 캐시 구조로 병목 해소 
  - 일정 주기마다 누적된 카운터를 배치로 DB 반영 
  - MongoDB $inc 연산을 통한 원자적 업데이트로 동시성 문제 방지
- **프로필 정보 캐싱**: 
  - 
  - 캐싱사용자 조회 시, 사용자 n명당 redis 까지 n RTT 발생하던 문제를 배치 파이프라이닝을 활용하여 1RTT로 개선 
  - 캐싱되지 않은 사용자 리스트도 sql에서 배치조회를 통해 1RTT로 감소
- **복합키의 randomIO**: 
  - 게시물+사용자 복합키 방식의 좋아요 테이블을 randomIO를 줄이기 위해서 단일 키 + 보조인덱스 방식으로 변경
  - 보조인덱스의 randomIO를 줄이기 위해서 mongoDB의 ID를 binary로 치환하여 저장
  - https://github.com/100-hours-a-week/3-logan-cho-community-BE/issues/11
- **연관 관계 수정 시, 벌크 쿼리 작성**:
  - 기존 소프트 딜리트시 삭제 전이를 영속성 컨텍스트에서 수행하는 방식에서 벌크 쿼리로 변경


### 개선 계획
- **게시물, 댓글의 MongoDB -> mysql migration**
  - 구성 초기에는 게시물, 댓글에 데이터가 가장 많이 적재될 것이고, mysql에서 비교적 간단하게 설계할 수 있는 수평 파티셔닝을 사용해서 하나의 디비서버에 모든 데이터를 저장하게 되면, 서비스 기간이 점점 증가함에 따라서 이를 감당하기 힘들 것이라고 판단하여,
    데이터가 가장 많이 쌓일 가능성이 높은 게시물, 댓글을 비교적 샤딩 설정이 간단한, 샤딩 친화적인 MongoDB를 선택했었습니다. 
  - 하지만, 해당 판단은 잘못된 판단이었습니다. 실제로 해당 상황이 도래했을 때, 직접 트래픽과, 자주 조회되는 데이터의 성격에 맞추어서, 그 상황에서 적합한 방식(샤딩이던지 아니면 파티셔닝이던지, 아카이브던지) 를 선택해서 마이그레이션하는 것이 옳은 판단이었다고 생각합니다.
  - 이에 다시 mysql로 게시물을 리팩토링 할 게획입니다.
- **벌크 쿼리의 maximum capacity 설정 필요**:
  - n개의 쿼리에서 1개의 쿼리로 줄인 이점도 크지만, batch size를 사용할 수 없는 만큼, 연관 데이터가 너무 많은 케이스에 대한 고려도 필요하다.
  - 벌크 쓰기 작업 시, nextKeyLock이 사용되지 않도록 인덱싱 설계와, 여러개의 쿼리로 분할하는 리팩토링 수행예정
- **이미지 업로드 로직 리팩토링**
  - <img width="943" height="639" alt="image" src="https://github.com/user-attachments/assets/fa253f9f-28cd-459e-8693-d951e7a8eb29" />

### 비용 계산
  <details>
  <summary>이미지 다운로드</summary>
  - 이미지 압축 목표크기
    - 프로필 사진 : 15KB
    - 게시물 썸네일 : 30KB
    - 게시물 본문 : 800KB
  - mau 100만
  - dau 25만

  25만명이 평균적으로 프로필 3개, 썸네일 2개, 상세이미지 0.5개를 본다고 가정
  하루 이미지 다운로드 바이트 :  (15*3 + 30* 2 + 800*0.5) * 25만 → 120GB
  한달 이미지 다운로드 : 120 * 30 == 3600GB

  cacheMiss : 0.3

  **CloudFront (signed-cookie)**
  Network 비용 : (3600 - 1000(매달 1TB무료)) * 0.12 = 312USD
  HTTPS 요청요금 : 이미지 다운로드 횟수(5.5 * 30 * 25만 == 4125만) * (만개당 0.012) = 49.5USD
  S3 get 요금 : 이미지 다운로드 횟수(4125만) * 캐시미스율(0.3) * s3요금(천개당 0.00035) = 4.3USD

  - total : 365USD

  **S3 (presigend-url)**
  Network 비용 : (3600 - 100(매달 100GB무료)) * 0.126 = 441USD
  S3 get 요금 : 이미지 다운로드 횟수(4125만) * s3요금(천개당 0.00035) = 14.3USD

  - total : 455USD
  </details>

### Infra architacture
- 도메인 모듈: 멤버, 게시글, 댓글, 좋아요, S3, 인증.
- 글로벌 계층: `config`(CORS/보안/Swagger/S3/Redis/JWT), `error`(단일 에러 코드/핸들러), `response`, `validator`, `cursor`(페이지네이션).
- 인증/인가: `JwtFilter`, `JwtProvider`, `PrincipalDetails`로 Security 필터 체인 구성. 퍼블릭/보호 API 분리.
- 데이터 접근: Spring Data JPA(MySQL) + Spring Data MongoDB, 커스텀 리포지토리로 복잡 쿼리 대응.
- 캐시/토큰: Redis로 이메일 인증 코드/토큰 상태 관리.




## 서비스 화면

### 홈
<img src="docs/images/home.png" width="800" alt="홈 화면">

### 인증
| 로그인 | 회원가입 | 이메일 |
|--------|----------|----------|
| <img src="docs/images/login.png" width="400" alt="로그인"> | <img src="docs/images/signup.png" width="400" alt="회원가입"> |

### 게시글 조회
| 게시글 목록 | 게시글 상세 |
|------------|------------|
| <img src="docs/images/board.png" width="400" alt="게시글 목록"> | <img src="docs/images/post-detail.png" width="400" alt="게시글 상세"> |

### 게시글 편집
| 게시글 등록                                                           | 게시글 수정                                                         |
|------------------------------------------------------------------|----------------------------------------------------------------|
| <img src="docs/images/writep-post.png" width="400" alt="게시글 등록"> | <img src="docs/images/edit-post.png" width="400" alt="게시글 수정"> |

### 회원 복구
| 복구 팝업                                                                    | 회원 복구                                                         |
|--------------------------------------------------------------------------|---------------------------------------------------------------|
| <img src="docs/images/recover-possiblility.png" width="400" alt="마이페이지"> | <img src="docs/images/recover.png" width="400" alt="비밀번호 변경"> |


<details>
<summary>폴더 구조</summary>

```text
kaboocamPostProject/
├─ .dockerignore
├─ .env
├─ .gitattributes
├─ .github/
│  └─ workflows/
│     └─ cicd.yml
├─ .gitignore
├─ Dockerfile
├─ HELP.md
├─ README.md
├─ build.gradle
├─ docker-compose.yml
├─ gradlew
├─ gradlew.bat
├─ settings.gradle
├─ src/
│  ├─ main/
│  │  ├─ java/com/example/kaboocampostproject/
│  │  │  ├─ KaboocamPostProjectApplication.java
│  │  │  ├─ domain/
│  │  │  │  ├─ auth/
│  │  │  │  │  ├─ controller/AuthController.java
│  │  │  │  │  ├─ dto/req/{LoginReqDTO.java,SendEmailReqDTO.java,VerifyEmailReqDTO.java}
│  │  │  │  │  ├─ dto/res/{AccessJwtResDTO.java,SendEmailResDTO.java,VerifyEmailResDTO.java}
│  │  │  │  │  ├─ email/{EmailSender.java,EmailVerifier.java}
│  │  │  │  │  ├─ entity/AuthMember.java
│  │  │  │  │  ├─ error/{AuthMemberErrorCode.java,AuthMemberException.java}
│  │  │  │  │  ├─ jwt/
│  │  │  │  │  │  ├─ dto/{AccessClaims.java,IssuedJwts.java,RefreshClaims.java,ReissueJwts.java}
│  │  │  │  │  │  ├─ exception/{JwtErrorCode.java,JwtException.java}
│  │  │  │  │  │  ├─ JwtAccessDeniedHandler.java
│  │  │  │  │  │  ├─ JwtAuthenticationEntryPoint.java
│  │  │  │  │  │  ├─ JwtFilter.java
│  │  │  │  │  │  └─ JwtProvider.java
│  │  │  │  │  ├─ repository/AuthMemberRepository.java
│  │  │  │  │  └─ service/AuthMemberService.java
│  │  │  │  ├─ comment/
│  │  │  │  │  ├─ controller/CommentController.java
│  │  │  │  │  ├─ converter/CommentConverter.java
│  │  │  │  │  ├─ document/CommentDocument.java
│  │  │  │  │  ├─ dto/{CommentReqDTO.java,CommentSliceItem.java,CommentSliceResDTO.java}
│  │  │  │  │  ├─ error/{CommentErrorCode.java,CommentException.java}
│  │  │  │  │  ├─ repository/{CommentCustomRepository.java,CommentMongoRepository.java}
│  │  │  │  │  ├─ repository/impl/CommentCustomRepositoryImpl.java
│  │  │  │  │  └─ service/CommentMongoService.java
│  │  │  │  ├─ like/
│  │  │  │  │  ├─ dto/PostLikeStatsDto.java
│  │  │  │  │  ├─ entity/PostLike.java
│  │  │  │  │  └─ repository/PostLikeRepository.java
│  │  │  │  ├─ member/
│  │  │  │  │  ├─ anotations/{MemberIdInfo.java}
│  │  │  │  │  ├─ anotations/resolver/MemberIdArgumentResolver.java
│  │  │  │  │  ├─ cache/{MemberProfileCacheDTO.java,MemberProfileCacheService.java}
│  │  │  │  │  ├─ controller/MemberController.java
│  │  │  │  │  ├─ converter/MemberConverter.java
│  │  │  │  │  ├─ dto/request/{MemberRegisterReqDTO.java,RecoverMemberReqDTO.java,UpdateMemberReqDTO.java}
│  │  │  │  │  ├─ dto/response/MemberProfileAndEmailResDTO.java
│  │  │  │  │  ├─ entity/{Member.java,UserRole.java}
│  │  │  │  │  ├─ error/{MemberErrorCode.java,MemberException.java}
│  │  │  │  │  ├─ repository/MemberRepository.java
│  │  │  │  │  └─ service/MemberService.java
│  │  │  │  ├─ policySSR/PolicyController.java
│  │  │  │  ├─ post/
│  │  │  │  │  ├─ controller/PostController.java
│  │  │  │  │  ├─ converter/PostConverter.java
│  │  │  │  │  ├─ document/PostDocument.java
│  │  │  │  │  ├─ dto/req/{PostCreatReqDTO.java,PostUpdateReqDTO.java}
│  │  │  │  │  ├─ dto/res/{PostDetailResDTO.java,PostSimple.java,PostSliceItem.java,PostSliceResDTO.java}
│  │  │  │  │  ├─ error/{PostErrorCode.java,PostException.java}
│  │  │  │  │  ├─ repository/{PostCustomRepository.java,PostMongoRepository.java}
│  │  │  │  │  ├─ repository/impl/PostCustomRepositoryImpl.java
│  │  │  │  │  └─ service/{PostMongoService.java,PostViewService.java}
│  │  │  │  └─ s3/
│  │  │  │     ├─ controller/S3Controller.java
│  │  │  │     ├─ dto/req/{UploadListReqDTO.java,UploadReqDTO.java}
│  │  │  │     ├─ dto/res/{PresignedUrlListResDTO.java,PresignedUrlResDTO.java}
│  │  │  │     ├─ enums/FileDomain.java
│  │  │  │     ├─ error/{S3ErrorCode.java,S3Exception.java}
│  │  │  │     ├─ service/S3Service.java
│  │  │  │     └─ util/{CloudFrontUtil.java,S3Util.java}
│  │  │  └─ global/
│  │  │     ├─ config/{CorsConfig.java,CorsProperties.java,JwtProperties.java,MailConfig.java,MongoDBConfig.java,RedisConfig.java,S3Config.java,SecurityConfig.java,SecurityProperties.java,SwaggerConfig.java,WebConfig.java}
│  │  │     ├─ cursor/{Cursor.java,CursorCodec.java,PageSlice.java}
│  │  │     ├─ entity/BaseTimeEntity.java
│  │  │     ├─ error/{BaseErrorCode.java,CustomException.java,GeneralErrorCode.java,GlobalExceptionHandler.java}
│  │  │     ├─ health/{HealthCheckController.java,TestController.java}
│  │  │     ├─ metadata/{JwtMetadata.java,MailVerifyMetadata.java,RedisMetadata.java}
│  │  │     ├─ mongo/StringIdBinaryConverter.java
│  │  │     ├─ response/CustomResponse.java
│  │  │     └─ validator/
│  │  │        ├─ annotation/{ValidName.java,ValidPassword.java}
│  │  │        ├─ NameValidator.java
│  │  │        └─ PasswordValidator.java
│  │  └─ resources/
│  │     ├─ application-prod.yml
│  │     ├─ application.yml
│  │     ├─ static/css/policy.css
│  │     └─ templates/
│  │        ├─ mail/verify-email-form.html
│  │        └─ policy/{privacy.html,terms.html}
│  └─ test/
│     └─ java/com/example/kaboocampostproject/
│        └─ domain/member/controller/MemberControllerTest.java
├─ gradlew
├─ gradlew.bat
├─ build.gradle
├─ settings.gradle
├─ docker-compose.yml
├─ Dockerfile
├─ HELP.md
└─ README.md
```

</details>

### 링크/자료
- Front-end Github: https://github.com/100-hours-a-week/3-logan-cho-community-FE
- 서비스 시연 영상: https://www.youtube.com/watch?v=VHedUtEJXq4
