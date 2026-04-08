# ============================================================
# Deploy Purview MCP Server to Azure App Service
# FIX: Includes node_modules in zip — skips Azure build
# ============================================================

param(
    [string]$ResourceGroup = "rg-purview-mcp",
    [string]$AppName = "purview-mcp",
    [string]$Region = "canadacentral",
    [string]$TenantId = "",
    [string]$ClientId = "",
    [string]$ClientSecret = "",
    [string]$Sku = "B1"
)

$STARTUP_CMD = "node dist/web.js"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Purview MCP Server — Azure Deploy"                             -ForegroundColor Cyan
Write-Host "  106 Tools | Pre-built Deploy (no Azure build)"                  -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ---- Check CLI ----
Write-Host "[1/11] Azure CLI..." -ForegroundColor Yellow
$azVer = az version --output json 2>$null | ConvertFrom-Json
if (-not $azVer) { Write-Host "Install: https://aka.ms/installazurecliwindows" -ForegroundColor Red; exit 1 }
Write-Host "  Version: $($azVer.'azure-cli')" -ForegroundColor Green
Write-Host ""

# ---- Credentials ----
Write-Host "[2/11] Credentials..." -ForegroundColor Yellow
if (-not $TenantId) { $TenantId = Read-Host "PURVIEW_TENANT_ID" }
if (-not $ClientId) { $ClientId = Read-Host "PURVIEW_CLIENT_ID" }
if (-not $ClientSecret) { $ClientSecret = Read-Host "PURVIEW_CLIENT_SECRET" }
if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) { Write-Host "All 3 required!" -ForegroundColor Red; exit 1 }
$FullAppName = "$AppName-$($TenantId.Substring(0,8).ToLower())"
Write-Host "  App: https://$FullAppName.azurewebsites.net" -ForegroundColor Cyan
Write-Host ""

# ---- Login ----
Write-Host "[3/11] Azure Login..." -ForegroundColor Yellow
az logout 2>$null
az config set core.enable_broker_on_windows=false 2>$null
az login --tenant $TenantId
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Trying device code..." -ForegroundColor Yellow
    az login --tenant $TenantId --use-device-code
}
Write-Host ""
az account show --output table
Write-Host ""

# ---- Resource Group ----
Write-Host "[4/11] Resource Group..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Region --output table
Write-Host ""

# ---- Plan ----
Write-Host "[5/11] App Service Plan ($Sku)..." -ForegroundColor Yellow
az appservice plan create --name "${FullAppName}-plan" --resource-group $ResourceGroup --sku $Sku --is-linux --output table
Write-Host ""

# ---- Web App ----
Write-Host "[6/11] Web App..." -ForegroundColor Yellow
az webapp create --name $FullAppName --resource-group $ResourceGroup --plan "${FullAppName}-plan" --runtime "NODE:20-lts" --output table
Write-Host ""

# Check quota
$usage = az webapp show --name $FullAppName --resource-group $ResourceGroup --query "usageState" -o tsv 2>$null
if ($usage -eq "Exceeded") {
    Write-Host "  QUOTA EXCEEDED! Upgrading to B1..." -ForegroundColor Red
    az appservice plan update --name "${FullAppName}-plan" --resource-group $ResourceGroup --sku B1 --output table
    az webapp restart --name $FullAppName --resource-group $ResourceGroup
    Start-Sleep 10
}

# ---- Config ----
Write-Host "[7/11] Config + Env vars..." -ForegroundColor Yellow

