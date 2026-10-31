# syntax=docker/dockerfile:1

# Build: restore first (cached while project files don't change), then publish.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY global.json Directory.Build.props Directory.Packages.props .editorconfig ./
COPY src/Quizly.Domain/Quizly.Domain.csproj src/Quizly.Domain/
COPY src/Quizly.Application/Quizly.Application.csproj src/Quizly.Application/
COPY src/Quizly.Infrastructure/Quizly.Infrastructure.csproj src/Quizly.Infrastructure/
COPY src/Quizly.Web/Quizly.Web.csproj src/Quizly.Web/
RUN dotnet restore src/Quizly.Web/Quizly.Web.csproj
COPY src/ src/
RUN dotnet publish src/Quizly.Web/Quizly.Web.csproj -c Release -o /app --no-restore

# Runtime: Debian-based ASP.NET image (ICU + tzdata for Europe/Prague), non-root user.
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
# Data Protection keys live on a volume so admin cookies survive restarts.
RUN mkdir -p /data/keys && chown -R "$APP_UID" /data
COPY --from=build /app .
ENV ASPNETCORE_HTTP_PORTS=8080 \
    DataProtection__KeysPath=/data/keys
EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "Quizly.Web.dll"]
