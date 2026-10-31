using Microsoft.OpenApi;
using Quizly.Web.Auth;

namespace Quizly.Web.Api;

/// <summary>OpenAPI document at /api/openapi/v1.json and Swagger UI at /api/docs (behind the admin cookie in Production).</summary>
internal static class DocsEndpoints
{
    private const string SwaggerUiVersion = "5.17.14";

    public static IServiceCollection AddQuizlyOpenApi(this IServiceCollection services) =>
        services.AddOpenApi(options => options.AddDocumentTransformer((document, _, _) =>
        {
            document.Info = new OpenApiInfo { Title = "Quizly API", Version = "v1" };
            document.Components ??= new OpenApiComponents();
            document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
            document.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "JWT",
                Description = "App access token from POST /api/auth/login. Admin endpoints use the cookie from POST /api/admin/auth/login instead.",
            };
            document.Security = [new OpenApiSecurityRequirement { [new OpenApiSecuritySchemeReference("Bearer", document)] = [] }];
            return Task.CompletedTask;
        }));

    public static void MapDocs(this WebApplication app)
    {
        var openApi = app.MapOpenApi("/api/openapi/{documentName}.json");
        var ui = app.MapGet("/api/docs", () => TypedResults.Content(Page, "text/html; charset=utf-8"))
            .ExcludeFromDescription();

        if (!app.Environment.IsDevelopment())
        {
            openApi.RequireAuthorization(AuthSetup.AdminPolicy);
            ui.RequireAuthorization(AuthSetup.AdminPolicy);
        }
    }

    private static readonly string Page = $$"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Quizly API</title>
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@{{SwaggerUiVersion}}/swagger-ui.css">
        </head>
        <body>
          <div id="swagger-ui"></div>
          <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@{{SwaggerUiVersion}}/swagger-ui-bundle.js" crossorigin></script>
          <script>
            window.ui = SwaggerUIBundle({ url: '/api/openapi/v1.json', dom_id: '#swagger-ui', persistAuthorization: true });
          </script>
        </body>
        </html>
        """;
}
