FROM public.ecr.aws/lambda/java:25

WORKDIR ${LAMBDA_TASK_ROOT}
COPY target/springboot-with-aws-lambda-1.0.0-SNAPSHOT.jar app.jar
RUN jar -xf app.jar && rm app.jar

CMD ["com.example.aws_lambda_with_spring.FunctionUrlHandler::handleRequest"]