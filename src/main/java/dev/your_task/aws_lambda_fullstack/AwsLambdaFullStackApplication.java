package dev.your_task.aws_lambda_fullstack;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.function.RouterFunction;
import org.springframework.web.servlet.function.RouterFunctions;
import org.springframework.web.servlet.function.ServerResponse;

import java.util.Map;

@SpringBootApplication
public class AwsLambdaFullStackApplication {

	public static void main(String[] args) {
		SpringApplication.run(AwsLambdaFullStackApplication.class, args);
	}

	@Bean
	RouterFunction<ServerResponse> routerFunction(@Value("${spring.application.api.base-uri}") String baseUri) {
		return RouterFunctions
				.route()
				.path(baseUri, builder -> builder
						.GET("/ping", request -> ServerResponse.ok().body(
								Map.of(
										"message", "pong",
										"headers", request.headers().asHttpHeaders().toSingleValueMap()
								)
							)
						)
				)
				.build();
	}

}
