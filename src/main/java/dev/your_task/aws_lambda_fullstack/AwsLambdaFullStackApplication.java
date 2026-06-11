package dev.your_task.aws_lambda_fullstack;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.function.RouterFunction;
import org.springframework.web.servlet.function.RouterFunctions;
import org.springframework.web.servlet.function.ServerResponse;

import java.util.Map;

@SpringBootApplication
@Slf4j
public class AwsLambdaFullStackApplication {

	public static void main(String[] args) {
		SpringApplication.run(AwsLambdaFullStackApplication.class, args);
	}

	@Bean
	RouterFunction<ServerResponse> routerFunction(@Value("${spring.application.api.base-uri}") String baseUri) {
		return RouterFunctions
				.route()
				.before(request -> {
					log.info("{} {}", request.method(), request.path());
					return request;
				})
				.path(baseUri, builder -> builder
						.GET("/ping", request -> ServerResponse.ok().body(
								Map.of(
										"message", "pong",
										"headers", request.headers().asHttpHeaders().toSingleValueMap()
								)
							)
						)
						.POST("/map", request -> ServerResponse.ok().body(request.body(Map.class)))
				)
				.build();
	}

}
