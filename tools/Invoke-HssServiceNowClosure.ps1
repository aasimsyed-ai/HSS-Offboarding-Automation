[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $SctaskNumber,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $RitmNumber,

    [Parameter(Mandatory = $false)]
    [switch] $AlreadyDisabled,

    [Parameter(Mandatory = $false)]
    [string] $EdgeWindowTitle = 'HSS Service Management'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ServiceNowWindowTools {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@

function Get-EdgeServiceNowWindow {
    $windows = Get-Process msedge -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowHandle -ne 0 -and
            (
                $_.MainWindowTitle -like "*$EdgeWindowTitle*" -or
                $_.MainWindowTitle -like "*$SctaskNumber*" -or
                $_.MainWindowTitle -like "*$RitmNumber*"
            )
        } |
        Sort-Object -Property @{ Expression = { if ($_.MainWindowTitle -like "*$SctaskNumber*") { 0 } elseif ($_.MainWindowTitle -like "*$RitmNumber*") { 1 } else { 2 } } }

    return $windows | Select-Object -First 1
}

function Focus-ServiceNow {
    $window = Get-EdgeServiceNowWindow
    if (-not $window) {
        throw "Could not find an Edge ServiceNow window. Open the SCTASK or RITM in Edge, then run this again."
    }

    [void][ServiceNowWindowTools]::ShowWindowAsync($window.MainWindowHandle, 9)
    Start-Sleep -Milliseconds 300
    [void][ServiceNowWindowTools]::SetForegroundWindow($window.MainWindowHandle)
    Start-Sleep -Milliseconds 500
    return $window
}

function Wait-ForUser {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host ''
    Write-Host $Message -ForegroundColor Yellow
    Read-Host 'Press Enter when ready'
}

function Paste-Text {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 300
}

$comments = New-Object System.Collections.Generic.List[string]
if ($AlreadyDisabled) {
    $comments.Add('As checked, the account is already disabled.')
}
$comments.Add('Performed password reset.')
$comments.Add('Renamed the user in AD.')
$workNotes = $comments -join [Environment]::NewLine

Clear-Host
Write-Host 'HSS ServiceNow Closure Automation' -ForegroundColor Cyan
Write-Host '=================================' -ForegroundColor Cyan
Write-Host ''
Write-Host ('SCTASK: {0}' -f $SctaskNumber.ToUpperInvariant())
Write-Host ('RITM:   {0}' -f $RitmNumber.ToUpperInvariant())
Write-Host ''
Write-Host 'Work notes to paste:' -ForegroundColor Yellow
Write-Host $workNotes
Write-Host ''

$window = Focus-ServiceNow
Write-Host ('Focused Edge window: {0}' -f $window.MainWindowTitle) -ForegroundColor Green

Wait-ForUser 'Open the matching SCTASK in ServiceNow. Click inside the Work notes field, then return here.'
Focus-ServiceNow | Out-Null
Paste-Text -Text $workNotes
Write-Host 'Pasted work notes.' -ForegroundColor Green

Wait-ForUser 'Click the State/Status field in the SCTASK. If it is a dropdown, open it and place focus where typing a value works, then return here.'
Focus-ServiceNow | Out-Null
Paste-Text -Text 'Closed Complete'
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Write-Host 'Entered Closed Complete.' -ForegroundColor Green

Wait-ForUser 'Review the SCTASK. If work notes and status are correct, click/update focus on the Update/Save button or leave the page ready for Ctrl+S, then return here.'
Focus-ServiceNow | Out-Null
[System.Windows.Forms.SendKeys]::SendWait('^s')
Write-Host 'Sent Ctrl+S. If your ServiceNow form uses an Update button instead, click Update manually now.' -ForegroundColor Green

