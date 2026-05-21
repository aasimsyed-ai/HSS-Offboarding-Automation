[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $SamAccountName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $AdRenameValue,

    [Parameter(Mandatory = $false)]
    [string] $HorizonWindowTitle = 'Service Desk',

    [Parameter(Mandatory = $false)]
    [string] $HorizonClientPath = 'C:\Program Files\Omnissa\Omnissa Horizon Client\horizon-client.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WindowTools {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@

function Get-HorizonWindow {
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowHandle -ne 0 -and
            (
                $_.MainWindowTitle -like "*$HorizonWindowTitle*" -or
                $_.ProcessName -like '*horizon*'
            )
        } |
        Sort-Object -Property @{ Expression = { if ($_.MainWindowTitle -like "*$HorizonWindowTitle*") { 0 } else { 1 } } }, ProcessName

    return $processes | Select-Object -First 1
}

function Start-OrFocusHorizon {
    $window = Get-HorizonWindow

    if (-not $window) {
        if (-not (Test-Path -LiteralPath $HorizonClientPath)) {
            throw "Horizon client not found: $HorizonClientPath"
        }

        Start-Process -FilePath $HorizonClientPath | Out-Null
        Write-Host 'Waiting for Horizon window...' -ForegroundColor DarkGray
        Start-Sleep -Seconds 8
        $window = Get-HorizonWindow
    }

    if (-not $window) {
        throw 'Could not find a Horizon window. Open Omnissa Horizon Client and connect to the VDI, then run this again.'
    }

    [void][WindowTools]::ShowWindowAsync($window.MainWindowHandle, 9)
    Start-Sleep -Milliseconds 300
    [void][WindowTools]::SetForegroundWindow($window.MainWindowHandle)
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

function Send-ClipboardText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $false)]
        [switch] $ClearAfterPaste
    )

    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 300

    if ($ClearAfterPaste) {
        Set-Clipboard -Value ''
    }
}

function Read-SecretPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt
    )

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

Clear-Host
Write-Host 'HSS Horizon / AD Attended Automation' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'This script works through the Horizon GUI only. It does not use AD PowerShell cmdlets.' -ForegroundColor DarkGray
Write-Host 'You will be asked to confirm each AD screen before the bot pastes or submits values.' -ForegroundColor DarkGray
Write-Host ''

$window = Start-OrFocusHorizon
Write-Host ('Focused Horizon window: {0}' -f $window.MainWindowTitle) -ForegroundColor Green

Wait-ForUser 'In the VDI, open Active Directory Users and Computers. Open Find User, click in the search box, then return here.'
Start-OrFocusHorizon | Out-Null
Send-ClipboardText -Text $SamAccountName
Write-Host ('Pasted AD username: {0}' -f $SamAccountName) -ForegroundColor Green

Wait-ForUser 'In AD search results, select the exact user. Start Rename so the rename text field is active, then return here.'
Start-OrFocusHorizon | Out-Null
Send-ClipboardText -Text $AdRenameValue
Write-Host ('Pasted AD rename value: {0}' -f $AdRenameValue) -ForegroundColor Green

Wait-ForUser 'Review the rename value in AD. If it is correct, press Enter here and the bot will send Enter to confirm Rename. If it is wrong, close this window instead.'
Start-OrFocusHorizon | Out-Null
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Write-Host 'Sent Enter to confirm the rename.' -ForegroundColor Green

Wait-ForUser 'Open Reset Password for the same user. Click in the New password field, then return here.'
$newPassword = Read-SecretPlainText -Prompt 'Enter the password to set in AD'
$confirmPassword = Read-SecretPlainText -Prompt 'Re-enter the password'
if ($newPassword -cne $confirmPassword) {
    throw 'Passwords did not match. Password was not pasted.'
}

Start-OrFocusHorizon | Out-Null
Send-ClipboardText -Text $newPassword -ClearAfterPaste
[System.Windows.Forms.SendKeys]::SendWait('{TAB}')
Start-Sleep -Milliseconds 250
Send-ClipboardText -Text $newPassword -ClearAfterPaste
Write-Host 'Pasted password into both password fields and cleared the local clipboard.' -ForegroundColor Green

Wait-ForUser 'Review the Reset Password dialog. If it is correct, press Enter here and the bot will send Enter to submit. If it is wrong, close this window instead.'
Start-OrFocusHorizon | Out-Null
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Write-Host 'Sent Enter to submit password reset.' -ForegroundColor Green
Write-Host ''
Write-Host 'Now add the ServiceNow comments and set SCTASK status to Closed Complete.' -ForegroundColor Yellow

