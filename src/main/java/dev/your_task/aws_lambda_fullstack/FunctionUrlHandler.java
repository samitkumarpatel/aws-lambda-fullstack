package dev.your_task.aws_lambda_fullstack;

import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.model.HttpApiV2ProxyRequest;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestStreamHandler;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class FunctionUrlHandler implements RequestStreamHandler {
    private static final SpringBootLambdaContainerHandler<HttpApiV2ProxyRequest, AwsProxyResponse> handler;
    static {
        try {
            handler = SpringBootLambdaContainerHandler.getHttpApiV2ProxyHandler(AwsLambdaFullStackApplication.class);
        } catch (Exception e) {
            throw new RuntimeException("Could not initialize Spring Boot application", e);
        }
    }

    @Override
    public void handleRequest(InputStream in, OutputStream out, Context ctx) throws IOException {
        handler.proxyStream(in, out, ctx);
    }
}

//for spring-security it's needed

/**
 * Lambda Function URL (payload format 2.0) ignores multiValueHeaders — it only reads
 * Set-Cookie values from the cookies[] array. aws-serverless-java-container writes multiple
 * Set-Cookie headers (session + CSRF) into multiValueHeaders, which are silently dropped.
 * This moves them to cookies[] where the Function URL will forward them to the browser.
 */

/*
public class FunctionUrlHandler implements RequestStreamHandler {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static SpringBootLambdaContainerHandler<HttpApiV2ProxyRequest, AwsProxyResponse> handler;

    static {
        try {
            handler = SpringBootLambdaContainerHandler.getHttpApiV2ProxyHandler(MembershipServiceApplication.class);
        } catch (Exception e) {
            throw new RuntimeException("Could not initialize Spring Boot application", e);
        }
    }

    @Override
    public void handleRequest(InputStream in, OutputStream out, Context ctx) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        handler.proxyStream(in, buffer, ctx);
        out.write(fixCookiesForFunctionUrl(buffer.toByteArray()));
    }

    
    private static byte[] fixCookiesForFunctionUrl(byte[] responseBytes) throws IOException {
        ObjectNode json = (ObjectNode) MAPPER.readTree(responseBytes);
        JsonNode multiValue = json.get("multiValueHeaders");
        if (multiValue == null || !multiValue.isObject()) {
            return responseBytes;
        }

        List<String> setCookieValues = new ArrayList<>();
        List<String> keysToRemove = new ArrayList<>();

        multiValue.fields().forEachRemaining(entry -> {
            if ("set-cookie".equalsIgnoreCase(entry.getKey()) && entry.getValue().isArray()) {
                entry.getValue().forEach(v -> setCookieValues.add(v.asText()));
                keysToRemove.add(entry.getKey());
            }
        });

        if (setCookieValues.isEmpty()) {
            return responseBytes;
        }

        keysToRemove.forEach(((ObjectNode) multiValue)::remove);
        setCookieValues.forEach(json.withArray("cookies")::add);

        return MAPPER.writeValueAsBytes(json);
    }

*/
