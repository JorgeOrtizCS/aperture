using Aperture_WebAPI.Config;
using Aperture_WebAPI.Infrastructure;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// Was Web.config <httpRuntime maxRequestLength="8192" /> (KB).
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 8 * 1024 * 1024);

builder.Services.AddHttpContextAccessor();
builder.Services
    .AddControllers()
    .AddNewtonsoftJson(options =>
    {
        // Same wire format as the Web API 2 version: PascalCase names, nulls omitted.
        options.SerializerSettings.ContractResolver = new DefaultContractResolver();
        options.SerializerSettings.NullValueHandling = NullValueHandling.Ignore;
    });

// OpenAPI document + Swagger UI (Development only, see below).
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Aperture Web API",
        Version = "v1",
        Description = "Privacy-preserving content sharing with situational-awareness access control. "
            + "Log in with POST /api/auth/login, then click Authorize and paste the Token."
    });
    options.AddSecurityDefinition(SwaggerOperationFilter.BearerScheme, new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        Description = "The Token returned by POST /api/auth/login."
    });
    options.OperationFilter<SwaggerOperationFilter>();
    // Stable names for client generators and Bruno/Postman imports, e.g. "Content_Open".
    options.CustomOperationIds(api => api.ActionDescriptor.RouteValues["controller"] + "_" + api.ActionDescriptor.RouteValues["action"]);
    options.IncludeXmlComments(System.IO.Path.Combine(System.AppContext.BaseDirectory, "Aperture WebAPI.xml"));
});
// Describe the Newtonsoft wire format (PascalCase, nulls omitted), not System.Text.Json's.
builder.Services.AddSwaggerGenNewtonsoftSupport();

var app = builder.Build();

AppSettings.Configuration = app.Configuration;
AppSettings.ContentRootPath = app.Environment.ContentRootPath;
CurrentHttpContext.Configure(app.Services.GetRequiredService<IHttpContextAccessor>());

app.UseMiddleware<AuditLoggingMiddleware>();

if (app.Environment.IsDevelopment())
{
    // Spec at /swagger/v1/swagger.json, UI at /swagger.
    app.UseSwagger(options =>
    {
        // Advertise the address the spec was fetched from, so "Try it out" and imports hit this API.
        options.PreSerializeFilters.Add((document, request) =>
            document.Servers = new System.Collections.Generic.List<OpenApiServer>
            {
                new OpenApiServer { Url = request.Scheme + "://" + request.Host.Value }
            });
    });
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "Aperture Web API v1");
        options.EnablePersistAuthorization();
    });
}

app.MapControllers();

app.Run();
