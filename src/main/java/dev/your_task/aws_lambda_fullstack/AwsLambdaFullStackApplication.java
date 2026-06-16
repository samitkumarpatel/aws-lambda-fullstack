package dev.your_task.aws_lambda_fullstack;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;
import org.springframework.web.client.support.RestClientHttpServiceGroupConfigurer;
import org.springframework.web.service.annotation.GetExchange;
import org.springframework.web.service.registry.ImportHttpServices;
import org.springframework.web.servlet.function.RouterFunction;
import org.springframework.web.servlet.function.RouterFunctions;
import org.springframework.web.servlet.function.ServerResponse;

import java.util.List;
import java.util.Map;

@SpringBootApplication
@ImportHttpServices(group = "json-placeholder", types = JsonPlaceHolderService.class)
@RequiredArgsConstructor
@Slf4j
public class AwsLambdaFullStackApplication {

	final JsonPlaceHolderService jsonPlaceHolderService;

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
				.path("/json-placeholder", builder -> builder
						.GET("/users", request -> ServerResponse.ok().body(jsonPlaceHolderService.getUsers()))
				)
				.build();
	}
}

@Component
class HttpServiceConfiguration {
	@Bean
	RestClientHttpServiceGroupConfigurer groupConfigurer() {
		return groups -> {

			groups.filterByName("json-placeholder").forEachClient((_, builder) ->
					builder.baseUrl("https://jsonplaceholder.typicode.com"));
		};
	}
}



record User(Long id, String name, String email, String phone, String website, Address address, Company company) {
	record Address(String street, String suite, String city, String zipCode, Geo geo) {
		record Geo(String lat, String lng){}
	}
	record Company(String name,String catchPhrase, String bs) {}
}

interface JsonPlaceHolderService {
	@GetExchange("/users")
	List<User> getUsers();
}
