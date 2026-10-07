package com.greenwave.backend.repository;

import com.greenwave.backend.entity.UserLocation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface UserLocationRepository extends JpaRepository<UserLocation, UUID> {

    @Query(value = """
            SELECT ul.* FROM user_locations ul
            JOIN users u ON u.id = ul.user_id
            WHERE u.role = :role
            """, nativeQuery = true)
    List<UserLocation> findByUserRole(@Param("role") String role);
}