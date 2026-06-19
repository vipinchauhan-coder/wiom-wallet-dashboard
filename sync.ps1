# sync.ps1 - Wiom Wallet Dashboard Data Sync
# No Node.js required. Run from inside Wiom network.
# Usage: powershell -ExecutionPolicy Bypass -File sync.ps1

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

Write-Host " [..] Authenticating with Metabase..."
try {
    $authBody = @{ username = $MB_EMAIL; password = $MB_PASSWORD } | ConvertTo-Json
    $authResp = Invoke-RestMethod -Uri "$MB_URL/api/session" -Method POST -ContentType 'application/json' -Body $authBody -ErrorAction Stop
    $token = $authResp.id
} catch {
    try {
        $authBody = @{ email = $MB_EMAIL; password = $MB_PASSWORD } | ConvertTo-Json
        $authResp = Invoke-RestMethod -Uri "$MB_URL/api/session" -Method POST -ContentType 'application/json' -Body $authBody -ErrorAction Stop
        $token = $authResp.id
    } catch {
        Write-Host " [ERROR] Metabase auth failed. Make sure this PC is on Wiom network/VPN."
        Read-Host "Press Enter to exit"; exit 1
    }
}
Write-Host " [OK] Authenticated."

Write-Host " [..] Downloading data..."
try {
    $headers = @{ 'X-Metabase-Session' = $token; 'Content-Type' = 'application/json' }
    $csvBytes = Invoke-WebRequest -Uri "$MB_URL/api/card/$MB_QID/query/csv" -Method POST -Headers $headers -Body '{"parameters":[]}' -ErrorAction Stop
    $csvText = [System.Text.Encoding]::UTF8.GetString($csvBytes.Content)
    $rowCount = ($csvText -split "`n").Count - 1
    Write-Host " [OK] Got $rowCount rows."
} catch {
    Write-Host " [ERROR] Download failed: $_"
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
    Write-Host " [ERROR] GitHub push failed: $_"
    Read-Host "Press Enter to exit"; exit 1
}

Write-Host ""
Write-Host " Dashboard: https://vipinchauhan-coder.github.io/wiom-wallet-dashboard/"
Write-Host ""
Read-Host "Press Enter to exit"