package com.example.aws_lambda_with_spring;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.function.RouterFunction;
import org.springframework.web.servlet.function.RouterFunctions;
import org.springframework.web.servlet.function.ServerResponse;

import java.util.Map;

@SpringBootApplication
public class AwsLambdaWithSpringApplication {

	public static void main(String[] args) {
		SpringApplication.run(AwsLambdaWithSpringApplication.class, args);
	}

	@Bean
	RouterFunction<ServerResponse> routerFunction(@Value("${spring.application.api.base-uri}") String baseUri) {
		return RouterFunctions
				.route()
				.path(baseUri, uriBuilder -> uriBuilder
						.GET("/ping", request -> ServerResponse.ok().body(
									Map.of(
											"message", "pong",
											"headers", request.headers().asHttpHeaders()
									)
								)
						)
				)
				.build();
	}

}
