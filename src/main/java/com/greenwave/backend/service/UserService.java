package com.greenwave.backend.service;

import com.greenwave.backend.dto.SignupRequest;
import com.greenwave.backend.dto.UserResponse;
import com.greenwave.backend.entity.Role;
import com.greenwave.backend.entity.User;
import com.greenwave.backend.repository.UserRepository;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public UserService(
            UserRepository userRepository,
            PasswordEncoder passwordEncoder
    ) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    public UserResponse signup(SignupRequest request) {

        // 1. Check duplicate email
        if (userRepository.findByEmail(request.email()).isPresent()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "Email already registered"
            );
        }

        // 2. Prevent ADMIN self-registration
        if (request.role() == Role.ADMIN) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN,
                    "Cannot self-register as ADMIN"
            );
        }

        // 3. Hash password
        String passwordHash =
                passwordEncoder.encode(request.password());

        // 4. Create user
        User user = User.builder()
                .email(request.email())
                .passwordHash(passwordHash)
                .fullName(request.fullName())
                .role(request.role())
                .isVerified(false)
                .build();

        // 5. Save to PostgreSQL
        User savedUser = userRepository.save(user);

        // 6. Return safe response
        return toResponse(savedUser);
    }

    private UserResponse toResponse(User user) {

        return new UserResponse(
                user.getId(),
                user.getEmail(),
                user.getFullName(),
                user.getRole(),
                user.isVerified()
        );
    }
}