# CRITICAL: Disable Azure build — we include node_modules in zip
az webapp config appsettings set --name $FullAppName --resource-group $ResourceGroup --settings `
    PURVIEW_TENANT_ID="$TenantId" `
    PURVIEW_CLIENT_ID="$ClientId" `
    PURVIEW_CLIENT_SECRET="$ClientSecret" `
    PURVIEW_EXPORT_PATH="/tmp/PurviewExports" `
    SCM_DO_BUILD_DURING_DEPLOYMENT="false" `
    ENABLE_ORYX_BUILD="false" `
    WEBSITES_PORT="8000" `
    NODE_ENV="production" `
    --output table
Write-Host ""

az webapp config set --name $FullAppName --resource-group $ResourceGroup --startup-file $STARTUP_CMD --output table
Write-Host ""

# ---- Build locally ----
Write-Host "[8/11] Build + Install deps locally..." -ForegroundColor Yellow
if (-not (Test-Path "package.json")) { Write-Host "Run from purview-mcp-server folder!" -ForegroundColor Red; exit 1 }

# Build TypeScript
Write-Host "  npm run build..." -ForegroundColor Gray
npm run build
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed!" -ForegroundColor Red; exit 1 }
Write-Host "  Build OK!" -ForegroundColor Green

# Install production deps
Write-Host "  npm install --production (for deployment)..." -ForegroundColor Gray
$prodDir = "$env:TEMP\purview-prod"
if (Test-Path $prodDir) { Remove-Item $prodDir -Recurse -Force }
New-Item -ItemType Directory -Path $prodDir -Force | Out-Null

# Copy essentials
Copy-Item "package.json" "$prodDir\package.json"
if (Test-Path "package-lock.json") { Copy-Item "package-lock.json" "$prodDir\package-lock.json" }
Copy-Item "dist" "$prodDir\dist" -Recurse

# Install production deps in temp dir
Push-Location $prodDir
npm install --production --no-optional 2>&1 | Select-Object -Last 3
Pop-Location
Write-Host "  Dependencies installed!" -ForegroundColor Green
Write-Host ""

# ---- Package ----
Write-Host "[9/11] Creating deploy package..." -ForegroundColor Yellow
$zipPath = "$env:TEMP\purview-mcp-deploy.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Zip the prod directory (has dist + node_modules + package.json)
Compress-Archive -Path "$prodDir\*" -DestinationPath $zipPath -Force

$zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host "  Package: ${zipMB}MB (includes node_modules)" -ForegroundColor Green

# Count files
$z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$jsCount = ($z.Entries | Where-Object { $_.FullName -like "dist/*.js" }).Count
$nmCount = ($z.Entries | Where-Object { $_.FullName -like "node_modules/*" }).Count
$z.Dispose()
Write-Host "  dist/ JS files: $jsCount" -ForegroundColor Gray
Write-Host "  node_modules entries: $nmCount" -ForegroundColor Gray

# Cleanup
Remove-Item $prodDir -Recurse -Force
Write-Host ""

# ---- Deploy ----
Write-Host "[10/11] Deploying (no Azure build — pre-built)..." -ForegroundColor Yellow
Write-Host ""

$deployed = $false

# Method 1: az webapp deploy (preferred)
Write-Host "  Method 1: az webapp deploy..." -ForegroundColor Cyan
az webapp deploy --name $FullAppName --resource-group $ResourceGroup --src-path $zipPath --type zip --async false --output json 2>&1
if ($LASTEXITCODE -eq 0) {
    $deployed = $true
    Write-Host "  Deployed!" -ForegroundColor Green
}

# Method 2: config-zip
if (-not $deployed) {
    Write-Host "  Method 2: config-zip..." -ForegroundColor Yellow
    az webapp deployment source config-zip --name $FullAppName --resource-group $ResourceGroup --src $zipPath --timeout 300 --output json 2>&1
    if ($LASTEXITCODE -eq 0) {
        $deployed = $true
        Write-Host "  Deployed!" -ForegroundColor Green
    }
}

# Method 3: Kudu API direct upload
if (-not $deployed) {
    Write-Host "  Method 3: Direct Kudu API..." -ForegroundColor Yellow
    $creds = az webapp deployment list-publishing-credentials --name $FullAppName --resource-group $ResourceGroup --output json | ConvertFrom-Json
    if ($creds) {
        $kuduUrl = "https://$FullAppName.scm.azurewebsites.net/api/zipdeploy"
        $base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($creds.publishingUserName):$($creds.publishingPassword)"))
        try {
            Invoke-RestMethod -Uri $kuduUrl -Method POST -InFile $zipPath -ContentType "application/zip" -Headers @{ Authorization = "Basic $base64" } -TimeoutSec 300
            $deployed = $true
            Write-Host "  Deployed via Kudu!" -ForegroundColor Green
        } catch {
            Write-Host "  Kudu upload failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""

# Re-apply startup
az webapp config set --name $FullAppName --resource-group $ResourceGroup --startup-file $STARTUP_CMD -o none 2>$null
az webapp restart --name $FullAppName --resource-group $ResourceGroup 2>$null

# ---- Verify ----
Write-Host "[11/11] Health check (waiting 30s)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

$healthUrl = "https://$FullAppName.azurewebsites.net/health"
$mcpUrl = "https://$FullAppName.azurewebsites.net/mcp"
$healthy = $false

for ($i = 1; $i -le 5; $i++) {
    Write-Host "  Attempt $i/5..." -ForegroundColor Yellow
    try {
        $r = Invoke-WebRequest -Uri $healthUrl -Method GET -TimeoutSec 45 -UseBasicParsing
        $body = $r.Content | ConvertFrom-Json
        Write-Host "  HTTP $($r.StatusCode) — tools: $($body.tools), uptime: $($body.uptime)s" -ForegroundColor Green
        $healthy = $true
        break
    } catch {
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        if ($i -lt 5) { Start-Sleep 15 }
    }
}

# Try landing page
if (-not $healthy) {
    Write-Host ""
    Write-Host "  Trying landing page..." -ForegroundColor Yellow
    try {
        $r2 = Invoke-WebRequest -Uri "https://$FullAppName.azurewebsites.net" -Method GET -TimeoutSec 45 -UseBasicParsing
        Write-Host "  Landing page HTTP $($r2.StatusCode)!" -ForegroundColor Green
        $healthy = $true
    } catch {
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""

if (-not $healthy) {
    Write-Host "  Check logs: az webapp log tail --name $FullAppName -g $ResourceGroup" -ForegroundColor Cyan
}

# ---- Summary ----
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Landing: https://$FullAppName.azurewebsites.net" -ForegroundColor White
Write-Host "  MCP:     $mcpUrl" -ForegroundColor Cyan
Write-Host "  Health:  $healthUrl" -ForegroundColor White
Write-Host "  Tier:    $Sku" -ForegroundColor White
Write-Host ""
Write-Host "  -- Copilot Studio --" -ForegroundColor Yellow
Write-Host "  1. copilotstudio.microsoft.com" -ForegroundColor White
Write-Host "  2. Agent > Tools > Add > New > MCP" -ForegroundColor White
Write-Host "  3. URL: $mcpUrl" -ForegroundColor Cyan
Write-Host "  4. Auth: None > Create > Select all > Add" -ForegroundColor White
Write-Host "  5. Settings > Generative AI > Orchestration ON" -ForegroundColor White
Write-Host ""
Write-Host "  -- Commands --" -ForegroundColor Yellow
Write-Host "  Logs:      az webapp log tail --name $FullAppName -g $ResourceGroup" -ForegroundColor Gray
Write-Host "  Restart:   az webapp restart --name $FullAppName -g $ResourceGroup" -ForegroundColor Gray
Write-Host "  Downgrade: az appservice plan update --name ${FullAppName}-plan -g $ResourceGroup --sku F1" -ForegroundColor Gray
Write-Host "  Delete:    az group delete --name $ResourceGroup --yes" -ForegroundColor Gray
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
try { $mcpUrl | Set-Clipboard; Write-Host "  MCP URL copied to clipboard!" -ForegroundColor Green } catch {}
Write-Host ""
