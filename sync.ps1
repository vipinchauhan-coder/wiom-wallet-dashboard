# sync.ps1 - Wiom Wallet Dashboard Data Sync
# No Node.js required. Run from inside Wiom network.

$GITHUB_PAT  = if ($env:GITHUB_PAT) { $env:GITHUB_PAT } else { Read-Host "Enter GitHub PAT" }
$GITHUB_REPO = 'vipinchauhan-coder/wiom-wallet-dashboard'
$MB_URL      = 'https://metabase.wiom.in'
$MB_EMAIL    = 'Vipin.Chauhan@wiom.in'
$MB_PASSWORD = 'Wiom@2117'
$MB_QID      = '11227'

add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host " Wiom Wallet Dashboard - Data Sync"
Write-Host ""

Write-Host " [..] Authenticating with Metabase at $MB_URL ..."
$token = $null

# Try method 1: username field
try {
    $authBody = @{ username = $MB_EMAIL; password = $MB_PASSWORD } | ConvertTo-Json
    $authResp = Invoke-RestMethod -Uri "$MB_URL/api/session" -Method POST -ContentType 'application/json' -Body $authBody -ErrorAction Stop
    $token = $authResp.id
    Write-Host " [OK] Auth OK (method 1)"
} catch {
    Write-Host " [..] Method 1 failed: $($_.Exception.Message)"
}

# Try method 2: email field
if (-not $token) {
    try {
        $authBody = @{ email = $MB_EMAIL; password = $MB_PASSWORD } | ConvertTo-Json
        $authResp = Invoke-RestMethod -Uri "$MB_URL/api/session" -Method POST -ContentType 'application/json' -Body $authBody -ErrorAction Stop
        $token = $authResp.id
        Write-Host " [OK] Auth OK (method 2)"
    } catch {
        Write-Host " [..] Method 2 failed: $($_.Exception.Message)"
    }
}

if (-not $token) {
    Write-Host " [ERROR] Both auth methods failed."
    Read-Host "Press Enter to exit"; exit 1
}

Write-Host " [..] Downloading data (question $MB_QID)..."
try {
    $headers = @{ 'X-Metabase-Session' = $token; 'Content-Type' = 'application/json' }
    $csvBytes = Invoke-WebRequest -Uri "$MB_URL/api/card/$MB_QID/query/csv" -Method POST -Headers $headers -Body '{"parameters":[]}' -ErrorAction Stop
    $csvText = [System.Text.Encoding]::UTF8.GetString($csvBytes.Content)
    $rowCount = ($csvText -split "`n").Count - 1
    Write-Host " [OK] Got $rowCount rows."
} catch {
    Write-Host " [ERROR] Download failed: $($_.Exception.Message)"
    Read-Host "Press Enter to exit"; exit 1
}

function Push-ToGitHub($filePath, $content, $message) {
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    $apiUrl = "https://api.github.com/repos/$GITHUB_REPO/contents/$filePath"
    $ghHeaders = @{ Authorization = "token $GITHUB_PAT"; Accept = 'application/vnd.github.v3+json'; 'User-Agent' = 'wiom-wallet-sync' }
    $sha = $null
    try { $sha = (Invoke-RestMethod -Uri $apiUrl -Headers $ghHeaders -ErrorAction Stop).sha } catch {}
    $body = @{ message = $message; content = $encoded }
    if ($sha) { $body.sha = $sha }
    Invoke-RestMethod -Uri $apiUrl -Headers $ghHeaders -Method PUT -ContentType 'application/json' -Body ($body | ConvertTo-Json) | Out-Null
}

Write-Host " [..] Pushing to GitHub..."
try {
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm UTC")
    Push-ToGitHub 'data/latest.csv' $csvText $now
    Push-ToGitHub 'data/last-sync.txt' $now $now
    Write-Host " [OK] Done!"
} catch {
    Write-Host " [ERROR] GitHub push failed: $($_.Exception.Message)"
    Read-Host "Press Enter to exit"; exit 1
}

Write-Host ""
Write-Host " Dashboard: https://vipinchauhan-coder.github.io/wiom-wallet-dashboard/"
Write-Host ""
Read-Host "Press Enter to exit"