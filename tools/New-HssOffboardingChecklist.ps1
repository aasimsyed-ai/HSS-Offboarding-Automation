[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $FullName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $SamAccountName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^RITM\d+$')]
    [string] $RitmNumber,

    [Parameter(Mandatory = $true)]
    [datetime] $TerminationDate,

    [Parameter(Mandatory = $false)]
    [switch] $EmailForwardingOrAccessRequired,

    [Parameter(Mandatory = $false)]
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-HssDate {
    param(
        [Parameter(Mandatory = $true)]
        [datetime] $Date
    )

    return $Date.ToString('d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
}

function Format-HssAdDate {
    param(
        [Parameter(Mandatory = $true)]
        [datetime] $Date
    )

    return $Date.ToString('ddMMMyy', [Globalization.CultureInfo]::InvariantCulture).ToUpperInvariant()
}

$monthsToAdd = if ($EmailForwardingOrAccessRequired) { 3 } else { 1 }
$accessDecision = if ($EmailForwardingOrAccessRequired) {
    'Email forwarding or email access required'
} else {
    'No email forwarding or email access required'
}

$pendingTerminationDate = $TerminationDate.AddMonths($monthsToAdd)
$renameValue = '{0} PendingTermination {1} {2}' -f $FullName.Trim(), (Format-HssAdDate $pendingTerminationDate), $RitmNumber.Trim().ToUpperInvariant()

$result = [ordered]@{
    taskType = 'Rename AD Account to Add Pending Termination Date'
    shortDescriptionMustContain = 'Disable account and rename to Full Name-Pending Termination for'
    fullName = $FullName.Trim()
    samAccountName = $SamAccountName.Trim()
    ritmNumber = $RitmNumber.Trim().ToUpperInvariant()
    terminationDate = (Format-HssDate $TerminationDate)
    accessDecision = $accessDecision
    monthsAdded = $monthsToAdd
    pendingTerminationDate = (Format-HssDate $pendingTerminationDate)
    pendingTerminationAdDate = (Format-HssAdDate $pendingTerminationDate)
    adRenameValue = $renameValue
    checklist = @(
        'Confirm the ServiceNow short description matches the expected offboarding task.',
        'Open the SCTASK and copy the Request Number beginning with RITM.',
        'Open the RITM in another ServiceNow tab for easy reference.',
        'Confirm Departure Date, Email forwarding / Email Access, and AD account section username.',
        'Open AD in Omnisa Horizon / VDI.',
        'Right click NA.IKO and choose Find User.',
        ('Search for user: {0}' -f $SamAccountName.Trim()),
        'From search results, right click the user and choose Rename.',
        ('Enter exactly: {0}' -f $renameValue),
        'Click OK.',
        'Do not change any other AD fields.',
        'Right click the user account and choose Reset Password.',
        'Enter the standard reset password for this workflow.',
        'If the account was already disabled, add this SCTASK comment: As checked, the account is already disabled.',
        'Add this SCTASK comment: Performed password reset.',
        'Add this SCTASK comment: Renamed the user in AD.',
        'Change SCTASK status to Closed Complete.',
        'Return to the RITM and continue with newly created tasks.'
    )
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 4
    return
}

Write-Host ''
Write-Host 'HSS Offboarding Task Helper' -ForegroundColor Cyan
Write-Host '===========================' -ForegroundColor Cyan
Write-Host ''
Write-Host ('Full name:                {0}' -f $result.fullName)
Write-Host ('AD user name:             {0}' -f $result.samAccountName)
Write-Host ('RITM number:              {0}' -f $result.ritmNumber)
Write-Host ('Termination date:         {0}' -f $result.terminationDate)
Write-Host ('Access decision:          {0}' -f $result.accessDecision)
Write-Host ('Pending termination date: {0}' -f $result.pendingTerminationDate)
Write-Host ''
Write-Host 'AD rename value:' -ForegroundColor Yellow
Write-Host $result.adRenameValue
Write-Host ''
Write-Host 'Checklist:' -ForegroundColor Yellow
for ($i = 0; $i -lt $result.checklist.Count; $i++) {
    Write-Host ('{0}. {1}' -f ($i + 1), $result.checklist[$i])
}
Write-Host ''
