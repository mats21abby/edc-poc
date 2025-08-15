/*
 *  Copyright (c) 2025 Cofinity-X
 *
 *  This program and the accompanying materials are made available under the
 *  terms of the Apache License, Version 2.0 which is available at
 *  https://www.apache.org/licenses/LICENSE-2.0
 *
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Contributors:
 *       Cofinity-X - initial API and implementation
 *
 */

package org.eclipse.edc.sample.extension.proxy;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import org.eclipse.edc.connector.dataplane.spi.iam.DataPlaneAuthorizationService;

import java.io.IOException;
import java.net.URI;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;

import static jakarta.ws.rs.core.HttpHeaders.AUTHORIZATION;
import static jakarta.ws.rs.core.HttpHeaders.CONTENT_TYPE;
import static jakarta.ws.rs.core.MediaType.APPLICATION_FORM_URLENCODED;
import static jakarta.ws.rs.core.MediaType.APPLICATION_OCTET_STREAM;
import static jakarta.ws.rs.core.MediaType.WILDCARD;
import static jakarta.ws.rs.core.Response.Status.BAD_REQUEST;
import static jakarta.ws.rs.core.Response.Status.FORBIDDEN;
import static jakarta.ws.rs.core.Response.Status.UNAUTHORIZED;
import static java.util.Collections.emptyMap;
import static org.eclipse.edc.spi.constants.CoreConstants.EDC_NAMESPACE;

@Path("{any:.*}")
@Produces(WILDCARD)
public class ProxyController {

    private final DataPlaneAuthorizationService authorizationService;

    public ProxyController(DataPlaneAuthorizationService authorizationService) {
        this.authorizationService = authorizationService;
    }

    private final HttpClient httpClient = HttpClient.newHttpClient();

    @GET
    @Consumes(WILDCARD)
    public Response proxyGet(@Context ContainerRequestContext requestContext) {
        return handleRequest(requestContext);
    }

