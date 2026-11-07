# Wipes the development database and starts an empty one. The next `dotnet run --project src/Quizly.Web`
# fills it with the sample users, decks and shop (#44). Development only: it deletes the dev volume.
#   pwsh deploy/dev-reset.ps1
$compose = Join-Path $PSScriptRoot 'docker-compose.dev.yml'
docker compose -f $compose down -v
docker compose -f $compose up -d

Write-Host 'Waiting for PostgreSQL...'
do {
    Start-Sleep -Seconds 1
    docker compose -f $compose exec -T db pg_isready -U quizly -d quizly *> $null
} until ($LASTEXITCODE -eq 0)
Write-Host 'Ready. Start the app: dotnet run --project src/Quizly.Web'
