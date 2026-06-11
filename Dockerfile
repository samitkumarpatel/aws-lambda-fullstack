FROM public.ecr.aws/lambda/java:25

WORKDIR ${LAMBDA_TASK_ROOT}
COPY target/aws-lambda-with-spring-1.0.0-SNAPSHOT.jar app.jar
RUN jar -xf app.jar && rm app.jar

CMD ["dev.your_task.aws_lambda_fullstack.FunctionUrlHandler::handleRequest"]