    @POST
    @Consumes({APPLICATION_FORM_URLENCODED, "application/sparql-query", "application/json", "text/plain", WILDCARD})
    public Response proxyPost(@Context ContainerRequestContext requestContext) {
        var contentType = requestContext.getHeaderString(CONTENT_TYPE);
        
        // Read the request body once at the beginning
        String requestBody = null;
        try {
            requestBody = new String(requestContext.getEntityStream().readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return Response.status(BAD_REQUEST)
                    .entity("{\"error\": \"Failed to read request body\"}")
                    .build();
        }
        
        if (contentType != null) {
            if (contentType.contains("application/x-www-form-urlencoded")) {
                // Extract query parameter from form data
                String query = null;
                if (requestBody.startsWith("query=")) {
                    try {
                        query = URLDecoder.decode(requestBody.substring(6), StandardCharsets.UTF_8);
                    } catch (Exception e) {
                        return Response.status(BAD_REQUEST)
                                .entity("{\"error\": \"Failed to decode query parameter\"}")
                                .build();
                    }
                }
                return handleSparqlRequest(requestContext, query);
            } else if (contentType.contains("application/sparql-query")) {
                return handleDirectSparqlRequest(requestContext, requestBody);
            }
        }
        
        // Default POST handling for other content types
        return handleRequest(requestContext, requestBody);
    }

    private Response handleRequest(ContainerRequestContext requestContext) {
        return handleRequest(requestContext, null);
    }

    private Response handleRequest(ContainerRequestContext requestContext, String requestBody) {
        var token = requestContext.getHeaderString(AUTHORIZATION);
        if (token == null) {
            return Response.status(UNAUTHORIZED).build();
        }

        var authorization = authorizationService.authorize(token, emptyMap());
        if (authorization.failed()) {
            return Response.status(FORBIDDEN).build();
        }

        var sourceDataAddress = authorization.getContent();

        try {
            var targetUrl = sourceDataAddress.getStringProperty(EDC_NAMESPACE + "baseUrl") + "/" + requestContext.getUriInfo().getPath();
            var requestBuilder = HttpRequest.newBuilder()
                    .uri(URI.create(targetUrl));

            if (requestBody != null && !requestBody.isEmpty()) {
                requestBuilder.method(requestContext.getMethod(), HttpRequest.BodyPublishers.ofString(requestBody));
            } else {
                requestBuilder.method(requestContext.getMethod(), HttpRequest.BodyPublishers.noBody());
            }

            var request = requestBuilder.build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
            return Response.status(response.statusCode())
                    .header(CONTENT_TYPE, response.headers().firstValue(CONTENT_TYPE).orElse(APPLICATION_OCTET_STREAM))
                    .entity(response.body())
                    .build();
        } catch (IOException | InterruptedException e) {
            return Response.status(Response.Status.BAD_GATEWAY)
                    .entity("{\"error\": \"Failed to contact backend service\"}")
                    .build();
        }
    }

    private Response handleSparqlRequest(ContainerRequestContext requestContext, String query) {
        var token = requestContext.getHeaderString(AUTHORIZATION);
        if (token == null) {
            return Response.status(UNAUTHORIZED).build();
        }

        var authorization = authorizationService.authorize(token, emptyMap());
        if (authorization.failed()) {
            return Response.status(FORBIDDEN).build();
        }

        if (query == null || query.trim().isEmpty()) {
            return Response.status(BAD_REQUEST)
                    .entity("{\"error\": \"SPARQL query is required\"}")
                    .build();
        }

        var sourceDataAddress = authorization.getContent();

        try {
            var targetUrl = sourceDataAddress.getStringProperty(EDC_NAMESPACE + "baseUrl");
            
            // SPARQL query as form data
            var formData = "query=" + URLEncoder.encode(query, StandardCharsets.UTF_8);
            
            var request = HttpRequest.newBuilder()
                    .uri(URI.create(targetUrl))
                    .header(CONTENT_TYPE, APPLICATION_FORM_URLENCODED)
                    .header("Accept", "application/sparql-results+json")
                    .POST(HttpRequest.BodyPublishers.ofString(formData))
                    .build();

            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
            return Response.status(response.statusCode())
                    .header(CONTENT_TYPE, response.headers().firstValue(CONTENT_TYPE).orElse("application/sparql-results+json"))
                    .entity(response.body())
                    .build();
        } catch (IOException | InterruptedException e) {
            return Response.status(Response.Status.BAD_GATEWAY)
                    .entity("{\"error\": \"Failed to contact SPARQL endpoint: " + e.getMessage() + "\"}")
                    .build();
        }
    }

    private Response handleDirectSparqlRequest(ContainerRequestContext requestContext, String queryString) {
        var token = requestContext.getHeaderString(AUTHORIZATION);
        if (token == null) {
            return Response.status(UNAUTHORIZED).build();
        }

        var authorization = authorizationService.authorize(token, emptyMap());
        if (authorization.failed()) {
            return Response.status(FORBIDDEN).build();
        }

        var sourceDataAddress = authorization.getContent();

        try {
            var targetUrl = sourceDataAddress.getStringProperty(EDC_NAMESPACE + "baseUrl");
            
            var request = HttpRequest.newBuilder()
                    .uri(URI.create(targetUrl))
                    .header(CONTENT_TYPE, "application/sparql-query")
                    .header("Accept", "application/sparql-results+json")
                    .POST(HttpRequest.BodyPublishers.ofString(queryString))
                    .build();

            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
            return Response.status(response.statusCode())
                    .header(CONTENT_TYPE, response.headers().firstValue(CONTENT_TYPE).orElse("application/sparql-results+json"))
                    .entity(response.body())
                    .build();
        } catch (IOException | InterruptedException e) {
            return Response.status(Response.Status.BAD_GATEWAY)
                    .entity("{\"error\": \"Failed to contact SPARQL endpoint: " + e.getMessage() + "\"}")
                    .build();
        }
    }
}
