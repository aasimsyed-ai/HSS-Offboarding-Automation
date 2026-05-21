[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helperPath = Join-Path $PSScriptRoot 'New-HssOffboardingChecklist.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Helper script not found: $helperPath"
}

function Read-RequiredText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [Parameter(Mandatory = $false)]
        [scriptblock] $Validator = { param($Value) -not [string]::IsNullOrWhiteSpace($Value) },

        [Parameter(Mandatory = $false)]
        [string] $ErrorMessage = 'Value is required.'
    )

    while ($true) {
        $value = Read-Host $Prompt
        if (& $Validator $value) {
            return $value.Trim()
        }

        Write-Host $ErrorMessage -ForegroundColor Red
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt
    )

    while ($true) {
        $value = (Read-Host "$Prompt (Y/N)").Trim().ToUpperInvariant()
        if ($value -in @('Y', 'YES')) { return $true }
        if ($value -in @('N', 'NO')) { return $false }
        Write-Host 'Please enter Y or N.' -ForegroundColor Red
    }
}

function Read-DateValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt
    )

    while ($true) {
        $value = Read-Host $Prompt
        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref] $parsedDate)) {
            return $parsedDate
        }

        Write-Host 'Enter a valid date, for example 2026-01-31 or 31 January 2026.' -ForegroundColor Red
    }
}

Clear-Host
Write-Host 'HSS Offboarding Bot' -ForegroundColor Cyan
Write-Host '===================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Use this after you find a matching ServiceNow SCTASK:' -ForegroundColor Yellow
Write-Host 'Disable account and rename to Full Name-Pending Termination for'
Write-Host ''

$sctaskNumber = Read-RequiredText -Prompt 'SCTASK number' -Validator {
    param($Value)
    $Value -match '^SCTASK\d+$'
} -ErrorMessage 'SCTASK number should look like SCTASK1234567.'

$ritmNumber = Read-RequiredText -Prompt 'Request Number / RITM number' -Validator {
    param($Value)
    $Value -match '^RITM\d+$'
} -ErrorMessage 'RITM number should look like RITM1234567.'

$fullName = Read-RequiredText -Prompt 'Departed employee full name'
$samAccountName = Read-RequiredText -Prompt 'AD username from AD account section'
$departureDate = Read-DateValue -Prompt 'Departure Date from RITM'
$emailForwarding = Read-YesNo -Prompt 'Is Email forwarding checked?'
$emailAccess = Read-YesNo -Prompt 'Is Email Access checked?'
$alreadyDisabled = Read-YesNo -Prompt 'In AD, is the account already disabled?'

$helperArgs = @{
    FullName = $fullName
    SamAccountName = $samAccountName
    RitmNumber = $ritmNumber
    TerminationDate = $departureDate
    AsJson = $true
}

if ($emailForwarding -or $emailAccess) {
    $helperArgs.EmailForwardingOrAccessRequired = $true
}

$result = & $helperPath @helperArgs | ConvertFrom-Json

Write-Host ''
Write-Host 'Calculated AD rename value' -ForegroundColor Yellow
Write-Host '--------------------------' -ForegroundColor Yellow
Write-Host $result.adRenameValue -ForegroundColor Green
Write-Host ''

Write-Host 'Perform these actions now' -ForegroundColor Yellow
Write-Host '-------------------------' -ForegroundColor Yellow
for ($i = 0; $i -lt $result.checklist.Count; $i++) {
    Write-Host ('{0}. {1}' -f ($i + 1), $result.checklist[$i])
}

Write-Host ''
Write-Host 'ServiceNow closure comments' -ForegroundColor Yellow
Write-Host '---------------------------' -ForegroundColor Yellow
if ($alreadyDisabled) {
    Write-Host 'As checked, the account is already disabled.'
}
Write-Host 'Performed password reset.'
Write-Host 'Renamed the user in AD.'
Write-Host ''
Write-Host 'Set SCTASK status to: Closed Complete' -ForegroundColor Green
Write-Host ''

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$safeSctask = $sctaskNumber.ToUpperInvariant()
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $OutputDirectory "$safeSctask-$timestamp.json"

$log = [ordered]@{
    createdAt = (Get-Date).ToString('o')
    sctaskNumber = $sctaskNumber.ToUpperInvariant()
    ritmNumber = $ritmNumber.ToUpperInvariant()
    fullName = $fullName
    samAccountName = $samAccountName
    departureDate = $departureDate.ToString('yyyy-MM-dd')
    emailForwardingChecked = $emailForwarding
    emailAccessChecked = $emailAccess
    alreadyDisabled = $alreadyDisabled
    pendingTerminationDate = $result.pendingTerminationDate
    adRenameValue = $result.adRenameValue
    serviceNowClosureComments = @(
        if ($alreadyDisabled) { 'As checked, the account is already disabled.' }
        'Performed password reset.'
        'Renamed the user in AD.'
    )
    serviceNowClosureStatus = 'Closed Complete'
}

$log | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host ('Saved local run log: {0}' -f $logPath) -ForegroundColor DarkGray

