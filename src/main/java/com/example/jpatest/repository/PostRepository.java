package com.example.jpatest.repository;

import com.example.jpatest.dto.SimplePostResDTO;
import com.example.jpatest.entity.Post;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PostRepository extends JpaRepository<Post, Long> {

    @Query("""
      select new com.example.jpatest.dto.SimplePostResDTO(
        p.id, p.title, u.id, u.name, p.createdAt
      )
      from Post p
      join p.author u
      order by p.createdAt desc, p.id desc
    """)
    List<SimplePostResDTO> findSimplePostsOrderByDesc();

}
